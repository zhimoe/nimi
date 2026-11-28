## Pointer, scrollbar, wheel, focus traversal, shortcut, and keyboard dispatch.

import std/tables

import ./[editor, node]
import ../keys

proc hitIndex*(engine: Engine, x, y: float32): int =
  for i in countdown(engine.hits.len - 1, 0):
    let r = engine.hits[i].rect
    let c = engine.hits[i].clip
    if c.w <= 0 or c.h <= 0 or
        x < c.x or x >= c.x + c.w or y < c.y or y >= c.y + c.h:
      continue
    if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h:
      return i
  result = -1

proc moveScrollbar*(engine: Engine, x, y: float32) =
  let drag = engine.scrollbarDrag
  let bar = drag.scrollbar
  let position = if bar.horizontal: x else: y
  let offset = clamp((position - drag.trackStart - drag.grab) / drag.travel,
                     0'f32, 1'f32) * bar.maximum
  if bar.horizontal: engine.manualScrollX(bar.inputKey, offset)
  else: engine.scrollOffsets[bar.inputKey] = offset

proc beginScrollbarDrag*(engine: Engine, hit: Hit, x, y: float32) =
  let bar = hit.scrollbar
  let position = if bar.horizontal: x else: y
  let thumbStart = if bar.horizontal: bar.thumb.x else: bar.thumb.y
  let thumbLength = if bar.horizontal: bar.thumb.w else: bar.thumb.h
  let trackLength = if bar.horizontal: hit.rect.w else: hit.rect.h
  let travel = trackLength - thumbLength
  if travel <= 0: return
  engine.scrollbarDrag = InputScrollbarDrag(scrollbar: bar, travel: travel,
    trackStart: (if bar.horizontal: hit.rect.x else: hit.rect.y),
    grab: (if bar.thumb.contains(x, y): position - thumbStart else: thumbLength / 2))
  engine.moveScrollbar(x, y)

proc handleMouseDown*(engine: Engine, x, y: float32, clicks: int = 1) =
  engine.lastMouseX = x
  engine.lastMouseY = y
  let i = hitIndex(engine, x, y)
  engine.pressedDrag = nil
  engine.scrollbarDrag = InputScrollbarDrag()
  if i >= 0:
    let hit = engine.hits[i]
    if clicks >= 2 and hit.onDoubleClick != nil:
      engine.pressedKey = ""
      hit.onDoubleClick()
      engine.notifyFrame()
      return
    engine.pressedKey = hit.key
    if engine.markedText.len > 0 and engine.markedKey != hit.key:
      engine.markedText.setLen(0)
      engine.markedKey = ""
    if hit.focusable:
      engine.focusedKey = hit.key
    if hit.scrollbar.inputKey.len > 0:
      engine.beginScrollbarDrag(hit, x, y)
    elif hit.onDrag != nil:
      engine.pressedDrag = hit.onDrag
      engine.pressedRect = hit.rect
      hit.onDrag(hit.rect, x, y)
    if hit.input:
      engine.manuallyScrolledInput = ""
      engine.caretKey = hit.key
      let displayCaret = caretIndexAt(
        hit, x, y, engine.scrollOffsets.getOrDefault(hit.key, 0))
      engine.caretPos = displayByteToDoc(engine, hit.key, hit.text, displayCaret)
      engine.selectionAnchor = engine.caretPos
      engine.selectingInput = hit.key
      if clicks >= 2:
        engine.selectWordOrLine(hit, clicks)
  else:
    engine.pressedKey = ""
  engine.notifyFrame()

proc handleMouseUp*(engine: Engine, x, y: float32) =
  let i = hitIndex(engine, x, y)
  if i >= 0 and engine.pressedKey == engine.hits[i].key:
    if engine.hits[i].onClick != nil:
      engine.hits[i].onClick()
  engine.pressedKey = ""
  engine.pressedDrag = nil
  engine.scrollbarDrag = InputScrollbarDrag()
  engine.selectingInput = ""
  engine.notifyFrame()

proc handleMouseMove*(engine: Engine, x, y: float32) =
  engine.lastMouseX = x
  engine.lastMouseY = y
  if engine.scrollbarDrag.travel > 0:
    engine.moveScrollbar(x, y)
    engine.notifyFrame()
    return
  if engine.pressedDrag != nil:
    engine.pressedDrag(engine.pressedRect, x, y)
    engine.notifyFrame()
    return
  if engine.selectingInput.len > 0:
    for hit in engine.hits:
      if hit.key == engine.selectingInput and hit.input:
        let displayCaret = caretIndexAt(
          hit, x, y, engine.scrollOffsets.getOrDefault(hit.key, 0))
        engine.caretPos = displayByteToDoc(engine, hit.key, hit.text, displayCaret)
        engine.notifyFrame()
        return
  let i = hitIndex(engine, x, y)
  let key = if i >= 0: engine.hits[i].key else: ""
  if key != engine.hoveredKey:
    engine.hoveredKey = key
    engine.notifyFrame()

proc keyPressed*(c: Context, key: string): bool =
  if c.engine == nil:
    return false
  for i in 0 ..< c.engine.pendingKeys.len:
    if c.engine.pendingKeys[i] == key:
      c.engine.pendingKeys[i] = c.engine.pendingKeys[^1]
      c.engine.pendingKeys.setLen(c.engine.pendingKeys.len - 1)
      return true
  result = false

