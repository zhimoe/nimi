## Shared state for the GTK3 backend. Kept separate from app/window/menu so
## those modules can call each other without import cycles.

import std/tables

import ../contract

type
  MenuAction* = ref object
    label*: string
    role*: string
    callbackId*: uint32
    enabled*: bool
    checkable*: bool
    accelKey*: cuint
    accelMods*: cuint
    owner*: pointer

  LinuxWindow* = ref object
    id*: uint64
    window*: pointer
    box*: pointer
    content*: pointer
    drawing*: pointer
    menuBar*: pointer
    accelGroup*: pointer
    handler*: WindowHandler
    webview*: pointer
    userContentManager*: pointer
    scheme*: string
    fileRoot*: string
    usesWebView*: bool
    menuActions*: seq[MenuAction]
    animating*: bool
    animationSource*: cuint
    lastFrame*: float64
    closed*: bool

  LinuxState* = ref object
    handler*: AppHandler
    appName*: string
    initialized*: bool
    running*: bool
    loopActive*: bool
    quitRequested*: bool
    shuttingDown*: bool
    mainThreadId*: int
    displayHandler*: proc() {.closure.}
    themeHandler*: proc() {.closure.}

var
  linuxState*: LinuxState
  linuxWindows*: Table[pointer, LinuxWindow]
  linuxWindowsById*: Table[uint64, LinuxWindow]
  lastFocusedWindow*: LinuxWindow
  currentMenu*: PlatformMenu
  currentMenuHandler*: MenuHandler
