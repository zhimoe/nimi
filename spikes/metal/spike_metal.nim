## Feasibility spike 5: CAMetalLayer + Metal clear pass from Nim via the
## Objective-C runtime, driven by an NSTimer on the main run loop.
##   nim c -r --mm:orc spike_metal.nim
## Opens a window with a Metal layer that clears to a colour and quits.

import std/dynlib

type
  Id = pointer
  SEL = distinct pointer
  NSRect {.bycopy.} = object
    x, y, w, h: float64
  CGSize {.bycopy.} = object
    w, h: float64
  MTLClearColor {.bycopy.} = object
    r, g, b, a: float64
  NSUInteger = uint

  MsgSend0 = proc(a: Id, s: SEL): Id {.cdecl.}
  MsgSendVoid = proc(a: Id, s: SEL) {.cdecl.}
  MsgSendId1 = proc(a: Id, s: SEL, b: Id): Id {.cdecl.}
  MsgSendVoidId = proc(a: Id, s: SEL, b: Id) {.cdecl.}
  MsgSendVoidInt = proc(a: Id, s: SEL, b: int) {.cdecl.}
  MsgSendVoidUInt = proc(a: Id, s: SEL, b: NSUInteger) {.cdecl.}
  MsgSendVoidDouble = proc(a: Id, s: SEL, b: float64) {.cdecl.}
  MsgSendVoidSize = proc(a: Id, s: SEL, b: CGSize) {.cdecl.}
  MsgSendVoidColor = proc(a: Id, s: SEL, b: MTLClearColor) {.cdecl.}
  MsgSendVoidBool = proc(a: Id, s: SEL, b: bool) {.cdecl.}

let
  objc = loadLib("/usr/lib/libobjc.A.dylib")
  appkit = loadLib("/System/Library/Frameworks/AppKit.framework/AppKit")
  quartz = loadLib("/System/Library/Frameworks/QuartzCore.framework/QuartzCore")
  metal = loadLib("/System/Library/Frameworks/Metal.framework/Metal")
  msgSend = cast[pointer](symAddr(objc, "objc_msgSend"))
  getClass = cast[proc(name: cstring): Id {.cdecl.}](symAddr(objc, "objc_getClass"))
  registerName = cast[proc(name: cstring): SEL {.cdecl.}](symAddr(objc, "sel_registerName"))
  createDevice = cast[proc(): Id {.cdecl.}](symAddr(metal, "MTLCreateSystemDefaultDevice"))

proc sel(name: string): SEL = registerName(name.cstring)
proc send0(o: Id, s: SEL): Id = cast[MsgSend0](msgSend)(o, s)
proc sendVoid(o: Id, s: SEL) = cast[MsgSendVoid](msgSend)(o, s)
proc sendId1(o: Id, s: SEL, b: Id): Id = cast[MsgSendId1](msgSend)(o, s, b)
proc sendVoidId(o: Id, s: SEL, b: Id) = cast[MsgSendVoidId](msgSend)(o, s, b)

var
  gApp, gWindow, gView, gLayer, gQueue: Id
  gFrames = 0
  gDrew = false

proc drawFrame(self: Id, cmd: SEL, timer: Id) {.cdecl.} =
  let drawable = send0(gLayer, sel("nextDrawable"))
  if gFrames == 0: echo "first nextDrawable non-nil: ", drawable != nil
  if drawable == nil:
    echo "nextDrawable returned nil"
    return
  let texture = send0(drawable, sel("texture"))
  let cb = send0(gQueue, sel("commandBuffer"))
  let desc = send0(getClass("MTLRenderPassDescriptor"), sel("renderPassDescriptor"))
  let attachments = send0(desc, sel("colorAttachments"))
  let att = cast[proc(a: Id, s: SEL, i: NSUInteger): Id {.cdecl.}](msgSend)(
    attachments, sel("objectAtIndexedSubscript:"), 0)
  sendVoidId(att, sel("setTexture:"), texture)
  cast[MsgSendVoidUInt](msgSend)(att, sel("setLoadAction:"), 2)  # clear
  cast[MsgSendVoidUInt](msgSend)(att, sel("setStoreAction:"), 1) # store
  let color = MTLClearColor(r: 0.10, g: 0.35, b: 0.85, a: 1.0)
  cast[MsgSendVoidColor](msgSend)(att, sel("setClearColor:"), color)
  let enc = sendId1(cb, sel("renderCommandEncoderWithDescriptor:"), desc)
  sendVoid(enc, sel("endEncoding"))
  sendVoidId(cb, sel("presentDrawable:"), drawable)
  sendVoid(cb, sel("commit"))
  inc gFrames
  gDrew = true
  if gFrames >= 20:
    echo "drew 20 frames; clear colour presented"
    sendVoid(timer, sel("invalidate"))
    sendVoidId(gApp, sel("terminate:"), nil)

