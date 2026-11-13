## Win32 host with native scenes, menus, Unicode input and opt-in IMM32 composition.
when not defined(windows):
  {.error: "Win32 host requires Windows".}
import std/[monotimes, os, strutils, tables, widestrs, unicode]
import ../[contract, unsupported]
import ./dialogs
import ./menu as winMenu
import ./[input, ime]

const hostHeader = (currentSourcePath.parentDir / "host.h").replace('\\', '/')
{.compile: "host.c".}
{.passL: "-luser32 -lgdi32".}
type Paint {.importc: "NimiPaint", header: hostHeader, bycopy.} = object
  dc: pointer
  width, height: cfloat
proc hostScale(w: pointer): cfloat {.cdecl, importc: "nimi_host_scale", header: hostHeader.}
proc hostModifiers(): cuint {.cdecl, importc: "nimi_host_modifiers", header: hostHeader.}
proc hostInvalidate(w: pointer) {.cdecl, importc: "nimi_host_invalidate", header: hostHeader.}
proc hostStartAnimation(w: pointer, fps: cint): cint {.cdecl, importc: "nimi_host_start_animation", header: hostHeader.}
proc hostStopAnimation(w: pointer) {.cdecl, importc: "nimi_host_stop_animation", header: hostHeader.}
type EventCallback = proc(window: pointer, message: cuint, wp: uint, lp: int): int {.cdecl.}
proc hostInit(cb: EventCallback): cint {.cdecl, importc: "nimi_host_init", header: hostHeader.}
proc hostRun(): cint {.cdecl, importc: "nimi_host_run", header: hostHeader.}
proc hostShutdown() {.cdecl, importc: "nimi_host_shutdown", header: hostHeader.}
proc hostStep() {.cdecl, importc: "nimi_host_step", header: hostHeader.}
proc hostQuit() {.cdecl, importc: "nimi_host_quit", header: hostHeader.}
proc hostSignal() {.cdecl, importc: "nimi_host_signal", header: hostHeader.}
proc hostMainThread(): cint {.cdecl, importc: "nimi_host_main_thread", header: hostHeader.}
proc hostWindow(title: WideCString, width, height, resizable: cint): pointer {.cdecl, importc: "nimi_host_window", header: hostHeader.}
proc hostClose(w: pointer) {.cdecl, importc: "nimi_host_close", header: hostHeader.}
proc hostDestroy(w: pointer) {.cdecl, importc: "nimi_host_destroy", header: hostHeader.}
proc hostTitle(w: pointer, title: WideCString) {.cdecl, importc: "nimi_host_title", header: hostHeader.}
proc hostShow(w: pointer, mode: cint) {.cdecl, importc: "nimi_host_show", header: hostHeader.}
proc hostSize(w: pointer, width, height: cint) {.cdecl, importc: "nimi_host_size", header: hostHeader.}
proc hostPosition(w: pointer, x, y: cint) {.cdecl, importc: "nimi_host_position", header: hostHeader.}
proc hostResizable(w: pointer, enabled: cint) {.cdecl, importc: "nimi_host_resizable", header: hostHeader.}
proc hostFullscreen(w: pointer, toggle: cint): cint {.cdecl, importc: "nimi_host_fullscreen", header: hostHeader.}
proc hostZoom(w: pointer) {.cdecl, importc: "nimi_host_zoom", header: hostHeader.}
proc hostClientSize(w: pointer, width, height: ptr cfloat) {.cdecl, importc: "nimi_host_client_size", header: hostHeader.}
proc hostCenter(w: pointer) {.cdecl, importc: "nimi_host_center", header: hostHeader.}
proc hostTopmost(w: pointer, enabled: cint) {.cdecl, importc: "nimi_host_topmost", header: hostHeader.}
proc hostFocused(w: pointer): cint {.cdecl, importc: "nimi_host_focused", header: hostHeader.}
proc hostFocus(w: pointer) {.cdecl, importc: "nimi_host_focus", header: hostHeader.}

proc hostClipboardRead(text: ptr WideCString): cint {.cdecl, importc: "nimi_host_clipboard_read", header: hostHeader.}
proc hostFree(p: pointer) {.cdecl, importc: "nimi_host_free", header: hostHeader.}
proc hostClipboardWrite(text: WideCString): cint {.cdecl, importc: "nimi_host_clipboard_write", header: hostHeader.}
proc hostClipboardClear(): cint {.cdecl, importc: "nimi_host_clipboard_clear", header: hostHeader.}
proc hostInputError() {.cdecl, importc: "nimi_host_input_error", header: hostHeader.}
proc hostMessage(title, text: WideCString, confirm: cint): cint {.cdecl, importc: "nimi_host_message", header: hostHeader.}

