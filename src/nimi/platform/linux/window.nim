## GTK3 window, native drawing surface, input and WebKitGTK pages.

when not defined(linux):
  {.error: "The Linux window backend requires Linux".}

import std/[math, monotimes, strutils, tables, unicode, uri]

import ../contract
import ../unsupported
import ../../core/[bridge, fileserver]
import ./[ffi, menu, state]

const
  GdkEventPropagate = 0
  GdkEventStop = 1
  GdkButtonPress = 4
  Gdk2ButtonPress = 5
  Gdk3ButtonPress = 6

  GdkShiftMask = 1'u32 shl 0
  GdkControlMask = 1'u32 shl 2
  GdkMod1Mask = 1'u32 shl 3
  GdkSuperMask = 1'u32 shl 26
  GdkMetaMask = 1'u32 shl 28

  GdkPointerMotionMask = 1 shl 2
  GdkButtonPressMask = 1 shl 8
  GdkButtonReleaseMask = 1 shl 9
  GdkScrollMask = 1 shl 21
  GdkSmoothScrollMask = 1 shl 23
  GdkKeyPressMask = 1 shl 0
  GdkKeyReleaseMask = 1 shl 1

  GdkWindowStateIconified = 1 shl 1
  GdkWindowStateMaximized = 1 shl 2
  GdkWindowStateFullscreen = 1 shl 4

  GdkScrollUp = 0
  GdkScrollDown = 1
  GdkScrollLeft = 2
  GdkScrollRight = 3
  GdkScrollSmooth = 4

  WebKitUserContentInjectAllFrames = 0
  WebKitUserScriptInjectionAtDocumentStart = 0
  NimiMessageHandlerName = "nimi"

type
  SchemeRoot = ref object
    scheme: string
    server: FileServer

var
  schemeRoots: seq[SchemeRoot]
  registeredSchemes: Table[string, bool]
  lastClickTime = 0.0
  lastClickX, lastClickY: float32
  lastClickCount = 0

proc nowSeconds(): float64 =
  getMonoTime().ticks.float64 / 1_000_000_000.0

# --- keyboard --------------------------------------------------------------

let keyNames = {
  0xff08'u32: "backspace",
  0xff09'u32: "tab",
  0xff0d'u32: "enter",
  0xff8d'u32: "enter",
  0xff1b'u32: "escape",
  0x0020'u32: "space",
  0xff55'u32: "pageup",
  0xff56'u32: "pagedown",
  0xff57'u32: "end",
  0xff50'u32: "home",
  0xff51'u32: "left",
  0xff52'u32: "up",
  0xff53'u32: "right",
  0xff54'u32: "down",
  0xff63'u32: "insert",
  0xffff'u32: "delete",
}.toTable

proc keyName(keyval: cuint): string =
  if keyNames.hasKey(uint32(keyval)):
    return keyNames[uint32(keyval)]
  if keyval >= 0xffbe'u32 and keyval <= 0xffd7'u32:
    return "f" & $(int(keyval) - 0xffbe + 1)
  let unicode = gdk_keyval_to_unicode(keyval)
  if unicode >= 32 and unicode != 127 and unicode <= 0x10ffff:
    try:
      result = $Rune(unicode)
    except ValueError:
      result = ""