proc stopApp(self: Id, cmd: SEL, timer: Id) {.cdecl.} =
  echo "safety timer: quitting"
  sendVoidId(gApp, sel("terminate:"), nil)

proc addMethod(cls: Id, name: string, imp: pointer, types: cstring): bool =
  cast[proc(c: Id, s: SEL, i: pointer, t: cstring): bool {.cdecl.}](
    symAddr(objc, "class_addMethod"))(cls, sel(name), imp, types)

proc makeHandler(): Id =
  let cls = cast[proc(s: Id, n: cstring, e: uint): Id {.cdecl.}](
    symAddr(objc, "objc_allocateClassPair"))(getClass("NSObject"), "NimiMetalSpike", 0)
  discard addMethod(cls, "draw:", cast[pointer](drawFrame), "v@:@")
  discard addMethod(cls, "stop:", cast[pointer](stopApp), "v@:@")
  cast[proc(c: Id) {.cdecl.}](symAddr(objc, "objc_registerClassPair"))(cls)
  send0(cls, sel("new"))

when isMainModule:
  echo "metal loaded: ", metal != nil, ", quartz: ", quartz != nil
  let pool = send0(send0(getClass("NSAutoreleasePool"), sel("alloc")), sel("init"))
  gApp = send0(getClass("NSApplication"), sel("sharedApplication"))
  cast[MsgSendVoidInt](msgSend)(gApp, sel("setActivationPolicy:"), 0)

  let device = createDevice()
  doAssert device != nil, "no Metal device"
  gQueue = send0(device, sel("newCommandQueue"))
  doAssert gQueue != nil, "no command queue"

  let rect = NSRect(x: 200, y: 200, w: 640, h: 360)
  gWindow = cast[proc(a: Id, s: SEL, r: NSRect, m: NSUInteger, b: NSUInteger, d: bool): Id {.cdecl.}](
    msgSend)(send0(getClass("NSWindow"), sel("alloc")),
             sel("initWithContentRect:styleMask:backing:defer:"),
             rect, NSUInteger(1 or 2 or 4 or 8), 2, false)
  gView = cast[proc(a: Id, s: SEL, r: NSRect): Id {.cdecl.}](
    msgSend)(send0(getClass("NSView"), sel("alloc")), sel("initWithFrame:"),
             NSRect(x: 0, y: 0, w: 640, h: 360))
  cast[MsgSendVoidBool](msgSend)(gView, sel("setWantsLayer:"), true)

  gLayer = send0(getClass("CAMetalLayer"), sel("layer"))
  sendVoidId(gLayer, sel("setDevice:"), device)
  cast[MsgSendVoidUInt](msgSend)(gLayer, sel("setPixelFormat:"), 80) # BGRA8Unorm
  cast[MsgSendVoidSize](msgSend)(gLayer, sel("setDrawableSize:"), CGSize(w: 1280, h: 720))
  cast[MsgSendVoidDouble](msgSend)(gLayer, sel("setContentsScale:"), 2.0)
  sendVoidId(gView, sel("setLayer:"), gLayer)
  sendVoidId(gWindow, sel("setContentView:"), gView)
  let title = cast[proc(a: Id, s: SEL, b: cstring): Id {.cdecl.}](msgSend)(
    send0(getClass("NSString"), sel("alloc")), sel("initWithUTF8String:"),
    "Nimi Metal spike")
  sendVoidId(gWindow, sel("setTitle:"), title)
  sendVoidId(gWindow, sel("makeKeyAndOrderFront:"), nil)
  cast[MsgSendVoidBool](msgSend)(gApp, sel("activateIgnoringOtherApps:"), true)

  let handler = makeHandler()
  discard cast[proc(a: Id, s: SEL, t: float64, target: Id, selector: SEL, info: Id, repeats: bool): Id {.cdecl.}](
    msgSend)(getClass("NSTimer"),
             sel("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"),
             1.0 / 30.0, handler, sel("draw:"), nil, true)
  discard cast[proc(a: Id, s: SEL, t: float64, target: Id, selector: SEL, info: Id, repeats: bool): Id {.cdecl.}](
    msgSend)(getClass("NSTimer"),
             sel("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"),
             5.0, handler, sel("stop:"), nil, false)

  echo "running; expected 20 Metal frames"
  sendVoid(gApp, sel("run"))
  echo "frames drawn: ", gFrames, ", drew: ", gDrew
  quit(if gDrew: 0 else: 1)