proc pageScroll*(engine: Engine, pages: float32) =
  var region: ScrollRegion
  var found = false
  for i in countdown(engine.scrollRegions.len - 1, 0):
    let r = engine.scrollRegions[i]
    if r.layer >= engine.topModalLayer and r.rect.contains(engine.lastMouseX, engine.lastMouseY):
      region = r
      found = true
      break
  if not found:
    for r in engine.scrollRegions:
      if r.layer >= engine.topModalLayer and r.rect.w > 0 and r.rect.h > 0 and
          r.key == engine.focusedKey:
        region = r
        found = true
        break
  if not found:
    for r in engine.scrollRegions:
      if r.layer >= engine.topModalLayer and r.rect.w > 0 and r.rect.h > 0:
        region = r
        found = true
        break
  if not found:
    return
  let maxOff = max(0.0'f32, region.contentH - region.viewportH)
  let old = engine.scrollOffsets.getOrDefault(region.key, 0)
  let next = max(0.0'f32, min(old + pages * region.viewportH * 0.8, maxOff))
  if next != old:
    engine.scrollOffsets[region.key] = next
    engine.notifyFrame()

proc handleKeyDown*(engine: Engine, key: string, modifiers: uint32 = 0) =
  if key.len == 0:
    return
  if key == "pageup" or key == "pagedown":
    engine.pageScroll(if key == "pageup": -1.0'f32 else: 1.0'f32)
    return
  if key == "tab":
    var stops: seq[int]
    for i in 0 ..< engine.hits.len:
      let hit = engine.hits[i]
      if hit.tabStop and
          (engine.topModalLayer == 0 or hit.layer == engine.topModalLayer):
        let visible = intersect(hit.rect, hit.clip)
        if visible.w > 0 and visible.h > 0:
          stops.add i
    if stops.len > 0:
      var current = -1
      for k, idx in stops:
        if engine.hits[idx].key == engine.focusedKey:
          current = k
      let step = if (modifiers and KeyShift) != 0: -1 else: 1
      let next =
        if current < 0: 0
        else: (current + step + stops.len) mod stops.len
      engine.clearComposition()
      engine.focusedKey = engine.hits[stops[next]].key
      engine.manuallyScrolledInput = ""
      engine.caretKey = ""
      engine.selectionAnchor = 0
      engine.notifyFrame()
    return
  var focused = -1
  var focusedInput = false
  for i in 0 ..< engine.hits.len:
    if engine.hits[i].key == engine.focusedKey:
      focused = i
      focusedInput = engine.hits[i].input
  let shortcutMods = modifiers and (KeyShortcut or KeyAlt)
  if not focusedInput or shortcutMods != 0 or key == "escape":
    let shortcut = engine.shortcuts.getOrDefault(shortcutKey(key, modifiers))
    if shortcut != nil:
      shortcut()
      engine.notifyFrame()
      return
  if focused >= 0 and engine.hits[focused].input:
    editInput(engine, focused, key, modifiers)
    return
  if (modifiers and KeyShortcut) != 0:
    return
  if key in ["enter", "space"]:
    for hit in engine.hits:
      if hit.key == engine.focusedKey:
        let fn =
          if key == "enter" and hit.onActivate != nil: hit.onActivate
          elif key == "space" and hit.onSpace != nil: hit.onSpace
          else: hit.onClick
        if fn != nil:
          fn()
          engine.notifyFrame()
        break
    return
  engine.pendingKeys.add key
  engine.notifyFrame()

proc handleScroll*(engine: Engine, x, y, dy: float32) =
  for i in countdown(engine.scrollRegions.len - 1, 0):
    let r = engine.scrollRegions[i]
    if r.layer >= engine.topModalLayer and r.rect.contains(x, y):
      let maxOff = max(0.0'f32, r.contentH - r.viewportH)
      let old = engine.scrollOffsets.getOrDefault(r.key, 0)
      let next = max(0.0'f32, min(old + dy, maxOff))
      if next != old:
        engine.scrollOffsets[r.key] = next
        engine.notifyFrame()
      return

proc handleHorizontalScroll*(engine: Engine, x, y, dx: float32): bool {.discardable.} =
  let index = engine.hitIndex(x, y)
  if index < 0 or engine.hits[index].layer < engine.topModalLayer: return
  let target = engine.hits[index]
  let key = if target.input: target.key else: target.scrollbar.inputKey
  if key.len == 0: return
  for hit in engine.hits:
    if hit.input and hit.layer == target.layer and hit.key == key and hit.maxScrollX > 0:
      let old = engine.inputOffsets.getOrDefault(key)
      let next = clamp(old + dx, 0'f32, hit.maxScrollX)
      if next != old:
        engine.manualScrollX(key, next)
        engine.notifyFrame()
      return true

proc clickKey*(engine: Engine, key: string): bool =
  for hit in engine.hits:
    if hit.key == key:
      let x = hit.rect.x + hit.rect.w / 2
      let y = hit.rect.y + hit.rect.h / 2
      engine.handleMouseDown(x, y)
      engine.handleMouseUp(x, y)
      return true
  result = false
