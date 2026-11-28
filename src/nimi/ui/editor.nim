## Single-line & multiline text editing, undo/redo stacks, clipboard actions,
## grapheme-aware caret hit-testing, and IME composition protocol.

import std/[strutils, tables]

import ./node
import ../keys
import ../text/[grapheme, measure, range]

proc hitIndexInEditor(engine: Engine, x, y: float32): int =
  for i in countdown(engine.hits.len - 1, 0):
    let r = engine.hits[i].rect
    let c = engine.hits[i].clip
    if c.w <= 0 or c.h <= 0 or
        x < c.x or x >= c.x + c.w or y < c.y or y >= c.y + c.h:
      continue
    if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h:
      return i
  result = -1

proc caretIndexLine*(text: string, x, left, fontSize: float32,
                     family: string): int =
  let local = x - left
  if local <= 0:
    return 0
  var best = 0
  var bestDist = abs(local)
  for boundary in graphemeBoundaries(text):
    if boundary == 0:
      continue
    let width = measureText(text[0 ..< boundary], fontSize, false,
                            family).width
    let distance = abs(width - local)
    if distance < bestDist:
      bestDist = distance
      best = boundary
  if local > measureText(text, fontSize, false, family).width:
    best = text.len
  result = best

proc hitText*(hit: Hit): string =
  if hit.displayText.len > 0: hit.displayText else: hit.text

proc caretIndex*(hit: Hit, x: float32): int =
  result = caretIndexLine(hitText(hit), x,
    hit.rect.x + hit.padX - hit.scrollX, hit.fontSize, hit.family)

proc caretIndexAt*(hit: Hit, x, y: float32, scrollY: float32 = 0): int =
  if not hit.multiline or hit.lines.len == 0:
    return caretIndex(hit, x)
  let lineIdx = max(0, min(hit.lines.high,
    int((y - hit.rect.y - hit.padY + scrollY) /
        max(hit.lineHeight, 1))))
  let offset = lineOffset(hit.lineStarts, lineIdx)
  let line = hit.lines[lineIdx]
  result = offset + caretIndexLine(line, x,
    hit.rect.x + hit.padX - hit.scrollX, hit.fontSize, hit.family)

proc isWordChar(ch: char): bool =
  ch.isAlphaNumeric or ch == '_' or ord(ch) >= 128

proc selectWordOrLine*(engine: Engine, hit: Hit, clicks: int) =
  if not hit.input or hit.text.len == 0 or markedActive(engine, hit.key):
    return
  let pos = max(0, min(engine.caretPos, hit.text.len))
  var start, finish: int
  if clicks >= 3:
    if hit.multiline and hit.lines.len > 0:
      let (lineIdx, _) = caretLineCol(hit.lines, hit.lineStarts, pos)
      start = lineOffset(hit.lineStarts, lineIdx)
      finish = start + hit.lines[lineIdx].len
    else:
      start = 0
      finish = hit.text.len
  else:
    var p = pos
    if p >= hit.text.len and p > 0:
      dec p
    start = p
    finish = p
    while start > 0 and isWordChar(hit.text[start - 1]):
      dec start
    while finish < hit.text.len and isWordChar(hit.text[finish]):
      inc finish
    if start == finish and finish < hit.text.len:
      inc finish
  start = graphemeStartAt(hit.text, start)
  finish = graphemeCeil(hit.text, finish)
  engine.caretKey = hit.key
  engine.caretPos = finish
  engine.selectionAnchor = start

proc focusedInputIndex*(engine: Engine): int =
  for i in 0 ..< engine.hits.len:
    if engine.hits[i].key == engine.focusedKey and engine.hits[i].input:
      return i
  result = -1

proc snapshot*(engine: Engine, key, text: string, caret, anchor: int) =
  var stack = engine.undoStacks.getOrDefault(key)
  stack.add EditSnapshot(text: text, caret: caret, anchor: anchor)
  if stack.len > 100:
    stack.delete(0)
  engine.undoStacks[key] = stack
  engine.redoStacks[key] = @[]

