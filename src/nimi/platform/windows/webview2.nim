## WebView2 host and the Nimi bridge. The COM/vtable shim lives in
## webview2/webview2.c; this module owns the Nim callback context.
when not defined(windows):
  {.error: "WebView2 requires Windows".}

import std/[os, strutils, tables, tempfiles, widestrs]

import ../../core/[bridge, loop]
import ../contract

const
  header = (currentSourcePath.parentDir / "webview2" / "webview2.h")
    .replace('\\', '/')
  loaderHint = currentSourcePath.parentDir / "webview2" / "sdk" /
    (when defined(arm64): "arm64" else: "x64") / "WebView2Loader.dll"

{.compile: "webview2/webview2.c".}
{.passL: "-lole32 -luuid".}

type
  Callbacks {.importc: "NimiWebView2Callbacks", header: header, bycopy.} = object
    ready: proc(context: pointer) {.cdecl.}
    message: proc(context: pointer, text: cstring) {.cdecl.}
    error: proc(context: pointer, text: cstring) {.cdecl.}
    finalized: proc(context: pointer) {.cdecl.}
    context: pointer
  NativeCookie {.importc: "NimiCookie", header: header, bycopy.} = object
    name, value, domain, path: WideCString
    secure, http_only: cint
  CookiesDone = proc(context: pointer, id: uint, list: ptr NativeCookie,
                     count: cuint, status: int32) {.cdecl.}
  CookieCallback = proc(cookies: seq[PlatformCookie])
  ReadyCallback = proc(view: WebView2, ready: bool)

  WebView2* = ref object
    owner: pointer
    userId: uint64
    handler: WindowHandler
    error: string
    userDataDir: string
    readyCallbacks: seq[ReadyCallback]
    cookieCallbacks: Table[uint, CookieCallback]
    nextCookieId: uint

var webviews: Table[pointer, WebView2]

proc cCreate(parent: pointer, userDataFolder, loaderHint, scheme, fileRoot,
             bridge: WideCString, callbacks: Callbacks, error: cstring,
             errorSize: cint): pointer
  {.cdecl, importc: "nimi_webview2_create", header: header.}
proc cReady(view: pointer): cint
  {.cdecl, importc: "nimi_webview2_ready", header: header.}
proc cResize(view: pointer, width, height: cint, scale: cfloat)
  {.cdecl, importc: "nimi_webview2_resize", header: header.}
proc cShow(view: pointer, visible: cint)
  {.cdecl, importc: "nimi_webview2_show", header: header.}
proc cFocus(view: pointer)
  {.cdecl, importc: "nimi_webview2_focus", header: header.}
proc cLoadHTML(view: pointer, html, baseUrl: WideCString)
  {.cdecl, importc: "nimi_webview2_load_html", header: header.}
proc cLoadURL(view: pointer, url: WideCString)
  {.cdecl, importc: "nimi_webview2_load_url", header: header.}
proc cEval(view: pointer, js: WideCString)
  {.cdecl, importc: "nimi_webview2_eval", header: header.}
proc cReadCookies(view: pointer, id: uint, done: CookiesDone): int32
  {.cdecl, importc: "nimi_webview2_read_cookies", header: header.}
proc cClearCookies(view: pointer): int32
  {.cdecl, importc: "nimi_webview2_clear_cookies", header: header.}
proc cClose(view: pointer)
  {.cdecl, importc: "nimi_webview2_close", header: header.}

const webView2Shim = """
(function () {
  window.webkit = window.webkit || {};
  window.webkit.messageHandlers = window.webkit.messageHandlers || {};
  if (!window.webkit.messageHandlers.nimi) {
    window.webkit.messageHandlers.nimi = {
      postMessage: function (message) {
        if (window.chrome && window.chrome.webview) {
          window.chrome.webview.postMessage(message);
        }
      }
    };
  }
})();
"""

proc bridgeScript*(secret, token: string): string =
  ## Keep the page-side bridge identical to macOS; only the transport shim
  ## changes from WKWebView message handlers to chrome.webview.
  webView2Shim & "\n" & bridgeJs
    .replace("__NIMI_SECRET__", secret)
    .replace("__NIMI_TOKEN__", token)

proc completeReadiness(view: WebView2, ok: bool) =
  let pending = move(view.readyCallbacks)
  if pending.len > 0:
    discard postMain(proc() =
      if view.owner != nil:
        for callback in pending: callback(view, ok))

proc onReady(context: pointer) {.cdecl.} =
  let view = webviews.getOrDefault(context)
  if view != nil: completeReadiness(view, true)

proc onMessage(context: pointer, text: cstring) {.cdecl.} =
  let webview = cast[WebView2](context)
  if webview == nil or text == nil:
    return
  let message = $text
  if webview.handler.message != nil:
    try:
      webview.handler.message(webview.userId, message)
    except CatchableError:
      discard

proc onError(context: pointer, text: cstring) {.cdecl.} =
  let webview = cast[WebView2](context)
  if webview == nil:
    return
  webview.error = if text == nil: "WebView2 error" else: $text
  try: stderr.writeLine("webview2: " & webview.error)
  except IOError: discard
  completeReadiness(webview, false)

