## WebView2 host and the Nimi bridge. The COM/vtable shim lives in
## webview2/webview2.c; this module owns the Nim callback context.
when not defined(windows):
  {.error: "WebView2 requires Windows".}

import std/[os, strutils, tables, times, widestrs]

import ../../core/bridge
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

  WebView2* = ref object
    owner: pointer
    userId: uint64
    handler: WindowHandler
    ready, closed, failed: bool
    error: string
    userDataDir: string

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

proc onReady(context: pointer) {.cdecl.} =
  let webview = cast[WebView2](context)
  if webview != nil:
    webview.ready = true

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
  webview.failed = true
  webview.error = if text == nil: "WebView2 error" else: $text
  stderr.writeLine("webview2: " & webview.error)

proc onFinalized(context: pointer) {.cdecl.} =
  let webview = cast[WebView2](context)
  if webview == nil:
    return
  if webview.userDataDir.len > 0:
    try:
      removeDir(webview.userDataDir)
    except CatchableError:
      discard
  if webview.owner != nil:
    webviews.del(webview.owner)

var ephemeralCounter = 0

proc newWebView2*(parent: pointer, userId: uint64, handler: WindowHandler,
                  scheme, fileRoot, secret, token: string,
                  ephemeral: bool): WebView2 =
  if parent == nil:
    raise newException(BackendError, "WebView2 requires a parent window")
  result = WebView2(userId: userId, handler: handler)
  if ephemeral:
    inc ephemeralCounter
    result.userDataDir = getTempDir() / ("nimi-webview2-" &
      $getTime().toUnix & "-" & $ephemeralCounter)
    createDir(result.userDataDir)
  let callbacks = Callbacks(
    ready: onReady,
    message: onMessage,
    error: onError,
    finalized: onFinalized,
    context: cast[pointer](result))
  var error = newString(512)
  result.owner = cCreate(parent, newWideCString(result.userDataDir),
    newWideCString(loaderHint), newWideCString(scheme),
    newWideCString(fileRoot), newWideCString(bridgeScript(secret, token)),
    callbacks, cast[cstring](addr error[0]), cint(error.len))
  if result.owner == nil:
    if result.userDataDir.len > 0:
      try:
        removeDir(result.userDataDir)
      except CatchableError:
        discard
    raise newException(BackendError,
      "WebView2: " & $cast[cstring](addr error[0]))
  webviews[result.owner] = result

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

proc close*(webview: WebView2) =
  if webview == nil or webview.closed:
    return
  webview.closed = true
  if webview.owner != nil:
    cClose(webview.owner)
