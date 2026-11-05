## M2 UI: a small per-frame node tree with column/row layout, text and
## buttons. The view function rebuilds the tree every frame; click handlers
## mutate the app's state and request another frame.
##
## This is intentionally a stepping stone toward the arena/Element design in
## docs/03-native-ui.md. It keeps the same view-function model and scene
## output, without the generation handles and layout cache yet.

import std/[strutils, tables]

import ../keys
import ../scene/scene
import ../text/measure

export scene

type
  NodeKind* = enum
    nkColumn
    nkRow
    nkText
    nkButton
    nkCheckbox
    nkSwitch
    nkSlider
    nkProgress
    nkDivider
    nkInput
    nkScroll
    nkImage

  Node* = ref object
    kind*: NodeKind
    key*: string
    text*: string
    fontSize*: float32
    bold*: bool
    color*: Color
    bg*: Color
    radius*: float32
    padX*, padY*, gap*: float32
    fill*: bool
    center*: bool
    wrap*: bool
    lines*: seq[string]
    lineHeight*: float32
    fixedW*, fixedH*: float32
    contentH*: float32
    scrollY*: float32
    imagePath*: string
    children*: seq[Node]
    onClick*: proc() {.closure.}
    onDrag*: proc(rect: Rect, x, y: float32) {.closure.}
    onText*: proc(text: string) {.closure.}
    placeholder*: string
    multiline*: bool
    checked*: bool
    value*, minValue*, maxValue*: float32
    boxSize*: float32
    x*, y*, w*, h*: float32

  Hit* = object
    rect*: Rect
    key*: string
    onClick*: proc() {.closure.}
    onDrag*: proc(rect: Rect, x, y: float32) {.closure.}
    input*: bool
    text*: string
    onText*: proc(text: string) {.closure.}
    multiline*: bool
    lines*: seq[string]
    lineHeight*: float32
    padX*, padY*, fontSize*: float32
    clip*: Rect

  EditSnapshot = object
    text: string
    caret: int
    anchor: int

  ScrollRegion* = object
    key*: string
    rect*: Rect
    contentH*: float32

  Engine* = ref object
    scrollOffsets*: Table[string, float32]
    scrollRegions*: seq[ScrollRegion]
    hoveredKey*: string
    pressedKey*: string
    pressedDrag*: proc(rect: Rect, x, y: float32) {.closure.}
    pressedRect*: Rect
    focusedKey*: string
    caretKey*: string
    caretPos*: int
    selectionAnchor*: int
    selectingInput*: string
    clipboardRead*: proc(): string {.closure.}
    clipboardWrite*: proc(text: string) {.closure.}
    undoStacks*: Table[string, seq[EditSnapshot]]
    redoStacks*: Table[string, seq[EditSnapshot]]
    markedText*: string
    markedKey*: string
    pendingKeys*: seq[string]
    hits*: seq[Hit]
    requestFrame*: proc() {.closure.}

  Context* = ref object
    width*, height*: float32
    scene*: Scene
    engine*: Engine
    parent*, root*: Node

let
  defaultText = rgb(0.08, 0.08, 0.10)
  defaultButton = rgb(0.16, 0.40, 0.90)

proc initContext*(width, height: float32, engine: Engine): Context =
  result = Context(
    width: width,
    height: height,
    engine: engine,
    scene: Scene(width: width, height: height, clear: rgb(1, 1, 1)))

proc addNode(c: Context, n: Node): Node =
  if c.parent != nil:
    c.parent.children.add n
  else:
    c.root = n
  result = n

# --- constructors ----------------------------------------------------------

proc column*(c: Context): Node {.discardable.} =
  addNode(c, Node(kind: nkColumn))

proc row*(c: Context): Node {.discardable.} =
  addNode(c, Node(kind: nkRow))

proc text*(c: Context, text: string, size: float32 = 14,
           color: Color = defaultText, bold: bool = false): Node {.discardable.} =
  addNode(c, Node(kind: nkText, text: text, fontSize: size,
                  color: color, bold: bold))

proc button*(c: Context, label: string, onClick: proc(),
             key: string = "", size: float32 = 14): Node {.discardable.} =
  addNode(c, Node(
    kind: nkButton,
    key: if key.len > 0: key else: label,
    text: label,
    fontSize: size,
    color: rgb(1, 1, 1),
    bg: defaultButton,
    radius: 6,
    padX: 12, padY: 6,
    onClick: onClick))

proc checkbox*(c: Context, label: string, checked: bool, onToggle: proc(),
               key: string = ""): Node {.discardable.} =
  addNode(c, Node(
    kind: nkCheckbox,
    key: if key.len > 0: key else: label,
    text: label,
    checked: checked,
    fontSize: 14,
    color: defaultText,
    boxSize: 16,
    onClick: onToggle))

proc switch*(c: Context, on: bool, onToggle: proc(),
             key: string = ""): Node {.discardable.} =
  addNode(c, Node(
    kind: nkSwitch,
    key: if key.len > 0: key else: "switch",
    checked: on,
    boxSize: 22,
    bg: defaultButton,
    onClick: onToggle))

