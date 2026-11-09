## A very small Objective-C runtime layer. No cgo and no Objective-C source:
## frameworks are dlopen'ed and every message is a typed objc_msgSend call.
## Only the signatures M1 needs are declared; add typed helpers as features
## land (the ABI rule: never call objc_msgSend through varargs).

import std/[dynlib, tables]

type
  Id* = pointer
  SEL* = distinct pointer
  NSUInteger* = uint
  NSInteger* = int
  CGFloat* = float64

  NSPoint* {.bycopy.} = object
    x*, y*: CGFloat
  NSSize* {.bycopy.} = object
    w*, h*: CGFloat
  NSRect* {.bycopy.} = object
    x*, y*, w*, h*: CGFloat
  NSRange* {.bycopy.} = object
    location*, length*: NSUInteger

  MsgSend0* = proc(a: Id, s: SEL): Id {.cdecl.}
  MsgSendVoid* = proc(a: Id, s: SEL) {.cdecl.}
  MsgSendId1* = proc(a: Id, s: SEL, b: Id): Id {.cdecl.}
  MsgSendIdUInt* = proc(a: Id, s: SEL, i: NSUInteger): Id {.cdecl.}
  MsgSendIdDouble* = proc(a: Id, s: SEL, v: float64): Id {.cdecl.}
  MsgSendVoidId* = proc(a: Id, s: SEL, b: Id) {.cdecl.}
  MsgSendVoidId2* = proc(a: Id, s: SEL, b, c: Id) {.cdecl.}
  MsgSendVoidId3* = proc(a: Id, s: SEL, b, c, d: Id) {.cdecl.}
  MsgSendVoidObserver* = proc(a: Id, s: SEL, observer: Id, selector: SEL,
                              name: Id, obj: Id) {.cdecl.}
  MsgSendVoidIdBool* = proc(a: Id, s: SEL, b: Id, c: bool) {.cdecl.}
  MsgSendVoidBool* = proc(a: Id, s: SEL, b: bool) {.cdecl.}
  MsgSendVoidInt* = proc(a: Id, s: SEL, b: int) {.cdecl.}
  MsgSendVoidUInt* = proc(a: Id, s: SEL, b: NSUInteger) {.cdecl.}
  MsgSendVoidDouble* = proc(a: Id, s: SEL, b: float64) {.cdecl.}
  MsgSendVoidPoint* = proc(a: Id, s: SEL, p: NSPoint) {.cdecl.}
  MsgSendVoidSize* = proc(a: Id, s: SEL, sz: NSSize) {.cdecl.}
  MsgSendColorComponents* = proc(a: Id, s: SEL, r, g, b, alpha: ptr CGFloat): bool {.cdecl.}
  MsgSendBool* = proc(a: Id, s: SEL): bool {.cdecl.}
  MsgSendBoolId* = proc(a: Id, s: SEL, b: Id): bool {.cdecl.}
  MsgSendUInt* = proc(a: Id, s: SEL): NSUInteger {.cdecl.}
  MsgSendDouble* = proc(a: Id, s: SEL): float64 {.cdecl.}
  MsgSendCString* = proc(a: Id, s: SEL): cstring {.cdecl.}
  MsgSendRect* = proc(a: Id, s: SEL): NSRect {.cdecl.}
  MsgSendRectId* = proc(a: Id, s: SEL, r: NSRect, b: Id): NSRect {.cdecl.}
  MsgSendRectRect* = proc(a: Id, s: SEL, r: NSRect): NSRect {.cdecl.}
  MsgSendPoint* = proc(a: Id, s: SEL): NSPoint {.cdecl.}
  MsgSendInt* = proc(a: Id, s: SEL): NSInteger {.cdecl.}
  MsgSendUShort* = proc(a: Id, s: SEL): uint16 {.cdecl.}
  MsgSendMouseEvent* = proc(a: Id, s: SEL, typ: NSUInteger, loc: NSPoint,
                            flags: NSUInteger, ts: float64, win: NSInteger,
                            ctx: Id, eventNum, clickCount: NSInteger,
                            pressure: float32): Id {.cdecl.}
  MsgSendKeyEvent* = proc(a: Id, s: SEL, typ: NSUInteger, loc: NSPoint,
                          flags: NSUInteger, ts: float64, win: NSInteger,
                          ctx: Id, chars: Id, charsIgnoring: Id,
                          isARepeat: bool, keyCode: uint16): Id {.cdecl.}
  MsgSendInitWindow* = proc(a: Id, s: SEL, r: NSRect, style: NSUInteger,
                            backing: NSUInteger, deferCreation: bool): Id {.cdecl.}
  MsgSendInitView* = proc(a: Id, s: SEL, r: NSRect): Id {.cdecl.}
  MsgSendInitWebView* = proc(a: Id, s: SEL, r: NSRect, config: Id): Id {.cdecl.}
  MsgSendInitUserScript* = proc(a: Id, s: SEL, source: Id,
                                injectionTime: NSUInteger,
                                forMainFrameOnly: bool): Id {.cdecl.}
  MsgSendOtherEvent* = proc(a: Id, s: SEL, typ: NSUInteger, loc: NSPoint,
                            flags: NSUInteger, ts: float64, win: NSInteger,
                            ctx: Id, subtype: int16, data1: NSInteger,
                            data2: NSInteger): Id {.cdecl.}
  MsgSendInitMenuItem* = proc(a: Id, s: SEL, title: Id, action: SEL,
                              key: Id): Id {.cdecl.}
  MsgSendInitURLResponse* = proc(a: Id, s: SEL, url: Id, mime: Id,
                                 length: int64, encoding: Id): Id {.cdecl.}
  MsgSendDataWithBytes* = proc(a: Id, s: SEL, bytes: pointer,
                               length: NSUInteger): Id {.cdecl.}
  MsgSendScheduledTimer* = proc(a: Id, s: SEL, interval: float64,
                                target: Id, selector: SEL, info: Id,
                                repeats: bool): Id {.cdecl.}