type WindowState = ref object
  handle: pointer
  handler: WindowHandler
  textInput: Utf16Input
  imeEnabled, imeActive, composing, syncingIme: bool
  animating: bool
  lastFrameTime: float64
  menuPlan: MenuPlan
  menuHandler: MenuHandler
var windowStates: Table[pointer, WindowState]
var appHandler: AppHandler
var callbackError: string
var initialized, running, shuttingDown: bool
var currentMenuPlan: MenuPlan
var currentMenuHandler: MenuHandler

proc frameNow(): float64 =
  getMonoTime().ticks.float64 / 1_000_000_000.0

proc syncIme(state: WindowState) =
  if state.handle == nil or not state.imeEnabled or state.syncingIme: return
  # IMM positioning can synchronously send WM_IME_NOTIFY back to this window.
  state.syncingIme = true
  defer: state.syncingIme = false
  let surface = state.handler.surface
  let active = surface.textInputActive == nil or surface.textInputActive()
  if active != state.imeActive:
    state.imeActive = active
    if not active:
      cancelIme(state.handle)
      state.composing = false
      if surface.unmarkText != nil: surface.unmarkText()
    if state.handle != nil: enableIme(state.handle, cint(active))
  if active and state.handle != nil: placeIme(state.handle, surface)

proc menuCommand(state: WindowState, command: uint16) =
  if command == 0 or int(command) > state.menuPlan.commands.len: return
  let item = state.menuPlan.commands[int(command) - 1]
  if not item.enabled: return
  let h = state.handler.surface
  case item.role
  of "":
    if state.menuHandler.select != nil: state.menuHandler.select(item.callbackId)
  of "quit":
    if appHandler.quitRequested == nil or appHandler.quitRequested(): hostQuit()
  of "close": hostClose(state.handle)
  of "minimize": hostShow(state.handle, 6)
  of "zoom": hostZoom(state.handle)
  of "fullscreen":
    if hostFullscreen(state.handle, 1) < 0: raise newException(BackendError, "Cannot toggle fullscreen")
  of "hide": hostShow(state.handle, 0)
  of "showAll", "bringAllToFront":
    for window in windowStates.values: hostShow(window.handle, 5)
    hostFocus(state.handle)
  of "about": discard hostMessage(newWideCString("About"), newWideCString("Nimi application"), 0)
  of "undo":
    if h.undo != nil: h.undo()
  of "redo":
    if h.redo != nil: h.redo()
  of "cut":
    if h.cut != nil: h.cut()
  of "copy":
    if h.copy != nil: h.copy()
  of "paste":
    if h.paste != nil: h.paste()
  of "selectAll":
    if h.selectAll != nil: h.selectAll()
  of "delete":
    if h.keyDown != nil: h.keyDown("delete", 0)
  else: discard