proc slider*(c: Context, value: float32, onInput: proc(v: float32),
             minValue: float32 = 0, maxValue: float32 = 1,
             key: string = ""): Node {.discardable.} =
  let lo = minValue
  let hi = maxValue
  let cb = onInput
  addNode(c, Node(
    kind: nkSlider,
    key: if key.len > 0: key else: "slider",
    value: value,
    minValue: lo,
    maxValue: hi,
    bg: rgb(0.85, 0.85, 0.88),
    color: defaultButton,
    onDrag: proc(rect: Rect, x, y: float32) =
      let span = max(rect.w, 1.0'f32)
      let t = max(0.0'f32, min(1.0'f32, (x - rect.x) / span))
      cb(lo + t * (hi - lo))))

proc progress*(c: Context, value: float32, maxValue: float32 = 1,
               key: string = ""): Node {.discardable.} =
  addNode(c, Node(
    kind: nkProgress,
    key: if key.len > 0: key else: "progress",
    value: value,
    minValue: 0,
    maxValue: maxValue,
    bg: rgb(0.88, 0.88, 0.90),
    color: defaultButton))

proc divider*(c: Context): Node {.discardable.} =
  addNode(c, Node(kind: nkDivider, color: rgb(0.82, 0.82, 0.85)))

proc textInput*(c: Context, value: string, onText: proc(text: string),
                key: string = "", placeholder: string = "",
                size: float32 = 14): Node {.discardable.} =
  addNode(c, Node(
    kind: nkInput,
    key: if key.len > 0: key else: "input",
    text: value,
    onText: onText,
    placeholder: placeholder,
    fontSize: size,
    color: defaultText,
    bg: rgb(1, 1, 1),
    padX: 8, padY: 5))

proc scrollView*(c: Context, key: string, height: float32 = 240): Node {.discardable.} =
  addNode(c, Node(kind: nkScroll, key: key, fixedH: height))

proc image*(c: Context, path: string, width: float32 = 120,
            height: float32 = 120): Node {.discardable.} =
  addNode(c, Node(kind: nkImage, imagePath: path,
                  fixedW: width, fixedH: height))

proc textArea*(c: Context, value: string, onText: proc(text: string),
               key: string = "", placeholder: string = "",
               size: float32 = 14, height: float32 = 120): Node {.discardable.} =
  addNode(c, Node(
    kind: nkInput,
    key: if key.len > 0: key else: "textarea",
    text: value,
    onText: onText,
    placeholder: placeholder,
    multiline: true,
    fixedH: height,
    fontSize: size,
    color: defaultText,
    bg: rgb(1, 1, 1),
    padX: 8, padY: 6))

# --- fluent options --------------------------------------------------------

proc fill*(n: Node): Node {.discardable.} =
  n.fill = true
  n

proc center*(n: Node): Node {.discardable.} =
  n.center = true
  n

proc gap*(n: Node, px: float32): Node {.discardable.} =
  n.gap = px
  n

proc padding*(n: Node, x, y: float32): Node {.discardable.} =
  n.padX = x
  n.padY = y
  n

proc width*(n: Node, px: float32): Node {.discardable.} =
  n.fixedW = px
  n

proc height*(n: Node, px: float32): Node {.discardable.} =
  n.fixedH = px
  n

proc fontSize*(n: Node, size: float32): Node {.discardable.} =
  n.fontSize = size
  n

proc bold*(n: Node): Node {.discardable.} =
  n.bold = true
  n

proc wrap*(n: Node): Node {.discardable.} =
  n.wrap = true
  n

proc color*(n: Node, c: Color): Node {.discardable.} =
  n.color = c
  n

proc background*(n: Node, c: Color): Node {.discardable.} =
  n.bg = c
  n

proc children*(n: Node, c: Context, body: proc()) =
  let prev = c.parent
  c.parent = n
  body()
  c.parent = prev

# --- direct painting (custom views) ---------------------------------------

proc drawRect*(c: Context, x, y, w, h: float32, color: Color,
               radius: float32 = 0) =
  c.scene.rect(Rect(x: x, y: y, w: w, h: h), color, radius)

proc drawText*(c: Context, text: string, x, y: float32, size: float32,
               color: Color, bold: bool = false) =
  c.scene.text(text, x, y, size, color, bold)

# --- measurement -----------------------------------------------------------