let libobjc* = loadLib("/usr/lib/libobjc.A.dylib")
let appkit* = loadLib("/System/Library/Frameworks/AppKit.framework/AppKit")
let webkit* = loadLib("/System/Library/Frameworks/WebKit.framework/WebKit")
let foundation* = loadLib("/System/Library/Frameworks/Foundation.framework/Foundation")
let carbon* = loadLib("/System/Library/Frameworks/Carbon.framework/Carbon")
let fsevents* = loadLib("/System/Library/Frameworks/CoreServices.framework/Frameworks/FSEvents.framework/FSEvents")
let libsystem* = loadLib("/usr/lib/libSystem.B.dylib")

let
  msgSend* = cast[pointer](symAddr(libobjc, "objc_msgSend"))
  objcGetClass = cast[proc(name: cstring): Id {.cdecl.}](
    symAddr(libobjc, "objc_getClass"))
  objcRegisterName = cast[proc(name: cstring): SEL {.cdecl.}](
    symAddr(libobjc, "sel_registerName"))
  objcAllocateClassPair = cast[proc(super: Id, name: cstring,
                                    extra: uint): Id {.cdecl.}](
    symAddr(libobjc, "objc_allocateClassPair"))
  objcRegisterClassPair = cast[proc(c: Id) {.cdecl.}](
    symAddr(libobjc, "objc_registerClassPair"))
  objcClassAddMethod = cast[proc(c: Id, s: SEL, imp: pointer,
                                 types: cstring): bool {.cdecl.}](
    symAddr(libobjc, "class_addMethod"))
  objcObjectGetClass = cast[proc(o: Id): Id {.cdecl.}](
    symAddr(libobjc, "object_getClass"))
  selGetName = cast[proc(s: SEL): cstring {.cdecl.}](
    symAddr(libobjc, "sel_getName"))
  objcAutoreleasePoolPush = cast[proc(): Id {.cdecl.}](
    symAddr(libobjc, "objc_autoreleasePoolPush"))
  objcAutoreleasePoolPop = cast[proc(pool: Id) {.cdecl.}](
    symAddr(libobjc, "objc_autoreleasePoolPop"))
  pthreadMainNp = cast[proc(): cint {.cdecl.}](
    symAddr(libsystem, "pthread_main_np"))
  # dispatch_get_main_queue is an inline/macro on macOS; the exported object
  # is _dispatch_main_q. Its address is the dispatch_queue_t value.
  dispatchMainQueue = cast[pointer](symAddr(libsystem, "_dispatch_main_q"))
  dispatchAsyncF = cast[proc(q: pointer, ctx: pointer,
                             work: proc(ctx: pointer) {.cdecl.}) {.cdecl.}](
    symAddr(libsystem, "dispatch_async_f"))
  globalBlockIsa* = symAddr(libsystem, "_NSConcreteGlobalBlock")

