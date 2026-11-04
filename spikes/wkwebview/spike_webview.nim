## Feasibility spike 2: WKWebView from Nim through the Objective-C runtime,
## with a runtime-defined WKScriptMessageHandler and no Objective-C source.
## The page posts a message; Nim prints it and quits after one second.
##   nim c -r --mm:orc spike_webview.nim

import std/dynlib

type
  Id = pointer
  SEL = distinct pointer
  NSRect {.bycopy.} = object
    x, y, w, h: float64
  NSUInteger = uint

  MsgSend0 = proc(a: Id, s: SEL): Id {.cdecl.}
  MsgSendVoid = proc(a: Id, s: SEL) {.cdecl.}
  MsgSendId1 = proc(a: Id, s: SEL, b: Id): Id {.cdecl.}
  MsgSendVoidId = proc(a: Id, s: SEL, b: Id) {.cdecl.}
  MsgSendVoidId2 = proc(a: Id, s: SEL, b, c: Id) {.cdecl.}
  MsgSendVoidBool = proc(a: Id, s: SEL, b: bool) {.cdecl.}
  MsgSendVoidInt = proc(a: Id, s: SEL, b: int) {.cdecl.}
  MsgSendVoidFloat = proc(a: Id, s: SEL, b: float64) {.cdecl.}
  MsgSendCString = proc(a: Id, s: SEL): cstring {.cdecl.}

let
  objc = loadLib("/usr/lib/libobjc.A.dylib")
  appkit = loadLib("/System/Library/Frameworks/AppKit.framework/AppKit")
  webkit = loadLib("/System/Library/Frameworks/WebKit.framework/WebKit")
  msgSend = cast[pointer](symAddr(objc, "objc_msgSend"))
  getClass = cast[proc(name: cstring): Id {.cdecl.}](symAddr(objc, "objc_getClass"))
  registerName = cast[proc(name: cstring): SEL {.cdecl.}](symAddr(objc, "sel_registerName"))

proc sel(name: string): SEL = registerName(name.cstring)
proc send0(o: Id, s: SEL): Id = cast[MsgSend0](msgSend)(o, s)
proc sendVoid(o: Id, s: SEL) = cast[MsgSendVoid](msgSend)(o, s)
proc sendId1(o: Id, s: SEL, b: Id): Id = cast[MsgSendId1](msgSend)(o, s, b)
proc sendVoidId(o: Id, s: SEL, b: Id) = cast[MsgSendVoidId](msgSend)(o, s, b)

proc nsstr(s: string): Id =
  let allocated = send0(getClass("NSString"), sel("alloc"))
  cast[proc(a: Id, s: SEL, b: cstring): Id {.cdecl.}](msgSend)(
    allocated, sel("initWithUTF8String:"), s.cstring)

proc cstr(o: Id): string =
  if o == nil: return ""
  let p = cast[MsgSendCString](msgSend)(o, sel("UTF8String"))
  if p == nil: "" else: $p

var
  gApp: Id
  gWebView: Id
  gHandler: Id
  gGotMessage = false

proc stopSoon() {.cdecl.} =
  discard cast[proc(a: Id, s: SEL, t: float64, target: Id, selector: SEL, info: Id, repeats: bool): Id {.cdecl.}](
    msgSend)(
      getClass("NSTimer"),
      sel("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"),
      0.8, gHandler, sel("stop:"), nil, false)

proc onMessage(self: Id, cmd: SEL, controller: Id, message: Id) {.cdecl.} =
  let body = send0(message, sel("body"))
  echo "JS -> Nim: ", cstr(send0(body, sel("description")))
  gGotMessage = true
  stopSoon()

proc didFinish(self: Id, cmd: SEL, webView: Id, navigation: Id) {.cdecl.} =
  echo "page loaded; evaluating JavaScript"
  let js = nsstr("window.webkit.messageHandlers.nimi.postMessage({hello: 'from the page', n: 42});")
  cast[proc(a: Id, s: SEL, b: Id, c: Id) {.cdecl.}](msgSend)(
    webView, sel("evaluateJavaScript:completionHandler:"), js, nil)