proc updateImeCursor(w: LinuxWindow) =
  if w == nil or w.imeContext == nil or w.closed:
    return
  let surface = w.handler.surface
  if surface.caretRect == nil:
    return
  let caret = surface.caretRect()
  var area = GdkRectangle(x: cint(caret.x), y: cint(caret.y),
                          width: cint(max(1.0'f32, caret.w)),
                          height: cint(max(1.0'f32, caret.h)))
  gtk_im_context_set_cursor_location(w.imeContext, addr area)

proc utf16Prefix(text: string, characters: int): int =
  var seen = 0
  for rune in text.runes:
    if seen >= characters:
      break
    inc seen
    result += (if int(rune) > 0xffff: 2 else: 1)

proc byteOffsetForUtf16(text: string, units: int): int =
  var seen = 0
  for rune in text.runes:
    if seen >= units:
      break
    let code = int(rune)
    seen += (if code > 0xffff: 2 else: 1)
    result += (if code < 0x80: 1 elif code < 0x800: 2
               elif code < 0x10000: 3 else: 4)
  result = min(result, text.len)

proc onImeCommit(context: pointer, text: cstring, data: pointer) {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed or text == nil:
    return
  if w.handler.surface.insertText != nil:
    try:
      w.handler.surface.insertText($text, NoTextRange)
    except CatchableError:
      discard
  updateImeCursor(w)

proc onImePreeditChanged(context, data: pointer) {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed:
    return
  var text: cstring
  var cursor: cint
  gtk_im_context_get_preedit_string(context, addr text,
                                    cast[ptr pointer](nil), addr cursor)
  if text == nil:
    return
  let preedit = $text
  g_free(cast[pointer](text))
  let surface = w.handler.surface
  if preedit.len == 0:
    if surface.unmarkText != nil:
      try:
        surface.unmarkText()
      except CatchableError:
        discard
  elif surface.setMarkedText != nil:
    try:
      surface.setMarkedText(preedit,
        TextRange(location: utf16Prefix(preedit, int(cursor)), length: 0),
        NoTextRange)
    except CatchableError:
      discard
  updateImeCursor(w)

proc onImePreeditEnd(context, data: pointer) {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed:
    return
  if w.handler.surface.unmarkText != nil:
    try:
      w.handler.surface.unmarkText()
    except CatchableError:
      discard

proc onImeRetrieveSurrounding(context, data: pointer): cint {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed:
    return 0
  let surface = w.handler.surface
  if surface.textInputActive != nil and not surface.textInputActive():
    return 0
  if surface.textLength == nil or surface.attributedSubstring == nil:
    return 0
  let length = surface.textLength()
  if length <= 0 or length > 65535:
    return 0
  let text = surface.attributedSubstring(TextRange(location: 0, length: length))
  if text.len == 0:
    return 0
  var caretUnits = length
  if surface.selectedRange != nil:
    caretUnits = max(0, min(surface.selectedRange().location, length))
  let caretBytes = byteOffsetForUtf16(text, caretUnits)
  gtk_im_context_set_surrounding(context, text.cstring, cint(text.len),
                                 cint(caretBytes))
  1

proc onImeDeleteSurrounding(context, offset, nChars: cint,
                            data: pointer): cint {.cdecl.} =
  # Deleting surrounding text needs a shared-engine range deletion API.
  # Returning false lets GTK fall back without corrupting the document.
  0

proc onRealize(widget, data: pointer) {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed or w.imeContext == nil:
    return
  gtk_im_context_set_client_window(w.imeContext, gtk_widget_get_window(widget))

proc modifiersFrom(state: cuint): uint32 =
  if (state and GdkShiftMask) != 0: result = result or KeyShift
  if (state and GdkControlMask) != 0: result = result or KeyControl
  if (state and GdkMod1Mask) != 0: result = result or KeyAlt
  if (state and (GdkSuperMask or GdkMetaMask)) != 0:
    result = result or KeyCommand

# --- events ----------------------------------------------------------------

proc eventCoords(event: pointer): tuple[x, y: float32] =
  var x, y: cdouble
  if gdk_event_get_coords(event, addr x, addr y) != 0:
    result = (float32(x), float32(y))

proc onDraw(widget, cr, data: pointer): cint {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed or w.handler.surface.draw == nil:
    return GdkEventStop
  try:
    let width = float32(max(1, int(gtk_widget_get_allocated_width(widget))))
    let height = float32(max(1, int(gtk_widget_get_allocated_height(widget))))
    w.handler.surface.draw(cr, width, height)
    updateImeCursor(w)
  except CatchableError:
    discard
  GdkEventStop

proc onKeyPress(widget, event, data: pointer): cint {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed:
    return GdkEventPropagate
  let surface = w.handler.surface
  if w.imeContext != nil and
      (surface.textInputActive == nil or surface.textInputActive()):
    if gtk_im_context_filter_keypress(w.imeContext, event) != 0:
      updateImeCursor(w)
      return GdkEventStop
  var keyval: cuint
  var state: cuint
  if gdk_event_get_keyval(event, addr keyval) == 0:
    return GdkEventPropagate
  discard gdk_event_get_state(event, addr state)
  let key = keyName(keyval)
  if key.len == 0:
    return GdkEventPropagate
  if surface.keyDown != nil:
    try:
      surface.keyDown(key, modifiersFrom(state))
    except CatchableError:
      discard
  GdkEventStop

proc onButtonPress(widget, event, data: pointer): cint {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed:
    return GdkEventPropagate
  # GTK emits a plain BUTTON_PRESS before 2BUTTON_PRESS/3BUTTON_PRESS for
  # the same physical click; only handle the first to avoid duplicates.
  let eventType = gdk_event_get_event_type(event)
  if eventType == Gdk2ButtonPress or eventType == Gdk3ButtonPress:
    return GdkEventStop
  var button: cuint
  if gdk_event_get_button(event, addr button) == 0 or button != 1:
    return GdkEventPropagate
  let (x, y) = eventCoords(event)
  let now = nowSeconds()
  if now - lastClickTime <= 0.4 and
      abs(x - lastClickX) < 4 and abs(y - lastClickY) < 4:
    lastClickCount = min(3, lastClickCount + 1)
  else:
    lastClickCount = 1
  lastClickTime = now
  lastClickX = x
  lastClickY = y
  if w.drawing != nil:
    gtk_widget_grab_focus(w.drawing)
  if w.handler.surface.mouseDown != nil:
    try:
      w.handler.surface.mouseDown(x, y, lastClickCount)
    except CatchableError:
      discard
  updateImeCursor(w)
  GdkEventStop

proc onButtonRelease(widget, event, data: pointer): cint {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed:
    return GdkEventPropagate
  var button: cuint
  if gdk_event_get_button(event, addr button) == 0 or button != 1:
    return GdkEventPropagate
  let (x, y) = eventCoords(event)
  if w.handler.surface.mouseUp != nil:
    try:
      w.handler.surface.mouseUp(x, y)
    except CatchableError:
      discard
  updateImeCursor(w)
  GdkEventStop

proc onMotion(widget, event, data: pointer): cint {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed:
    return GdkEventPropagate
  let (x, y) = eventCoords(event)
  if w.handler.surface.mouseMoved != nil:
    try:
      w.handler.surface.mouseMoved(x, y)
    except CatchableError:
      discard
  GdkEventPropagate

proc onScroll(widget, event, data: pointer): cint {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed:
    return GdkEventPropagate
  let (x, y) = eventCoords(event)
  var state: cuint
  discard gdk_event_get_state(event, addr state)
  var dx, dy: cdouble
  var direction: cint
  if gdk_event_get_scroll_deltas(event, addr dx, addr dy) != 0:
    dx = dx * 40.0
    dy = dy * 40.0
  elif gdk_event_get_scroll_direction(event, addr direction) != 0:
    case direction
    of GdkScrollUp: dy = -40
    of GdkScrollDown: dy = 40
    of GdkScrollLeft: dx = -40
    of GdkScrollRight: dx = 40
    else: discard
  let shift = (state and GdkShiftMask) != 0
  let surface = w.handler.surface
  if dx != 0 and surface.scrollHorizontal != nil:
    try:
      discard surface.scrollHorizontal(x, y, float32(dx))
    except CatchableError:
      discard
    return GdkEventStop
  if dy != 0 and shift and surface.scrollHorizontal != nil:
    let handled =
      try: surface.scrollHorizontal(x, y, float32(dy))
      except CatchableError: false
    if handled:
      return GdkEventStop
  if dy != 0 and surface.scroll != nil:
    try:
      surface.scroll(x, y, float32(dy))
    except CatchableError:
      discard
    return GdkEventStop
  GdkEventPropagate

proc onFocusIn(widget, event, data: pointer): cint {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed:
    return GdkEventPropagate
  lastFocusedWindow = w
  if w.imeContext != nil:
    gtk_im_context_focus_in(w.imeContext)
  if w.handler.focused != nil:
    try:
      w.handler.focused(w.id)
    except CatchableError:
      discard
  GdkEventPropagate

proc onFocusOut(widget, event, data: pointer): cint {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed:
    return GdkEventPropagate
  if w.imeContext != nil:
    gtk_im_context_focus_out(w.imeContext)
    gtk_im_context_reset(w.imeContext)
  if w.handler.surface.cancelInput != nil:
    try:
      w.handler.surface.cancelInput(true)
    except CatchableError:
      discard
  if w.handler.blurred != nil:
    try:
      w.handler.blurred(w.id)
    except CatchableError:
      discard
  if lastFocusedWindow == w:
    lastFocusedWindow = nil
  GdkEventPropagate

proc onDelete(widget, event, data: pointer): cint {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed or w.handler.shouldClose == nil:
    return GdkEventPropagate
  try:
    if w.handler.shouldClose(w.id):
      GdkEventPropagate
    else:
      GdkEventStop
  except CatchableError:
    GdkEventStop

proc onDestroy(widget, data: pointer) {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed:
    return
  w.closed = true
  if w.animationSource != 0:
    discard g_source_remove(w.animationSource)
    w.animationSource = 0
  w.animating = false
  if w.imeContext != nil:
    gtk_im_context_set_client_window(w.imeContext, nil)
    g_object_unref(w.imeContext)
    w.imeContext = nil
  if w.userContentManager != nil and w.ownsUserContentManager:
    g_object_unref(w.userContentManager)
  w.userContentManager = nil
  w.ownsUserContentManager = false
  if w.webContext != nil:
    g_object_unref(w.webContext)
    w.webContext = nil
  w.webview = nil
  w.drawing = nil
  w.content = nil
  w.menuBar = nil
  w.menuActions.setLen(0)
  linuxWindows.del(w.window)
  linuxWindowsById.del(w.id)
  if lastFocusedWindow == w:
    lastFocusedWindow = nil
  let handler = w.handler
  w.handler = WindowHandler()
  w.window = nil
  if handler.closed != nil:
    try:
      handler.closed(w.id)
    except CatchableError:
      discard

proc onAnimationTick(data: pointer): cint {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed or not w.animating:
    return 0
  let now = nowSeconds()
  var dt = now - w.lastFrame
  w.lastFrame = now
  if dt < 0: dt = 0
  elif dt > 0.25: dt = 0.25
  if w.handler.frame != nil:
    try:
      w.handler.frame(w.id, now, dt)
    except CatchableError:
      discard
  if not w.closed:
    updateImeCursor(w)
    if w.drawing != nil:
      gtk_widget_queue_draw(w.drawing)
    elif w.webview != nil:
      gtk_widget_queue_draw(w.webview)
  if w.animating and not w.closed: 1 else: 0

# --- WebKit ----------------------------------------------------------------

proc onWebMessage(manager, result, data: pointer) {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed or result == nil:
    return
  let value = webkit_javascript_result_get_js_value(result)
  if value == nil:
    return
  let text = jsc_value_to_string(value)
  if text == nil:
    return
  let message = $text
  g_free(cast[pointer](text))
  if w.handler.message != nil:
    try:
      w.handler.message(w.id, message)
    except CatchableError:
      discard

type
  GError = object
    domain: uint32
    code: cint
    message: cstring

proc onLoadFailed(view, loadEvent, failingUri, error: pointer,
                  data: pointer): cint {.cdecl.} =
  if error != nil:
    let err = cast[ptr GError](error)
    let uri = if failingUri != nil: $cast[cstring](failingUri) else: ""
    stderr.writeLine("nimi: page load failed " & uri & ": " &
      (if err.message != nil: $err.message else: "unknown"))
  0

proc onWebTitle(widget, pspec, data: pointer) {.cdecl.} =
  let w = cast[LinuxWindow](data)
  if w == nil or w.closed or w.webview == nil:
    return
  let title = webkit_web_view_get_title(w.webview)
  if title == nil:
    return
  let value = $title
  if w.handler.titleChanged != nil:
    try:
      w.handler.titleChanged(w.id, value)
    except CatchableError:
      discard

proc onEvalDone(view, result, data: pointer) {.cdecl.} =
  if view == nil or result == nil:
    return
  let value = webkit_web_view_evaluate_javascript_finish(view, result, nil)
  if value != nil:
    g_object_unref(value)

proc onSchemeRequest(request, data: pointer) {.cdecl.} =
  let info = cast[SchemeRoot](data)
  if info == nil or request == nil:
    return
  let uriText = webkit_uri_scheme_request_get_uri(request)
  if uriText == nil:
    return
  var path = "/"
  try:
    let uri = parseUri($uriText)
    if uri.path.len > 0:
      path = uri.path
  except ValueError:
    discard
  let served = info.server.serve(path)
  var bytes: pointer
  if served.data.len > 0:
    bytes = g_bytes_new(served.data.cstring, csize_t(served.data.len))
  else:
    bytes = g_bytes_new(nil, 0)
  if bytes == nil:
    return
  let stream = g_memory_input_stream_new_from_bytes(bytes)
  g_bytes_unref(bytes)
  if stream == nil:
    return
  webkit_uri_scheme_request_finish(request, stream, int64(served.data.len),
                                   served.mime.cstring)
  g_object_unref(stream)

proc ensureScheme(context: pointer, scheme, fileRoot: string) =
  if scheme.len == 0 or fileRoot.len == 0:
    return
  let target =
    if context != nil: context
    else: webkit_web_context_get_default()
  if target == nil:
    raise newException(BackendError, "WebKitGTK context is unavailable")
  let key = $cast[uint](target) & ":" & scheme
  if registeredSchemes.hasKey(key):
    return
  let security = webkit_web_context_get_security_manager(target)
  if security != nil:
    webkit_security_manager_register_uri_scheme_as_secure(security,
                                                          scheme.cstring)
    webkit_security_manager_register_uri_scheme_as_cors_enabled(security,
                                                                scheme.cstring)
  let info = SchemeRoot(scheme: scheme,
                        server: newFileServer(fileRoot, scheme))
  schemeRoots.add info
  webkit_web_context_register_uri_scheme(target, scheme.cstring,
                                         cast[pointer](onSchemeRequest),
                                         cast[pointer](info), nil)
  registeredSchemes[key] = true

proc createWebView(w: LinuxWindow, opts: PlatformWindowOptions) =
  if not ensureWebKit():
    raise newException(BackendError,
      "WebKitGTK 4.1/4.0 runtime is not installed")
  var context, manager, view: pointer
  if opts.ephemeral:
    context = webkit_web_context_new_ephemeral()
    if context == nil:
      raise newException(BackendError,
        "Cannot create a private WebKit context")
    w.webContext = context
    view = webkit_web_view_new_with_context(context)
    if view == nil:
      raise newException(BackendError, "Cannot create a WebKit web view")
    manager = webkit_web_view_get_user_content_manager(view)
    if manager == nil:
      raise newException(BackendError,
        "WebKit view has no user content manager")
    w.userContentManager = manager
    w.ownsUserContentManager = false
  else:
    manager = webkit_user_content_manager_new()
    if manager == nil:
      raise newException(BackendError,
        "Cannot create a WebKit user content manager")
    w.userContentManager = manager
    w.ownsUserContentManager = true
    view = webkit_web_view_new_with_user_content_manager(manager)
    if view == nil:
      raise newException(BackendError, "Cannot create a WebKit web view")
    w.webview = view

  discard g_signal_connect_data(manager,
    ("script-message-received::" & NimiMessageHandlerName).cstring,
    cast[pointer](onWebMessage), cast[pointer](w), nil, 0)
  if webkit_user_content_manager_register_script_message_handler(
      manager, NimiMessageHandlerName.cstring) == 0:
    raise newException(BackendError,
      "Cannot register the WebKit nimi message handler")
  let source = bridgeJs.replace("__NIMI_SECRET__", opts.secret)
    .replace("__NIMI_TOKEN__", opts.token)
  let script = webkit_user_script_new(source.cstring,
    WebKitUserContentInjectAllFrames, WebKitUserScriptInjectionAtDocumentStart,
    cast[ptr cstring](nil), cast[ptr cstring](nil))
  if script != nil:
    webkit_user_content_manager_add_script(manager, script)
    webkit_user_script_unref(script)
  w.webview = view
  discard g_signal_connect_data(view, "notify::title".cstring,
                                cast[pointer](onWebTitle),
                                cast[pointer](w), nil, 0)
  discard g_signal_connect_data(view, "load-failed".cstring,
                                cast[pointer](onLoadFailed),
                                cast[pointer](w), nil, 0)
  gtk_box_pack_start(w.box, view, 1, 1, 0)
  if opts.scheme.len > 0 and opts.fileRoot.len > 0:
    ensureScheme(context, opts.scheme, opts.fileRoot)
  if opts.html.len > 0:
    webkit_web_view_load_html(view, opts.html.cstring, nil)
  elif opts.url.len > 0:
    webkit_web_view_load_uri(view, opts.url.cstring)

# --- native window methods -------------------------------------------------

proc requireLive(w: LinuxWindow) =
  if w == nil or w.closed or w.window == nil:
    raise newException(BackendError, "Window has been destroyed")
  if linuxState != nil and getThreadId() != linuxState.mainThreadId:
    raise newException(BackendError, "Window operation must run on the main thread")

proc requireWebView(w: LinuxWindow): pointer =
  requireLive(w)
  if w.webview == nil:
    raise newException(BackendError, "Window has no web view")
  result = w.webview

proc frameNow(): float64 = nowSeconds()

proc keyNameForTest(code: int): string =
  case code
  of 8: "backspace"
  of 9: "tab"
  of 13: "enter"
  of 27: "escape"
  of 32: "space"
  of 0x21: "pageup"
  of 0x22: "pagedown"
  of 0x23: "end"
  of 0x24: "home"
  of 0x25: "left"
  of 0x26: "up"
  of 0x27: "right"
  of 0x28: "down"
  of 0x2d: "insert"
  of 0x2e: "delete"
  of 112 .. 135: "f" & $(code - 111)
  else:
    if code >= 32 and code <= 0x10ffff:
      try:
        $Rune(code)
      except ValueError:
        ""
    else:
      ""

proc createLinuxWindow*(opts: PlatformWindowOptions,
                        handler: WindowHandler): NativeWindow =
  if linuxState == nil or not linuxState.initialized or linuxState.shuttingDown:
    raise newException(BackendError, "Create windows after backend initialization")
  if getThreadId() != linuxState.mainThreadId:
    raise newException(BackendError, "Create windows on the main thread")

  let usesWebView = not opts.content and
    (opts.html.len > 0 or opts.url.len > 0 or opts.scheme.len > 0)
  let window = gtk_window_new(0)
  if window == nil:
    raise newException(BackendError, "Cannot create a GTK window")
  let box = gtk_box_new(1, 0)
  if box == nil:
    gtk_widget_destroy(window)
    raise newException(BackendError, "Cannot create the GTK window layout")
  gtk_container_add(window, box)

  let w = LinuxWindow(id: handler.windowId, window: window, box: box,
                      handler: handler, scheme: opts.scheme,
                      fileRoot: opts.fileRoot, usesWebView: usesWebView)
  linuxWindows[window] = w
  linuxWindowsById[handler.windowId] = w

  try:
    gtk_window_set_title(window, opts.title.cstring)
    gtk_window_set_default_size(window, cint(max(1, opts.width)),
                                cint(max(1, opts.height)))
    gtk_window_set_resizable(window, cint(opts.resizable))
    gtk_widget_add_events(window, GdkKeyPressMask or GdkKeyReleaseMask)
    discard g_signal_connect_data(window, "delete-event".cstring,
                                  cast[pointer](onDelete), cast[pointer](w),
                                  nil, 0)
    discard g_signal_connect_data(window, "destroy".cstring,
                                  cast[pointer](onDestroy), cast[pointer](w),
                                  nil, 0)
    discard g_signal_connect_data(window, "focus-in-event".cstring,
                                  cast[pointer](onFocusIn), cast[pointer](w),
                                  nil, 0)
    discard g_signal_connect_data(window, "focus-out-event".cstring,
                                  cast[pointer](onFocusOut), cast[pointer](w),
                                  nil, 0)
    if not usesWebView:
      discard g_signal_connect_data(window, "key-press-event".cstring,
                                    cast[pointer](onKeyPress),
                                    cast[pointer](w), nil, 0)

    installMenu(w)

    if usesWebView:
      createWebView(w, opts)
    else:
      let drawing = gtk_drawing_area_new()
      if drawing == nil:
        raise newException(BackendError, "Cannot create the GTK drawing area")
      w.drawing = drawing
      w.content = drawing
      gtk_widget_set_can_focus(drawing, 1)
      gtk_widget_add_events(drawing, GdkPointerMotionMask or
        GdkButtonPressMask or GdkButtonReleaseMask or GdkScrollMask or
        GdkSmoothScrollMask)
      discard g_signal_connect_data(drawing, "draw".cstring,
                                    cast[pointer](onDraw), cast[pointer](w),
                                    nil, 0)
      discard g_signal_connect_data(drawing, "button-press-event".cstring,
                                    cast[pointer](onButtonPress),
                                    cast[pointer](w), nil, 0)
      discard g_signal_connect_data(drawing, "button-release-event".cstring,
                                    cast[pointer](onButtonRelease),
                                    cast[pointer](w), nil, 0)
      discard g_signal_connect_data(drawing, "motion-notify-event".cstring,
                                    cast[pointer](onMotion),
                                    cast[pointer](w), nil, 0)
      discard g_signal_connect_data(drawing, "scroll-event".cstring,
                                    cast[pointer](onScroll),
                                    cast[pointer](w), nil, 0)
      if opts.ime:
        w.imeContext = gtk_im_multicontext_new()
        if w.imeContext != nil:
          gtk_im_context_set_use_preedit(w.imeContext, 1)
          discard g_signal_connect_data(w.imeContext, "commit".cstring,
            cast[pointer](onImeCommit), cast[pointer](w), nil, 0)
          discard g_signal_connect_data(w.imeContext, "preedit-changed".cstring,
            cast[pointer](onImePreeditChanged), cast[pointer](w), nil, 0)
          discard g_signal_connect_data(w.imeContext, "preedit-end".cstring,
            cast[pointer](onImePreeditEnd), cast[pointer](w), nil, 0)
          discard g_signal_connect_data(w.imeContext,
            "retrieve-surrounding".cstring,
            cast[pointer](onImeRetrieveSurrounding), cast[pointer](w), nil, 0)
          discard g_signal_connect_data(w.imeContext,
            "delete-surrounding".cstring,
            cast[pointer](onImeDeleteSurrounding), cast[pointer](w), nil, 0)
          discard g_signal_connect_data(drawing, "realize".cstring,
            cast[pointer](onRealize), cast[pointer](w), nil, 0)
      gtk_box_pack_start(box, drawing, 1, 1, 0)

    gtk_widget_show_all(window)
    gtk_window_present(window)
    if w.drawing != nil:
      gtk_widget_grab_focus(w.drawing)
      if w.imeContext != nil:
        gtk_im_context_set_client_window(w.imeContext,
                                         gtk_widget_get_window(w.drawing))
    elif w.webview != nil:
      gtk_widget_grab_focus(w.webview)
    lastFocusedWindow = w
  except:
    if w.window != nil:
      gtk_widget_destroy(window)
    raise

  result = newUnsupportedNativeWindow("linux")
  result.id = handler.windowId
  result.setTitle = proc(title: string) =
    requireLive(w)
    gtk_window_set_title(w.window, title.cstring)
    if w.handler.titleChanged != nil:
      w.handler.titleChanged(w.id, title)
  result.show = proc() =
    requireLive(w)
    gtk_widget_show_all(w.window)
    gtk_window_present(w.window)
  result.hide = proc() =
    requireLive(w)
    gtk_widget_hide(w.window)
  result.focus = proc() =
    requireLive(w)
    gtk_window_present(w.window)
    if w.drawing != nil:
      gtk_widget_grab_focus(w.drawing)
    elif w.webview != nil:
      gtk_widget_grab_focus(w.webview)
  result.close = proc() =
    if not w.closed and w.window != nil:
      gtk_window_close(w.window)
  result.center = proc() =
    requireLive(w)
    var width, height, x, y: cint
    gtk_window_get_size(w.window, addr width, addr height)
    let screen = gdk_screen_get_default()
    if screen != nil and gdk_screen_get_n_monitors(screen) > 0:
      var work: GdkRectangle
      let monitor =
        if gdk_screen_get_primary_monitor(screen) >= 0:
          gdk_screen_get_primary_monitor(screen)
        else: 0
      gdk_screen_get_monitor_workarea(screen, monitor, addr work)
      x = work.x + max(0, (work.width - width) div 2)
      y = work.y + max(0, (work.height - height) div 2)
    else:
      x = max(0, (1400 - width) div 2)
      y = max(0, (900 - height) div 2)
    gtk_window_move(w.window, x, y)
  result.minimize = proc() =
    requireLive(w)
    gtk_window_iconify(w.window)
  result.deminimize = proc() =
    requireLive(w)
    gtk_window_deiconify(w.window)
    gtk_window_present(w.window)
  result.zoom = proc() =
    requireLive(w)
    if gtk_window_is_maximized(w.window) != 0:
      gtk_window_unmaximize(w.window)
    else:
      gtk_window_maximize(w.window)
  result.toggleFullScreen = proc() =
    requireLive(w)
    let gdkWindow = gtk_widget_get_window(w.window)
    if gdkWindow != nil and
        (gdk_window_get_state(gdkWindow) and GdkWindowStateFullscreen) != 0:
      gtk_window_unfullscreen(w.window)
    else:
      gtk_window_fullscreen(w.window)
  result.isFullScreen = proc(): bool =
    requireLive(w)
    let gdkWindow = gtk_widget_get_window(w.window)
    gdkWindow != nil and
      (gdk_window_get_state(gdkWindow) and GdkWindowStateFullscreen) != 0
  result.isFocused = proc(): bool =
    requireLive(w)
    gtk_window_is_active(w.window) != 0
  result.isVisible = proc(): bool =
    if w == nil or w.closed or w.window == nil:
      return false
    if gtk_widget_get_visible(w.window) == 0:
      return false
    let gdkWindow = gtk_widget_get_window(w.window)
    not (gdkWindow != nil and
         (gdk_window_get_state(gdkWindow) and GdkWindowStateIconified) != 0)
  result.isMinimized = proc(): bool =
    requireLive(w)
    let gdkWindow = gtk_widget_get_window(w.window)
    gdkWindow != nil and
      (gdk_window_get_state(gdkWindow) and GdkWindowStateIconified) != 0
  result.isMaximized = proc(): bool =
    requireLive(w)
    if gtk_window_is_maximized(w.window) != 0:
      return true
    let gdkWindow = gtk_widget_get_window(w.window)
    gdkWindow != nil and
      (gdk_window_get_state(gdkWindow) and GdkWindowStateMaximized) != 0
  result.setSize = proc(width, height: int) =
    requireLive(w)
    gtk_window_resize(w.window, cint(max(1, width)), cint(max(1, height)))
  result.setPosition = proc(x, y: int) =
    requireLive(w)
    gtk_window_move(w.window, cint(x), cint(y))
  result.getSize = proc(width, height: var int) =
    requireLive(w)
    var ww, hh: cint
    gtk_window_get_size(w.window, addr ww, addr hh)
    width = int(ww)
    height = int(hh)
  result.getPosition = proc(x, y: var int) =
    requireLive(w)
    var xx, yy: cint
    gtk_window_get_position(w.window, addr xx, addr yy)
    x = int(xx)
    y = int(yy)
  result.setAppearance = proc(dark: bool) =
    ## GTK3 has no per-window dark switch; this changes the application-wide
    ## prefer-dark setting. The system theme still decides when unset.
    let settings = gtk_settings_get_default()
    if settings != nil:
      g_object_set(settings, "gtk-application-prefer-dark-theme".cstring,
                   cint(dark), nil)
  result.setResizable = proc(enabled: bool) =
    requireLive(w)
    gtk_window_set_resizable(w.window, cint(enabled))
  result.setAlwaysOnTop = proc(always: bool) =
    requireLive(w)
    gtk_window_set_keep_above(w.window, cint(always))
  result.loadHTML = proc(html: string, baseURL: string) =
    let view = requireWebView(w)
    if baseURL.len > 0:
      webkit_web_view_load_html(view, html.cstring, baseURL.cstring)
    else:
      webkit_web_view_load_html(view, html.cstring, nil)
  result.loadURL = proc(url: string) =
    webkit_web_view_load_uri(requireWebView(w), url.cstring)
  result.eval = proc(js: string) =
    let view = requireWebView(w)
    webkit_web_view_evaluate_javascript(view, js.cstring, int64(js.len),
                                        nil, nil, nil,
                                        cast[GAsyncReadyCallback](onEvalDone),
                                        view)
  result.requestFrame = proc() =
    if w == nil or w.closed:
      return
    if w.drawing != nil:
      gtk_widget_queue_draw(w.drawing)
    elif w.webview != nil:
      gtk_widget_queue_draw(w.webview)
  result.startAnimation = proc(fps: int) =
    requireLive(w)
    if w.animationSource != 0:
      discard g_source_remove(w.animationSource)
      w.animationSource = 0
    let rate = max(1, fps)
    let interval = cuint(max(1, 1000 div rate))
    w.lastFrame = frameNow()
    w.animating = true
    w.animationSource = g_timeout_add(interval,
      cast[GTimeoutFunc](onAnimationTick), cast[pointer](w))
    if w.animationSource == 0:
      w.animating = false
      raise newException(BackendError, "Cannot start the GTK animation timer")
  result.stopAnimation = proc() =
    if w != nil and w.animationSource != 0:
      discard g_source_remove(w.animationSource)
      w.animationSource = 0
    if w != nil:
      w.animating = false
  result.testClick = proc(x, y: float32) =
    requireLive(w)
    let surface = w.handler.surface
    if surface.mouseDown != nil:
      surface.mouseDown(x, y, 1)
    if surface.mouseUp != nil:
      surface.mouseUp(x, y)
    if w.drawing != nil:
      gtk_widget_queue_draw(w.drawing)
  result.testKey = proc(keyCode: int) =
    requireLive(w)
    let key = keyNameForTest(keyCode)
    if key.len > 0 and w.handler.surface.keyDown != nil:
      w.handler.surface.keyDown(key, 0)
  result.testKeyText = proc(text: string) =
    requireLive(w)
    if w.handler.surface.insertText != nil:
      w.handler.surface.insertText(text, NoTextRange)
  result.testKeyMods = proc(keyCode: int, modifiers: uint32) =
    requireLive(w)
    let key = keyNameForTest(keyCode)
    if key.len > 0 and w.handler.surface.keyDown != nil:
      w.handler.surface.keyDown(key, modifiers)
  result.testMenuKey = proc(keyCode: int, modifiers: uint32) =
    requireLive(w)
    testMenuKey(w, keyCode, modifiers)
  result.destroy = proc() =
    if w != nil and not w.closed and w.window != nil:
      gtk_widget_destroy(w.window)
