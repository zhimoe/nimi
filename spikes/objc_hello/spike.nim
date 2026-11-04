## Feasibility spike: talk to the Objective-C runtime from Nim with no cgo,
## no Objective-C source, and no external bindings.
##
## It creates an NSApplication, an NSWindow, a runtime-defined delegate class
## and an NSTimer that quits the app after one second. Build & run:
##   nim c -r --mm:orc spike.nim

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
  MsgSendVoidBool = proc(a: Id, s: SEL, b: bool) {.cdecl.}
  MsgSendVoidInt = proc(a: Id, s: SEL, b: int) {.cdecl.}
  MsgSendCString = proc(a: Id, s: SEL): cstring {.cdecl.}
  MsgSendRect = proc(a: Id, s: SEL): NSRect {.cdecl.}

const
  libobjcPath = "/usr/lib/libobjc.A.dylib"
  libAppKitPath = "/System/Library/Frameworks/AppKit.framework/AppKit"

let
  objc = loadLib(libobjcPath)
  appkit = loadLib(libAppKitPath)
  msgSend = cast[pointer](symAddr(objc, "objc_msgSend"))
  getClass = cast[proc(name: cstring): Id {.cdecl.}](symAddr(objc, "objc_getClass"))
  registerName = cast[proc(name: cstring): SEL {.cdecl.}](symAddr(objc, "sel_registerName"))

proc sel(name: string): SEL =
  registerName(name.cstring)

proc send0(o: Id, s: SEL): Id =
  cast[MsgSend0](msgSend)(o, s)

proc sendVoid(o: Id, s: SEL) =
  cast[MsgSendVoid](msgSend)(o, s)

proc sendId1(o: Id, s: SEL, b: Id): Id =
  cast[MsgSendId1](msgSend)(o, s, b)

proc nsstr(s: string): Id =
  let cls = getClass("NSString")
  let allocated = send0(cls, sel("alloc"))
  cast[proc(a: Id, s: SEL, b: cstring): Id {.cdecl.}](msgSend)(
    allocated, sel("initWithUTF8String:"), s.cstring)

# --- a class defined at runtime, with a Nim proc as its method ---------------

proc stopApp(self: Id, cmd: SEL, timer: Id) {.cdecl.} =
  discard
  # [NSApp terminate:nil]
  let app = send0(getClass("NSApplication"), sel("sharedApplication"))
  cast[MsgSendVoidId](msgSend)(app, sel("terminate:"), nil)

proc addMethod(cls: Id, name: string, imp: pointer, types: cstring): bool =
  cast[proc(c: Id, s: SEL, i: pointer, t: cstring): bool {.cdecl.}](
    symAddr(objc, "class_addMethod"))(cls, sel(name), imp, types)

proc allocateClassPair(super: Id, name: cstring, extra: uint): Id =
  cast[proc(s: Id, n: cstring, e: uint): Id {.cdecl.}](
    symAddr(objc, "objc_allocateClassPair"))(super, name, extra)

proc registerClassPair(cls: Id) =
  cast[proc(c: Id) {.cdecl.}](symAddr(objc, "objc_registerClassPair"))(cls)

proc makeDelegate(): Id =
  let nsObject = getClass("NSObject")
  let cls = allocateClassPair(nsObject, "NimiSpikeDelegate", 0)
  discard addMethod(cls, "stop:", cast[pointer](stopApp), "v@:@")
  registerClassPair(cls)
  send0(cls, sel("new"))

# --- the app ----------------------------------------------------------------

when isMainModule:
  echo "objc runtime: ", objc != nil, ", appkit: ", appkit != nil
  echo "NSString roundtrip: ", $cast[MsgSendCString](msgSend)(nsstr("hello from Nim"), sel("UTF8String"))

  let pool = send0(send0(getClass("NSAutoreleasePool"), sel("alloc")), sel("init"))

  let app = send0(getClass("NSApplication"), sel("sharedApplication"))
  cast[MsgSendVoidInt](msgSend)(app, sel("setActivationPolicy:"), 0) # Regular

  let rect = NSRect(x: 200, y: 200, w: 480, h: 320)
  let styleMask: NSUInteger = 1 or 2 or 4 or 8 # titled | closable | miniaturizable | resizable
  let winCls = getClass("NSWindow")
  let win = cast[proc(a: Id, s: SEL, r: NSRect, m: NSUInteger, b: NSUInteger, d: bool): Id {.cdecl.}](
    msgSend)(
      send0(winCls, sel("alloc")),
      sel("initWithContentRect:styleMask:backing:defer:"),
      rect, styleMask, 2, false) # backing: buffered
  cast[MsgSendVoidId](msgSend)(win, sel("setTitle:"), nsstr("Nimi feasibility spike"))
  cast[MsgSendVoidId](msgSend)(win, sel("makeKeyAndOrderFront:"), nil)
  cast[MsgSendVoidBool](msgSend)(app, sel("activateIgnoringOtherApps:"), true)

  let delegate = makeDelegate()
  # [NSTimer scheduledTimerWithTimeInterval:1 target:delegate selector:@selector(stop:) userInfo:nil repeats:NO]
  discard cast[proc(a: Id, s: SEL, t: float64, target: Id, selector: SEL, info: Id, repeats: bool): Id {.cdecl.}](
    msgSend)(
      getClass("NSTimer"),
      sel("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"),
      1.0, delegate, sel("stop:"), nil, false)

  echo "starting NSApplication run loop (window closes itself in 1s)"
  sendVoid(app, sel("run"))
  echo "run loop returned"

  cast[MsgSendVoid](msgSend)(pool, sel("drain"))