proc stopApp(self: Id, cmd: SEL, timer: Id) {.cdecl.} =
  echo "quitting"
  sendVoidId(gApp, sel("terminate:"), nil)

proc addMethod(cls: Id, name: string, imp: pointer, types: cstring): bool =
  cast[proc(c: Id, s: SEL, i: pointer, t: cstring): bool {.cdecl.}](
    symAddr(objc, "class_addMethod"))(cls, sel(name), imp, types)

proc makeHandler(): Id =
  let cls = cast[proc(s: Id, n: cstring, e: uint): Id {.cdecl.}](
    symAddr(objc, "objc_allocateClassPair"))(getClass("NSObject"), "NimiSpikeHandler", 0)
  discard addMethod(cls, "userContentController:didReceiveScriptMessage:",
                    cast[pointer](onMessage), "v@:@@")
  discard addMethod(cls, "webView:didFinishNavigation:",
                    cast[pointer](didFinish), "v@:@@")
  discard addMethod(cls, "stop:", cast[pointer](stopApp), "v@:@")
  cast[proc(c: Id) {.cdecl.}](symAddr(objc, "objc_registerClassPair"))(cls)
  send0(cls, sel("new"))

when isMainModule:
  echo "webkit loaded: ", webkit != nil
  let pool = send0(send0(getClass("NSAutoreleasePool"), sel("alloc")), sel("init"))
  gApp = send0(getClass("NSApplication"), sel("sharedApplication"))
  cast[MsgSendVoidInt](msgSend)(gApp, sel("setActivationPolicy:"), 0)

  gHandler = makeHandler()

  let config = send0(getClass("WKWebViewConfiguration"), sel("new"))
  let ucc = send0(config, sel("userContentController"))
  cast[MsgSendVoidId2](msgSend)(ucc, sel("addScriptMessageHandler:name:"), gHandler, nsstr("nimi"))

  let rect = NSRect(x: 240, y: 240, w: 520, h: 340)
  gWebView = cast[proc(a: Id, s: SEL, r: NSRect, c: Id): Id {.cdecl.}](
    msgSend)(send0(getClass("WKWebView"), sel("alloc")),
             sel("initWithFrame:configuration:"), rect, config)
  sendVoidId(gWebView, sel("setNavigationDelegate:"), gHandler)
  let html = """<!doctype html><meta charset=utf-8>
    <body style="font: 15px -apple-system; padding: 24px; background: #111; color: #eee">
    <h1>Nimi + WKWebView</h1><p id=p>waiting…</p>
    <script>document.getElementById('p').textContent = 'JS is running';</script>
    </body>"""
  cast[proc(a: Id, s: SEL, b: Id, c: Id) {.cdecl.}](msgSend)(
    gWebView, sel("loadHTMLString:baseURL:"), nsstr(html), nil)

  let win = cast[proc(a: Id, s: SEL, r: NSRect, m: NSUInteger, b: NSUInteger, d: bool): Id {.cdecl.}](
    msgSend)(send0(getClass("NSWindow"), sel("alloc")),
             sel("initWithContentRect:styleMask:backing:defer:"),
             rect, NSUInteger(1 or 2 or 4 or 8), 2, false)
  sendVoidId(win, sel("setTitle:"), nsstr("Nimi WKWebView spike"))
  sendVoidId(win, sel("setContentView:"), gWebView)
  sendVoidId(win, sel("makeKeyAndOrderFront:"), nil)
  cast[MsgSendVoidBool](msgSend)(gApp, sel("activateIgnoringOtherApps:"), true)

  # Safety net in case the page never loads: quit after 6 seconds.
  discard cast[proc(a: Id, s: SEL, t: float64, target: Id, selector: SEL, info: Id, repeats: bool): Id {.cdecl.}](
    msgSend)(getClass("NSTimer"),
             sel("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"),
             6.0, gHandler, sel("stop:"), nil, false)

  echo "running NSApplication"
  sendVoid(gApp, sel("run"))
  echo "message received: ", gGotMessage
  cast[MsgSendVoid](msgSend)(pool, sel("drain"))
  quit(if gGotMessage: 0 else: 1)
