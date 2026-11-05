## NSWindow + WKWebView + the runtime-defined delegate that receives page
## messages and window close events.

import std/[strutils, tables]

import ../contract
import ../../core/bridge
import ./[objc, protocol, types]

const
  NimiMessageHandlerName = "nimi"
  NimiWindowDelegateClass = "NimiWindowDelegate"

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
  let h = gState.windowHandlers.getOrDefault(id)
  if h.closed != nil:
    h.closed(id)
  gState.windowHandlers.del(id)
  gState.delegateToId.del(self)
  gState.webViews.del(id)
  gState.userContentControllers.del(id)
  gState.windowDelegates.del(id)
  let surfaceView = gState.surfaceViews.getOrDefault(id)
  if surfaceView != nil:
    gState.surfaceToId.del(surfaceView)
  gState.surfaceViews.del(id)
  gState.surfaceHandlers.del(id)
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
    if h.mouseDown != nil: h.mouseDown(x, y)
  of 1:
    if h.mouseUp != nil: h.mouseUp(x, y)
  else:
    if h.mouseMoved != nil: h.mouseMoved(x, y)

proc surfaceAcceptsFirstMouse(self: Id, cmd: SEL, event: Id): bool {.cdecl.} =
  result = true

proc surfaceMouseDown(self: Id, cmd: SEL, event: Id) {.cdecl.} =
  surfaceMouseEvent(self, event, 0)

proc surfaceMouseUp(self: Id, cmd: SEL, event: Id) {.cdecl.} =
  surfaceMouseEvent(self, event, 1)

proc surfaceMouseDragged(self: Id, cmd: SEL, event: Id) {.cdecl.} =
  surfaceMouseEvent(self, event, 2)

proc surfaceMouseMoved(self: Id, cmd: SEL, event: Id) {.cdecl.} =
  surfaceMouseEvent(self, event, 2)

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

proc surfaceKeyDown(self: Id, cmd: SEL, event: Id) {.cdecl.} =
  if gState == nil:
    return
  let id = gState.surfaceToId.getOrDefault(self, 0'u64)
  if id == 0:
    return
  let h = gState.surfaceHandlers.getOrDefault(id)
  if h.keyDown == nil:
    return
  let chars = goString(send0(event, sel("characters")))
  let code = int(sendUShort(event, sel("keyCode")))
  h.keyDown(keyName(code, chars))

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
    ("keyDown:", cast[pointer](surfaceKeyDown), "v@:@"),
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
  ])

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
    proc sendKeyEvent(text: string, keyCode: uint16) =
      let winNum = sendInt(win, sel("windowNumber"))
      let chars = nsString(text)
      let event = cast[MsgSendKeyEvent](msgSend)(
        loadClass("NSEvent"),
        sel("keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:"),
        10, NSPoint(x: 0, y: 0), 0, 0.0, winNum, nil, chars, chars,
        false, keyCode)
      if event != nil:
        sendVoidId(state.nsApp, sel("sendEvent:"), event)
    result.testKey = proc(keyCode: int) =
      sendKeyEvent("", uint16(keyCode))
    result.testKeyText = proc(text: string) =
      sendKeyEvent(text, 0)
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
    result.destroy = proc() =
      let u = state.userContentControllers.getOrDefault(id)
      if u != nil:
        sendVoidId(u, sel("removeScriptMessageHandlerForName:"),
                  nsString(NimiMessageHandlerName))
      sendVoidId(webView, sel("setNavigationDelegate:"), nil)
      sendVoid(webView, sel("stopLoading"))
      sendVoidId(win, sel("setContentView:"), nil)
      sendVoid(win, sel("close"))