proc measure(n: Node, availW, availH: float32) =
  case n.kind
  of nkText:
    let wrapWidth =
      if n.fixedW > 0: n.fixedW
      elif n.wrap and availW > 0: availW
      else: 0.0'f32
    let layout = layoutText(n.text, n.fontSize, n.bold, wrapWidth)
    n.lines = layout.lines
    n.lineHeight = layout.lineHeight
    n.w = if n.fixedW > 0: n.fixedW else: layout.width
    n.h = if n.fixedH > 0: n.fixedH else: layout.height
  of nkButton:
    let m = measureText(n.text, n.fontSize, false)
    n.w = if n.fixedW > 0: n.fixedW else: m.width + 2 * n.padX
    n.h = if n.fixedH > 0: n.fixedH else: m.height + 2 * n.padY
  of nkCheckbox:
    let m = measureText(n.text, n.fontSize, false)
    n.w = if n.fixedW > 0: n.fixedW else: n.boxSize + 8 + m.width
    n.h = if n.fixedH > 0: n.fixedH else: max(n.boxSize, m.height)
  of nkSwitch:
    n.w = if n.fixedW > 0: n.fixedW else: 40
    n.h = if n.fixedH > 0: n.fixedH else: 22
  of nkSlider:
    n.w = if n.fixedW > 0: n.fixedW else: 160
    n.h = if n.fixedH > 0: n.fixedH else: 24
  of nkProgress:
    n.w = if n.fixedW > 0: n.fixedW else: 160
    n.h = if n.fixedH > 0: n.fixedH else: 8
  of nkDivider:
    n.w = if n.fixedW > 0: n.fixedW elif availW > 0: availW else: 0
    n.h = if n.fixedH > 0: n.fixedH else: 1
  of nkInput:
    if n.multiline:
      n.w = if n.fixedW > 0: n.fixedW
            elif availW > 0: availW
            else: 320.0'f32
      n.h = if n.fixedH > 0: n.fixedH else: 120.0'f32
      let layout = layoutText(n.text, n.fontSize, false,
                              max(1.0'f32, n.w - 2 * n.padX))
      n.lines = layout.lines
      n.lineHeight = layout.lineHeight
    else:
      let sample = if n.text.len > 0: n.text else: n.placeholder
      let m = measureText(sample, n.fontSize, false)
      n.w = if n.fixedW > 0: n.fixedW else: max(200.0'f32, m.width + 2 * n.padX)
      n.h = if n.fixedH > 0: n.fixedH else: max(28.0'f32, m.height + 2 * n.padY)
  of nkImage:
    n.w = if n.fixedW > 0: n.fixedW else: 120
    n.h = if n.fixedH > 0: n.fixedH else: 120
  of nkScroll:
    n.w = if n.fixedW > 0: n.fixedW
          elif availW > 0: availW
          else: 320.0'f32
    n.h = if n.fixedH > 0: n.fixedH
          elif availH > 0: availH
          else: 240.0'f32
    let contentW = max(1.0'f32, n.w - 2 * n.padX)
    var sumH, maxW: float32
    for ch in n.children:
      measure(ch, contentW, 1_000_000'f32)
      sumH += ch.h
      maxW = max(maxW, ch.w)
    if n.children.len > 1:
      sumH += n.gap * float32(n.children.len - 1)
    n.contentH = max(sumH + 2 * n.padY, n.h)
    if n.fixedW <= 0 and maxW > 0:
      n.w = max(n.w, maxW + 2 * n.padX)
  of nkColumn, nkRow:
    var maxW, maxH, sumW, sumH: float32
    for ch in n.children:
      measure(ch, availW - 2 * n.padX, availH - 2 * n.padY)
      maxW = max(maxW, ch.w)
      maxH = max(maxH, ch.h)
      sumW += ch.w
      sumH += ch.h
    if n.children.len > 1:
      let gaps = n.gap * float32(n.children.len - 1)
      sumW += gaps
      sumH += gaps
    if n.kind == nkColumn:
      n.w = if n.fill and availW > 0: availW else: maxW + 2 * n.padX
      n.h = if n.fill and availH > 0: availH else: sumH + 2 * n.padY
    else:
      n.w = if n.fill and availW > 0: availW else: sumW + 2 * n.padX
      n.h = if n.fill and availH > 0: availH else: maxH + 2 * n.padY
    if n.fixedW > 0: n.w = n.fixedW
    if n.fixedH > 0: n.h = n.fixedH

# --- arrangement -----------------------------------------------------------

proc arrange(n: Node, x, y: float32) =
  n.x = x
  n.y = y
  if n.kind == nkScroll:
    var cy = n.y + n.padY - n.scrollY
    for ch in n.children:
      arrange(ch, n.x + n.padX, cy)
      cy += ch.h + n.gap
    return
  if n.kind notin {nkColumn, nkRow}:
    return
  let contentX = n.x + n.padX
  let contentY = n.y + n.padY
  let contentW = n.w - 2 * n.padX
  let contentH = n.h - 2 * n.padY
  var totalW, totalH: float32
  for ch in n.children:
    totalW += ch.w
    totalH += ch.h
  if n.children.len > 1:
    let gaps = n.gap * float32(n.children.len - 1)
    totalW += gaps
    totalH += gaps

  if n.kind == nkColumn:
    var cy = if n.center: contentY + (contentH - totalH) / 2 else: contentY
    for ch in n.children:
      let cx = if n.center: contentX + (contentW - ch.w) / 2 else: contentX
      arrange(ch, cx, cy)
      cy += ch.h + n.gap
  else:
    var cx = if n.center: contentX + (contentW - totalW) / 2 else: contentX
    for ch in n.children:
      let cy = if n.center: contentY + (contentH - ch.h) / 2 else: contentY
      arrange(ch, cx, cy)
      cx += ch.w + n.gap

# --- painting and hit regions ---------------------------------------------

proc lighten(c: Color, amount: float32): Color =
  Color(r: min(c.r + amount, 1), g: min(c.g + amount, 1),
        b: min(c.b + amount, 1), a: c.a)

proc darken(c: Color, amount: float32): Color =
  Color(r: max(c.r - amount, 0), g: max(c.g - amount, 0),
        b: max(c.b - amount, 0), a: c.a)

proc caretLineCol(lines: seq[string], pos: int): tuple[line, col: int] =
  var offset = 0
  for i, line in lines:
    let finish = offset + line.len
    if pos <= finish:
      return (i, max(0, pos - offset))
    offset = finish + 1
  if lines.len > 0:
    result = (lines.high, lines[^1].len)
  else:
    result = (0, 0)

proc lineOffset(lines: seq[string], index: int): int =
  let last = min(index, lines.len)
  for i in 0 ..< last:
    result += lines[i].len + 1

proc clampInt(value, lo, hi: int): int =
  max(lo, min(value, hi))

proc selectionRange(engine: Engine, key: string,
                    textLen: int): tuple[start, finish: int] =
  if engine.caretKey == key:
    let a = clampInt(engine.selectionAnchor, 0, textLen)
    let b = clampInt(engine.caretPos, 0, textLen)
    result = (min(a, b), max(a, b))
  else:
    result = (textLen, textLen)

const selectionColor = Color(r: 0.22, g: 0.47, b: 0.95, a: 0.18)

proc paintSelection(n: Node, c: Context,
                    engine: Engine): tuple[start, finish: int] =
  result = selectionRange(engine, n.key, n.text.len)
  if result.start >= result.finish:
    return
  if n.multiline:
    var ly = n.y + n.padY
    for i, line in n.lines:
      let lineStart = lineOffset(n.lines, i)
      let lineFinish = lineStart + line.len
      let a = max(result.start, lineStart)
      let b = min(result.finish, lineFinish)
      if a < b:
        let left = a - lineStart
        let right = b - lineStart
        let x1 = n.x + n.padX +
          measureText(line[0 ..< min(left, line.len)], n.fontSize, false).width
        let x2 = n.x + n.padX +
          measureText(line[0 ..< min(right, line.len)], n.fontSize, false).width
        c.scene.rect(Rect(x: x1, y: ly, w: max(1.0'f32, x2 - x1),
                          h: n.lineHeight), selectionColor)
      ly += n.lineHeight
  else:
    let x1 = n.x + n.padX +
      measureText(n.text[0 ..< result.start], n.fontSize, false).width
    let x2 = n.x + n.padX +
      measureText(n.text[0 ..< result.finish], n.fontSize, false).width
    c.scene.rect(Rect(x: x1, y: n.y + 4, w: max(1.0'f32, x2 - x1),
                      h: n.h - 8), selectionColor)

proc paintFocus(n: Node, c: Context, radius: float32 = 6) =
  if c.engine != nil and c.engine.focusedKey == n.key:
    c.scene.rect(Rect(x: n.x - 3, y: n.y - 3, w: n.w + 6, h: n.h + 6),
                 rgb(0.35, 0.62, 1.0), radius)

proc paint(n: Node, c: Context) =
  case n.kind
  of nkText:
    if n.lines.len == 0:
      c.scene.text(n.text, n.x, n.y, n.fontSize, n.color, n.bold)
    else:
      var y = n.y
      for line in n.lines:
        c.scene.text(line, n.x, y, n.fontSize, n.color, n.bold)
        y += n.lineHeight
  of nkButton:
    paintFocus(n, c, n.radius + 3)
    var bg = n.bg
    if c.engine != nil:
      if c.engine.pressedKey == n.key:
        bg = darken(bg, 0.12)
      elif c.engine.hoveredKey == n.key:
        bg = lighten(bg, 0.08)
    c.scene.rect(Rect(x: n.x, y: n.y, w: n.w, h: n.h), bg, n.radius)
    let m = measureText(n.text, n.fontSize, false)
    c.scene.text(n.text, n.x + (n.w - m.width) / 2,
                 n.y + (n.h - m.height) / 2, n.fontSize, n.color, false)
  of nkCheckbox:
    paintFocus(n, c, 6)
    let box = n.boxSize
    let by = n.y + (n.h - box) / 2
    c.scene.rect(Rect(x: n.x - 1, y: by - 1, w: box + 2, h: box + 2),
                 rgb(0.62, 0.62, 0.68), 5)
    c.scene.rect(Rect(x: n.x, y: by, w: box, h: box),
                 if n.checked: defaultButton else: rgb(1, 1, 1), 4)
    if n.checked:
      let check = measureText("✓", 12, true)
      c.scene.text("✓", n.x + (box - check.width) / 2,
                   by + (box - check.height) / 2, 12, rgb(1, 1, 1), true)
    let m = measureText(n.text, n.fontSize, false)
    c.scene.text(n.text, n.x + box + 8, n.y + (n.h - m.height) / 2,
                 n.fontSize, n.color, false)
  of nkSwitch:
    paintFocus(n, c, n.h / 2 + 3)
    let radius = min(n.h, 22) / 2
    let track = if n.checked: defaultButton else: rgb(0.80, 0.80, 0.84)
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
    c.scene.rect(Rect(x: n.x, y: ty, w: n.w, h: trackH), n.bg, trackH / 2)
    c.scene.rect(Rect(x: n.x, y: ty, w: n.w * t, h: trackH), n.color, trackH / 2)
    let knob = 16.0'f32
    let kx = n.x + n.w * t - knob / 2
    c.scene.rect(Rect(x: kx, y: n.y + (n.h - knob) / 2, w: knob, h: knob),
                 n.color, knob / 2)
  of nkProgress:
    let t =
      if n.maxValue > 0: max(0.0'f32, min(1.0'f32, n.value / n.maxValue))
      else: 0.0'f32
    c.scene.rect(Rect(x: n.x, y: n.y, w: n.w, h: n.h), n.bg, n.h / 2)
    c.scene.rect(Rect(x: n.x, y: n.y, w: n.w * t, h: n.h), n.color, n.h / 2)
  of nkDivider:
    c.scene.rect(Rect(x: n.x, y: n.y, w: n.w, h: max(1.0'f32, n.h)), n.color)
  of nkInput:
    paintFocus(n, c, 6)
    c.scene.rect(Rect(x: n.x - 1, y: n.y - 1, w: n.w + 2, h: n.h + 2),
                 rgb(0.62, 0.62, 0.68), 6)
    c.scene.rect(Rect(x: n.x, y: n.y, w: n.w, h: n.h), n.bg, 5)
    if c.engine != nil and c.engine.focusedKey == n.key:
      discard paintSelection(n, c, c.engine)
    if n.multiline:
      let textColor = if n.text.len > 0: n.color else: rgb(0.55, 0.55, 0.60)
      if n.text.len == 0:
        c.scene.text(n.placeholder, n.x + n.padX, n.y + n.padY,
                     n.fontSize, textColor, false)
      else:
        var ly = n.y + n.padY
        for line in n.lines:
          if ly + n.lineHeight > n.y + n.h - n.padY + 0.5:
            break
          c.scene.text(line, n.x + n.padX, ly, n.fontSize, n.color, false)
          ly += n.lineHeight
      if c.engine != nil and c.engine.markedText.len > 0 and
          c.engine.markedKey == n.key:
        let (ml, mc) = caretLineCol(n.lines,
          if c.engine.caretKey == n.key: c.engine.caretPos else: n.text.len)
        let my = n.y + n.padY + float32(ml) * n.lineHeight
        let mx = n.x + n.padX +
          measureText(n.lines[ml][0 ..< min(mc, n.lines[ml].len)],
                      n.fontSize, false).width
        c.scene.text(c.engine.markedText, mx, my, n.fontSize,
                     rgb(0.22, 0.47, 0.95), false)
        c.scene.rect(Rect(x: mx, y: my + n.lineHeight - 2,
                          w: measureText(c.engine.markedText, n.fontSize,
                                         false).width, h: 1),
                     rgb(0.22, 0.47, 0.95))
      if c.engine != nil and c.engine.focusedKey == n.key:
        let pos =
          if c.engine.caretKey == n.key:
            max(0, min(c.engine.caretPos, n.text.len))
          else:
            n.text.len
        let (lineIdx, col) = caretLineCol(n.lines, pos)
        if lineIdx < n.lines.len:
          let line = n.lines[lineIdx]
          let prefix = if col > 0: line[0 ..< min(col, line.len)] else: ""
          let pw = measureText(prefix, n.fontSize, false).width
          let cx = n.x + n.padX + min(pw, max(0.0'f32, n.w - 2 * n.padX - 1))
          let cy = n.y + n.padY + float32(lineIdx) * n.lineHeight
          if cy < n.y + n.h - n.padY:
            c.scene.rect(Rect(x: cx, y: cy, w: 1.5'f32,
                              h: min(n.lineHeight - 2, n.h - cy - n.padY)),
                         defaultText)
    else:
      let shown = if n.text.len > 0: n.text else: n.placeholder
      let textColor = if n.text.len > 0: n.color else: rgb(0.55, 0.55, 0.60)
      let m = measureText(shown, n.fontSize, false)
      c.scene.text(shown, n.x + n.padX, n.y + (n.h - m.height) / 2,
                   n.fontSize, textColor, false)
      if c.engine != nil and c.engine.focusedKey == n.key:
        let pos =
          if c.engine.caretKey == n.key: max(0, min(c.engine.caretPos, n.text.len))
          else: n.text.len
        let prefix = if pos > 0: n.text[0 ..< pos] else: ""
        let pw = measureText(prefix, n.fontSize, false).width
        let cx = n.x + n.padX + min(pw, max(0.0'f32, n.w - 2 * n.padX - 1))
        c.scene.rect(Rect(x: cx, y: n.y + 6, w: 1.5'f32, h: n.h - 12),
                     defaultText)
  of nkImage:
    c.scene.image(n.imagePath, Rect(x: n.x, y: n.y, w: n.w, h: n.h))
  of nkScroll:
    c.scene.clip(Rect(x: n.x, y: n.y, w: n.w, h: n.h))
    for ch in n.children:
      paint(ch, c)
    c.scene.restoreClip()
  of nkColumn, nkRow:
    for ch in n.children:
      paint(ch, c)

proc intersect(a, b: Rect): Rect =
  let x = max(a.x, b.x)
  let y = max(a.y, b.y)
  let r = min(a.x + a.w, b.x + b.w)
  let btm = min(a.y + a.h, b.y + b.h)
  if r <= x or btm <= y:
    result = Rect(x: x, y: y, w: 0, h: 0)
  else:
    result = Rect(x: x, y: y, w: r - x, h: btm - y)

proc collectHits(n: Node, engine: Engine, clip: Rect) =
  var currentClip = clip
  if n.kind == nkScroll:
    currentClip = intersect(clip, Rect(x: n.x, y: n.y, w: n.w, h: n.h))
    engine.scrollRegions.add ScrollRegion(
      key: n.key,
      rect: Rect(x: n.x, y: n.y, w: n.w, h: n.h),
      contentH: n.contentH)
  if n.onClick != nil or n.onDrag != nil or n.kind == nkInput:
    engine.hits.add Hit(
      rect: Rect(x: n.x, y: n.y, w: n.w, h: n.h),
      key: n.key,
      onClick: n.onClick,
      onDrag: n.onDrag,
      input: n.kind == nkInput,
      text: n.text,
      onText: n.onText,
      multiline: n.multiline,
      lines: n.lines,
      lineHeight: n.lineHeight,
      padX: n.padX,
      padY: n.padY,
      fontSize: n.fontSize,
      clip: currentClip)
  for ch in n.children:
    collectHits(ch, engine, currentClip)

# --- frame and input -------------------------------------------------------

proc render*(engine: Engine, view: proc(c: Context),
             width, height: float32): Scene =
  let c = initContext(width, height, engine)
  view(c)
  engine.pendingKeys.setLen(0)
  if c.root != nil:
    measure(c.root, width, height)
    if c.root.fill:
      c.root.w = width
      c.root.h = height
    proc applyScroll(n: Node) =
      if n.kind == nkScroll:
        let maxOff = max(0.0'f32, n.contentH - n.h)
        let off = max(0.0'f32, min(engine.scrollOffsets.getOrDefault(n.key, 0), maxOff))
        engine.scrollOffsets[n.key] = off
        n.scrollY = off
      for ch in n.children:
        applyScroll(ch)
    applyScroll(c.root)
    arrange(c.root, 0, 0)
    engine.hits.setLen(0)
    engine.scrollRegions.setLen(0)
    paint(c.root, c)
    collectHits(c.root, engine, Rect(x: 0, y: 0, w: width, h: height))
  else:
    engine.hits.setLen(0)
  result = c.scene

proc hitIndex(engine: Engine, x, y: float32): int =
  for i in countdown(engine.hits.len - 1, 0):
    let r = engine.hits[i].rect
    let c = engine.hits[i].clip
    if c.w > 0 and c.h > 0 and
        (x < c.x or x >= c.x + c.w or y < c.y or y >= c.y + c.h):
      continue
    if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h:
      return i
  result = -1

proc requestFrame(engine: Engine) =
  if engine.requestFrame != nil:
    engine.requestFrame()

proc caretIndexLine(text: string, x, left, fontSize: float32): int =
  let local = x - left
  if local <= 0:
    return 0
  var best = 0
  var bestDist = abs(local)
  for i in 1 .. text.len:
    let w = measureText(text[0 ..< i], fontSize, false).width
    let d = abs(w - local)
    if d < bestDist:
      bestDist = d
      best = i
  if local > measureText(text, fontSize, false).width:
    best = text.len
  result = best

proc caretIndex(hit: Hit, x: float32): int =
  result = caretIndexLine(hit.text, x, hit.rect.x + hit.padX, hit.fontSize)

proc caretIndexAt(hit: Hit, x, y: float32): int =
  if not hit.multiline or hit.lines.len == 0:
    return caretIndex(hit, x)
  let lineIdx = max(0, min(hit.lines.high,
    int((y - hit.rect.y - hit.padY) / max(hit.lineHeight, 1))))
  var offset = 0
  for i in 0 ..< lineIdx:
    offset += hit.lines[i].len + 1
  let line = hit.lines[lineIdx]
  result = offset + caretIndexLine(line, x, hit.rect.x + hit.padX, hit.fontSize)

proc handleMouseDown*(engine: Engine, x, y: float32) =
  let i = hitIndex(engine, x, y)
  engine.pressedDrag = nil
  if i >= 0:
    let hit = engine.hits[i]
    engine.pressedKey = hit.key
    engine.focusedKey = hit.key
    if hit.onDrag != nil:
      engine.pressedDrag = hit.onDrag
      engine.pressedRect = hit.rect
      hit.onDrag(hit.rect, x, y)
    if hit.input:
      engine.caretKey = hit.key
      engine.caretPos = caretIndexAt(hit, x, y)
      engine.selectionAnchor = engine.caretPos
      engine.selectingInput = hit.key
  else:
    engine.pressedKey = ""
  requestFrame(engine)

proc handleMouseUp*(engine: Engine, x, y: float32) =
  let i = hitIndex(engine, x, y)
  if i >= 0 and engine.pressedKey == engine.hits[i].key:
    if engine.hits[i].onClick != nil:
      engine.hits[i].onClick()
  engine.pressedKey = ""
  engine.pressedDrag = nil
  engine.selectingInput = ""
  requestFrame(engine)

proc handleMouseMove*(engine: Engine, x, y: float32) =
  if engine.pressedDrag != nil:
    engine.pressedDrag(engine.pressedRect, x, y)
    requestFrame(engine)
    return
  if engine.selectingInput.len > 0:
    for hit in engine.hits:
      if hit.key == engine.selectingInput and hit.input:
        engine.caretPos = caretIndexAt(hit, x, y)
        requestFrame(engine)
        return
  let i = hitIndex(engine, x, y)
  let key = if i >= 0: engine.hits[i].key else: ""
  if key != engine.hoveredKey:
    engine.hoveredKey = key
    requestFrame(engine)

proc keyPressed*(c: Context, key: string): bool =
  ## Consume a pending key for this frame.
  if c.engine == nil:
    return false
  for i in 0 ..< c.engine.pendingKeys.len:
    if c.engine.pendingKeys[i] == key:
      c.engine.pendingKeys[i] = c.engine.pendingKeys[^1]
      c.engine.pendingKeys.setLen(c.engine.pendingKeys.len - 1)
      return true
  result = false


proc selectionRangeFor(engine: Engine, key: string,
                       textLen: int): tuple[start, finish: int] =
  selectionRange(engine, key, textLen)

proc focusedInputIndex(engine: Engine): int =
  for i in 0 ..< engine.hits.len:
    if engine.hits[i].key == engine.focusedKey and engine.hits[i].input:
      return i
  result = -1

proc snapshot(engine: Engine, key, text: string, caret, anchor: int) =
  var stack = engine.undoStacks.getOrDefault(key)
  stack.add EditSnapshot(text: text, caret: caret, anchor: anchor)
  if stack.len > 100:
    stack.delete(0)
  engine.undoStacks[key] = stack
  engine.redoStacks[key] = @[]

proc applySnapshot(engine: Engine, index: int, s: EditSnapshot) =
  let hit = engine.hits[index]
  engine.hits[index].text = s.text
  engine.caretKey = hit.key
  engine.caretPos = s.caret
  engine.selectionAnchor = s.anchor
  if hit.onText != nil:
    hit.onText(s.text)
  requestFrame(engine)

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

proc applyInput(engine: Engine, index: int, text: string,
                caret, anchor: int) =
  let hit = engine.hits[index]
  engine.hits[index].text = text
  engine.caretKey = hit.key
  engine.caretPos = caret
  engine.selectionAnchor = anchor
  if hit.onText != nil:
    hit.onText(text)
  requestFrame(engine)

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
  if index < 0:
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
  if not hit.multiline:
    text = text.replace("\r", " ").replace("\n", " ")
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
  requestFrame(engine)

proc insertText*(engine: Engine, text: string) =
  let index = focusedInputIndex(engine)
  if index < 0 or text.len == 0:
    return
  let hit = engine.hits[index]
  var insert = text
  if not hit.multiline:
    insert = insert.replace("\r", " ").replace("\n", " ")
  let sel = selectionRange(engine, hit.key, hit.text.len)
  engine.snapshot(hit.key, hit.text, engine.caretPos, engine.selectionAnchor)
  let next = hit.text[0 ..< sel.start] & insert & hit.text[sel.finish .. ^1]
  engine.markedText = ""
  engine.markedKey = ""
  engine.applyInput(index, next, sel.start + insert.len, sel.start + insert.len)

proc setMarkedText*(engine: Engine, text: string) =
  if text.len == 0:
    engine.markedText = ""
    engine.markedKey = ""
  else:
    engine.markedText = text
    engine.markedKey = engine.focusedKey
  requestFrame(engine)

proc unmarkText*(engine: Engine) =
  engine.markedText = ""
  engine.markedKey = ""
  requestFrame(engine)

proc hasMarkedText*(engine: Engine): bool =
  engine.markedText.len > 0

proc caretRect*(engine: Engine): Rect =
  let index = focusedInputIndex(engine)
  if index < 0:
    return Rect(x: 0, y: 0, w: 1, h: 18)
  let hit = engine.hits[index]
  let text = hit.text
  let pos =
    if engine.caretKey == hit.key: max(0, min(engine.caretPos, text.len))
    else: text.len
  if hit.multiline:
    let lines = if hit.lines.len > 0: hit.lines else: @[""]
    let (lineIdx, col) = caretLineCol(lines, pos)
    let line = lines[lineIdx]
    let prefix = if col > 0: line[0 ..< min(col, line.len)] else: ""
    let x = hit.rect.x + hit.padX +
      measureText(prefix, hit.fontSize, false).width
    let y = hit.rect.y + hit.padY + float32(lineIdx) * hit.lineHeight
    return Rect(x: x, y: y, w: 2, h: max(12, hit.lineHeight))
  let prefix = if pos > 0: text[0 ..< pos] else: ""
  let x = hit.rect.x + hit.padX +
    measureText(prefix, hit.fontSize, false).width
  Rect(x: x, y: hit.rect.y + 6, w: 2, h: max(12, hit.rect.h - 12))

proc editInput(engine: Engine, index: int, key: string, modifiers: uint32) =
  let hit = engine.hits[index]
  let cmd = (modifiers and KeyCommand) != 0
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
      discard

  var text = hit.text
  let beforeText = text
  var caret =
    if engine.caretKey == hit.key: max(0, min(engine.caretPos, text.len))
    else: text.len
  let sel = engine.selectionRangeFor(hit.key, text.len)
  let hasSel = sel.finish > sel.start
  let anchorBefore = if hasSel: engine.selectionAnchor else: caret
  let lines = if hit.multiline: hit.lines else: @[text]
  let (lineIdx, col) = caretLineCol(lines, caret)
  var handled = true
  case key
  of "backspace":
    if hasSel:
      text = text[0 ..< sel.start] & text[sel.finish .. ^1]
      caret = sel.start
    elif caret > 0:
      text = text[0 ..< caret - 1] & text[caret .. ^1]
      dec caret
  of "delete":
    if hasSel:
      text = text[0 ..< sel.start] & text[sel.finish .. ^1]
      caret = sel.start
    elif caret < text.len:
      text = text[0 ..< caret] & text[caret + 1 .. ^1]
  of "left":
    if hasSel and not shift:
      caret = sel.start
    elif caret > 0:
      dec caret
  of "right":
    if hasSel and not shift:
      caret = sel.finish
    elif caret < text.len:
      inc caret
  of "home":
    if hit.multiline:
      caret = lineOffset(lines, lineIdx)
    else:
      caret = 0
  of "end":
    if hit.multiline:
      caret = lineOffset(lines, lineIdx) + lines[lineIdx].len
    else:
      caret = text.len
  of "up", "down":
    if hit.multiline and lines.len > 0:
      let target = if key == "up": max(0, lineIdx - 1)
                   else: min(lines.high, lineIdx + 1)
      caret = lineOffset(lines, target) + min(col, lines[target].len)
  of "escape":
    engine.focusedKey = ""
    engine.caretKey = ""
    engine.caretPos = 0
    engine.selectionAnchor = 0
    requestFrame(engine)
    return
  of "enter", "\n":
    if hit.multiline:
      text = text[0 ..< sel.start] & "\n" & text[sel.finish .. ^1]
      caret = sel.start + 1
    else:
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

proc handleKeyDown*(engine: Engine, key: string, modifiers: uint32 = 0) =
  if key.len == 0:
    return
  if key == "tab":
    if engine.hits.len > 0:
      var current = -1
      for i in 0 ..< engine.hits.len:
        if engine.hits[i].key == engine.focusedKey:
          current = i
      let step = if (modifiers and KeyShift) != 0: -1 else: 1
      let next =
        if current < 0: 0
        else: (current + step + engine.hits.len) mod engine.hits.len
      engine.focusedKey = engine.hits[next].key
      engine.caretKey = ""
      engine.selectionAnchor = 0
      requestFrame(engine)
    return
  var focused = -1
  for i in 0 ..< engine.hits.len:
    if engine.hits[i].key == engine.focusedKey:
      focused = i
  if focused >= 0 and engine.hits[focused].input:
    editInput(engine, focused, key, modifiers)
    return
  if (modifiers and KeyCommand) != 0:
    return
  if key in ["enter", "space"]:
    for hit in engine.hits:
      if hit.key == engine.focusedKey:
        if hit.onClick != nil:
          hit.onClick()
          requestFrame(engine)
        break
    return
  engine.pendingKeys.add key
  requestFrame(engine)

proc handleScroll*(engine: Engine, x, y, dy: float32) =
  for i in countdown(engine.scrollRegions.len - 1, 0):
    let r = engine.scrollRegions[i]
    if x >= r.rect.x and x < r.rect.x + r.rect.w and
        y >= r.rect.y and y < r.rect.y + r.rect.h:
      let maxOff = max(0.0'f32, r.contentH - r.rect.h)
      let old = engine.scrollOffsets.getOrDefault(r.key, 0)
      let next = max(0.0'f32, min(old + dy, maxOff))
      if next != old:
        engine.scrollOffsets[r.key] = next
        requestFrame(engine)
      return

proc clickKey*(engine: Engine, key: string): bool =
  ## Test/dev hook: click a control by its key in the last built frame.
  for hit in engine.hits:
    if hit.key == key:
      hit.onClick()
      requestFrame(engine)
      return true
  result = false
