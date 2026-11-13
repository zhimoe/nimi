## Explicit failure defaults for partial platform implementations.
## Backends replace supported operations; no callback remains nil.
import ./contract

proc unsupported(platform, operation: string) {.noreturn.} =
  raise newException(UnsupportedBackendError, platform & ": unsupported operation " & operation)

proc newUnsupportedDialogs*(platform: string): Dialogs =
  result = Dialogs()
  result.open = proc(title, defaultPath: string, multiple, directory: bool): seq[string] =
    unsupported(platform, "Dialogs.open")
  result.openWith = proc(title, defaultPath: string, multiple, directory: bool, filters: seq[string]): seq[string] =
    unsupported(platform, "Dialogs.openWith")
  result.save = proc(title, defaultPath: string): string =
    unsupported(platform, "Dialogs.save")
  result.saveWith = proc(title, defaultPath, defaultExtension: string, filters: seq[string]): string =
    unsupported(platform, "Dialogs.saveWith")
  result.message = proc(title, text: string): int =
    unsupported(platform, "Dialogs.message")
  result.messageWith = proc(title, text: string, buttons: seq[string]): int =
    unsupported(platform, "Dialogs.messageWith")

proc newUnsupportedClipboard*(platform: string): Clipboard =
  result = Clipboard()
  result.readText = proc(): string =
    unsupported(platform, "Clipboard.readText")
  result.writeText = proc(text: string) =
    unsupported(platform, "Clipboard.writeText")
  result.readHTML = proc(): string =
    unsupported(platform, "Clipboard.readHTML")
  result.writeHTML = proc(html: string) =
    unsupported(platform, "Clipboard.writeHTML")
  result.clear = proc() =
    unsupported(platform, "Clipboard.clear")

proc newUnsupportedNativeWindow*(platform: string): NativeWindow =
  result = NativeWindow()
  result.setTitle = proc(title: string) =
    unsupported(platform, "NativeWindow.setTitle")
  result.show = proc() =
    unsupported(platform, "NativeWindow.show")
  result.hide = proc() =
    unsupported(platform, "NativeWindow.hide")
  result.focus = proc() =
    unsupported(platform, "NativeWindow.focus")
  result.close = proc() =
    unsupported(platform, "NativeWindow.close")
  result.center = proc() =
    unsupported(platform, "NativeWindow.center")
  result.minimize = proc() =
    unsupported(platform, "NativeWindow.minimize")
  result.deminimize = proc() =
    unsupported(platform, "NativeWindow.deminimize")
  result.zoom = proc() =
    unsupported(platform, "NativeWindow.zoom")
  result.toggleFullScreen = proc() =
    unsupported(platform, "NativeWindow.toggleFullScreen")
  result.isFullScreen = proc(): bool =
    unsupported(platform, "NativeWindow.isFullScreen")
  result.isFocused = proc(): bool =
    unsupported(platform, "NativeWindow.isFocused")
  result.setSize = proc(width, height: int) =
    unsupported(platform, "NativeWindow.setSize")
  result.setPosition = proc(x, y: int) =
    unsupported(platform, "NativeWindow.setPosition")
  result.setResizable = proc(resizable: bool) =
    unsupported(platform, "NativeWindow.setResizable")
  result.setAlwaysOnTop = proc(always: bool) =
    unsupported(platform, "NativeWindow.setAlwaysOnTop")
  result.loadHTML = proc(html: string, baseURL: string) =
    unsupported(platform, "NativeWindow.loadHTML")
  result.loadURL = proc(url: string) =
    unsupported(platform, "NativeWindow.loadURL")
  result.eval = proc(js: string) =
    unsupported(platform, "NativeWindow.eval")
  result.requestFrame = proc() =
    unsupported(platform, "NativeWindow.requestFrame")
  result.startAnimation = proc(fps: int) =
    unsupported(platform, "NativeWindow.startAnimation")
  result.stopAnimation = proc() =
    unsupported(platform, "NativeWindow.stopAnimation")
  result.testClick = proc(x, y: float32) =
    unsupported(platform, "NativeWindow.testClick")
  result.testKey = proc(keyCode: int) =
    unsupported(platform, "NativeWindow.testKey")
  result.testKeyText = proc(text: string) =
    unsupported(platform, "NativeWindow.testKeyText")
  result.testKeyMods = proc(keyCode: int, modifiers: uint32) =
    unsupported(platform, "NativeWindow.testKeyMods")
  result.testMenuKey = proc(keyCode: int, modifiers: uint32) =
    unsupported(platform, "NativeWindow.testMenuKey")
  result.destroy = proc() =
    unsupported(platform, "NativeWindow.destroy")

