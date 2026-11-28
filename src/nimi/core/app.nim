## The application singleton, lifecycle, capability probes, and backend bridge.

import std/os

import ./[content, ipc, ipcpool, log, loop, menu, pageevents, paths, window]
import ../platform/[contract, loginargs]

when defined(macosx):
  import ../platform/darwin/app as darwinApp
  import ../render/cg
  import ../scene/scene
elif defined(windows):
  import ../platform/windows/app as windowsApp
  import ../render/gdi
  import ../scene/scene
elif defined(linux):
  import ../platform/linux/app as linuxApp
  import ../render/cairo
  import ../scene/scene

type
  QuitEvent* = object
    prevented*: bool

  App* = ref object
    name*: string
    slug*: string
    identifier*: string
    version*: string
    fixGuiPathOnStart*: bool
    ready*: bool
    quitting*: bool
    smokeQuitOnReady*: bool
    readyQueue*: seq[proc() {.closure.}]
    beforeQuitListeners*: seq[proc(e: var QuitEvent) {.closure.}]
    openURLListeners*: seq[proc(url: string) {.closure.}]
    menu*: Menu

var app* = App(
  name: "Nimi",
  slug: "nimi",
  identifier: "com.nimi.app",
  version: "0.2.0",
  fixGuiPathOnStart: true,
)

proc effectiveSlug*(a: App): string =
  if a.slug.len > 0 and a.slug != "nimi":
    sanitizeSlug(a.slug)
  elif a.name.len > 0:
    sanitizeSlug(a.name)
  else:
    "nimi"

proc setName*(a: App, name: string) =
  a.name = name
  if a.slug == "nimi" and name.len > 0:
    a.slug = sanitizeSlug(name)

proc setSlug*(a: App, slug: string) =
  a.slug = sanitizeSlug(slug)

proc setIdentifier*(a: App, identifier: string) =
  a.identifier = identifier

proc setVersion*(a: App, version: string) =
  a.version = version

proc dataDir*(a: App): string =
  appDataDir(a.effectiveSlug())

proc configDir*(a: App): string =
  appConfigDir(a.effectiveSlug())

proc cacheDir*(a: App): string =
  appCacheDir(a.effectiveSlug())

proc logDir*(a: App): string =
  appLogDir(a.effectiveSlug())

proc capabilities*(a: App): set[PlatformCapability] =
  if currentBackend != nil and currentBackend.capabilities != nil:
    currentBackend.capabilities()
  else:
    {}

proc supports*(a: App, cap: PlatformCapability): bool =
  cap in a.capabilities()

proc isReady*(a: App): bool =
  a.ready

proc whenReady*(a: App, fn: proc()) =
  if a.ready:
    if isMainThread():
      fn()
    else:
      discard postMain(fn)
  else:
    a.readyQueue.add fn

proc onReady*(a: App, fn: proc()) =
  a.whenReady(fn)

proc onBeforeQuit*(a: App, fn: proc(e: var QuitEvent)) =
  a.beforeQuitListeners.add fn

proc onOpenURL*(a: App, fn: proc(url: string)) =
  a.openURLListeners.add fn

proc setOpenAtLogin*(a: App, enabled: bool) =
  if currentBackend == nil or currentBackend.setOpenAtLogin == nil:
    raise newException(BackendError,
      "setOpenAtLogin requires a running application")
  currentBackend.setOpenAtLogin(enabled)

proc openAtLogin*(a: App): bool =
  currentBackend != nil and currentBackend.openAtLogin != nil and
    currentBackend.openAtLogin()

proc wasOpenedAtLogin*(a: App): bool =
  hasOpenedAtLoginArg(commandLineParams()) or
    (currentBackend != nil and currentBackend.wasOpenedAtLogin != nil and
     currentBackend.wasOpenedAtLogin())

proc installMenu*(a: App) =
  if currentBackend == nil:
    return
  when defined(windows):
    if a.menu == nil:
      currentBackend.setMenu(PlatformMenu(), MenuHandler())
      return
  let m = if a.menu != nil: a.menu else: defaultMenu(a.name)
  let (platform, handler) = toPlatformMenu(m)
  currentBackend.setMenu(platform, handler)

