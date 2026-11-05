## WKURLSchemeHandler for local static assets (nimi://...).

import std/[strutils, tables]

import ../../core/fileserver
import ./[objc, types]

const NimiSchemeHandlerClass = "NimiSchemeHandler"

proc startURLSchemeTask(self: Id, cmd: SEL, webView: Id,
                        task: Id) {.cdecl.} =
  if gState == nil:
    return
  let root = gState.schemeRoots.getOrDefault(self)
  if root.len == 0:
    return
  let request = send0(task, sel("request"))
  let url = if request != nil: send0(request, sel("URL")) else: nil
  let path = if url != nil: goString(send0(url, sel("path"))) else: "/"
  let result = serve(FileServer(root: root), path)
  when defined(nimiProtocolDebug):
    stderr.writeLine("protocol: " & path & " status=" & $result.status &
      " mime=" & result.mime & " len=" & $result.data.len)
    stderr.flushFile()
  if result.status != 200:
    sendVoidId(task, sel("didFailWithError:"),
               nsError("NimiFileServer", result.status))
    return
  let textEncoding =
    if result.mime.startsWith("text/") or result.mime in
        ["application/json", "application/xml", "image/svg+xml"]:
      nsString("utf-8")
    else:
      nil
  let response = initURLResponse(url, nsString(result.mime),
                                 int64(result.data.len), textEncoding)
  when defined(nimiProtocolDebug):
    stderr.writeLine("response mime: " & (if response != nil:
      goString(send0(response, sel("MIMEType"))) else: "nil"))
    stderr.flushFile()
  if response == nil:
    sendVoidId(task, sel("didFailWithError:"),
               nsError("NimiFileServer", 500))
    return
  sendVoidId(task, sel("didReceiveResponse:"), response)
  sendVoidId(task, sel("didReceiveData:"), nsData(result.data))
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
                          windowId: uint64): Id =
  if gState == nil or config == nil or scheme.len == 0 or root.len == 0:
    return nil
  let handler = send0(schemeHandlerClass(), sel("new"))
  if handler == nil:
    return nil
  gState.schemeRoots[handler] = root
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
    gState.schemeHandlers.del(windowId)
    release(handler)