proc newUnsupportedBackend*(platform: string): Backend =
  result = Backend()
  result.init = proc(h: AppHandler, opts: AppOptions) =
    unsupported(platform, "Backend.init")
  result.run = proc() =
    unsupported(platform, "Backend.run")
  result.quit = proc() =
    unsupported(platform, "Backend.quit")
  result.signal = proc() =
    unsupported(platform, "Backend.signal")
  result.step = proc() =
    unsupported(platform, "Backend.step")
  result.wake = proc() =
    unsupported(platform, "Backend.wake")
  result.isMainThread = proc(): bool =
    unsupported(platform, "Backend.isMainThread")
  result.newWindow = proc(opts: PlatformWindowOptions, h: WindowHandler): NativeWindow =
    unsupported(platform, "Backend.newWindow")
  result.setMenu = proc(menu: PlatformMenu, h: MenuHandler) =
    unsupported(platform, "Backend.setMenu")
  result.newTray = proc(opts: PlatformTrayOptions): NativeTray =
    unsupported(platform, "Backend.newTray")
  result.notify = proc(n: PlatformNotification) =
    unsupported(platform, "Backend.notify")
  result.setNowPlaying = proc(info: PlatformNowPlayingInfo) =
    unsupported(platform, "Backend.setNowPlaying")
  result.clearNowPlaying = proc() =
    unsupported(platform, "Backend.clearNowPlaying")
  result.setMediaCommandHandler = proc(fn: proc(cmd: PlatformMediaCommand, position: float64)) =
    unsupported(platform, "Backend.setMediaCommandHandler")
  result.watchFiles = proc(path: string, h: proc(e: PlatformFileEvent)): NativeFileWatcher =
    unsupported(platform, "Backend.watchFiles")
  result.getCookies = proc(cb: proc(cookies: seq[PlatformCookie])) =
    unsupported(platform, "Backend.getCookies")
  result.clearCookies = proc(cb: proc()) =
    unsupported(platform, "Backend.clearCookies")
  result.registerShortcut = proc(accel: string, fn: proc()): bool =
    unsupported(platform, "Backend.registerShortcut")
  result.unregisterShortcut = proc(accel: string): bool =
    unsupported(platform, "Backend.unregisterShortcut")
  result.unregisterAllShortcuts = proc() =
    unsupported(platform, "Backend.unregisterAllShortcuts")
  result.screens = proc(): seq[PlatformDisplay] =
    unsupported(platform, "Backend.screens")
  result.cursorPosition = proc(): PlatformPoint =
    unsupported(platform, "Backend.cursorPosition")
  result.themeInfo = proc(): PlatformTheme =
    unsupported(platform, "Backend.themeInfo")
  result.onDisplayChanged = proc(cb: proc()) =
    unsupported(platform, "Backend.onDisplayChanged")
  result.onThemeChanged = proc(cb: proc()) =
    unsupported(platform, "Backend.onThemeChanged")
  result.shutdown = proc() =
    unsupported(platform, "Backend.shutdown")
  result.name = platform
  result.dialogs = newUnsupportedDialogs(platform)
  result.clipboard = newUnsupportedClipboard(platform)

