## The application singleton, lifecycle and the backend bridge.

import std/[os, tables]

import ./[content, ipc, ipcpool, loop, menu, window]
import ../platform/contract

when defined(macosx):
  import ../platform/darwin/app as darwinApp
  import ../render/cg
  import ../scene/scene
elif defined(windows):
  import ../platform/windows/app as windowsApp
  import ../render/gdi
  import ../scene/scene

type
  QuitEvent* = object
    prevented*: bool

  App* = ref object
    name*: string
    version*: string
    ready*: bool
    quitting*: bool
    readyQueue*: seq[proc() {.closure.}]
    beforeQuitListeners*: seq[proc(e: var QuitEvent) {.closure.}]
    openURLListeners*: seq[proc(url: string) {.closure.}]
    menu*: Menu

var app* = App(name: "Nimi", version: "0.1.0")

proc setName*(a: App, name: string) =
  a.name = name

proc setVersion*(a: App, version: string) =
  a.version = version

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

proc toPlatform(k: MenuItemKind): PlatformMenuItemKind =
  case k
  of miNormal: pmiNormal
  of miSeparator: pmiSeparator
  of miSubmenu: pmiSubmenu
  of miCheckbox: pmiCheckbox

proc buildItems(items: seq[MenuItem],
                nextId: var uint32, callbacks: var Table[uint32, proc()]): seq[PlatformMenuItem] =
  for item in items:
    var p = PlatformMenuItem(
      label: item.label,
      kind: toPlatform(item.kind),
      role: item.role,
      accelerator: item.accelerator,
      checked: item.checked,
      enabled: item.enabled)
    if item.kind == miSubmenu:
      p.submenu = buildItems(item.submenu, nextId, callbacks)
    elif item.onSelect != nil:
      inc nextId
      p.id = nextId
      callbacks[p.id] = item.onSelect
    result.add p

proc installMenu*(a: App) =
  if currentBackend == nil:
    return
  when defined(windows):
    if a.menu == nil:
      currentBackend.setMenu(PlatformMenu(), MenuHandler())
      return # Clearing a Windows menu must detach the previous native menus.
  let m = if a.menu != nil: a.menu else: defaultMenu(a.name)
  var nextId = 0'u32
  var callbacks: Table[uint32, proc()]
  let platform = PlatformMenu(items: buildItems(m.items, nextId, callbacks))
  let handler = MenuHandler(select: proc(id: uint32) =
    let cb = callbacks.getOrDefault(id)
    if cb != nil:
      cb())
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

proc run*(a: App) =
  ## Must be called from the process main thread.
  let generatePath = getEnv("NIMI_GENERATE")
  if generatePath.len > 0:
    if services.len > 0:
      writeFile(generatePath, generateTypeScript())
    return

  when defined(macosx) or defined(windows):
    if currentBackend != nil:
      raise newException(BackendError, "An application backend is already active")
    defaultContentRenderer = proc(ctx: pointer, scene: Scene) =
      drawScene(ctx, scene)
    when defined(macosx):
      let backend = darwinApp.newDarwinBackend()
    else:
      let backend = windowsApp.newWindowsBackend()
    currentBackend = backend
    setLoopHooks(backend.signal, backend.isMainThread)
    when defined(macosx):
      setWakeHook(darwinApp.wakeMain)
    else:
      setWakeHook(windowsApp.wakeWindowsMain)
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
    try:
      backend.init(handler, AppOptions(name: a.name))
      installMenu(a)
      backend.run()
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
