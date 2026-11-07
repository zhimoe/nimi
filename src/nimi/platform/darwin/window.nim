## NSWindow + WKWebView + the runtime-defined delegate that receives page
## messages and window close events.

import std/[monotimes, strutils, tables]

import ../contract
import ../../core/bridge
import ./[objc, protocol, types]

const
  NimiMessageHandlerName = "nimi"
  NimiWindowDelegateClass = "NimiWindowDelegate"

var imeHandled = false

proc windowLookupId(delegate: Id): uint64 =
  if gState == nil:
    return 0
  gState.delegateToId.getOrDefault(delegate, 0'u64)

# --- runtime delegate methods ---------------------------------------------

proc windowShouldClose(self: Id, cmd: SEL, sender: Id): bool {.cdecl.} =
  let id = windowLookupId(self)
  if id == 0:
    return true
  let h = gState.windowHandlers.getOrDefault(id)
  if h.shouldClose == nil:
    return true
  result = h.shouldClose(id)

proc windowWillClose(self: Id, cmd: SEL, notification: Id) {.cdecl.} =
  let id = windowLookupId(self)
  if id == 0:
    return
  if gState.windowTimers.hasKey(id):
    let timer = gState.windowTimers[id]
    if timer != nil:
      sendVoid(timer, sel("invalidate"))
    gState.windowTimers.del(id)
  gState.animationLast.del(id)
  let surfaceView = gState.surfaceViews.getOrDefault(id)
  if surfaceView != nil:
    let ctx = gState.inputContexts.getOrDefault(surfaceView)
    if ctx != nil:
      gState.inputContexts.del(surfaceView)
      release(ctx)
  let h = gState.windowHandlers.getOrDefault(id)
  if h.closed != nil:
    h.closed(id)
  gState.windowHandlers.del(id)
  gState.delegateToId.del(self)
  gState.webViews.del(id)
  gState.userContentControllers.del(id)
  gState.windowDelegates.del(id)
  if surfaceView != nil:
    gState.surfaceToId.del(surfaceView)
  gState.surfaceViews.del(id)
  gState.surfaceHandlers.del(id)
  gState.imeWindows.del(id)
  releaseSchemeHandler(id)

proc didReceiveScriptMessage(self: Id, cmd: SEL, controller: Id,
                             message: Id) {.cdecl.} =
  let id = windowLookupId(self)
  if id == 0:
    return
  let body = send0(message, sel("body"))
  let text = goString(body)
  let h = gState.windowHandlers.getOrDefault(id)
  if h.message != nil:
    h.message(id, text)

proc didFinishNavigation(self: Id, cmd: SEL, webView: Id,
                         navigation: Id) {.cdecl.} =
  discard

proc windowAnimationTick(self: Id, cmd: SEL, timer: Id) {.cdecl.} =
  if gState == nil:
    return
  let id = windowLookupId(self)
  if id == 0:
    return
  let h = gState.windowHandlers.getOrDefault(id)
  if h.frame == nil:
    return
  let now = getMonoTime().ticks.float64 / 1_000_000_000.0
  let last = gState.animationLast.getOrDefault(id, now)
  gState.animationLast[id] = now
  let dt = if last <= 0: 0.0 else: now - last
  h.frame(id, now, dt)

proc windowDidBecomeKey(self: Id, cmd: SEL, notification: Id) {.cdecl.} =
  let id = windowLookupId(self)
  if id == 0:
    return
  let h = gState.windowHandlers.getOrDefault(id)
  if h.focused != nil:
    h.focused(id)

proc windowDidResignKey(self: Id, cmd: SEL, notification: Id) {.cdecl.} =
  let id = windowLookupId(self)
  if id == 0:
    return
  let h = gState.windowHandlers.getOrDefault(id)
  if h.blurred != nil:
    h.blurred(id)

proc windowDidBecomeMain(self: Id, cmd: SEL, notification: Id) {.cdecl.} =
  windowDidBecomeKey(self, cmd, notification)

proc windowDidResignMain(self: Id, cmd: SEL, notification: Id) {.cdecl.} =
  windowDidResignKey(self, cmd, notification)

proc appKitOrigin(win: Id, x, y: int): NSPoint =
  ## Nimi window coordinates are top-left relative to the primary display;
  ## AppKit window origins are bottom-left in screen coordinates.
  let frame = sendRect(win, sel("frame"))
  let list = send0(loadClass("NSScreen"), sel("screens"))
  if list != nil and int(sendInt(list, sel("count"))) > 0:
    let first = sendIdUInt(list, sel("objectAtIndex:"), NSUInteger(0))
    let primary = sendRect(first, sel("frame"))
    return NSPoint(
      x: primary.x + CGFloat(x),
      y: primary.y + primary.h - CGFloat(y) - frame.h)
  result = NSPoint(x: CGFloat(x), y: CGFloat(y))

# --- native UI surface -----------------------------------------------------

proc surfaceDraw(self: Id, cmd: SEL, dirty: NSRect) {.cdecl.} =
  let id = if gState != nil: gState.surfaceToId.getOrDefault(self, 0'u64) else: 0'u64
  if id == 0:
    return
  let h = gState.surfaceHandlers.getOrDefault(id)
  if h.draw == nil:
    return
  let context = send0(loadClass("NSGraphicsContext"), sel("currentContext"))
  if context == nil:
    return
  let port = send0(context, sel("graphicsPort"))
  let bounds = sendRect(self, sel("bounds"))
  h.draw(port, float32(bounds.w), float32(bounds.h))

proc surfaceAcceptsFirstResponder(self: Id, cmd: SEL): bool {.cdecl.} =
  result = true

proc surfaceMouseEvent(self: Id, event: Id, kind: int) =
  if gState == nil:
    return
  let id = gState.surfaceToId.getOrDefault(self, 0'u64)
  if id == 0:
    return
  let h = gState.surfaceHandlers.getOrDefault(id)
  let p = sendPoint(event, sel("locationInWindow"))
  let bounds = sendRect(self, sel("bounds"))
  let x = float32(p.x)
  let y = float32(bounds.h - p.y)
  case kind
  of 0:
    if h.mouseDown != nil: h.mouseDown(x, y, 1)
  of 1:
    if h.mouseUp != nil: h.mouseUp(x, y)
  else:
    if h.mouseMoved != nil: h.mouseMoved(x, y)

proc surfaceAcceptsFirstMouse(self: Id, cmd: SEL, event: Id): bool {.cdecl.} =
  result = true

proc surfaceMouseDown(self: Id, cmd: SEL, event: Id) {.cdecl.} =
  if gState == nil:
    return
  let id = gState.surfaceToId.getOrDefault(self, 0'u64)
  if id == 0:
    return
  let h = gState.surfaceHandlers.getOrDefault(id)
  if h.mouseDown == nil:
    return
  let p = sendPoint(event, sel("locationInWindow"))
  let bounds = sendRect(self, sel("bounds"))
  h.mouseDown(float32(p.x), float32(bounds.h - p.y),
              int(sendInt(event, sel("clickCount"))))

proc surfaceMouseUp(self: Id, cmd: SEL, event: Id) {.cdecl.} =
  surfaceMouseEvent(self, event, 1)

proc surfaceMouseDragged(self: Id, cmd: SEL, event: Id) {.cdecl.} =
  surfaceMouseEvent(self, event, 2)

proc surfaceMouseMoved(self: Id, cmd: SEL, event: Id) {.cdecl.} =
  surfaceMouseEvent(self, event, 2)

proc surfaceScrollWheel(self: Id, cmd: SEL, event: Id) {.cdecl.} =
  if gState == nil:
    return
  let id = gState.surfaceToId.getOrDefault(self, 0'u64)
  if id == 0:
    return
  let h = gState.surfaceHandlers.getOrDefault(id)
  if h.scroll == nil:
    return
  let p = sendPoint(event, sel("locationInWindow"))
  let bounds = sendRect(self, sel("bounds"))
  h.scroll(float32(p.x), float32(bounds.h - p.y),
           float32(sendDouble(event, sel("scrollingDeltaY"))))

proc keyName*(keyCode: int, chars: string): string =
  case keyCode
  of 126: "up"
  of 125: "down"
  of 123: "left"
  of 124: "right"
  of 36: "enter"
  of 49: "space"
  of 48: "tab"
  of 53: "escape"
  of 51: "backspace"
  of 117: "delete"
  of 115: "home"
  of 119: "end"
  of 116: "pageup"
  of 121: "pagedown"
  else: chars

proc surfaceHandlerFor(self: Id): SurfaceHandler =
  if gState == nil:
    return
  let id = gState.surfaceToId.getOrDefault(self, 0'u64)
  if id == 0:
    return
  result = gState.surfaceHandlers.getOrDefault(id)

proc imeString(obj: Id): string =
  if obj == nil:
    return ""
  let responds = cast[proc(a: Id, s: SEL, b: SEL): bool {.cdecl.}](msgSend)(
    obj, sel("respondsToSelector:"), sel("string"))
  if responds:
    goString(send0(obj, sel("string")))
  else:
    goString(obj)

proc toTextRange(r: NSRange): TextRange =
  if r.location == high(NSUInteger):
    NoTextRange
  else:
    TextRange(location: int(r.location), length: int(r.length))

proc toNSRange(r: TextRange): NSRange =
  if r.location < 0:
    NSRange(location: high(NSUInteger), length: 0)
  else:
    NSRange(location: NSUInteger(r.location),
            length: NSUInteger(max(0, r.length)))

proc surfaceInsertText(self: Id, cmd: SEL, text: Id,
                       range: NSRange) {.cdecl.} =
  imeHandled = true
  when defined(nimiImeDebug): echo "insertText: ", imeString(text)
  let h = self.surfaceHandlerFor()
  if h.insertText != nil:
    h.insertText(imeString(text), toTextRange(range))

proc surfaceSetMarkedText(self: Id, cmd: SEL, text: Id, selected: NSRange,
                          replacement: NSRange) {.cdecl.} =
  imeHandled = true
  when defined(nimiImeDebug):
    let s = toTextRange(selected)
    let r = toTextRange(replacement)
    echo "setMarkedText: ", imeString(text), " selected=", s.location, "+",
         s.length, " replacement=", r.location, "+", r.length
  let h = self.surfaceHandlerFor()
  if h.setMarkedText != nil:
    h.setMarkedText(imeString(text), toTextRange(selected),
                    toTextRange(replacement))

proc surfaceUnmarkText(self: Id, cmd: SEL) {.cdecl.} =
  imeHandled = true
  let h = self.surfaceHandlerFor()
  if h.unmarkText != nil:
    h.unmarkText()

proc surfaceHasMarkedText(self: Id, cmd: SEL): bool {.cdecl.} =
  let h = self.surfaceHandlerFor()
  result = h.hasMarkedText != nil and h.hasMarkedText()

proc surfaceMarkedRange(self: Id, cmd: SEL): NSRange {.cdecl.} =
  let h = self.surfaceHandlerFor()
  if h.markedRange != nil:
    result = toNSRange(h.markedRange())
  else:
    result = NSRange(location: high(NSUInteger), length: 0)

proc surfaceSelectedRange(self: Id, cmd: SEL): NSRange {.cdecl.} =
  let h = self.surfaceHandlerFor()
  if h.selectedRange != nil:
    result = toNSRange(h.selectedRange())
  else:
    result = NSRange(location: 0, length: 0)

proc surfaceValidAttributes(self: Id, cmd: SEL): Id {.cdecl.} =
  result = send0(loadClass("NSArray"), sel("array"))

proc surfaceAttributedSubstring(self: Id, cmd: SEL, range: NSRange,
                                actual: ptr NSRange): Id {.cdecl.} =
  let h = self.surfaceHandlerFor()
  if range.location == high(NSUInteger) or h.attributedSubstring == nil:
    return nil
  let total = if h.textLength != nil: h.textLength() else: 0
  let start = max(0, min(int(range.location), total))
  let finish = max(start, min(start + int(range.length), total))
  let text = h.attributedSubstring(
    TextRange(location: start, length: finish - start))
  if actual != nil:
    actual[] = NSRange(location: NSUInteger(start),
                       length: NSUInteger(finish - start))
  let attributed = sendId1(
    send0(loadClass("NSAttributedString"), sel("alloc")),
    sel("initWithString:"), nsString(text))
  if attributed != nil:
    autorelease(attributed)
  result = attributed

proc surfaceFirstRect(self: Id, cmd: SEL, range: NSRange,
                      actual: ptr NSRange): NSRect {.cdecl.} =
  let h = self.surfaceHandlerFor()
  if h.caretRect == nil:
    return NSRect(x: 0, y: 0, w: 1, h: 1)
  let r = h.caretRect()
  let bounds = sendRect(self, sel("bounds"))
  let viewRect = NSRect(
    x: CGFloat(r.x),
    y: CGFloat(bounds.h - r.y - r.h),
    w: CGFloat(r.w), h: CGFloat(r.h))
  let win = send0(self, sel("window"))
  var screenRect = viewRect
  if win != nil:
    let windowRect = sendRectId(self, sel("convertRect:toView:"), viewRect, nil)
    screenRect = sendRectRect(win, sel("convertRectToScreen:"), windowRect)
  if actual != nil:
    actual[] = if range.location == high(NSUInteger):
      NSRange(location: 0, length: 0)
    else:
      range
  result = screenRect

proc surfaceCharacterIndex(self: Id, cmd: SEL,
                           point: NSPoint): NSUInteger {.cdecl.} =
  let h = self.surfaceHandlerFor()
  if h.characterIndexAt == nil:
    return 0
  let bounds = sendRect(self, sel("bounds"))
  let index = h.characterIndexAt(float32(point.x),
                                 float32(bounds.h - point.y))
  result = NSUInteger(max(0, index))

proc surfaceDoCommand(self: Id, cmd: SEL, selector: SEL) {.cdecl.} =
  when defined(nimiImeDebug): echo "doCommand: ", selName(selector)
  let h = self.surfaceHandlerFor()
  imeHandled = h.command != nil and h.command(selName(selector))

proc surfaceInputContext(self: Id, cmd: SEL): Id {.cdecl.} =
  when defined(nimiImeDebug): echo "inputContext called"
  if gState == nil:
    return nil
  if gState.inputContexts.hasKey(self):
    return gState.inputContexts[self]
  let cls = loadClass("NSTextInputContext")
  let ctx = sendId1(send0(cls, sel("alloc")),
                    sel("initWithClient:"), self)
  if ctx != nil:
    retain(ctx)
    gState.inputContexts[self] = ctx
  result = ctx

proc surfaceCopy(self: Id, cmd: SEL, sender: Id) {.cdecl.} =
  when defined(nimiClipDebug): echo "surfaceCopy"
  if gState == nil: return
  let id = gState.surfaceToId.getOrDefault(self, 0'u64)
  let h = gState.surfaceHandlers.getOrDefault(id)
  if h.copy != nil: h.copy()

proc surfaceCut(self: Id, cmd: SEL, sender: Id) {.cdecl.} =
  if gState == nil: return
  let id = gState.surfaceToId.getOrDefault(self, 0'u64)
  let h = gState.surfaceHandlers.getOrDefault(id)
  if h.cut != nil: h.cut()

proc surfacePaste(self: Id, cmd: SEL, sender: Id) {.cdecl.} =
  when defined(nimiClipDebug): echo "surfacePaste"
  if gState == nil: return
  let id = gState.surfaceToId.getOrDefault(self, 0'u64)
  let h = gState.surfaceHandlers.getOrDefault(id)
  if h.paste != nil: h.paste()

proc surfaceSelectAll(self: Id, cmd: SEL, sender: Id) {.cdecl.} =
  when defined(nimiClipDebug): echo "surfaceSelectAll"
  if gState == nil: return
  let id = gState.surfaceToId.getOrDefault(self, 0'u64)
  let h = gState.surfaceHandlers.getOrDefault(id)
  if h.selectAll != nil: h.selectAll()

proc surfaceUndo(self: Id, cmd: SEL, sender: Id) {.cdecl.} =
  if gState == nil: return
  let id = gState.surfaceToId.getOrDefault(self, 0'u64)
  let h = gState.surfaceHandlers.getOrDefault(id)
  if h.undo != nil: h.undo()

proc surfaceRedo(self: Id, cmd: SEL, sender: Id) {.cdecl.} =
  if gState == nil: return
  let id = gState.surfaceToId.getOrDefault(self, 0'u64)
  let h = gState.surfaceHandlers.getOrDefault(id)
  if h.redo != nil: h.redo()

proc surfaceKeyDown(self: Id, cmd: SEL, event: Id) {.cdecl.} =
  if gState == nil:
    return
  let id = gState.surfaceToId.getOrDefault(self, 0'u64)
  if id == 0:
    return
  let h = gState.surfaceHandlers.getOrDefault(id)
  if gState.imeWindows.getOrDefault(id, false):
    when defined(nimiImeDebug): echo "ime keydown: ", goString(send0(event, sel("characters")))
    let events = sendId1(loadClass("NSArray"), sel("arrayWithObject:"), event)
    if events != nil:
      imeHandled = false
      sendVoidId(self, sel("interpretKeyEvents:"), events)
      if imeHandled:
        return
      when defined(nimiImeDebug): echo "ime fallback"
  if h.keyDown == nil:
    return
  let chars = goString(send0(event, sel("characters")))
  let code = int(sendUShort(event, sel("keyCode")))
  let flags = sendUInt(event, sel("modifierFlags"))
  var mods = 0'u32
  if (flags and NSEventModifierFlagShift) != 0: mods = mods or KeyShift
  if (flags and NSEventModifierFlagControl) != 0: mods = mods or KeyControl
  if (flags and NSEventModifierFlagOption) != 0: mods = mods or KeyAlt
  if (flags and NSEventModifierFlagCommand) != 0: mods = mods or KeyCommand
  h.keyDown(keyName(code, chars), mods)

proc surfaceClass(): Id =
  registerClass("NimiSurfaceView", loadClass("NSView"), [
    ("drawRect:", cast[pointer](surfaceDraw),
      "v@:{CGRect={CGPoint=dd}{CGSize=dd}}"),
    ("acceptsFirstResponder:", cast[pointer](surfaceAcceptsFirstResponder), "c@:"),
    ("acceptsFirstMouse:", cast[pointer](surfaceAcceptsFirstMouse), "c@:@"),
    ("mouseDown:", cast[pointer](surfaceMouseDown), "v@:@"),
    ("mouseUp:", cast[pointer](surfaceMouseUp), "v@:@"),
    ("mouseDragged:", cast[pointer](surfaceMouseDragged), "v@:@"),
    ("mouseMoved:", cast[pointer](surfaceMouseMoved), "v@:@"),
    ("scrollWheel:", cast[pointer](surfaceScrollWheel), "v@:@"),
    ("keyDown:", cast[pointer](surfaceKeyDown), "v@:@"),
    ("copy:", cast[pointer](surfaceCopy), "v@:@"),
    ("cut:", cast[pointer](surfaceCut), "v@:@"),
    ("paste:", cast[pointer](surfacePaste), "v@:@"),
    ("selectAll:", cast[pointer](surfaceSelectAll), "v@:@"),
    ("undo:", cast[pointer](surfaceUndo), "v@:@"),
    ("redo:", cast[pointer](surfaceRedo), "v@:@"),
    ("insertText:replacementRange:",
      cast[pointer](surfaceInsertText), "v@:@{_NSRange=QQ}"),
    ("setMarkedText:selectedRange:replacementRange:",
      cast[pointer](surfaceSetMarkedText), "v@:@{_NSRange=QQ}{_NSRange=QQ}"),
    ("unmarkText", cast[pointer](surfaceUnmarkText), "v@:"),
    ("hasMarkedText", cast[pointer](surfaceHasMarkedText), "c@:"),
    ("markedRange", cast[pointer](surfaceMarkedRange), "{_NSRange=QQ}@:"),
    ("selectedRange", cast[pointer](surfaceSelectedRange), "{_NSRange=QQ}@:"),
    ("validAttributesForMarkedText",
      cast[pointer](surfaceValidAttributes), "@@:"),
    ("attributedSubstringForProposedRange:actualRange:",
      cast[pointer](surfaceAttributedSubstring),
      "@@:{_NSRange=QQ}^{_NSRange=QQ}"),
    ("firstRectForCharacterRange:actualRange:",
      cast[pointer](surfaceFirstRect),
      "{CGRect={CGPoint=dd}{CGSize=dd}}@:{_NSRange=QQ}^{_NSRange=QQ}"),
    ("characterIndexForPoint:", cast[pointer](surfaceCharacterIndex),
      "Q@:{CGPoint=dd}"),
    ("doCommandBySelector:", cast[pointer](surfaceDoCommand), "v@::"),
    ("inputContext", cast[pointer](surfaceInputContext), "@@:"),
  ])

proc delegateClass(): Id =
  registerClass(NimiWindowDelegateClass, loadClass("NSObject"), [
    ("windowShouldClose:", cast[pointer](windowShouldClose), "c@:@"),
    ("windowWillClose:", cast[pointer](windowWillClose), "v@:@"),
    ("userContentController:didReceiveScriptMessage:",
      cast[pointer](didReceiveScriptMessage), "v@:@@"),
    ("webView:didFinishNavigation:", cast[pointer](didFinishNavigation), "v@:@@"),
    ("windowDidBecomeKey:", cast[pointer](windowDidBecomeKey), "v@:@"),
    ("windowDidResignKey:", cast[pointer](windowDidResignKey), "v@:@"),
    ("windowDidBecomeMain:", cast[pointer](windowDidBecomeMain), "v@:@"),
    ("windowDidResignMain:", cast[pointer](windowDidResignMain), "v@:@"),
    ("animationTick:", cast[pointer](windowAnimationTick), "v@:@"),
  ])

proc keyTextForCode(keyCode: int): string =
  case keyCode
  of 0: "a"
  of 1: "s"
  of 2: "d"
  of 3: "f"
  of 4: "h"
  of 5: "g"
  of 6: "z"
  of 7: "x"
  of 8: "c"
  of 9: "v"
  of 11: "b"
  of 12: "q"
  of 13: "w"
  of 14: "e"
  of 15: "r"
  of 16: "y"
  of 17: "t"
  of 31: "o"
  of 32: "u"
  of 34: "i"
  of 35: "p"
  of 37: "l"
  of 38: "j"
  of 40: "k"
  of 45: "n"
  of 46: "m"
  of 49: " "
  else: ""

# --- window creation -------------------------------------------------------

proc createWindow*(state: DarwinState, opts: PlatformWindowOptions,
                   h: WindowHandler): NativeWindow =
  let id = h.windowId
  var style = NSWindowStyleMaskTitled or NSWindowStyleMaskClosable or
              NSWindowStyleMaskMiniaturizable
  if opts.resizable:
    style = style or NSWindowStyleMaskResizable

  let frame = NSRect(x: 100, y: 100,
                     w: float64(if opts.width > 0: opts.width else: 800),
                     h: float64(if opts.height > 0: opts.height else: 600))
  let win = cast[MsgSendInitWindow](msgSend)(
    send0(loadClass("NSWindow"), sel("alloc")),
    sel("initWithContentRect:styleMask:backing:defer:"),
    frame, style, NSBackingStoreBuffered, false)
  if win == nil:
    raise newException(BackendError, "cannot create NSWindow")
  sendVoidBool(win, sel("setReleasedWhenClosed:"), false)
  sendVoidId(win, sel("setTitle:"), nsString(opts.title))

  let delegate = send0(delegateClass(), sel("new"))
  state.windowHandlers[id] = h
  state.imeWindows[id] = opts.ime
  state.delegateToId[delegate] = id
  state.windowDelegates[id] = delegate

  var webView: Id = nil
  var surfaceView: Id = nil

  if opts.content:
    let viewClass = surfaceClass()
    let view = cast[MsgSendInitView](msgSend)(
      send0(viewClass, sel("alloc")),
      sel("initWithFrame:"), NSRect(x: 0, y: 0, w: frame.w, h: frame.h))
    sendVoidUInt(view, sel("setAutoresizingMask:"),
                 NSViewWidthSizable or NSViewHeightSizable)
    state.surfaceHandlers[id] = h.surface
    state.surfaceViews[id] = view
    state.surfaceToId[view] = id
    sendVoidId(win, sel("setContentView:"), view)
    sendVoidId(win, sel("makeFirstResponder:"), view)
    sendVoidBool(win, sel("setAcceptsMouseMovedEvents:"), true)
    surfaceView = view
  else:
    let config = send0(loadClass("WKWebViewConfiguration"), sel("new"))
    let dataStore =
      if opts.ephemeral:
        send0(loadClass("WKWebsiteDataStore"), sel("nonPersistentDataStore"))
      else:
        send0(loadClass("WKWebsiteDataStore"), sel("defaultDataStore"))
    if dataStore != nil:
      sendVoidId(config, sel("setWebsiteDataStore:"), dataStore)
    if opts.scheme.len > 0 and opts.fileRoot.len > 0:
      discard attachSchemeHandler(config, opts.scheme, opts.fileRoot, id)
    let ucc = send0(config, sel("userContentController"))
    sendVoidId2(ucc, sel("addScriptMessageHandler:name:"), delegate,
                nsString(NimiMessageHandlerName))
    let scriptSource = bridgeJs
      .replace("__NIMI_SECRET__", opts.secret)
      .replace("__NIMI_TOKEN__", opts.token)
    let userScript = cast[MsgSendInitUserScript](msgSend)(
      send0(loadClass("WKUserScript"), sel("alloc")),
      sel("initWithSource:injectionTime:forMainFrameOnly:"),
      nsString(scriptSource), WKUserScriptInjectionTimeAtDocumentStart, true)
    sendVoidId(ucc, sel("addUserScript:"), userScript)
    release(userScript)

    webView = cast[MsgSendInitWebView](msgSend)(
      send0(loadClass("WKWebView"), sel("alloc")),
      sel("initWithFrame:configuration:"),
      NSRect(x: 0, y: 0, w: frame.w, h: frame.h), config)
    if webView == nil:
      raise newException(BackendError, "cannot create WKWebView")
    sendVoidId(webView, sel("setNavigationDelegate:"), delegate)
    sendVoidUInt(webView, sel("setAutoresizingMask:"),
                 NSViewWidthSizable or NSViewHeightSizable)
    sendVoidId(win, sel("setContentView:"), webView)
    state.webViews[id] = webView
    state.userContentControllers[id] = ucc

    if opts.html.len > 0:
      sendVoidId2(webView, sel("loadHTMLString:baseURL:"), nsString(opts.html), nil)
    elif opts.url.len > 0:
      sendVoidId(webView, sel("loadRequest:"), nsRequest(nsURL(opts.url)))

  sendVoidId(win, sel("setDelegate:"), delegate)
  sendVoidId(win, sel("makeKeyAndOrderFront:"), nil)
  sendVoidBool(state.nsApp, sel("activateIgnoringOtherApps:"), true)

  result = NativeWindow()
  result.id = id
  result.setTitle = proc(title: string) =
    sendVoidId(win, sel("setTitle:"), nsString(title))
  result.show = proc() =
    sendVoidId(win, sel("makeKeyAndOrderFront:"), nil)
    sendVoidBool(state.nsApp, sel("activateIgnoringOtherApps:"), true)
  result.close = proc() =
    sendVoid(win, sel("close"))
  result.hide = proc() =
    sendVoidId(win, sel("orderOut:"), nil)
  result.focus = proc() =
    sendVoidId(win, sel("makeKeyAndOrderFront:"), nil)
    sendVoidBool(state.nsApp, sel("activateIgnoringOtherApps:"), true)
  result.center = proc() =
    sendVoid(win, sel("center"))
  result.minimize = proc() =
    sendVoidId(win, sel("miniaturize:"), nil)
  result.deminimize = proc() =
    sendVoid(win, sel("deminiaturize:"))
  result.zoom = proc() =
    sendVoidId(win, sel("performZoom:"), nil)
  result.toggleFullScreen = proc() =
    sendVoidId(win, sel("toggleFullScreen:"), nil)
  result.isFullScreen = proc(): bool =
    result = (sendUInt(win, sel("styleMask")) and
              NSWindowStyleMaskFullScreen) != 0
  result.isFocused = proc(): bool =
    result = sendBool(win, sel("isKeyWindow"))
  result.setSize = proc(width, height: int) =
    sendVoidSize(win, sel("setContentSize:"),
                 NSSize(w: CGFloat(width), h: CGFloat(height)))
  result.setPosition = proc(x, y: int) =
    sendVoidPoint(win, sel("setFrameOrigin:"), appKitOrigin(win, x, y))
  result.setResizable = proc(resizable: bool) =
    var mask = sendUInt(win, sel("styleMask"))
    if resizable:
      mask = mask or NSWindowStyleMaskResizable
    else:
      mask = mask and not NSWindowStyleMaskResizable
    sendVoidUInt(win, sel("setStyleMask:"), mask)
  result.setAlwaysOnTop = proc(always: bool) =
    sendVoidInt(win, sel("setLevel:"),
                if always: int(NSFloatingWindowLevel)
                else: int(NSNormalWindowLevel))

  if opts.content:
    result.loadHTML = proc(html: string, baseURL: string) = discard
    result.loadURL = proc(url: string) = discard
    result.eval = proc(js: string) = discard
    result.requestFrame = proc() =
      sendVoidBool(surfaceView, sel("setNeedsDisplay:"), true)
    result.startAnimation = proc(fps: int) =
      if state.windowTimers.hasKey(id):
        let old = state.windowTimers[id]
        if old != nil:
          sendVoid(old, sel("invalidate"))
      state.animationLast[id] = getMonoTime().ticks.float64 / 1_000_000_000.0
      let rate = if fps > 0: fps else: 60
      let timer = scheduledTimer(1.0 / float64(rate), delegate,
                                 "animationTick:", true)
      if timer != nil:
        state.windowTimers[id] = timer
    result.stopAnimation = proc() =
      if state.windowTimers.hasKey(id):
        let timer = state.windowTimers[id]
        if timer != nil:
          sendVoid(timer, sel("invalidate"))
        state.windowTimers.del(id)
      state.animationLast.del(id)
    result.testClick = proc(x, y: float32) =
      let winNum = sendInt(win, sel("windowNumber"))
      let loc = NSPoint(x: CGFloat(x), y: CGFloat(frame.h - CGFloat(y)))
      let selector = sel("mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:")
      for typ in [NSUInteger(1), NSUInteger(2)]:
        let event = cast[MsgSendMouseEvent](msgSend)(
          loadClass("NSEvent"), selector, typ, loc, 0, 0.0, winNum, nil,
          0, 1, 1.0'f32)
        if event != nil:
          sendVoidId(state.nsApp, sel("sendEvent:"), event)
    proc sendKeyEvent(text: string, keyCode: uint16, flags: uint32 = 0) =
      let winNum = sendInt(win, sel("windowNumber"))
      let chars = nsString(text)
      var eventFlags = 0'u32
      if (flags and KeyShift) != 0: eventFlags = eventFlags or uint32(NSEventModifierFlagShift)
      if (flags and KeyControl) != 0: eventFlags = eventFlags or uint32(NSEventModifierFlagControl)
      if (flags and KeyAlt) != 0: eventFlags = eventFlags or uint32(NSEventModifierFlagOption)
      if (flags and KeyCommand) != 0: eventFlags = eventFlags or uint32(NSEventModifierFlagCommand)
      let event = cast[MsgSendKeyEvent](msgSend)(
        loadClass("NSEvent"),
        sel("keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:"),
        10, NSPoint(x: 0, y: 0), NSUInteger(eventFlags), 0.0, winNum, nil,
        chars, chars, false, keyCode)
      if event != nil:
        sendVoidId(state.nsApp, sel("sendEvent:"), event)
    result.testKey = proc(keyCode: int) =
      sendKeyEvent("", uint16(keyCode))
    result.testKeyText = proc(text: string) =
      sendKeyEvent(text, 0)
    result.testKeyMods = proc(keyCode: int, modifiers: uint32) =
      sendKeyEvent(keyTextForCode(keyCode), uint16(keyCode), modifiers)
    result.testMenuKey = proc(keyCode: int, modifiers: uint32) =
      let flags = NSUInteger(
        (if (modifiers and KeyShift) != 0: NSEventModifierFlagShift else: 0) or
        (if (modifiers and KeyControl) != 0: NSEventModifierFlagControl else: 0) or
        (if (modifiers and KeyAlt) != 0: NSEventModifierFlagOption else: 0) or
        (if (modifiers and KeyCommand) != 0: NSEventModifierFlagCommand else: 0))
      let chars = nsString(keyTextForCode(keyCode))
      let event = cast[MsgSendKeyEvent](msgSend)(
        loadClass("NSEvent"),
        sel("keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:"),
        10, NSPoint(x: 0, y: 0), flags, 0.0,
        sendInt(win, sel("windowNumber")), nil, chars, chars, false,
        uint16(keyCode))
      if event != nil:
        let mainMenu = send0(state.nsApp, sel("mainMenu"))
        if mainMenu != nil:
          let ok = sendBoolId(mainMenu, sel("performKeyEquivalent:"), event)
          when defined(nimiClipDebug):
            echo "performKeyEquivalent code=", keyCode, " ok=", ok,
                 " chars=", keyTextForCode(keyCode)
    result.destroy = proc() =
      sendVoidId(win, sel("setContentView:"), nil)
      sendVoid(win, sel("close"))
  else:
    result.loadHTML = proc(html: string, baseURL: string) =
      let base = if baseURL.len > 0: nsURL(baseURL) else: nil
      sendVoidId2(webView, sel("loadHTMLString:baseURL:"), nsString(html), base)
    result.loadURL = proc(url: string) =
      sendVoidId(webView, sel("loadRequest:"), nsRequest(nsURL(url)))
    result.eval = proc(js: string) =
      sendVoidId2(webView, sel("evaluateJavaScript:completionHandler:"),
                 nsString(js), nil)
    result.requestFrame = proc() = discard
    result.startAnimation = proc(fps: int) = discard
    result.stopAnimation = proc() = discard
    result.destroy = proc() =
      let u = state.userContentControllers.getOrDefault(id)
      if u != nil:
        sendVoidId(u, sel("removeScriptMessageHandlerForName:"),
                  nsString(NimiMessageHandlerName))
      sendVoidId(webView, sel("setNavigationDelegate:"), nil)
      sendVoid(webView, sel("stopLoading"))
      sendVoidId(win, sel("setContentView:"), nil)
      sendVoid(win, sel("close"))

