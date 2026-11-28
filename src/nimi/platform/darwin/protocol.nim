## WKURLSchemeHandler for local & VFS assets (nimi://...).

import std/[strutils, tables]

import ../contract
import ../../core/fileserver
import ./[objc, types]

const NimiSchemeHandlerClass = "NimiSchemeHandler"

proc startURLSchemeTask(self: Id, cmd: SEL, webView: Id,
                        task: Id) {.cdecl.} =
  if gState == nil:
    return
  let cb = gState.schemeCallbacks.getOrDefault(self, nil)
  let root = gState.schemeRoots.getOrDefault(self)
  if cb == nil and root.len == 0:
    return
  let request = send0(task, sel("request"))
  let url = if request != nil: send0(request, sel("URL")) else: nil
  let path = if url != nil: goString(send0(url, sel("path"))) else: "/"
  let served =
    if cb != nil:
      cb(path)
    else:
      let r = serve(newFileServer(root), path)
      PlatformResource(status: r.status, mime: r.mime, data: r.data)
  when defined(nimiProtocolDebug):
    stderr.writeLine("protocol: " & path & " status=" & $served.status &
      " mime=" & served.mime & " len=" & $served.data.len)
    stderr.flushFile()
  if served.status != 200:
    sendVoidId(task, sel("didFailWithError:"),
               nsError("NimiFileServer", served.status))
    return
  let textEncoding =
    if served.mime.startsWith("text/") or served.mime in
        ["application/json", "application/xml", "image/svg+xml"]:
      nsString("utf-8")
    else:
      nil
  let response = initURLResponse(url, nsString(served.mime),
                                 int64(served.data.len), textEncoding)
  if response == nil:
    sendVoidId(task, sel("didFailWithError:"),
               nsError("NimiFileServer", 500))
    return
  sendVoidId(task, sel("didReceiveResponse:"), response)
  sendVoidId(task, sel("didReceiveData:"), nsData(served.data))
  sendVoid(task, sel("didFinish"))
  release(response)

proc stopURLSchemeTask(self: Id, cmd: SEL, webView: Id,
                       task: Id) {.cdecl.} =
  discard

proc schemeHandlerClass(): Id =
  registerClass(NimiSchemeHandlerClass, loadClass("NSObject"), [
    ("webView:startURLSchemeTask:",
      cast[pointer](startURLSchemeTask), "v@:@@"),
    ("webView:stopURLSchemeTask:",
      cast[pointer](stopURLSchemeTask), "v@:@@"),
  ])

proc attachSchemeHandler*(config: Id, scheme, root: string,
                          windowId: uint64,
                          serveCb: PlatformSchemeHandler = nil): Id =
  if gState == nil or config == nil or scheme.len == 0 or
      (serveCb == nil and root.len == 0):
    return nil
  let handler = send0(schemeHandlerClass(), sel("new"))
  if handler == nil:
    return nil
  if root.len > 0:
    gState.schemeRoots[handler] = root
  if serveCb != nil:
    gState.schemeCallbacks[handler] = serveCb
  retain(handler)
  sendVoidId2(config, sel("setURLSchemeHandler:forURLScheme:"),
              handler, nsString(scheme))
  gState.schemeHandlers[windowId] = handler
  result = handler

proc releaseSchemeHandler*(windowId: uint64) =
  if gState == nil:
    return
  let handler = gState.schemeHandlers.getOrDefault(windowId)
  if handler != nil:
    gState.schemeRoots.del(handler)
    gState.schemeCallbacks.del(handler)
    gState.schemeHandlers.del(windowId)
    release(handler)
