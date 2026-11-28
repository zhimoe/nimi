## UI frame orchestration facade.
##
## Submodules:
## - `ui/node`:    data model, constructors, fluent modifiers, IME offsets
## - `ui/layout`:  two-pass flex, scroll, and text measurement & arrangement
## - `ui/paint`:   scene display-list emission and hit-region collection
## - `ui/editor`:  text editing, undo/redo, clipboard, and IME composition
## - `ui/input`:   pointer, wheel, focus traversal, shortcut, and key dispatch

import std/tables

import ./[editor, input, layout, node, paint]

export node, layout, paint, editor, input

proc render*(engine: Engine, view: proc(c: Context),
             width, height: float32): Scene =
  let c = initContext(width, height, engine)
  engine.shortcuts.clear()
  view(c)
  engine.pendingKeys.setLen(0)
  engine.pendingShortcuts.setLen(0)

  proc applyScroll(n: Node) =
    if n.kind == nkScroll:
      let maxOff = max(0.0'f32, n.contentH - n.h)
      let off = max(0.0'f32, min(engine.scrollOffsets.getOrDefault(n.key, 0), maxOff))
      engine.scrollOffsets[n.key] = off
      n.scrollY = off
    elif n.kind == nkInput and n.multiline:
      let viewport = n.inputViewport()
      let maxOff = max(0.0'f32, viewport.contentH - viewport.height)
      let off = max(0.0'f32, min(engine.scrollOffsets.getOrDefault(n.key, 0), maxOff))
      engine.scrollOffsets[n.key] = off
    for ch in n.children:
      applyScroll(ch)

  proc arrangeRoot(n: Node, w, h: float32) =
    let fw = n.fixedW
    let fh = n.fixedH
    if n.fill:
      n.fixedW = 0
      n.fixedH = 0
    arrange(n, 0, 0, w, h)
    n.fixedW = fw
    n.fixedH = fh

  engine.hits.setLen(0)
  engine.scrollRegions.setLen(0)
  engine.topModalLayer = 0
  if c.root != nil:
    measure(c.root, width, height)
    if c.root.fill:
      c.root.w = width
      c.root.h = height
    arrangeRoot(c.root, width, height)
    applyScroll(c.root)
    arrangeRoot(c.root, width, height)
    paint(c.root, c)
    collectHits(c.root, engine, Rect(x: 0, y: 0, w: width, h: height), 0)
  var layer = 0
  for o in c.overlays:
    inc layer
    measure(o, width, height)
    o.w = width
    o.h = height
    arrangeRoot(o, width, height)
    applyScroll(o)
    arrangeRoot(o, width, height)
    paint(o, c)
    collectHits(o, engine, Rect(x: 0, y: 0, w: width, h: height), layer)
    if o.modalOverlay:
      engine.topModalLayer = layer
  if engine.focusRequest.len > 0:
    for hit in engine.hits:
      if hit.key == engine.focusRequest:
        engine.focusedKey = hit.key
        engine.manuallyScrolledInput = ""
        if hit.input:
          engine.caretKey = hit.key
          engine.caretPos = hit.text.len
          engine.selectionAnchor =
            if engine.focusSelectAll: 0 else: hit.text.len
        break
    engine.focusRequest = ""
    engine.focusSelectAll = false
    engine.notifyFrame()
  result = c.scene
