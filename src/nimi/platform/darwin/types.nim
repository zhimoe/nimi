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
    windowHandlers*: Table[uint64, WindowHandler]
    surfaceHandlers*: Table[uint64, SurfaceHandler]
    surfaceViews*: Table[uint64, Id]
    surfaceToId*: Table[pointer, uint64]
    delegateToId*: Table[pointer, uint64]
    webViews*: Table[uint64, Id]
    userContentControllers*: Table[uint64, Id]
    windowDelegates*: Table[uint64, Id]
    menuHandler*: MenuHandler
    menuTarget*: Id

var gState*: DarwinState