var
  selectorCache: Table[string, SEL]
  classCache: Table[string, Id]

proc sel*(name: string): SEL =
  selectorCache.mgetOrPut(name, objcRegisterName(name.cstring))

proc cls*(name: string): Id =
  classCache.getOrDefault(name, nil)

proc loadClass*(name: string): Id =
  if name notin classCache:
    let c = objcGetClass(name.cstring)
    if c == nil:
      raise newException(ValueError, "Objective-C class not found: " & name)
    classCache[name] = c
  classCache[name]

proc isMainThread*(): bool =
  pthreadMainNp() != 0

# --- msgSend helpers -------------------------------------------------------

proc send0*(o: Id, s: SEL): Id =
  cast[MsgSend0](msgSend)(o, s)

proc sendVoid*(o: Id, s: SEL) =
  cast[MsgSendVoid](msgSend)(o, s)

proc sendId1*(o: Id, s: SEL, b: Id): Id =
  cast[MsgSendId1](msgSend)(o, s, b)

proc sendIdUInt*(o: Id, s: SEL, i: NSUInteger): Id =
  cast[MsgSendIdUInt](msgSend)(o, s, i)

proc sendIdDouble*(o: Id, s: SEL, v: float64): Id =
  cast[MsgSendIdDouble](msgSend)(o, s, v)

proc sendVoidId*(o: Id, s: SEL, b: Id) =
  cast[MsgSendVoidId](msgSend)(o, s, b)

proc sendVoidId2*(o: Id, s: SEL, b, c: Id) =
  cast[MsgSendVoidId2](msgSend)(o, s, b, c)

proc sendVoidId3*(o: Id, s: SEL, b, c, d: Id) =
  cast[MsgSendVoidId3](msgSend)(o, s, b, c, d)

proc sendAddObserver*(o: Id, observer: Id, selector: SEL, name: Id,
                      obj: Id) =
  cast[MsgSendVoidObserver](msgSend)(
    o, sel("addObserver:selector:name:object:"), observer, selector, name, obj)

proc sendVoidIdBool*(o: Id, s: SEL, b: Id, c: bool) =
  cast[MsgSendVoidIdBool](msgSend)(o, s, b, c)

proc sendVoidBool*(o: Id, s: SEL, b: bool) =
  cast[MsgSendVoidBool](msgSend)(o, s, b)

proc sendVoidInt*(o: Id, s: SEL, b: int) =
  cast[MsgSendVoidInt](msgSend)(o, s, b)

proc sendVoidUInt*(o: Id, s: SEL, b: NSUInteger) =
  cast[MsgSendVoidUInt](msgSend)(o, s, b)

proc sendVoidDouble*(o: Id, s: SEL, b: float64) =
  cast[MsgSendVoidDouble](msgSend)(o, s, b)

proc sendVoidPoint*(o: Id, s: SEL, p: NSPoint) =
  cast[MsgSendVoidPoint](msgSend)(o, s, p)

proc sendVoidSize*(o: Id, s: SEL, sz: NSSize) =
  cast[MsgSendVoidSize](msgSend)(o, s, sz)

proc sendColorComponents*(o: Id, s: SEL, r, g, b, alpha: ptr CGFloat): bool =
  cast[MsgSendColorComponents](msgSend)(o, s, r, g, b, alpha)

proc sendUInt*(o: Id, s: SEL): NSUInteger =
  cast[MsgSendUInt](msgSend)(o, s)

proc sendDouble*(o: Id, s: SEL): float64 =
  cast[MsgSendDouble](msgSend)(o, s)

proc sendBool*(o: Id, s: SEL): bool =
  cast[MsgSendBool](msgSend)(o, s)

