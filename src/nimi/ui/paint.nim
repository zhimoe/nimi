## Scene display-list emission and interactive hit-region collection.

import std/[strutils, tables]

import ./node
import ../text/measure

const
  selectionColor = Color(r: 0.22, g: 0.47, b: 0.95, a: 0.18)
  compositionColor = Color(r: 0.22, g: 0.47, b: 0.95)

proc lighten(c: Color, amount: float32): Color =
  Color(r: min(c.r + amount, 1), g: min(c.g + amount, 1),
        b: min(c.b + amount, 1), a: c.a)

proc darken(c: Color, amount: float32): Color =
  Color(r: max(c.r - amount, 0), g: max(c.g - amount, 0),
        b: max(c.b - amount, 0), a: c.a)

proc paintSelection*(n: Node, c: Context,
                     engine: Engine): tuple[start, finish: int] =
  result = selectionRange(engine, n.key, n.text.len)
  if result.start >= result.finish:
    return
  if n.multiline:
    let off = if c.engine != nil: c.engine.scrollOffsets.getOrDefault(n.key, 0)
              else: 0.0'f32
    var ly = n.y + topPad(n) - off
    for i, line in n.lines:
      let lineStart = lineOffset(n.lineStarts, i)
      let lineFinish = lineStart + line.len
      let a = max(result.start, lineStart)
      let b = min(result.finish, lineFinish)
      if a < b:
        let left = a - lineStart
        let right = b - lineStart
        let x1 = n.x + leftPad(n) + n.gutterW - n.scrollX +
          measureText(line[0 ..< min(left, line.len)], n.fontSize, false,
                      n.family).width
        let x2 = n.x + leftPad(n) + n.gutterW - n.scrollX +
          measureText(line[0 ..< min(right, line.len)], n.fontSize, false,
                      n.family).width
        c.scene.rect(Rect(x: x1, y: ly, w: max(1.0'f32, x2 - x1),
                          h: n.lineHeight), selectionColor)
      ly += n.lineHeight
  else:
    let x1 = n.x + leftPad(n) - n.scrollX +
      measureText(n.text[0 ..< result.start], n.fontSize, false,
                  n.family).width
    let x2 = n.x + leftPad(n) - n.scrollX +
      measureText(n.text[0 ..< result.finish], n.fontSize, false,
                  n.family).width
    c.scene.rect(Rect(x: x1, y: n.y + 4, w: max(1.0'f32, x2 - x1),
                      h: n.h - 8), selectionColor)

proc paintFocus*(n: Node, c: Context, radius: float32 = 6) =
  if c.engine != nil and c.engine.focusedKey == n.key:
    var color = rgb(0.35, 0.62, 1.0)
    if n.accent.a > 0:
      color = Color(r: n.accent.r, g: n.accent.g, b: n.accent.b, a: 0.55)
    c.scene.rect(Rect(x: n.x - 3, y: n.y - 3, w: n.w + 6, h: n.h + 6),
                 color, radius)

proc paintInputLine*(n: Node, c: Context, line: string, x, y: float32,
                     lineStart, markedStart, markedLen: int) =
  let lineFinish = lineStart + line.len
  let markStart = max(lineStart, markedStart)
  let markFinish = min(lineFinish, markedStart + markedLen)
  if markedLen <= 0 or markStart >= markFinish:
    c.scene.text(line, x, y, n.fontSize, n.color, false, n.family)
    return
  let a = markStart - lineStart
  let b = markFinish - lineStart
  var cx = x
  if a > 0:
    let prefix = line[0 ..< a]
    c.scene.text(prefix, cx, y, n.fontSize, n.color, false, n.family)
    cx += measureText(prefix, n.fontSize, false, n.family).width
  let marked = line[a ..< b]
  c.scene.text(marked, cx, y, n.fontSize, compositionColor, false, n.family)
  let markedWidth = measureText(marked, n.fontSize, false, n.family).width
  let underlineY =
    y + (if n.multiline: max(1.0'f32, n.lineHeight - 2)
         else: n.fontSize + 2)
  c.scene.rect(Rect(x: cx, y: underlineY, w: markedWidth, h: 1),
               compositionColor)
  cx += markedWidth
  if b < line.len:
    c.scene.text(line[b .. ^1], cx, y, n.fontSize, n.color, false, n.family)

proc paintContainerBox*(n: Node, c: Context) =
  var bg = n.bg
  if c.engine != nil:
    if n.pressedBg.a > 0 and c.engine.pressedKey == n.key:
      bg = n.pressedBg
    elif n.hoverBg.a > 0 and
        (c.engine.hoveredKey == n.key or c.pointerIn(n.key)):
      bg = n.hoverBg
  if bg.a > 0:
    c.scene.rect(Rect(x: n.x, y: n.y, w: n.w, h: n.h), bg, n.radius)
  if n.borderWidth > 0:
    let bw = n.borderWidth
    c.scene.rect(Rect(x: n.x, y: n.y, w: n.w, h: bw), n.borderColor)
    c.scene.rect(Rect(x: n.x, y: n.y + n.h - bw, w: n.w, h: bw),
                 n.borderColor)
    c.scene.rect(Rect(x: n.x, y: n.y, w: bw, h: n.h), n.borderColor)
    c.scene.rect(Rect(x: n.x + n.w - bw, y: n.y, w: bw, h: n.h),
                 n.borderColor)

proc placeholderPaintColor(n: Node): Color =
  if n.placeholderColor.a > 0: n.placeholderColor
  else: rgb(0.55, 0.55, 0.60)

proc textLineX(n: Node, line: string): float32 =
  let inner = n.w - leftPad(n) - rightPad(n)
  let lineW = measureText(line, n.fontSize, n.bold, n.family).width
  case n.textAlign
  of taStart: n.x + leftPad(n)
  of taCenter: n.x + leftPad(n) + (inner - lineW) / 2
  of taEnd: n.x + leftPad(n) + inner - lineW

proc paintRichText*(n: Node, c: Context) =
  let inner = max(1.0'f32, n.w - leftPad(n) - rightPad(n))
  let innerH = max(1.0'f32, n.h - topPad(n) - bottomPad(n))
  let sample = measureText("Ag", n.fontSize, n.bold, n.family)
  let y = n.y + topPad(n) + (innerH - sample.height) / 2
  c.scene.clip(Rect(x: n.x + leftPad(n), y: n.y + topPad(n),
                    w: inner, h: innerH), n.radius)
  var x = n.x + leftPad(n)
  var remaining = inner
  for run in n.richRuns:
    if remaining <= 0:
      break
    let runBold = run.bold or n.bold
    let m = measureText(run.text, n.fontSize, runBold, n.family)
    var shown = run.text
    var width = m.width
    var truncated = false
    if width > remaining:
      shown = ellipsizeText(run.text, n.fontSize, runBold, n.family, remaining)
      width = measureText(shown, n.fontSize, runBold, n.family).width
      truncated = true
    if run.bg.a > 0 and shown.len > 0:
      c.scene.rect(Rect(x: x, y: y, w: width, h: m.height), run.bg, 2)
    if shown.len > 0:
      c.scene.text(shown, x, y, n.fontSize, run.color, runBold, n.family)
    x += width
    remaining -= width
    if truncated:
      break
  c.scene.restoreClip()

proc paint*(n: Node, c: Context) =
  case n.kind
  of nkText:
    if n.lines.len == 0:
      c.scene.text(n.text, n.x + leftPad(n), n.y + topPad(n),
                   n.fontSize, n.color, n.bold, n.family)
    else:
      var y = n.y + topPad(n)
      for line in n.lines:
        c.scene.text(line, n.textLineX(line), y, n.fontSize, n.color,
                     n.bold, n.family)
        y += n.lineHeight
  of nkRichText:
    paintRichText(n, c)
  of nkButton:
    paintFocus(n, c, n.radius + 3)
    var bg = n.bg
    if c.engine != nil:
      if c.engine.pressedKey == n.key:
        bg = darken(bg, 0.12)
      elif c.engine.hoveredKey == n.key:
        bg = lighten(bg, 0.08)
    c.scene.rect(Rect(x: n.x, y: n.y, w: n.w, h: n.h), bg, n.radius)
    let m = measureText(n.text, n.fontSize, n.bold, n.family)
    c.scene.text(n.text, n.x + (n.w - m.width) / 2,
                 n.y + (n.h - m.height) / 2, n.fontSize, n.color,
                 n.bold, n.family)
  of nkButtonBase:
    n.paintContainerBox(c)
    if n.clipChildren:
      c.scene.clip(Rect(x: n.x, y: n.y, w: n.w, h: n.h), n.radius)
    for ch in n.children:
      paint(ch, c)
    if n.clipChildren:
      c.scene.restoreClip()
  of nkCustom:
    if n.customPaint != nil:
      n.customPaint(c, Rect(x: n.x, y: n.y, w: n.w, h: n.h))
  of nkCheckbox:
    paintFocus(n, c, 6)
    let box = n.boxSize
    let bx = n.x + leftPad(n)
    let by = n.y + (n.h - box) / 2
    let fill = if n.accent.a > 0: n.accent else: defaultButton
    c.scene.rect(Rect(x: bx - 1, y: by - 1, w: box + 2, h: box + 2),
                 rgb(0.62, 0.62, 0.68), 5)
    c.scene.rect(Rect(x: bx, y: by, w: box, h: box),
                 if n.checked or n.mixed: fill else: rgb(1, 1, 1), 4)
    if n.checked:
      let check = measureText("✓", 12, true)
      c.scene.text("✓", bx + (box - check.width) / 2,
                   by + (box - check.height) / 2, 12, rgb(1, 1, 1), true)
    elif n.mixed:
      c.scene.rect(Rect(x: bx + 4, y: by + box / 2 - 1,
                        w: box - 8, h: 2), rgb(1, 1, 1), 1)
    if n.text.len > 0:
      let m = measureText(n.text, n.fontSize, false, n.family)
      c.scene.text(n.text, bx + box + 8, n.y + (n.h - m.height) / 2,
                   n.fontSize, n.color, false, n.family)
  of nkSwitch:
    paintFocus(n, c, n.h / 2 + 3)
    let radius = min(n.h, 22) / 2
    let fill = if n.accent.a > 0: n.accent else: defaultButton
    let track = if n.checked: fill else: rgb(0.80, 0.80, 0.84)
    c.scene.rect(Rect(x: n.x, y: n.y, w: n.w, h: n.h), track, radius)
    let knob = max(4.0'f32, n.h - 4)
    let kx = if n.checked: n.x + n.w - knob - 2 else: n.x + 2
    c.scene.rect(Rect(x: kx, y: n.y + 2, w: knob, h: knob), rgb(1, 1, 1), knob / 2)
  of nkSlider:
    paintFocus(n, c, 6)
    let span =
      if n.maxValue > n.minValue:
        (n.value - n.minValue) / (n.maxValue - n.minValue)
      else:
        0.0'f32
    let t = max(0.0'f32, min(1.0'f32, span))
    let trackH = 4.0'f32
    let ty = n.y + n.h / 2 - trackH / 2
    let fill = if n.accent.a > 0: n.accent else: n.color
    c.scene.rect(Rect(x: n.x, y: ty, w: n.w, h: trackH), n.bg, trackH / 2)
    c.scene.rect(Rect(x: n.x, y: ty, w: n.w * t, h: trackH), fill, trackH / 2)
    let knob = 16.0'f32
    let kx = n.x + n.w * t - knob / 2
    c.scene.rect(Rect(x: kx, y: n.y + (n.h - knob) / 2, w: knob, h: knob),
                 fill, knob / 2)
  of nkProgress:
    let t =
      if n.maxValue > 0: max(0.0'f32, min(1.0'f32, n.value / n.maxValue))
      else: 0.0'f32
    let fill = if n.accent.a > 0: n.accent else: n.color
    c.scene.rect(Rect(x: n.x, y: n.y, w: n.w, h: n.h), n.bg, n.h / 2)
    c.scene.rect(Rect(x: n.x, y: n.y, w: n.w * t, h: n.h), fill, n.h / 2)
  of nkDivider:
    c.scene.rect(Rect(x: n.x, y: n.y, w: n.w, h: max(1.0'f32, n.h)), n.color)
  of nkInput:
    paintFocus(n, c, 6)
    if not n.plain:
      c.scene.rect(Rect(x: n.x - 1, y: n.y - 1, w: n.w + 2, h: n.h + 2),
                   rgb(0.62, 0.62, 0.68), 6)
      c.scene.rect(Rect(x: n.x, y: n.y, w: n.w, h: n.h), n.bg, 5)
    let lp = leftPad(n)
    let tp = topPad(n)
    let bp = bottomPad(n)
    let rp = rightPad(n)
    if n.multiline:
      let viewport = n.inputViewport()
      let viewBottom = n.y + viewport.height - bp
      let off = if c.engine != nil:
        c.engine.scrollOffsets.getOrDefault(n.key, 0)
      else:
        0.0'f32
      c.scene.clip(Rect(x: n.x + 1, y: n.y + 1,
                        w: max(0'f32, n.w - 2), h: max(0'f32, viewport.height - 1)))
      let composing = c.engine != nil and markedActive(c.engine, n.key)
      let info =
        if c.engine != nil: displayTextFor(c.engine, n.key, n.text)
        else: (text: n.text, markedStart: 0, markedLen: 0)
      let gutter = n.gutterW
      var hx = 0.0'f32
      if n.noWrap and c.engine != nil:
        hx = clamp(c.engine.inputOffsets.getOrDefault(n.key), 0'f32, viewport.maxX)
        if c.engine.focusedKey == n.key and c.engine.manuallyScrolledInput != n.key and
            viewport.width > 0 and n.lines.len > 0:
          let pos = displayCaretFor(c.engine, n.key, n.text,
            if c.engine.caretKey == n.key: c.engine.caretPos else: n.text.len)
          let (lineIdx, col) = caretLineCol(n.lines, n.lineStarts, pos)
          if lineIdx < n.lines.len:
            let line = n.lines[lineIdx]
            let prefix = if col > 0: line[0 ..< min(col, line.len)] else: ""
            let caretW = measureText(prefix, n.fontSize, false,
                                     n.family).width
            let visible = max(0'f32, viewport.width - 2)
            if caretW < hx: hx = caretW
            elif caretW > hx + visible: hx = caretW - visible
            hx = clamp(hx, 0'f32, viewport.maxX)
        c.engine.inputOffsets[n.key] = hx
      n.scrollX = hx
      if gutter > 0 and n.bg.a > 0:
        c.scene.rect(Rect(x: n.x + lp, y: n.y + 1,
                          w: gutter, h: max(0'f32, viewport.height - 1)), n.bg)
      let textRect = Rect(x: n.x + lp + gutter, y: n.y + 1,
                          w: viewport.width, h: max(0'f32, viewport.height - 1))
      c.scene.clip(textRect)
      if n.displayText.len == 0:
        c.scene.text(n.placeholder, n.x + lp + gutter, n.y + tp,
                     n.fontSize, placeholderPaintColor(n), false, n.family)
      else:
        if c.engine != nil and c.engine.focusedKey == n.key and not composing:
          discard paintSelection(n, c, c.engine)
        for i, line in n.lines:
          let ly = n.y + tp + float32(i) * n.lineHeight - off
          if ly + n.lineHeight < n.y + tp:
            continue
          if ly >= viewBottom:
            break
          paintInputLine(n, c, line, n.x + lp + gutter - hx, ly,
                         lineOffset(n.lineStarts, i),
                         info.markedStart, info.markedLen)
      if c.engine != nil and c.engine.focusedKey == n.key:
        let pos = displayCaretFor(c.engine, n.key, n.text,
          if c.engine.caretKey == n.key: c.engine.caretPos else: n.text.len)
        let (lineIdx, col) = caretLineCol(n.lines, n.lineStarts, pos)
        if lineIdx < n.lines.len:
          let line = n.lines[lineIdx]
          let prefix = if col > 0: line[0 ..< min(col, line.len)] else: ""
          let pw = measureText(prefix, n.fontSize, false, n.family).width
          let cx = n.x + lp + gutter + pw - hx
          let cy = n.y + tp + float32(lineIdx) * n.lineHeight - off
          if cy >= n.y + tp and cy < viewBottom:
            c.scene.rect(Rect(x: cx, y: cy, w: 1.5'f32,
                              h: max(1.0'f32, min(n.lineHeight - 2,
                                                 viewBottom - cy))),
                         n.color)
      c.scene.restoreClip()
      if gutter > 0:
        let digits = max(2, ($n.lines.len).len)
        for i, _ in n.lines:
          let ly = n.y + tp + float32(i) * n.lineHeight - off
          if ly + n.lineHeight < n.y + tp:
            continue
          if ly >= viewBottom:
            break
          let number = align($(i + 1), digits)
          let metrics = measureText(number, n.fontSize, false, n.family)
          c.scene.text(number, n.x + lp + gutter - 8 - metrics.width, ly,
                       n.fontSize, n.lineNumberColor, false, n.family)
        c.scene.rect(Rect(x: n.x + lp + gutter - 4, y: n.y + tp,
                          w: 1, h: max(0'f32, viewBottom - n.y - tp)),
                     Color(r: n.lineNumberColor.r, g: n.lineNumberColor.g,
                           b: n.lineNumberColor.b, a: 0.2))
      c.scene.restoreClip()
      for horizontal, track in [viewport.vertical, viewport.horizontal]:
        if track.w <= 0 or track.h <= 0: continue
        let extent = if horizontal == 1: viewport.width else: viewport.height
        let maximum = if horizontal == 1: viewport.maxX else: viewport.contentH - extent
        let thumb = inputThumb(track, extent, maximum,
                               if horizontal == 1: hx else: off, horizontal == 1)
        c.scene.rect(track, rgb(n.color.r, n.color.g, n.color.b, 0.15), 3)
        c.scene.rect(thumb, rgb(n.color.r, n.color.g, n.color.b, 0.6), 3)
    else:
      c.scene.clip(Rect(x: n.x + 1, y: n.y + 1, w: max(1'f32, n.w - 2), h: max(1'f32, n.h - 2)))
      if c.engine != nil and c.engine.focusedKey == n.key:
        let pos = displayCaretFor(c.engine, n.key, n.text,
          if c.engine.caretKey == n.key: c.engine.caretPos else: n.text.len)
        let prefix = n.displayText[0 ..< min(pos, n.displayText.len)]
        let caretWidth = measureText(prefix, n.fontSize, false, n.family).width
        let visible = max(1'f32, n.w - lp - rp - 2)
        let maxOffset = max(0'f32, measureText(n.displayText, n.fontSize,
                                               false, n.family).width - visible)
        n.scrollX = min(maxOffset, max(0'f32, c.engine.inputOffsets.getOrDefault(n.key, 0)))
        if caretWidth < n.scrollX: n.scrollX = caretWidth
        elif caretWidth > n.scrollX + visible: n.scrollX = caretWidth - visible
        c.engine.inputOffsets[n.key] = n.scrollX
      let composing = c.engine != nil and markedActive(c.engine, n.key)
      if c.engine != nil and c.engine.focusedKey == n.key and not composing:
        discard paintSelection(n, c, c.engine)
      let m = measureText(n.displayText, n.fontSize, false, n.family)
      if n.displayText.len == 0:
        c.scene.text(n.placeholder, n.x + lp,
                     n.y + (n.h - measureText(n.placeholder, n.fontSize,
                                               false, n.family).height) / 2,
                     n.fontSize, placeholderPaintColor(n), false, n.family)
      else:
        let info =
          if c.engine != nil: displayTextFor(c.engine, n.key, n.text)
          else: (text: n.text, markedStart: 0, markedLen: 0)
        paintInputLine(n, c, n.displayText, n.x + lp - n.scrollX,
                       n.y + (n.h - m.height) / 2, 0,
                       info.markedStart, info.markedLen)
      if c.engine != nil and c.engine.focusedKey == n.key:
        let pos = displayCaretFor(c.engine, n.key, n.text,
          if c.engine.caretKey == n.key: c.engine.caretPos else: n.text.len)
        let prefix =
          if pos > 0: n.displayText[0 ..< min(pos, n.displayText.len)]
          else: ""
        let pw = measureText(prefix, n.fontSize, false, n.family).width
        let cx = n.x + lp + pw - n.scrollX
        c.scene.rect(Rect(x: cx, y: n.y + 6, w: 1.5'f32, h: n.h - 12),
                     n.color)
      c.scene.restoreClip()
  of nkImage:
    c.scene.image(n.imagePath, Rect(x: n.x, y: n.y, w: n.w, h: n.h))
  of nkScroll:
    n.paintContainerBox(c)
    c.scene.clip(Rect(x: n.x, y: n.y, w: n.w, h: n.h), n.radius)
    for ch in n.children:
      paint(ch, c)
    c.scene.restoreClip()
    if n.contentH > n.h and n.w > 12:
      let track = Rect(x: n.x + n.w - 8, y: n.y + 2,
                       w: 6, h: max(1.0'f32, n.h - 4))
      c.scene.rect(track, rgb(0.35, 0.35, 0.40, 0.10), 3)
      let maxOff = max(0.0'f32, n.contentH - n.h)
      let thumbH = max(24.0'f32, track.h * n.h / max(n.contentH, 1))
      let travel = max(0.0'f32, track.h - thumbH)
      let t = if maxOff > 0: n.scrollY / maxOff else: 0
      c.scene.rect(Rect(x: track.x, y: track.y + t * travel,
                        w: track.w, h: thumbH),
                   rgb(0.45, 0.45, 0.52, 0.55), 3)
  of nkColumn, nkRow:
    n.paintContainerBox(c)
    if n.clipChildren:
      c.scene.clip(Rect(x: n.x, y: n.y, w: n.w, h: n.h), n.radius)
    for ch in n.children:
      paint(ch, c)
    if n.clipChildren:
      c.scene.restoreClip()

proc collectHits*(n: Node, engine: Engine, clip: Rect, layer: int = 0) =
  var currentClip = clip
  if n.key.len > 0:
    if engine.hoverRects.len >= 4096:
      engine.hoverRects.clear()
    engine.hoverRects[n.key] = Rect(x: n.x, y: n.y, w: n.w, h: n.h)
  if n.kind == nkScroll or n.clipChildren:
    currentClip = intersect(clip, Rect(x: n.x, y: n.y, w: n.w, h: n.h))
  if n.kind == nkScroll:
    engine.scrollRegions.add ScrollRegion(
      key: n.key,
      rect: intersect(clip, Rect(x: n.x, y: n.y, w: n.w, h: n.h)),
      contentH: n.contentH, viewportH: n.h, layer: layer)
  let viewport = if n.kind == nkInput and n.multiline: n.inputViewport()
                 else: InputViewport()
  if n.onClick != nil or n.onDrag != nil or n.kind == nkInput or n.blockClicks:
    engine.hits.add Hit(
      rect: Rect(x: n.x, y: n.y, w: n.w, h: n.h),
      key: n.key,
      onClick: n.onClick,
      onDoubleClick: n.onDoubleClick,
      onActivate: n.onActivate,
      onSpace: n.onSpace,
      onSubmit: n.onSubmit,
      onDrag: n.onDrag,
      input: n.kind == nkInput,
      focusable: n.focusable,
      tabStop: n.tabStop,
      blocks: n.blockClicks,
      layer: layer,
      text: n.text,
      displayText: n.displayText,
      onText: n.onText,
      multiline: n.multiline,
      noWrap: n.noWrap,
      lineNumbers: n.lineNumbers,
      lines: n.lines,
      lineStarts: n.lineStarts,
      lineHeight: n.lineHeight,
      padX: leftPad(n) + (if n.multiline: n.gutterW else: 0.0'f32),
      padY: topPad(n),
      fontSize: n.fontSize,
      family: n.family,
      scrollX: n.scrollX,
      textViewportW: viewport.width,
      textViewportH: viewport.height - topPad(n) - bottomPad(n),
      maxScrollX: viewport.maxX,
      clip: currentClip)
  if n.kind == nkInput and n.multiline:
    if viewport.contentH > viewport.height:
      engine.scrollRegions.add ScrollRegion(
        key: n.key,
        rect: intersect(currentClip, Rect(x: n.x, y: n.y, w: n.w, h: n.h)),
        contentH: viewport.contentH, viewportH: viewport.height, layer: layer)
    for axis, track in [viewport.vertical, viewport.horizontal]:
      if track.w <= 0 or track.h <= 0: continue
      let horizontal = axis == 1
      let extent = if horizontal: viewport.width else: viewport.height
      let maximum = if horizontal: viewport.maxX else: viewport.contentH - extent
      let offset = if horizontal: n.scrollX else: engine.scrollOffsets.getOrDefault(n.key)
      engine.hits.add Hit(rect: track, layer: layer, clip: currentClip,
        key: (if horizontal: "__textscrollx:" else: "__textscroll:") & n.key,
        scrollbar: InputScrollbar(inputKey: n.key, maximum: maximum, horizontal: horizontal,
          thumb: inputThumb(track, extent, maximum, offset, horizontal)))
  for ch in n.children:
    collectHits(ch, engine, currentClip, layer)
  if n.kind == nkScroll and n.contentH > n.h and n.w > 12:
    let track = Rect(x: n.x + n.w - 8, y: n.y + 2,
                     w: 6, h: max(1.0'f32, n.h - 4))
    let maxOff = max(0.0'f32, n.contentH - n.h)
    let thumbH = max(24.0'f32, track.h * n.h / max(n.contentH, 1))
    let travel = max(0.0'f32, track.h - thumbH)
    engine.hits.add Hit(
      rect: track,
      key: "__scroll:" & n.key,
      layer: layer,
      clip: currentClip,
      onDrag: proc(rect: Rect, x, y: float32) =
        let t = if travel > 0: max(0.0'f32, min(1.0'f32,
                      (y - rect.y - thumbH / 2) / travel)) else: 0.0'f32
        engine.scrollOffsets[n.key] = t * maxOff
        engine.notifyFrame())
