## WebView2 host and the Nimi bridge.
##
## Custom schemes (`nimi://app/*`) are intercepted via `WebResourceRequested`
## and routed through Nim's unified `FileServer` / `serveScheme` callback,
## aligning Windows with macOS (`WKURLSchemeHandler`) and Linux (`WebKitGTK`).
when not defined(windows):
  {.error: "WebView2 requires Windows".}

import std/[os, strutils, tables, tempfiles, widestrs]

import ../../core/[bridge, fileserver, loop, paths]
import ../contract

const
  header = (currentSourcePath.parentDir / "webview2" / "webview2.h")
    .replace('\\', '/')
  loaderHint = currentSourcePath.parentDir / "webview2" / "sdk" /
    (when defined(arm64): "arm64" else: "x64") / "WebView2Loader.dll"

{.compile: "webview2/webview2.c".}
{.passL: "-lole32 -luuid".}

type
  NativeWebResource {.importc: "NimiWebResource", header: header, bycopy.} = object
    data: pointer
    length: csize_t
    mime: pointer
    status: cint

  Callbacks {.importc: "NimiWebView2Callbacks", header: header, bycopy.} = object
    ready: proc(context: pointer) {.cdecl.}
    message: proc(context: pointer, text: cstring) {.cdecl.}
    error: proc(context: pointer, text: cstring) {.cdecl.}
    finalized: proc(context: pointer) {.cdecl.}
    serve_resource: proc(context: pointer, path: cstring,
                         outRes: ptr NativeWebResource): cint {.cdecl.}
    free_resource: proc(res: ptr NativeWebResource) {.cdecl.}
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
    serveScheme: PlatformSchemeHandler
    error: string
    userDataDir: string
    ephemeralDir: bool
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

proc allocCStringShared(s: string): pointer =
  let buf = cast[ptr UncheckedArray[char]](allocShared(s.len + 1))
  if s.len > 0:
    copyMem(buf, unsafeAddr s[0], s.len)
  buf[s.len] = '\0'
  buf

proc onServeResource(context: pointer, rawPath: cstring,
                     outRes: ptr NativeWebResource): cint {.cdecl.} =
  if outRes == nil:
    return 0
  let webview = webviews.getOrDefault(context)
  if webview == nil or webview.serveScheme == nil:
    return 0
  try:
    let path = if rawPath == nil: "/" else: $rawPath
    let served = webview.serveScheme(path)
    outRes.status = cint(if served.status > 0: served.status else: 404)
    outRes.mime = allocCStringShared(
      if served.mime.len > 0: served.mime else: "application/octet-stream")
    outRes.length = csize_t(served.data.len)
    if served.data.len > 0:
      let body = allocShared(served.data.len)
      copyMem(body, unsafeAddr served.data[0], served.data.len)
      outRes.data = body
    else:
      outRes.data = nil
    return 1
  except CatchableError:
    return 0

proc onFreeResource(res: ptr NativeWebResource) {.cdecl.} =
  if res == nil:
    return
  if res.data != nil:
    deallocShared(res.data)
    res.data = nil
  if res.mime != nil:
    deallocShared(res.mime)
    res.mime = nil
  res.length = 0

proc onFinalized(context: pointer) {.cdecl.} =
  let webview = webviews.getOrDefault(context)
  if webview == nil:
    return
  if webview.ephemeralDir and webview.userDataDir.len > 0:
    try:
      removeDir(webview.userDataDir)
    except CatchableError:
      discard
  webview.owner = nil
  webviews.del(context)

proc resolveDefaultUserDataDir(): string =
  ## Avoid WebView2's `<exe>.WebView2` fallback next to the executable, which
  ## fails when installed under `C:\Program Files`. Respect explicit env override.
  if getEnv("WEBVIEW2_USER_DATA_FOLDER").len > 0:
    return ""
  let slug = sanitizeSlug(try: splitFile(getAppFilename()).name except CatchableError: "nimi")
  result = appCacheDir(slug) / "webview2"
  try:
    createDir(result)
  except CatchableError:
    result = ""

proc newWebView2*(parent: pointer, userId: uint64, handler: WindowHandler,
                  scheme, fileRoot, secret, token: string,
                  ephemeral: bool,
                  serveScheme: PlatformSchemeHandler = nil,
                  userDataDir: string = ""): WebView2 =
  if parent == nil:
    raise newException(BackendError, "WebView2 requires a parent window")
  var effectiveServe = serveScheme
  if effectiveServe == nil and scheme.len > 0 and fileRoot.len > 0:
    let fs = newFileServer(fileRoot, scheme)
    effectiveServe = proc(path: string): PlatformResource {.gcsafe.} =
      let r = fs.serve(path)
      PlatformResource(status: r.status, mime: r.mime, data: r.data)

  result = WebView2(
    userId: userId,
    handler: handler,
    serveScheme: effectiveServe)
  if ephemeral:
    result.userDataDir = createTempDir("nimi-webview2-", "")
    result.ephemeralDir = true
  elif userDataDir.len > 0:
    result.userDataDir = userDataDir
    try: createDir(result.userDataDir) except CatchableError: discard
  else:
    result.userDataDir = resolveDefaultUserDataDir()

  let context = cast[pointer](result)
  let callbacks = Callbacks(
    ready: onReady,
    message: onMessage,
    error: onError,
    finalized: onFinalized,
    serve_resource: (if effectiveServe != nil: onServeResource else: nil),
    free_resource: onFreeResource,
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