proc sendBoolId*(o: Id, s: SEL, b: Id): bool =
  cast[MsgSendBoolId](msgSend)(o, s, b)

proc sendCString*(o: Id, s: SEL): cstring =
  cast[MsgSendCString](msgSend)(o, s)

proc sendRect*(o: Id, s: SEL): NSRect =
  cast[MsgSendRect](msgSend)(o, s)

proc sendRectId*(o: Id, s: SEL, r: NSRect, b: Id): NSRect =
  cast[MsgSendRectId](msgSend)(o, s, r, b)

proc sendRectRect*(o: Id, s: SEL, r: NSRect): NSRect =
  cast[MsgSendRectRect](msgSend)(o, s, r)

proc selName*(s: SEL): string =
  if cast[pointer](s) == nil: "" else: $selGetName(s)

proc sendPoint*(o: Id, s: SEL): NSPoint =
  cast[MsgSendPoint](msgSend)(o, s)

proc sendInt*(o: Id, s: SEL): NSInteger =
  cast[MsgSendInt](msgSend)(o, s)

proc sendUShort*(o: Id, s: SEL): uint16 =
  cast[MsgSendUShort](msgSend)(o, s)

# --- objects and strings ---------------------------------------------------

proc nsString*(s: string): Id =
  ## Convenience constructor; autoreleased. Callers run inside an AppKit
  ## event or our own pool, so the lifetime is the current call.
  cast[proc(a: Id, s: SEL, b: cstring): Id {.cdecl.}](msgSend)(
    loadClass("NSString"), sel("stringWithUTF8String:"), s.cstring)

proc nsData*(data: string): Id =
  if data.len == 0:
    return send0(loadClass("NSData"), sel("data"))
  cast[MsgSendDataWithBytes](msgSend)(
    loadClass("NSData"), sel("dataWithBytes:length:"),
    unsafeAddr data[0], NSUInteger(data.len))

proc initURLResponse*(url, mime: Id, length: int64,
                      encoding: Id): Id =
  cast[MsgSendInitURLResponse](msgSend)(
    send0(loadClass("NSURLResponse"), sel("alloc")),
    sel("initWithURL:MIMEType:expectedContentLength:textEncodingName:"),
    url, mime, length, encoding)

proc scheduledTimer*(interval: float64, target: Id, selectorName: string,
                     repeats: bool): Id =
  cast[MsgSendScheduledTimer](msgSend)(
    loadClass("NSTimer"),
    sel("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"),
    interval, target, sel(selectorName), nil, repeats)

proc nsError*(domain: string, code: int): Id =
  cast[proc(a: Id, s: SEL, d: Id, c: NSInteger, info: Id): Id {.cdecl.}](
    msgSend)(loadClass("NSError"), sel("errorWithDomain:code:userInfo:"),
    nsString(domain), NSInteger(code), nil)

proc nsURL*(s: string): Id =
  cast[proc(a: Id, s: SEL, b: Id): Id {.cdecl.}](msgSend)(
    loadClass("NSURL"), sel("URLWithString:"), nsString(s))

proc nsRequest*(url: Id): Id =
  cast[proc(a: Id, s: SEL, b: Id): Id {.cdecl.}](msgSend)(
    loadClass("NSURLRequest"), sel("requestWithURL:"), url)

proc goString*(o: Id): string =
  if o == nil:
    return ""
  let p = sendCString(o, sel("UTF8String"))
  if p == nil: "" else: $p

proc retain*(o: Id) =
  if o != nil:
    discard send0(o, sel("retain"))

proc release*(o: Id) =
  if o != nil:
    sendVoid(o, sel("release"))

proc autorelease*(o: Id) =
  if o != nil:
    discard send0(o, sel("autorelease"))

proc withPool*(body: proc()) =
  let pool = objcAutoreleasePoolPush()
  try:
    body()
  finally:
    objcAutoreleasePoolPop(pool)

# --- runtime classes -------------------------------------------------------

proc addMethod*(c: Id, name: string, imp: pointer, types: cstring): bool =
  objcClassAddMethod(c, sel(name), imp, types)

