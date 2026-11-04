## Headless UI driver for tests and screenshots. It wraps the same Engine the
## window uses, so layout, hit testing and painting are identical.

import ./context
import ../scene/scene

type
  Tester* = ref object
    engine*: Engine
    view*: proc(c: Context) {.closure.}
    width*, height*: float32
    scene*: Scene

proc newTester*(view: proc(c: Context),
                width: float32 = 640, height: float32 = 480): Tester =
  Tester(engine: Engine(), view: view, width: width, height: height)

proc render*(t: Tester): Scene =
  t.scene = t.engine.render(t.view, t.width, t.height)
  result = t.scene

proc click*(t: Tester, key: string): bool =
  if t.engine.hits.len == 0:
    discard t.render()
  result = t.engine.clickKey(key)
  discard t.render()

proc clickAt*(t: Tester, x, y: float32) =
  if t.engine.hits.len == 0:
    discard t.render()
  t.engine.handleMouseDown(x, y)
  t.engine.handleMouseUp(x, y)
  discard t.render()

proc key*(t: Tester, key: string) =
  t.engine.handleKeyDown(key)
  discard t.render()

proc typeText*(t: Tester, text: string) =
  for ch in text:
    t.engine.handleKeyDown($ch)
  discard t.render()

proc resize*(t: Tester, width, height: float32) =
  t.width = width
  t.height = height

proc texts*(t: Tester): seq[string] =
  for op in t.scene.ops:
    if op.kind == opText:
      result.add op.text

proc hasText*(t: Tester, text: string): bool =
  text in t.texts()