proc setMenu*(a: App, m: Menu) =
  let previous = a.menu
  a.menu = m
  try:
    if a.ready and currentBackend != nil:
      onMain(proc() = installMenu(a))
  except:
    a.menu = previous
    raise

proc refreshMenu*(a: App) =
  if a.ready and currentBackend != nil:
    onMain(proc() = installMenu(a))

proc setMenuItemEnabled*(a: App, label: string, enabled: bool): bool =
  if a.menu == nil:
    return false
  result = setEnabled(a.menu, label, enabled)
  if result:
    a.refreshMenu()

proc setMenuItemChecked*(a: App, label: string, checked: bool): bool =
  if a.menu == nil:
    return false
  result = setChecked(a.menu, label, checked)
  if result:
    a.refreshMenu()

proc requestQuit*(a: App): bool =
  if a.quitting:
    return true
  var e = QuitEvent()
  for fn in a.beforeQuitListeners:
    fn(e)
  if e.prevented:
    return false
  a.quitting = true
  if currentBackend != nil:
    currentBackend.quit()
  result = true

proc quit*(a: App) =
  discard a.requestQuit()

proc exit*(a: App, code: int) =
  if currentBackend != nil:
    currentBackend.quit()
  system.quit(code)

proc reportFirstPaint*(a: App, metadata: string = "") =
  ## Standardized first-paint smoke protocol (`--smoke` / `NIMI_SMOKE_OUT`).
  let line = if metadata.len > 0: "first_paint " & metadata else: "first_paint"
  let smokeOut = getEnv("NIMI_SMOKE_OUT")
  if smokeOut.len > 0:
    try:
      writeFile(smokeOut, line & "\n")
    except CatchableError:
      discard
  if a.smokeQuitOnReady or getEnv("NIMI_SMOKE") == "quit":
    discard postMain(proc() = a.quit())

proc run*(a: App) =
  ## Must be called from the process main thread.
  let generatePath = getEnv("NIMI_GENERATE")
  if generatePath.len > 0:
    if services.len > 0 or backgroundServices.len > 0:
      writeFile(generatePath, generateTypeScript())
    return

  initLoop()
  windowStateSlug = a.effectiveSlug()
  if a.fixGuiPathOnStart:
    fixGuiPath()
  for arg in commandLineParams():
    if arg in ["--smoke", "--nimi-smoke"]:
      a.smokeQuitOnReady = true

  when defined(macosx) or defined(windows) or defined(linux):
    if currentBackend != nil:
      raise newException(BackendError, "An application backend is already active")
    defaultContentRenderer = proc(ctx: pointer, scene: Scene) =
      drawScene(ctx, scene)
    when defined(macosx):
      let backend = darwinApp.newDarwinBackend()
    elif defined(windows):
      let backend = windowsApp.newWindowsBackend()
    else:
      let backend = linuxApp.newLinuxBackend()
    currentBackend = backend
    setLoopHooks(backend.signal, backend.isMainThread)
    when defined(macosx):
      setWakeHook(darwinApp.wakeMain)
    elif defined(windows):
      setWakeHook(windowsApp.wakeWindowsMain)
    else:
      setWakeHook(linuxApp.wakeLinuxMain)
    allClosedHook = proc() =
      if not a.quitting:
        discard a.requestQuit()

    var handler = AppHandler()
    handler.ready = proc() =
      a.ready = true
      let queued = a.readyQueue
      a.readyQueue = @[]
      for fn in queued:
        fn()
    handler.quitRequested = proc(): bool =
      a.requestQuit()
    handler.terminated = proc() =
      discard
    handler.openURL = proc(url: string) =
      for fn in a.openURLListeners:
        fn(url)
    handler.dispatch = proc() =
      drainMain()
      drainIpcPool()
      drainPageEvents()
    try:
      backend.init(handler, AppOptions(name: a.name, identifier: a.identifier))
      installMenu(a)
      backend.run()
    except CatchableError as e:
      discard writeCrashLog("app.run", $e.name & ": " & e.msg, a.effectiveSlug())
      raise
    finally:
      try:
        if backend.shutdown != nil: backend.shutdown()
      finally:
        setIpcCompletion(nil)
        shutdownIpcPool(200)
        shutdownLoop()
        currentBackend = nil
        allClosedHook = nil
        a.ready = false
  else:
    raise newException(BackendError,
      "nimi: this platform has no application backend")