proc allocateClassPair*(super: Id, name: string, extra: uint = 0): Id =
  objcAllocateClassPair(super, name.cstring, extra)

proc registerClassPair*(c: Id) =
  objcRegisterClassPair(c)

proc registerClass*(name: string, super: Id,
                    methods: openArray[(string, pointer, string)]): Id =
  ## Idempotent: if the class already exists (hot reload, second init), reuse it.
  var c = cls(name)
  if c != nil:
    return c
  c = allocateClassPair(super, name)
  if c == nil:
    raise newException(ValueError, "cannot allocate class " & name)
  for (methodName, imp, types) in methods:
    discard addMethod(c, methodName, imp, types.cstring)
  registerClassPair(c)
  classCache[name] = c
  c

# --- dispatch --------------------------------------------------------------

proc dispatchAvailable*(): bool =
  dispatchAsyncF != nil and dispatchMainQueue != nil

proc mainDispatchQueue*(): pointer =
  dispatchMainQueue

proc dispatchAsyncMain*(work: proc(ctx: pointer) {.cdecl.}) =
  if not dispatchAvailable():
    raise newException(OSError, "libdispatch main queue is unavailable")
  dispatchAsyncF(dispatchMainQueue, nil, work)

proc nsConstant*(lib: LibHandle, name: string): Id =
  let p = symAddr(lib, name)
  if p == nil: nil else: cast[ptr Id](p)[]

proc nsNumberInt*(value: int): Id =
  cast[proc(a: Id, s: SEL, v: NSInteger): Id {.cdecl.}](msgSend)(
    loadClass("NSNumber"), sel("numberWithInteger:"), NSInteger(value))

proc nsNumberDouble*(value: float64): Id =
  cast[proc(a: Id, s: SEL, v: cdouble): Id {.cdecl.}](msgSend)(
    loadClass("NSNumber"), sel("numberWithDouble:"), cdouble(value))

proc nsNumberBool*(value: bool): Id =
  cast[proc(a: Id, s: SEL, v: bool): Id {.cdecl.}](msgSend)(
    loadClass("NSNumber"), sel("numberWithBool:"), value)

proc newEventId*(typ: NSUInteger, loc: NSPoint, flags: NSUInteger,
                 win: NSInteger, subtype: int16): Id =
  cast[MsgSendOtherEvent](msgSend)(
    loadClass("NSEvent"),
    sel("otherEventWithType:location:modifierFlags:timestamp:windowNumber:context:subtype:data1:data2:"),
    typ, loc, flags, 0.0, win, nil, subtype, 0, 0)

# Commonly used AppKit constants.
const
  NSApplicationActivationPolicyRegular* = 0
  NSApplicationActivationPolicyAccessory* = 1
  NSApplicationActivationPolicyProhibited* = 2

  NSWindowStyleMaskTitled* = NSUInteger(1 shl 0)
  NSWindowStyleMaskClosable* = NSUInteger(1 shl 1)
  NSWindowStyleMaskMiniaturizable* = NSUInteger(1 shl 2)
  NSWindowStyleMaskResizable* = NSUInteger(1 shl 3)
  NSWindowStyleMaskFullScreen* = NSUInteger(1 shl 14)

  NSBackingStoreBuffered* = NSUInteger(2)
  NSFloatingWindowLevel* = NSInteger(3)
  NSNormalWindowLevel* = NSInteger(0)
  NSAlertFirstButtonReturn* = NSInteger(1000)
  NSVariableStatusItemLength* = -1.0
  NSViewWidthSizable* = NSUInteger(1 shl 1)
  NSViewHeightSizable* = NSUInteger(1 shl 4)

  NSEventTypeApplicationDefined* = NSUInteger(15)
  NSEventModifierFlagCommand* = NSUInteger(1 shl 20)
  NSEventModifierFlagShift* = NSUInteger(1 shl 17)
  NSEventModifierFlagControl* = NSUInteger(1 shl 18)
  NSEventModifierFlagOption* = NSUInteger(1 shl 19)
  NSTerminateCancel* = NSUInteger(0)
  NSTerminateNow* = NSUInteger(1)
  WKUserScriptInjectionTimeAtDocumentStart* = NSUInteger(0)