proc ensureCaretVisible*(engine: Engine, index: int) =
  let hit = engine.hits[index]
  engine.manuallyScrolledInput = ""
  if not hit.multiline or hit.rect.w <= 0:
    return
  let docCaret =
    if engine.caretKey == hit.key: max(0, min(engine.caretPos, hit.text.len))
    else: hit.text.len
  var caret = displayCaretFor(engine, hit.key, hit.text, docCaret)
  let width = max(1.0'f32, hit.textViewportW + 2)
  let display = displayTextFor(engine, hit.key, hit.text)
  if display.markedLen > 0:
    caret = max(caret, display.markedStart + display.markedLen)
  let layout = layoutText(display.text, hit.fontSize, false,
                          if hit.noWrap: 0.0'f32 else: width, hit.family)
  let (lineIdx, _) = caretLineCol(layout.lines, layout.lineStarts, caret)
  let viewportH = max(1.0'f32, hit.textViewportH)
  let top = float32(lineIdx) * layout.lineHeight
  var off = engine.scrollOffsets.getOrDefault(hit.key, 0)
  if top < off:
    off = top
  elif top + layout.lineHeight > off + viewportH:
    off = top + layout.lineHeight - viewportH
  let maxOff = max(0.0'f32, layout.height - viewportH)
  engine.scrollOffsets[hit.key] = max(0.0'f32, min(off, maxOff))

proc applySnapshot(engine: Engine, index: int, s: EditSnapshot) =
  let hit = engine.hits[index]
  engine.clearComposition()
  engine.hits[index].text = s.text
  engine.caretKey = hit.key
  engine.caretPos = s.caret
  engine.selectionAnchor = s.anchor
  if hit.onText != nil:
    hit.onText(s.text)
  engine.ensureCaretVisible(index)
  engine.notifyFrame()

proc undo*(engine: Engine) =
  let index = focusedInputIndex(engine)
  if index < 0:
    return
  let hit = engine.hits[index]
  var stack = engine.undoStacks.getOrDefault(hit.key)
  if stack.len == 0:
    return
  let s = stack.pop()
  engine.undoStacks[hit.key] = stack
  var redo = engine.redoStacks.getOrDefault(hit.key)
  redo.add EditSnapshot(text: hit.text, caret: engine.caretPos,
                        anchor: engine.selectionAnchor)
  engine.redoStacks[hit.key] = redo
  engine.applySnapshot(index, s)

proc redo*(engine: Engine) =
  let index = focusedInputIndex(engine)
  if index < 0:
    return
  let hit = engine.hits[index]
  var stack = engine.redoStacks.getOrDefault(hit.key)
  if stack.len == 0:
    return
  let s = stack.pop()
  engine.redoStacks[hit.key] = stack
  var undoStack = engine.undoStacks.getOrDefault(hit.key)
  undoStack.add EditSnapshot(text: hit.text, caret: engine.caretPos,
                             anchor: engine.selectionAnchor)
  engine.undoStacks[hit.key] = undoStack
  engine.applySnapshot(index, s)

proc applyInput*(engine: Engine, index: int, text: string,
                 caret, anchor: int) =
  let hit = engine.hits[index]
  engine.clearComposition()
  engine.hits[index].text = text
  engine.caretKey = hit.key
  engine.caretPos = caret
  engine.selectionAnchor = anchor
  if hit.onText != nil:
    hit.onText(text)
  engine.ensureCaretVisible(index)
  engine.notifyFrame()

proc textInputActive*(engine: Engine): bool =
  focusedInputIndex(engine) >= 0

proc copySelection*(engine: Engine) =
  let index = focusedInputIndex(engine)
  if index < 0:
    return
  let hit = engine.hits[index]
  let sel = selectionRange(engine, hit.key, hit.text.len)
  if sel.start < sel.finish and engine.clipboardWrite != nil:
    engine.clipboardWrite(hit.text[sel.start ..< sel.finish])

proc cutSelection*(engine: Engine) =
  let index = focusedInputIndex(engine)
  if index < 0 or engine.clipboardWrite == nil:
    return
  let hit = engine.hits[index]
  let sel = selectionRange(engine, hit.key, hit.text.len)
  if sel.start < sel.finish:
    if engine.clipboardWrite != nil:
      engine.clipboardWrite(hit.text[sel.start ..< sel.finish])
    engine.snapshot(hit.key, hit.text, engine.caretPos, engine.selectionAnchor)
    let text = hit.text[0 ..< sel.start] & hit.text[sel.finish .. ^1]
    engine.applyInput(index, text, sel.start, sel.start)

proc paste*(engine: Engine) =
  let index = focusedInputIndex(engine)
  if index < 0 or engine.clipboardRead == nil:
    return
  let hit = engine.hits[index]
  var text = engine.clipboardRead()
  if text.len == 0:
    return
  text = text.replace("\r\n", "\n").replace("\r", "\n")
  if not hit.multiline:
    text = text.replace("\n", " ")
  let sel = selectionRange(engine, hit.key, hit.text.len)
  engine.snapshot(hit.key, hit.text, engine.caretPos, engine.selectionAnchor)
  let next = hit.text[0 ..< sel.start] & text & hit.text[sel.finish .. ^1]
  engine.applyInput(index, next, sel.start + text.len, sel.start + text.len)

proc selectAll*(engine: Engine) =
  let index = focusedInputIndex(engine)
  if index < 0:
    return
  let hit = engine.hits[index]
  engine.caretKey = hit.key
  engine.caretPos = hit.text.len
  engine.selectionAnchor = 0
  engine.ensureCaretVisible(index)
  engine.notifyFrame()

proc replacementDocRange(engine: Engine, hit: Hit,
                         replacement: TextRange):
                         tuple[start, finish: int, overlaps: bool] =
  if not replacement.valid:
    if markedActive(engine, hit.key):
      let (start, finish) = markedDocRange(engine, hit.text)
      return (start, finish, true)
    let sel = selectionRange(engine, hit.key, hit.text.len)
    return (sel.start, sel.finish, false)
  if not markedActive(engine, hit.key):
    let start = utf8OffsetForUtf16(hit.text, replacement.location)
    let finish = utf8OffsetForUtf16(hit.text, replacement.finish)
    return (min(start, finish), max(start, finish), false)
  let info = displayTextFor(engine, hit.key, hit.text)
  let (docStart, docFinish) = markedDocRange(engine, hit.text)
  let start = utf8OffsetForUtf16(info.text, replacement.location)
  let finish = utf8OffsetForUtf16(info.text, replacement.finish)
  let markedFinish = info.markedStart + info.markedLen
  if start >= markedFinish:
    let offset = start - markedFinish
    let mappedFinish = finish - markedFinish
    return (docFinish + offset, docFinish + mappedFinish, false)
  if finish <= info.markedStart:
    return (start, finish, false)
  (docStart, docFinish, true)

proc insertText*(engine: Engine, text: string,
                 replacement: TextRange = NoTextRange) =
  let index = focusedInputIndex(engine)
  if index < 0 or text.len == 0:
    if engine.markedText.len > 0 and text.len == 0:
      engine.clearComposition()
      engine.notifyFrame()
    return
  let hit = engine.hits[index]
  var insert = text
  if not hit.multiline:
    insert = insert.replace("\r", " ").replace("\n", " ")
  var start, finish: int
  if markedActive(engine, hit.key):
    let resolved = replacementDocRange(engine, hit, replacement)
    if resolved.overlaps:
      (start, finish) = markedDocRange(engine, hit.text)
    else:
      start = resolved.start
      finish = resolved.finish
  elif replacement.valid:
    start = utf8OffsetForUtf16(hit.text, replacement.location)
    finish = utf8OffsetForUtf16(hit.text, replacement.finish)
    if start > finish: swap(start, finish)
  else:
    let sel = selectionRange(engine, hit.key, hit.text.len)
    start = sel.start
    finish = sel.finish
  start = max(0, min(start, hit.text.len))
  finish = max(start, min(finish, hit.text.len))
  engine.snapshot(hit.key, hit.text, engine.caretPos, engine.selectionAnchor)
  let next = hit.text[0 ..< start] & insert & hit.text[finish .. ^1]
  engine.clearComposition()
  engine.applyInput(index, next, start + insert.len, start + insert.len)

proc setMarkedText*(engine: Engine, text: string,
                    selected: TextRange = NoTextRange,
                    replacement: TextRange = NoTextRange) =
  let index = focusedInputIndex(engine)
  if index < 0:
    return
  let hit = engine.hits[index]
  if text.len == 0:
    engine.clearComposition()
    engine.notifyFrame()
    return
  if not markedActive(engine, hit.key):
    var start, finish: int
    if replacement.valid:
      start = utf8OffsetForUtf16(hit.text, replacement.location)
      finish = utf8OffsetForUtf16(hit.text, replacement.finish)
      if start > finish: swap(start, finish)
    else:
      let sel = selectionRange(engine, hit.key, hit.text.len)
      start = sel.start
      finish = sel.finish
    engine.markedStart = max(0, min(start, hit.text.len))
    engine.markedEnd = max(engine.markedStart, min(finish, hit.text.len))
  elif replacement.valid:
    let resolved = replacementDocRange(engine, hit, replacement)
    if not resolved.overlaps:
      engine.markedStart = max(0, min(resolved.start, hit.text.len))
      engine.markedEnd = max(engine.markedStart,
                             min(resolved.finish, hit.text.len))
  engine.markedText = text
  engine.markedKey = hit.key
  let units = utf16Length(text)
  if selected.valid:
    engine.markedSelectedStart = max(0, min(selected.location, units))
    engine.markedSelectedLen = max(0, min(selected.length,
      units - engine.markedSelectedStart))
  else:
    engine.markedSelectedStart = units
    engine.markedSelectedLen = 0
  engine.ensureCaretVisible(index)
  engine.notifyFrame()

proc unmarkText*(engine: Engine) =
  engine.clearComposition()
  engine.notifyFrame()

proc hasMarkedText*(engine: Engine): bool =
  engine.markedText.len > 0

proc markedRange*(engine: Engine): TextRange =
  let index = focusedInputIndex(engine)
  if index < 0 or not markedActive(engine, engine.hits[index].key):
    return NoTextRange
  let hit = engine.hits[index]
  let (start, _) = markedDocRange(engine, hit.text)
  TextRange(location: utf16OffsetForUtf8(hit.text, start),
            length: utf16Length(engine.markedText))

proc selectedRange*(engine: Engine): TextRange =
  let index = focusedInputIndex(engine)
  if index < 0:
    return TextRange(location: 0, length: 0)
  let hit = engine.hits[index]
  if markedActive(engine, hit.key):
    let (start, _) = markedDocRange(engine, hit.text)
    let prefix = utf16OffsetForUtf8(hit.text, start)
    return TextRange(location: prefix + engine.markedSelectedStart,
                     length: engine.markedSelectedLen)
  let sel = selectionRange(engine, hit.key, hit.text.len)
  let a = utf16OffsetForUtf8(hit.text, sel.start)
  let b = utf16OffsetForUtf8(hit.text, sel.finish)
  TextRange(location: min(a, b), length: abs(a - b))

proc attributedSubstring*(engine: Engine, range: TextRange): string =
  let index = focusedInputIndex(engine)
  if index < 0 or range.location < 0 or range.length < 0:
    return ""
  let hit = engine.hits[index]
  let text = displayTextFor(engine, hit.key, hit.text).text
  let total = utf16Length(text)
  let start = max(0, min(range.location, total))
  let finish = max(start, min(range.finish, total))
  let first = utf8OffsetForUtf16(text, start)
  let last = utf8OffsetForUtf16(text, finish)
  text[first ..< max(first, last)]

proc textLength*(engine: Engine): int =
  let index = focusedInputIndex(engine)
  if index < 0:
    return 0
  let hit = engine.hits[index]
  utf16Length(displayTextFor(engine, hit.key, hit.text).text)

proc characterIndexAt*(engine: Engine, x, y: float32): int =
  let index = hitIndexInEditor(engine, x, y)
  if index < 0 or not engine.hits[index].input:
    return 0
  let hit = engine.hits[index]
  let caret = caretIndexAt(hit, x, y,
    engine.scrollOffsets.getOrDefault(hit.key, 0))
  utf16OffsetForUtf8(hitText(hit), caret)

proc caretRect*(engine: Engine): Rect =
  let index = focusedInputIndex(engine)
  if index < 0:
    return Rect(x: 0, y: 0, w: 1, h: 18)
  let hit = engine.hits[index]
  let text = hit.text
  let docPos =
    if engine.caretKey == hit.key: max(0, min(engine.caretPos, text.len))
    else: text.len
  let pos = displayCaretFor(engine, hit.key, text, docPos)
  if hit.multiline:
    let lines = if hit.lines.len > 0: hit.lines else: @[""]
    let (lineIdx, col) = caretLineCol(lines, hit.lineStarts, pos)
    let line = lines[lineIdx]
    let prefix = if col > 0: line[0 ..< min(col, line.len)] else: ""
    let x = hit.rect.x + hit.padX - hit.scrollX +
      measureText(prefix, hit.fontSize, false, hit.family).width
    let off = engine.scrollOffsets.getOrDefault(hit.key, 0)
    let y = hit.rect.y + hit.padY + float32(lineIdx) * hit.lineHeight - off
    return Rect(x: x, y: y, w: 2, h: max(12, hit.lineHeight))
  let display = displayTextFor(engine, hit.key, text).text
  let prefix = if pos > 0: display[0 ..< min(pos, display.len)] else: ""
  let x = hit.rect.x + hit.padX - hit.scrollX +
    measureText(prefix, hit.fontSize, false, hit.family).width
  Rect(x: x, y: hit.rect.y + 6, w: 2, h: max(12, hit.rect.h - 12))

proc editInput*(engine: Engine, index: int, key: string, modifiers: uint32) =
  let hit = engine.hits[index]
  let cmd = (modifiers and KeyShortcut) != 0
  let shift = (modifiers and KeyShift) != 0
  if cmd:
    case key.toLowerAscii
    of "z":
      if (modifiers and KeyShift) != 0: engine.redo()
      else: engine.undo()
      return
    of "y":
      engine.redo()
      return
    of "a":
      engine.selectAll()
      return
    of "c":
      engine.copySelection()
      return
    of "x":
      engine.cutSelection()
      return
    of "v":
      engine.paste()
      return
    else:
      if key notin ["backspace", "delete", "left", "right", "home", "end", "up", "down"]:
        return

  var text = hit.text
  let beforeText = text
  var caret =
    if engine.caretKey == hit.key: max(0, min(engine.caretPos, text.len))
    else: text.len
  let sel = selectionRange(engine, hit.key, text.len)
  let hasSel = sel.finish > sel.start
  let anchorBefore = if hasSel: engine.selectionAnchor else: caret
  let lines = if hit.multiline: hit.lines else: @[text]
  let (lineIdx, col) = caretLineCol(lines, hit.lineStarts, caret)
  var handled = true
  case key
  of "insert", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10",
     "f11", "f12", "f13", "f14", "f15", "f16", "f17", "f18", "f19", "f20",
     "f21", "f22", "f23", "f24":
    return
  of "backspace":
    if hasSel:
      text = text[0 ..< sel.start] & text[sel.finish .. ^1]
      caret = sel.start
    elif caret > 0:
      let start = graphemeStartBefore(text, caret)
      text = text[0 ..< start] & text[caret .. ^1]
      caret = start
  of "delete":
    if hasSel:
      text = text[0 ..< sel.start] & text[sel.finish .. ^1]
      caret = sel.start
    elif caret < text.len:
      text = text[0 ..< caret] & text[graphemeEndAfter(text, caret) .. ^1]
  of "left":
    if hasSel and not shift:
      caret = sel.start
    elif caret > 0:
      caret = graphemeStartBefore(text, caret)
  of "right":
    if hasSel and not shift:
      caret = sel.finish
    elif caret < text.len:
      caret = graphemeEndAfter(text, caret)
  of "home":
    if hit.multiline:
      caret = lineOffset(hit.lineStarts, lineIdx)
    else:
      caret = 0
  of "end":
    if hit.multiline:
      caret = lineOffset(hit.lineStarts, lineIdx) + lines[lineIdx].len
    else:
      caret = text.len
  of "up", "down":
    if hit.multiline and lines.len > 0:
      let target = if key == "up": max(0, lineIdx - 1)
                   else: min(lines.high, lineIdx + 1)
      caret = lineOffset(hit.lineStarts, target) +
        graphemeStartAt(lines[target], min(col, lines[target].len))
  of "escape":
    engine.focusedKey = ""
    engine.caretKey = ""
    engine.caretPos = 0
    engine.selectionAnchor = 0
    engine.markedText.setLen(0)
    engine.markedKey = ""
    engine.notifyFrame()
    return
  of "enter", "\n":
    if hit.multiline:
      text = text[0 ..< sel.start] & "\n" & text[sel.finish .. ^1]
      caret = sel.start + 1
    else:
      if hit.onSubmit != nil:
        engine.clearComposition()
        hit.onSubmit()
        engine.notifyFrame()
      handled = false
  else:
    let insert =
      if key == "space": " "
      elif key in ["up", "down", "tab"]: ""
      else: key
    if insert.len > 0:
      text = text[0 ..< sel.start] & insert & text[sel.finish .. ^1]
      caret = sel.start + insert.len
    else:
      handled = false
  if not handled:
    return
  let navigation = key in ["left", "right", "home", "end", "up", "down"]
  let anchor = if shift and navigation: anchorBefore else: caret
  if text != beforeText:
    engine.snapshot(hit.key, beforeText, engine.caretPos, engine.selectionAnchor)
  engine.applyInput(index, text, caret, anchor)
