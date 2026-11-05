## A window's native content: a view function over the M2 Context.

import ../scene/scene
import ../ui/context

type
  Content* = ref object
    view*: proc(c: Context) {.closure.}
    engine*: Engine

proc uiView*(view: proc(c: Context)): Content =
  Content(view: view, engine: Engine())

proc renderContent*(content: Content, width, height: float32): Scene =
  result = content.engine.render(content.view, width, height)

proc handleMouseDown*(content: Content, x, y: float32) =
  content.engine.handleMouseDown(x, y)

proc handleMouseUp*(content: Content, x, y: float32) =
  content.engine.handleMouseUp(x, y)

proc handleMouseMove*(content: Content, x, y: float32) =
  content.engine.handleMouseMove(x, y)

proc clickKey*(content: Content, key: string): bool =
  content.engine.clickKey(key)

proc handleKeyDown*(content: Content, key: string, modifiers: uint32 = 0) =
  content.engine.handleKeyDown(key, modifiers)

proc copySelection*(content: Content) =
  content.engine.copySelection()

proc cutSelection*(content: Content) =
  content.engine.cutSelection()

proc paste*(content: Content) =
  content.engine.paste()

proc selectAll*(content: Content) =
  content.engine.selectAll()
