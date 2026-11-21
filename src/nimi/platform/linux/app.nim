## GTK3 backend: application lifecycle, main-context dispatching and the
## contract assembly. Native-only apps use GtkDrawingArea + Cairo; page apps
## additionally load WebKitGTK.

when not defined(linux):
  {.error: "The Linux backend requires Linux".}

import std/[tables]

import ../contract
import ../unsupported
import ./[clipboard, cookie, desktop, dialogs, ffi, menu, state, watch, window]

proc dispatchIdle(data: pointer): cint {.cdecl.} =
  if linuxState != nil and linuxState.handler.dispatch != nil:
    try:
      linuxState.handler.dispatch()
    except CatchableError:
      discard
  0

proc wakeLinuxMain*() {.gcsafe.} =
  ## Thread-safe wake for the GLib default context.
  {.cast(gcsafe).}:
    if g_idle_add != nil:
      discard g_idle_add(dispatchIdle, nil)

proc initLinuxBackend(state: LinuxState, h: AppHandler, opts: AppOptions) =
  ensureGtk()
  var argc: cint = 0
  var argv: pointer = nil
  if gtk_init_check(addr argc, addr argv) == 0:
    raise newException(BackendError,
      "Cannot open a GTK display; install the GTK3 runtime and run inside " &
      "X11 or Wayland (for CI use xvfb-run)")
  state.handler = h
  state.appName = opts.name
  state.mainThreadId = getThreadId()
  state.initialized = true
  linuxState = state
  initNotifications(opts.name)
  hookDesktopChanges()

proc shutdownLinux() =
  if linuxState == nil or not linuxState.initialized or linuxState.shuttingDown:
    return
  if getThreadId() != linuxState.mainThreadId:
    raise newException(BackendError,
      "Shutdown must run on the initializing thread")
  linuxState.shuttingDown = true
  try:
    var remaining: seq[LinuxWindow]
    for window in linuxWindows.values:
      remaining.add window
    for window in remaining:
      if window.window != nil:
        gtk_widget_destroy(window.window)
    cancelPendingCookies()
    closeAllWatches()
    shutdownDesktop()
    shutdownNotifications()
  finally:
    linuxWindows.clear()
    linuxWindowsById.clear()
    lastFocusedWindow = nil
    currentMenu = PlatformMenu()
    currentMenuHandler = MenuHandler()
    if linuxState != nil:
      linuxState.initialized = false
      linuxState.running = false
      linuxState.loopActive = false
      linuxState.quitRequested = false
      linuxState.shuttingDown = false
    linuxState = nil

proc newLinuxBackend*(): Backend =
  result = newUnsupportedBackend("linux")
  result.name = "linux/gtk"
  result.clipboard = newLinuxClipboard()
  result.dialogs = newLinuxDialogs()

  result.init = proc(h: AppHandler, opts: AppOptions) =
    if linuxState != nil and linuxState.initialized:
      raise newException(BackendError,
        "A Linux backend is already initialized")
    let state = LinuxState()
    initLinuxBackend(state, h, opts)

  result.run = proc() =
    if linuxState == nil or not linuxState.initialized:
      raise newException(BackendError, "Run requires an initialized backend")
    if linuxState.running:
      raise newException(BackendError, "Run is already active")
    if getThreadId() != linuxState.mainThreadId:
      raise newException(BackendError, "Run must execute on its owning thread")
    linuxState.running = true
    try:
      if linuxState.handler.ready != nil:
        linuxState.handler.ready()
      # Smoke tests and tiny apps may quit from ready() before gtk_main
      # starts; gtk_main_quit without a running loop only prints a critical.
      if not linuxState.quitRequested:
        linuxState.loopActive = true
        gtk_main()
        linuxState.loopActive = false
    finally:
      if linuxState != nil:
        linuxState.running = false
        linuxState.loopActive = false
        linuxState.quitRequested = false

  result.quit = proc() =
    if linuxState != nil and linuxState.initialized and
        not linuxState.shuttingDown:
      if getThreadId() != linuxState.mainThreadId:
        raise newException(BackendError,
          "Quit must run on the owning thread; use postMain")
      if linuxState.loopActive:
        gtk_main_quit()
      else:
        linuxState.quitRequested = true

  result.signal = proc() =
    wakeLinuxMain()

  result.wake = proc() =
    wakeLinuxMain()

  result.step = proc() =
    if ffi.gtkLoaded:
      discard g_main_context_iteration(nil, 0)

  result.isMainThread = proc(): bool =
    linuxState != nil and getThreadId() == linuxState.mainThreadId

  result.newWindow = proc(opts: PlatformWindowOptions,
                          h: WindowHandler): NativeWindow =
    createLinuxWindow(opts, h)

  result.setMenu = proc(platformMenu: PlatformMenu, h: MenuHandler) =
    if linuxState == nil or not linuxState.initialized:
      raise newException(BackendError,
        "Install menus on the initialized main thread")
    if getThreadId() != linuxState.mainThreadId:
      raise newException(BackendError,
        "Install menus on the initialized main thread")
    installMenuForAll(platformMenu, h)

  result.notify = proc(notification: PlatformNotification) =
    sendNotification(notification)

  result.screens = proc(): seq[PlatformDisplay] =
    screens()

  result.cursorPosition = proc(): PlatformPoint =
    cursorPosition()

  result.themeInfo = proc(): PlatformTheme =
    themeInfo()

  result.onDisplayChanged = proc(cb: proc()) =
    if linuxState != nil:
      linuxState.displayHandler = cb
      hookDesktopChanges()

  result.onThemeChanged = proc(cb: proc()) =
    if linuxState != nil:
      linuxState.themeHandler = cb
      hookDesktopChanges()

  result.watchFiles = proc(path: string,
                           h: proc(e: PlatformFileEvent)): NativeFileWatcher =
    watchFiles(path, h)

  result.getCookies = proc(cb: proc(cookies: seq[PlatformCookie])) =
    getCookies(cb)

  result.clearCookies = proc(cb: proc()) =
    clearCookies(cb)

  # GTK3 alone has no portable global-hotkey API (X11 grabs and the XDG
  # portal are separate integrations). Report failure instead of throwing.
  result.registerShortcut = proc(accel: string, fn: proc()): bool =
    false
  result.unregisterShortcut = proc(accel: string): bool =
    false
  result.unregisterAllShortcuts = proc() =
    discard

  result.shutdown = proc() =
    shutdownLinux()