proc event(window: pointer, message: cuint, wp: uint, lp: int): int {.cdecl.} =
  # Never unwind Nim exceptions through a Windows callback frame.
  try:
    if message == 0x8001:
      if appHandler.dispatch != nil: appHandler.dispatch()
      return 0
    let state = windowStates.getOrDefault(window)
    if state == nil: return 0
    let h = state.handler
    let surface = h.surface
    defer:
      if state.handle != nil and state.imeEnabled and message in
          [0x8002'u32, 0x0201, 0x0202, 0x0203, 0x0200, 0x020a, 0x0100,
           0x0102, 0x0109, 0x010d, 0x010e, 0x010f, 0x0281, 0x0051, 0x0007]:
        syncIme(state)
    let scale = hostScale(window)
    let x = float32(cast[int16](uint16(lp and 0xffff))) / scale
    let y = float32(cast[int16](uint16((lp shr 16) and 0xffff))) / scale
    case message
    of 0x8002:
      let paint = cast[ptr Paint](lp)
      if surface.draw != nil: surface.draw(paint.dc, paint.width, paint.height)
    of 0x0201, 0x0203:
      if state.composing:
        cancelIme(window)
        state.composing = false
        if surface.unmarkText != nil: surface.unmarkText()
      if surface.mouseDown != nil: surface.mouseDown(x, y, if message == 0x0203: 2 else: 1)
    of 0x0202:
      if surface.mouseUp != nil: surface.mouseUp(x, y)
    of 0x0200:
      if surface.mouseMoved != nil: surface.mouseMoved(x, y)
    of 0x020a:
      let delta = float32(cast[int16](uint16((wp shr 16) and 0xffff))) / 120 * 40
      if surface.scroll != nil: surface.scroll(x, y, -delta)
    of 0x0100:
      if state.composing: return 0
      let mods = uint32(hostModifiers())
      let key = keyName(wp, mods)
      # Text controls receive layout-produced spaces through WM_CHAR. Buttons
      # retain keyDown("space") activation, with no duplicate insertion.
      if wp == 32 and surface.textInputActive != nil and surface.textInputActive(): return 0
      if key.len > 0 and surface.keyDown != nil: surface.keyDown(key, mods)
    of 0x0102, 0x0109:
      if state.composing: return 0
      let textSpace = wp == 32 and (message == 0x0109 or
        (surface.textInputActive != nil and surface.textInputActive()))
      if (wp > 32 or textSpace) and wp != 127 and
          ((hostModifiers() and 2) == 0 or (hostModifiers() and 4) != 0):
        let text = state.textInput.feed(uint32(wp))
        if text.len > 0 and surface.insertText != nil: surface.insertText(text, NoTextRange)
      else: state.textInput.reset()
    of 0x0281, 0x0286: # SETCONTEXT / IME_CHAR: custom preedit, no duplicate commit.
      return int(state.imeEnabled)
    of 0x0282:
      if wp in [3'u, 5'u]: syncIme(state) # Candidate change/open, not our own placement notification.
    of 0x010d:
      if state.imeEnabled:
        state.textInput.reset()
        state.composing = true
        return 1
    of 0x010f:
      if state.imeEnabled:
        updateComposition(window, uint(lp), surface)
        return 1
    of 0x010e:
      if state.imeEnabled:
        state.composing = false
        if surface.unmarkText != nil: surface.unmarkText()
        return 1
    of 0x0111:
      menuCommand(state, uint16(wp and 0xffff))
    of 0x8003: # NIMI_FRAME: the Win32 animation timer.
      if state.animating:
        let now = frameNow()
        var dt = now - state.lastFrameTime
        state.lastFrameTime = now
        if dt < 0: dt = 0
        elif dt > 0.25: dt = 0.25
        if h.frame != nil:
          h.frame(h.windowId, now, dt)
    of 0x0010:
      return int(h.shouldClose == nil or h.shouldClose(h.windowId))
    of 0x0002:
      state.animating = false
      hostStopAnimation(state.handle)
      state.handle = nil
      windowStates.del(window)
      state.handler = WindowHandler()
      state.menuHandler = MenuHandler()
      state.menuPlan = MenuPlan()
      if h.closed != nil: h.closed(h.windowId)
    of 0x0007:
      if h.focused != nil: h.focused(h.windowId)
    of 0x0215, 0x001f:
      if surface.cancelInput != nil: surface.cancelInput(false)
    of 0x0008:
      state.textInput.reset()
      if state.imeEnabled: cancelIme(window)
      state.composing = false
      if surface.cancelInput != nil: surface.cancelInput(true)
      if h.blurred != nil: h.blurred(h.windowId)
    else: discard
  except ClipboardError:
    # Clipboard contention is recoverable. The edit has not changed its document.
    hostInputError()
  except Exception as e:
    if callbackError.len == 0: callbackError = e.msg
    if not shuttingDown: hostQuit()

proc requireLive(state: WindowState) =
  if hostMainThread() == 0:
    raise newException(BackendError, "Window operation must run on main thread")
  if state.handle == nil:
    raise newException(BackendError, "Window has been destroyed")

proc wakeWindowsMain*() {.gcsafe.} =
  hostSignal()

proc shutdownWindows() =
  if not initialized or shuttingDown: return
  if hostMainThread() == 0:
    raise newException(BackendError, "Shutdown must run on the initializing thread")
  shuttingDown = true
  try:
    var remaining: seq[WindowState]
    for state in windowStates.values: remaining.add state
    for state in remaining:
      if state.handle != nil: hostDestroy(state.handle)
    if appHandler.terminated != nil: appHandler.terminated()
  finally:
    windowStates.clear()
    appHandler = AppHandler()
    currentMenuHandler = MenuHandler()
    currentMenuPlan = MenuPlan()
    hostShutdown()
    initialized = false
    running = false
    shuttingDown = false

