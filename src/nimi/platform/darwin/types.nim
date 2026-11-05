## Shared Darwin backend state. Kept in one module so app.nim and window.nim
## can use it without a circular import.

import std/tables

import ../contract
import ./objc

type
  DarwinState* = ref object
    nsApp*: Id
    appDelegate*: Id
    handler*: AppHandler
    quitting*: bool
    nextWindowId*: uint64
    nextTrayId*: uint64
    windowHandlers*: Table[uint64, WindowHandler]
    surfaceHandlers*: Table[uint64, SurfaceHandler]
    surfaceViews*: Table[uint64, Id]
    surfaceToId*: Table[pointer, uint64]
    delegateToId*: Table[pointer, uint64]
    webViews*: Table[uint64, Id]
    userContentControllers*: Table[uint64, Id]
    windowDelegates*: Table[uint64, Id]
    menuTargets*: Table[pointer, MenuHandler]
    appMenuTarget*: Id
    trays*: Table[uint64, Id]
    trayTargets*: Table[uint64, Id]
    schemeRoots*: Table[pointer, string]
    schemeHandlers*: Table[uint64, Id]
    imeWindows*: Table[uint64, bool]
    inputContexts*: Table[pointer, Id]
    windowTimers*: Table[uint64, Id]
    animationLast*: Table[uint64, float64]
    nextWatchId*: uint64
    watchStreams*: Table[uint64, pointer]
    watchHandlers*: Table[uint64, proc(e: PlatformFileEvent) {.closure.}]
    shortcutRefs*: Table[string, pointer]
    shortcutCallbacks*: Table[uint32, proc()]
    nextShortcutId*: uint32
    shortcutHandler*: pointer
    shortcutsInstalled*: bool
    displayHandler*: proc() {.closure.}
    themeHandler*: proc() {.closure.}
    notificationObserver*: Id

var gState*: DarwinState