proc onFinalized(context: pointer) {.cdecl.} =
  let webview = webviews.getOrDefault(context)
  if webview == nil:
    return
  if webview.userDataDir.len > 0:
    try:
      removeDir(webview.userDataDir)
    except CatchableError:
      discard
  webview.owner = nil
  webviews.del(context)

proc newWebView2*(parent: pointer, userId: uint64, handler: WindowHandler,
                  scheme, fileRoot, secret, token: string,
                  ephemeral: bool): WebView2 =
  if parent == nil:
    raise newException(BackendError, "WebView2 requires a parent window")
  result = WebView2(userId: userId, handler: handler)
  if ephemeral:
    result.userDataDir = createTempDir("nimi-webview2-", "")
  let context = cast[pointer](result)
  let callbacks = Callbacks(
    ready: onReady,
    message: onMessage,
    error: onError,
    finalized: onFinalized,
    context: context)
  var error = newString(512)
  webviews[context] = result
  result.owner = cCreate(parent, newWideCString(result.userDataDir),
    newWideCString(loaderHint), newWideCString(scheme),
    newWideCString(fileRoot), newWideCString(bridgeScript(secret, token)),
    callbacks, cast[cstring](addr error[0]), cint(error.len))
  if result.owner == nil:
    onFinalized(context)
    raise newException(BackendError,
      "WebView2: " & $cast[cstring](addr error[0]))

proc isReady*(webview: WebView2): bool =
  webview != nil and webview.owner != nil and cReady(webview.owner) != 0

proc lastError*(webview: WebView2): string =
  if webview == nil: "" else: webview.error

proc resize*(webview: WebView2, width, height: int, scale: float32) =
  if webview != nil and webview.owner != nil:
    cResize(webview.owner, cint(width), cint(height), cfloat(scale))

proc show*(webview: WebView2, visible: bool) =
  if webview != nil and webview.owner != nil:
    cShow(webview.owner, cint(visible))

proc focus*(webview: WebView2) =
  if webview != nil and webview.owner != nil:
    cFocus(webview.owner)

proc loadHTML*(webview: WebView2, html, baseUrl: string) =
  if webview != nil and webview.owner != nil:
    cLoadHTML(webview.owner, newWideCString(html), newWideCString(baseUrl))

proc loadURL*(webview: WebView2, url: string) =
  if webview != nil and webview.owner != nil:
    cLoadURL(webview.owner, newWideCString(url))

proc eval*(webview: WebView2, js: string) =
  if webview != nil and webview.owner != nil:
    cEval(webview.owner, newWideCString(js))

proc whenReady(view: WebView2, callback: ReadyCallback) =
  let ready = view.isReady()
  if ready or view.lastError().len > 0:
    discard postMain(proc() =
      if view.owner != nil: callback(view, ready))
  else:
    view.readyCallbacks.add callback

proc cookieError(status: int32): string =
  "WebView2 cookie operation failed: HRESULT 0x" & toHex(cast[uint32](status), 8)

proc cookieString(value: WideCString): string =
  if value == nil: "" else: $value

proc onCookies(context: pointer, id: uint, items: ptr NativeCookie, count: cuint,
               status: int32) {.cdecl.} =
  let view = webviews.getOrDefault(context)
  if view == nil: return
  let callback = view.cookieCallbacks.getOrDefault(id)
  if callback == nil: return
  view.cookieCallbacks.del(id)
  var cookies: seq[PlatformCookie]
  let list = cast[ptr UncheckedArray[NativeCookie]](items)
  for i in 0..<int(count):
    let item = list[i]
    cookies.add PlatformCookie(name: cookieString(item.name), value: cookieString(item.value),
      domain: cookieString(item.domain), path: cookieString(item.path), secure: item.secure != 0,
      httpOnly: item.http_only != 0)
  discard postMain(proc() =
    if status < 0: stderr.writeLine(cookieError(status))
    callback(cookies))

proc getCookies*(view: WebView2, callback: CookieCallback) =
  if callback == nil: return
  view.whenReady(proc(store: WebView2, ready: bool) =
    if not ready:
      callback(@[])
      return
    inc store.nextCookieId
    let id = store.nextCookieId
    store.cookieCallbacks[id] = callback
    let status = cReadCookies(store.owner, id, onCookies)
    if status < 0:
      onCookies(cast[pointer](store), id, nil, 0, status))

proc clearCookies*(view: WebView2, callback: proc()) =
  view.whenReady(proc(store: WebView2, ready: bool) =
    if ready:
      let status = cClearCookies(store.owner)
      if status < 0: stderr.writeLine(cookieError(status))
    if callback != nil: callback())

proc close*(webview: WebView2) =
  if webview == nil or webview.owner == nil:
    return
  let owner = webview.owner
  webview.owner = nil
  webview.readyCallbacks.setLen(0)
  webview.cookieCallbacks.clear()
  cClose(owner)
