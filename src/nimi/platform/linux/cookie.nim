## WebKitGTK default cookie store queries and clearing. Callbacks run on the
## GTK main context.

import std/tables

import ../contract
import ./[ffi, state]

type
  CookieRequest = ref object
    id: uint64
    manager: pointer
    callback: proc(cookies: seq[PlatformCookie]) {.closure.}
    cancelled: bool

var
  requests: Table[uint64, CookieRequest]
  pending: seq[CookieRequest]
  nextRequestId = 1'u64

proc cookieManager(): pointer =
  let context = webkit_web_context_get_default()
  if context == nil:
    return nil
  webkit_web_context_get_cookie_manager(context)

proc text(value: cstring): string =
  if value == nil: "" else: $value

proc finishRequest(request: CookieRequest, cookies: seq[PlatformCookie]) =
  if request == nil:
    return
  requests.del(request.id)
  var remaining: seq[CookieRequest]
  for item in pending:
    if item != request:
      remaining.add item
  pending = remaining
  if not request.cancelled and request.callback != nil:
    request.callback(cookies)

proc onAllCookies(source, result, data: pointer) {.cdecl.} =
  let request = cast[CookieRequest](data)
  if request == nil:
    return
  var cookies: seq[PlatformCookie]
  if webkit_cookie_manager_get_all_cookies_finish != nil:
    let list = webkit_cookie_manager_get_all_cookies_finish(
      request.manager, result, nil)
    var node = list
    var guard = 0
    while node != nil and guard < 100000:
      inc guard
      let cookie = node.data
      if cookie != nil:
        cookies.add PlatformCookie(
          name: text(soup_cookie_get_name(cookie)),
          value: text(soup_cookie_get_value(cookie)),
          domain: text(soup_cookie_get_domain(cookie)),
          path: text(soup_cookie_get_path(cookie)),
          secure: soup_cookie_get_secure(cookie) != 0,
          httpOnly: soup_cookie_get_http_only(cookie) != 0)
        soup_cookie_free(cookie)
      node = node.next
    if list != nil:
      g_list_free(list)
  request.finishRequest(cookies)

proc getCookies*(callback: proc(cookies: seq[PlatformCookie])) =
  if linuxState == nil or not linuxState.initialized or
      not ensureWebKit() or webkit_cookie_manager_get_all_cookies == nil or
      webkit_cookie_manager_get_all_cookies_finish == nil:
    if callback != nil:
      callback(@[])
    return
  let manager = cookieManager()
  if manager == nil:
    if callback != nil:
      callback(@[])
    return
  let request = CookieRequest(id: nextRequestId, manager: manager,
                              callback: callback)
  inc nextRequestId
  requests[request.id] = request
  pending.add request
  webkit_cookie_manager_get_all_cookies(manager, nil, onAllCookies,
                                        cast[pointer](request))

proc clearCookies*(callback: proc() = nil) =
  if linuxState != nil and linuxState.initialized and ensureWebKit():
    let manager = cookieManager()
    if manager != nil:
      webkit_cookie_manager_delete_all_cookies(manager)
  if callback != nil:
    callback()

proc cancelPendingCookies*() =
  ## Keeps request objects alive until WebKit finishes, but drops callbacks
  ## after the backend has shut down.
  for request in pending:
    request.cancelled = true
    request.callback = nil
