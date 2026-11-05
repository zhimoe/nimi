## Screen/display information. Coordinates use a top-left origin relative to
## the primary display, matching the native UI scene convention.

import ../platform/contract

type
  Display* = object
    id*: string
    name*: string
    x*, y*: float32
    width*, height*: float32
    workX*, workY*: float32
    workWidth*, workHeight*: float32
    scale*: float32
    primary*: bool

  ScreenPoint* = object
    x*, y*: float32

var screenListeners: seq[proc() {.closure.}]
var screenHooked = false

proc ensureHook() =
  if screenHooked or currentBackend == nil:
    return
  screenHooked = true
  if currentBackend.onDisplayChanged != nil:
    currentBackend.onDisplayChanged(proc() =
      for fn in screenListeners:
        fn())

proc screens*(): seq[Display] =
  ensureHook()
  if currentBackend == nil or currentBackend.screens == nil:
    return @[]
  for p in currentBackend.screens():
    result.add Display(
      id: p.id,
      name: p.name,
      x: p.x, y: p.y,
      width: p.width, height: p.height,
      workX: p.workX, workY: p.workY,
      workWidth: p.workWidth, workHeight: p.workHeight,
      scale: p.scale,
      primary: p.primary)

proc primaryDisplay*(): Display =
  for d in screens():
    if d.primary:
      return d
  let all = screens()
  if all.len > 0:
    result = all[0]

proc cursorPosition*(): ScreenPoint =
  ensureHook()
  if currentBackend != nil and currentBackend.cursorPosition != nil:
    let p = currentBackend.cursorPosition()
    result = ScreenPoint(x: p.x, y: p.y)

proc onScreensChanged*(fn: proc()) =
  ensureHook()
  screenListeners.add fn