proc newWindowsBackend*(): Backend =
  var ownsHost = false
  proc requireClipboard() =
    if not ownsHost or not initialized or hostMainThread() == 0:
      raise newException(ClipboardError, "Clipboard requires the initialized owning thread")
  result = newUnsupportedBackend("windows")
  result.clipboard = newUnsupportedClipboard("windows")
  result.clipboard.readText = proc(): string =
    requireClipboard()
    var data: WideCString
    let status = hostClipboardRead(addr data)
    if status < 0: raise newException(ClipboardError, "Cannot read Windows clipboard")
    if status == 0: return ""
    defer: hostFree(cast[pointer](data))
    $data
  result.clipboard.writeText = proc(text: string) =
    requireClipboard()
    if '\0' in text or validateUtf8(text) != -1:
      raise newException(ClipboardError, "Clipboard text must be valid UTF-8 without NUL")
    if hostClipboardWrite(newWideCString(text)) == 0:
      raise newException(ClipboardError, "Cannot write Windows clipboard")
  result.clipboard.clear = proc() =
    requireClipboard()
    if hostClipboardClear() == 0:
      raise newException(ClipboardError, "Cannot clear Windows clipboard")
  result.clipboard.readHTML = proc(): string =
    raise newException(UnsupportedBackendError, "Windows HTML clipboard is not implemented")
  result.clipboard.writeHTML = proc(html: string) =
    raise newException(UnsupportedBackendError, "Windows HTML clipboard is not implemented")
  result.dialogs = newUnsupportedDialogs("windows")
  installFileDialogs(result.dialogs)
  result.dialogs.message = proc(title, text: string): int =
    if hostMessage(newWideCString(title), newWideCString(text), 0) == 0:
      raise newException(BackendError, "MessageBoxW failed")
    0
  result.dialogs.messageWith = proc(title, text: string, buttons: seq[string]): int =
    if buttons != @["OK", "Cancel"]:
      raise newException(UnsupportedBackendError, "Windows message dialog currently supports OK/Cancel only")
    let answer = hostMessage(newWideCString(title), newWideCString(text), 1)
    if answer == 0: raise newException(BackendError, "MessageBoxW failed")
    if answer == 1: 0 else: 1
  result.init = proc(h: AppHandler, opts: AppOptions) =
    if initialized or hostInit(event) == 0:
      raise newException(BackendError, "Cannot initialize Win32 host (or already initialized)")
    initialized = true
    ownsHost = true
    appHandler = h
    callbackError = ""
  result.shutdown = proc() =
    if ownsHost:
      try: shutdownWindows()
      finally: ownsHost = false
  result.run = proc() =
    if not ownsHost or not initialized or running or hostMainThread() == 0:
      raise newException(BackendError, "Run requires initialized, idle host on its owning thread")
    running = true
    try:
      if appHandler.ready != nil: appHandler.ready()
      let status = hostRun()
      if callbackError.len > 0: raise newException(BackendError, callbackError)
      if status < 0: raise newException(BackendError, "GetMessageW failed")
    finally:
      try: shutdownWindows()
      finally: ownsHost = false
  result.quit = proc() =
    if ownsHost and initialized:
      if hostMainThread() == 0:
        raise newException(BackendError, "Quit must run on the owning thread; use postMain")
      if not shuttingDown: hostQuit()
  result.signal = proc() = hostSignal()
  result.wake = proc() = hostSignal()
  result.step = proc() = hostStep()
  result.isMainThread = proc(): bool = hostMainThread() != 0
  result.setMenu = proc(menu: PlatformMenu, handler: MenuHandler) =
    if not ownsHost or not initialized or hostMainThread() == 0:
      raise newException(BackendError, "Install menus on the initialized owning thread")
    let plan = planMenu(menu)
    var changed: seq[WindowState]
    try:
      for state in windowStates.values:
        winMenu.installMenu(state.handle, plan)
        changed.add state
    except:
      # Leave the old command routing in force; restore prior native menus.
      for state in changed:
        try: winMenu.installMenu(state.handle, state.menuPlan)
        except CatchableError:
          # Never leave a new native command mapped to an old callback.
          state.menuPlan = MenuPlan()
          state.menuHandler = MenuHandler()
      raise
    for state in changed:
      state.menuPlan = plan
      state.menuHandler = handler
    currentMenuPlan = plan
    currentMenuHandler = handler
  result.newWindow = proc(opts: PlatformWindowOptions, handler: WindowHandler): NativeWindow =
    if not ownsHost or not initialized or shuttingDown or hostMainThread() == 0:
      raise newException(BackendError, "Create windows on the main thread")
    if opts.html.len > 0 or opts.url.len > 0:
      raise newException(UnsupportedBackendError, "Windows WebView is not implemented yet")
    let handle = hostWindow(newWideCString(opts.title), cint(max(1, opts.width)),
                            cint(max(1, opts.height)), cint(opts.resizable))
    if handle == nil: raise newException(BackendError, "CreateWindowExW failed")
    let state = WindowState(handle: handle, handler: handler, imeEnabled: opts.ime,
                            imeActive: true)
    windowStates[handle] = state
    try:
      winMenu.installMenu(handle, currentMenuPlan)
      state.menuPlan = currentMenuPlan
      state.menuHandler = currentMenuHandler
    except:
      hostDestroy(handle)
      raise
    result = newUnsupportedNativeWindow("windows")
    result.id = handler.windowId
    result.testMenuKey = proc(keyCode: int, modifiers: uint32) =
      requireLive(state)
      winMenu.testMenuKey(state.handle, cuint(keyCode), cuint(modifiers))
    result.requestFrame = proc() =
      requireLive(state)
      hostInvalidate(state.handle)
    result.startAnimation = proc(fps: int) =
      requireLive(state)
      let rate = max(1, fps)
      if hostStartAnimation(state.handle, cint(rate)) == 0:
        raise newException(BackendError, "Cannot start the Windows animation timer")
      state.animating = true
      state.lastFrameTime = frameNow()
    result.stopAnimation = proc() =
      if state.handle != nil:
        hostStopAnimation(state.handle)
      state.animating = false
    result.setResizable = proc(enabled: bool) =
      requireLive(state)
      hostResizable(state.handle, cint(enabled))
    result.toggleFullScreen = proc() =
      requireLive(state)
      if hostFullscreen(state.handle, 1) < 0:
        raise newException(BackendError, "Cannot change fullscreen state")
    result.isFullScreen = proc(): bool =
      requireLive(state)
      hostFullscreen(state.handle, 0) != 0
    result.show = proc() =
      requireLive(state)
      hostShow(state.handle, 5)
    result.hide = proc() =
      requireLive(state)
      hostShow(state.handle, 0)
    result.close = proc() =
      if state.handle != nil:
        requireLive(state)
        hostClose(state.handle)
    result.destroy = proc() =
      if state.handle != nil:
        requireLive(state)
        hostDestroy(state.handle)
    result.setTitle = proc(title: string) =
      requireLive(state)
      hostTitle(state.handle, newWideCString(title))
      if state.handler.titleChanged != nil:
        state.handler.titleChanged(state.handler.windowId, title)
    result.setSize = proc(w, h: int) =
      requireLive(state)
      hostSize(state.handle, cint(max(1, w)), cint(max(1, h)))
    result.setPosition = proc(x, y: int) =
      requireLive(state)
      hostPosition(state.handle, cint(x), cint(y))
    result.center = proc() =
      requireLive(state)
      hostCenter(state.handle)
    result.focus = proc() =
      requireLive(state)
      hostFocus(state.handle)
    result.isFocused = proc(): bool =
      requireLive(state)
      hostFocused(state.handle) != 0
    result.setAlwaysOnTop = proc(on: bool) =
      requireLive(state)
      hostTopmost(state.handle, cint(on))
    result.minimize = proc() =
      requireLive(state)
      hostShow(state.handle, 6)
    result.deminimize = proc() =
      requireLive(state)
      hostShow(state.handle, 9)
    result.zoom = proc() =
      requireLive(state)
      hostZoom(state.handle)

    hostShow(handle, 5)
    syncIme(state)

proc clientSizeDip*(id: uint64): PlatformPoint =
  for state in windowStates.values:
    if state.handler.windowId == id:
      requireLive(state)
      hostClientSize(state.handle, addr result.x, addr result.y)
      return
  raise newException(BackendError, "Unknown Windows window")
