## Feasibility spike 6: construct an Objective-C block in Nim (global block,
## no captures) and pass it to WKWebView's evaluateJavaScript:completionHandler:.
## Validates the block ABI without any Objective-C source or shim.
##   nim c -r --mm:orc spike_blocks.nim

import std/dynlib

type
  Id = pointer
  SEL = distinct pointer
  NSRect {.bycopy.} = object
    x, y, w, h: float64
  NSUInteger = uint
  BlockDescriptor {.bycopy.} = object
    reserved: uint
    size: uint
  BlockLiteral {.bycopy.} = object
    isa: pointer
    flags: int32
    reserved: int32
    invoke: pointer
    descriptor: ptr BlockDescriptor

let
  objc = loadLib("/usr/lib/libobjc.A.dylib")
  appkit = loadLib("/System/Library/Frameworks/AppKit.framework/AppKit")
  webkit = loadLib("/System/Library/Frameworks/WebKit.framework/WebKit")
  system = loadLib("/usr/lib/libSystem.B.dylib")
  msgSend = cast[pointer](symAddr(objc, "objc_msgSend"))
  getClass = cast[proc(name: cstring): Id {.cdecl.}](symAddr(objc, "objc_getClass"))
  registerName = cast[proc(name: cstring): SEL {.cdecl.}](symAddr(objc, "sel_registerName"))
  globalBlockIsa = symAddr(system, "_NSConcreteGlobalBlock")

var
  gApp: Id
  gWebView: Id
  gBlock: BlockLiteral
  gDescriptor: BlockDescriptor
  gNotified = false

proc sel(name: string): SEL = registerName(name.cstring)
proc send0(o: Id, s: SEL): Id = cast[proc(a: Id, s: SEL): Id {.cdecl.}](msgSend)(o, s)
proc sendVoid(o: Id, s: SEL) = cast[proc(a: Id, s: SEL) {.cdecl.}](msgSend)(o, s)
proc sendVoidId(o: Id, s: SEL, b: Id) = cast[proc(a: Id, s: SEL, b: Id) {.cdecl.}](msgSend)(o, s, b)
proc sendId1(o: Id, s: SEL, b: Id): Id = cast[proc(a: Id, s: SEL, b: Id): Id {.cdecl.}](msgSend)(o, s, b)

proc nsstr(s: string): Id =
  cast[proc(a: Id, s: SEL, b: cstring): Id {.cdecl.}](msgSend)(
    send0(getClass("NSString"), sel("alloc")), sel("initWithUTF8String:"), s.cstring)

proc jsDone(blk: pointer, result: Id, error: Id) {.cdecl.} =
  # void (^)(id result, NSError *error)
  let desc = if result != nil: send0(result, sel("description")) else: nsstr("<nil>")
  let text = cast[proc(a: Id, s: SEL): cstring {.cdecl.}](msgSend)(desc, sel("UTF8String"))
  echo "block called: result=", $text, " error=", error != nil
  gNotified = true
  sendVoidId(gApp, sel("terminate:"), nil)

proc addMethod(cls: Id, name: string, imp: pointer, types: cstring): bool =
  cast[proc(c: Id, s: SEL, i: pointer, t: cstring): bool {.cdecl.}](
    symAddr(objc, "class_addMethod"))(cls, sel(name), imp, types)

proc didFinish(self: Id, cmd: SEL, webView: Id, navigation: Id) {.cdecl.} =
  echo "navigation finished; evaluating JS with a Nim-made block"
  cast[proc(a: Id, s: SEL, b: Id, c: pointer) {.cdecl.}](msgSend)(
    webView, sel("evaluateJavaScript:completionHandler:"),
    nsstr("'answer: ' + (40 + 2)"), cast[pointer](addr gBlock))

proc stopApp(self: Id, cmd: SEL, timer: Id) {.cdecl.} =
  echo "safety timer fired"
  sendVoidId(gApp, sel("terminate:"), nil)

proc makeDelegate(): Id =
  let cls = cast[proc(s: Id, n: cstring, e: uint): Id {.cdecl.}](
    symAddr(objc, "objc_allocateClassPair"))(getClass("NSObject"), "NimiBlockDelegate", 0)
  discard addMethod(cls, "webView:didFinishNavigation:", cast[pointer](didFinish), "v@:@@")
  discard addMethod(cls, "stop:", cast[pointer](stopApp), "v@:@")
  cast[proc(c: Id) {.cdecl.}](symAddr(objc, "objc_registerClassPair"))(cls)
  send0(cls, sel("new"))

when isMainModule:
  echo "global block isa: ", globalBlockIsa != nil
  gDescriptor = BlockDescriptor(reserved: 0, size: uint(sizeof(BlockLiteral)))
  gBlock = BlockLiteral(
    isa: globalBlockIsa,
    flags: int32(1 shl 28), # BLOCK_IS_GLOBAL
    reserved: 0,
    invoke: cast[pointer](jsDone),
    descriptor: addr gDescriptor)

  let pool = send0(send0(getClass("NSAutoreleasePool"), sel("alloc")), sel("init"))
  gApp = send0(getClass("NSApplication"), sel("sharedApplication"))
  cast[proc(a: Id, s: SEL, b: int) {.cdecl.}](msgSend)(gApp, sel("setActivationPolicy:"), 0)

  let delegate = makeDelegate()
  let rect = NSRect(x: 220, y: 220, w: 480, h: 300)
  gWebView = cast[proc(a: Id, s: SEL, r: NSRect): Id {.cdecl.}](msgSend)(
    send0(getClass("WKWebView"), sel("alloc")), sel("initWithFrame:"), rect)
  sendVoidId(gWebView, sel("setNavigationDelegate:"), delegate)
  cast[proc(a: Id, s: SEL, b: Id, c: Id) {.cdecl.}](msgSend)(
    gWebView, sel("loadHTMLString:baseURL:"), nsstr("<h1>blocks</h1>"), nil)

  let win = cast[proc(a: Id, s: SEL, r: NSRect, m: NSUInteger, b: NSUInteger, d: bool): Id {.cdecl.}](
    msgSend)(send0(getClass("NSWindow"), sel("alloc")),
             sel("initWithContentRect:styleMask:backing:defer:"),
             rect, NSUInteger(1 or 2 or 4 or 8), 2, false)
  sendVoidId(win, sel("setContentView:"), gWebView)
  sendVoidId(win, sel("makeKeyAndOrderFront:"), nil)
  cast[proc(a: Id, s: SEL, b: bool) {.cdecl.}](msgSend)(gApp, sel("activateIgnoringOtherApps:"), true)

  # safety
  let timer = cast[proc(a: Id, s: SEL, t: float64, target: Id, selector: SEL, info: Id, repeats: bool): Id {.cdecl.}](
    msgSend)(getClass("NSTimer"),
             sel("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"),
             5.0, delegate, sel("stop:"), nil, false)
  discard timer

  sendVoid(gApp, sel("run"))
  echo "block notified: ", gNotified
  quit(if gNotified: 0 else: 1)
