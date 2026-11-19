## Native Nimi Windows environment-variable editor.

import std/[os, strutils, times]

import nimi
import nimi/ui

when defined(windows):
  import nimi/platform/windows/environment
  import nimi/platform/windows/app as winApp

import ./[service, state, storage, view]

proc dataDirFromArgs(): string =
  for arg in commandLineParams():
    if arg.startsWith("--data-dir="):
      return arg["--data-dir=".len .. ^1]
  when defined(windows):
    getEnv("LOCALAPPDATA", getHomeDir() / "AppData" / "Local") /
      "Nimi" / "Environment"
  else:
    getConfigDir() / "nimi-environment"

proc saveWindowState(appState: AppState) =
  if appState.window == nil:
    return
  let size = appState.window.getSize()
  let position = appState.window.getPosition()
  if size.width > 0 and size.height > 0:
    appState.settings.hasWindow = true
    appState.settings.windowWidth = size.width
    appState.settings.windowHeight = size.height
    if position.x != 0 or position.y != 0:
      appState.settings.windowX = position.x
      appState.settings.windowY = position.y
  appState.saveSettings()

when isMainModule:
  let dataDir = dataDirFromArgs()
  let backups = newStore(dataDir)
  when defined(windows):
    let envStore = newWindowsEnvironmentStore()
  else:
    raise newException(OSError, "Nimi Environment requires Windows")
  let envService = newService(envStore, backups)
  let appState = newAppState(envService, backups, dataDir)
  var win: Window

  appState.now = proc(): float64 = epochTime()
  appState.clipboardWrite = proc(text: string) = clipboard.writeText(text)
  appState.saveDialog = proc(defaultName: string): string =
    dialog.save("导出环境变量", defaultName, "env", @["env"])
  when defined(windows):
    appState.expandPath = proc(path: string): string =
      winApp.expandEnvironment(path)
    appState.pathExists = proc(path: string): bool = dirExists(path) or fileExists(path)
    appState.elevated = proc(): bool = winApp.isElevated()
    appState.relaunchElevated = proc(args: string): string =
      winApp.relaunchElevated(args)
  appState.quit = proc() = app.quit()

  appState.initApp()
  appState.applyPending()

  onThemeChanged(proc() =
    when defined(windows):
      appState.systemDark = isDark()
      appState.textScale = winApp.textScale()
      appState.highContrast = winApp.highContrast()
      if appState.window != nil:
        appState.window.setDarkAppearance(appState.effectiveDark())
        appState.window.invalidate())

  app.whenReady(proc() =
    when defined(windows):
      appState.systemDark = isDark()
      appState.textScale = winApp.textScale()
      appState.highContrast = winApp.highContrast()
    let width =
      if appState.settings.hasWindow and appState.settings.windowWidth > 0:
        appState.settings.windowWidth
      else:
        1180
    let height =
      if appState.settings.hasWindow and appState.settings.windowHeight > 0:
        appState.settings.windowHeight
      else:
        780
    win = newWindow(WindowOptions(
      title: "Nimi Environment Manager",
      width: width,
      height: height,
      content: uiView(proc(c: Context) = appState.appView(c)),
      ime: true))
    appState.window = win
    win.setDarkAppearance(appState.effectiveDark())
    if appState.settings.hasWindow and
        (appState.settings.windowX != 0 or appState.settings.windowY != 0):
      win.setPosition(appState.settings.windowX, appState.settings.windowY)
    when defined(windows):
      winApp.fitWindowToWorkArea(win.id)
    win.onClose(proc(e: var CloseEvent) =
      if appState.allowClose:
        saveWindowState(appState)
        return
      if appState.hasUnsaved():
        e.prevented = true
        appState.openDiscard("退出 Nimi Env", proc() =
          appState.allowClose = true
          win.close())
      else:
        saveWindowState(appState))
    win.onClosed(proc() =
      if appState.window == win:
        appState.window = nil)
    if appState.startupToast.len > 0:
      appState.showToast(appState.startupToast)
      appState.startupToast = ""
    win.invalidate())

  app.run()
