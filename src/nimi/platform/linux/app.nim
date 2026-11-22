## GTK3 backend: application lifecycle, main-context dispatching and the
## contract assembly. Native-only apps use GtkDrawingArea + Cairo; page apps
## additionally load WebKitGTK.

when not defined(linux):
  {.error: "The Linux backend requires Linux".}

import std/[os, tables]

import ../contract
import ../unsupported
import ./[clipboard, cookie, desktop, dialogs, ffi, instance, menu, nowplaying,
           shortcuts, state, tray, watch, window]

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

proc installAppIcon() =
  if gtk_window_set_default_icon_from_file == nil:
    return
  let directory = getAppDir()
  let exeName = splitFile(getAppFilename()).name
  for candidate in [directory / (exeName & ".png"), directory / "icon.png",
                    directory / "resources" / "icon.png"]:
    if fileExists(candidate):
      if gtk_window_set_default_icon_from_file(candidate.cstring, nil) != 0:
        return

proc initLinuxBackend(state: LinuxState, h: AppHandler, opts: AppOptions) =
  ensureGtk()
  var argc: cint = 0
  var argv: pointer = nil
  if gtk_init_check(addr argc, addr argv) == 0:
    raise newException(BackendError,
      "Cannot open a GTK display; install the GTK3 runtime and run inside " &
      "X11 or Wayland (for CI use xvfb-run)")
  installAppIcon()
  state.handler = h
  state.appName = opts.name
  state.mainThreadId = getThreadId()
  state.initialized = true
  linuxState = state
  initNotifications(opts.name)
  hookDesktopChanges()
  discard initInstance(h)

proc shutdownLinux() =
  if linuxState == nil or not linuxState.initialized or linuxState.shuttingDown:
    return
  if getThreadId() != linuxState.mainThreadId:
    raise newException(BackendError,
      "Shutdown must run on the initializing thread")
  linuxState.shuttingDown = true
  try:
    shutdownInstance()
    unregisterAllShortcuts()
    shutdownNowPlaying()
    closeTray()
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
  installShortcutBackend(result)
  installNowPlayingBackend(result)

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
      if isSecondaryInstance():
        return
      if linuxState.handler.ready != nil:
        linuxState.handler.ready()
      if linuxState.handler.openURL != nil:
        for url in initialURLs():
          linuxState.handler.openURL(url)
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

  result.newTray = proc(opts: PlatformTrayOptions): NativeTray =
    createTray(opts)

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

  result.shutdown = proc() =
    shutdownLinux()
