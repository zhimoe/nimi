## UI data model, widget constructors, fluent style modifiers, IME composition
## offset mapping, and box/scrollbar geometry primitives.

import std/[math, strutils, tables]

import ../keys
import ../scene/scene
import ../text/measure

export scene

type
  AlignItem* = enum
    aiAuto, aiStart, aiCenter, aiEnd, aiStretch
  Justify* = enum
    jcStart, jcCenter, jcEnd, jcSpaceBetween
  TextAlign* = enum
    taStart, taCenter, taEnd

  NodeKind* = enum
    nkColumn
    nkRow
    nkText
    nkButton
    nkButtonBase
    nkCheckbox
    nkSwitch
    nkSlider
    nkProgress
    nkDivider
    nkInput
    nkScroll
    nkImage
    nkCustom
    nkRichText

  TextRun* = object
    text*: string
    color*: Color
    bg*: Color
    bold*: bool

  InputViewport* = object
    width*, height*, maxX*, contentH*: float32
    horizontal*, vertical*: Rect

  InputScrollbar* = object
    inputKey*: string
    thumb*: Rect
    maximum*: float32
    horizontal*: bool

  InputScrollbarDrag* = object
    scrollbar*: InputScrollbar
    trackStart*, travel*, grab*: float32

  EditSnapshot* = object
    text*: string
    caret*: int
    anchor*: int

  ScrollRegion* = object
    key*: string
    rect*: Rect
    contentH*: float32
    viewportH*: float32
    layer*: int

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
    padL*, padT*, padR*, padB*: float32   # additive to padX/padY
    marginL*, marginT*, marginR*, marginB*: float32
    minW*, minH*, maxW*, maxH*: float32  # <= 0 means unset
    grow*, basis*: float32
    basisSet*: bool
    alignItems*: AlignItem
    justify*: Justify
    alignSelf*: AlignItem
    alignItemsSet*, justifySet*: bool
    clipChildren*: bool
    borderWidth*: float32
    borderColor*: Color
    hoverBg*, pressedBg*: Color
    accent*: Color
    plain*: bool
    focusable*, tabStop*, blockClicks*: bool
    modalOverlay*: bool
    fill*: bool
    fillW*, fillH*: bool
    center*: bool
    wrap*: bool
    lines*: seq[string]
    lineStarts*: seq[int]
    lineHeight*: float32
    fixedW*, fixedH*: float32
    virtualList*: bool
    itemCount*, firstItem*: int
    itemHeight*: float32
    contentH*: float32
    scrollY*, scrollX*: float32
    imagePath*: string
    displayText*: string
    children*: seq[Node]
    onClick*: proc() {.closure.}
    onDoubleClick*: proc() {.closure.}
    onActivate*: proc() {.closure.}
    onSpace*: proc() {.closure.}
    onSubmit*: proc() {.closure.}
    onDrag*: proc(rect: Rect, x, y: float32) {.closure.}
    onText*: proc(text: string) {.closure.}
    customPaint*: proc(c: Context, r: Rect) {.closure.}
    richRuns*: seq[TextRun]
    placeholder*: string
    placeholderColor*: Color
    multiline*: bool
    noWrap*: bool
    lineNumbers*: bool
    lineNumberColor*: Color
    gutterW*: float32
    textWidth*: float32
    singleLine*: bool
    textAlign*: TextAlign
    family*: string
    checked*: bool
    mixed*: bool
    value*, minValue*, maxValue*: float32
    boxSize*: float32
    x*, y*, w*, h*: float32
    prefW*, prefH*: float32

  Hit* = object
    rect*: Rect
    key*: string
    onClick*: proc() {.closure.}
    onDoubleClick*: proc() {.closure.}
    onActivate*: proc() {.closure.}
    onSpace*: proc() {.closure.}
    onSubmit*: proc() {.closure.}
    onDrag*: proc(rect: Rect, x, y: float32) {.closure.}
    input*: bool
    focusable*, tabStop*, blocks*: bool
    layer*: int
    text*: string
    displayText*: string
    onText*: proc(text: string) {.closure.}
    multiline*: bool
    noWrap*: bool
    lineNumbers*: bool
    lines*: seq[string]
    lineStarts*: seq[int]
    lineHeight*: float32
    padX*, padY*, fontSize*: float32
    family*: string
    clip*: Rect
    scrollX*: float32
    textViewportW*, textViewportH*, maxScrollX*: float32
    scrollbar*: InputScrollbar

  Engine* = ref object
    inputOffsets*: Table[string, float32]
    scrollOffsets*: Table[string, float32]
    scrollRegions*: seq[ScrollRegion]
    lastMouseX*, lastMouseY*: float32
    hoveredKey*: string
    hoverRects*: Table[string, Rect]
    pressedKey*: string
    pressedDrag*: proc(rect: Rect, x, y: float32) {.closure.}
    scrollbarDrag*: InputScrollbarDrag
    pressedRect*: Rect
    focusedKey*: string
    focusRequest*: string
    focusSelectAll*: bool
    caretKey*: string
    caretPos*: int
    selectionAnchor*: int
    selectingInput*: string
    manuallyScrolledInput*: string
    clipboardRead*: proc(): string {.closure.}
    clipboardWrite*: proc(text: string) {.closure.}
    undoStacks*: Table[string, seq[EditSnapshot]]
    redoStacks*: Table[string, seq[EditSnapshot]]
    markedText*: string
    markedKey*: string
    markedStart*: int
    markedEnd*: int
    markedSelectedStart*: int
    markedSelectedLen*: int
    pendingKeys*: seq[string]
    pendingShortcuts*: seq[tuple[key: string, modifiers: uint32]]
    shortcuts*: Table[string, proc() {.closure.}]
    topModalLayer*: int
    hits*: seq[Hit]
    requestFrame*: proc() {.closure.}

  Context* = ref object
    width*, height*: float32
    scene*: Scene
    engine*: Engine
    parent*, root*: Node
    overlays*: seq[Node]

converter toPlainClosure*(fn: proc() {.closure.}):
    proc() {.closure.} = fn

converter toPlainPaint*(fn: proc(c: Context, r: Rect) {.closure.}):
    proc(c: Context, r: Rect) {.closure.} = fn

const
  inputScrollbarSize* = 8.0'f32
  inputScrollbarInset* = 2.0'f32

let
  defaultText* = rgb(0.08, 0.08, 0.10)
  defaultButton* = rgb(0.16, 0.40, 0.90)

proc initContext*(width, height: float32, engine: Engine): Context =
  Context(
    width: width,
    height: height,
    engine: engine,
    scene: Scene(width: width, height: height, clear: rgb(1, 1, 1)))

proc addNode*(c: Context, n: Node): Node =
  if c.parent != nil:
    c.parent.children.add n
  else:
    c.root = n
  result = n

proc notifyFrame*(engine: Engine) =
  if engine != nil and engine.requestFrame != nil:
    (engine.requestFrame)()

proc manualScrollX*(engine: Engine, key: string, offset: float32) =
  engine.manuallyScrolledInput = key
  engine.inputOffsets[key] = offset

# --- IME composition mapping ----------------------------------------------

proc markedActive*(engine: Engine, key: string): bool =
  engine != nil and engine.markedText.len > 0 and engine.markedKey == key

proc markedDocRange*(engine: Engine, text: string): tuple[start, finish: int] =
  let start = max(0, min(engine.markedStart, text.len))
  result = (start, max(start, min(engine.markedEnd, text.len)))

proc displayTextFor*(engine: Engine, key, text: string):
                     tuple[text: string, markedStart, markedLen: int] =
  if not markedActive(engine, key):
    return (text, 0, 0)
  let (start, finish) = markedDocRange(engine, text)
  result.text = text[0 ..< start] & engine.markedText & text[finish .. ^1]
  result.markedStart = start
  result.markedLen = engine.markedText.len

proc displayCaretFor*(engine: Engine, key, text: string, docCaret: int): int =
  let caret = max(0, min(docCaret, text.len))
  if not markedActive(engine, key):
    return caret
  let (start, finish) = markedDocRange(engine, text)
  if caret <= start: caret
  elif caret >= finish: caret - (finish - start) + engine.markedText.len
  else: start + engine.markedText.len

proc displayByteToDoc*(engine: Engine, key, text: string,
                       displayOffset: int): int =
  let offset = max(0, min(displayOffset, text.len + engine.markedText.len))
  if not markedActive(engine, key):
    return max(0, min(offset, text.len))
  let (start, finish) = markedDocRange(engine, text)
  if offset <= start: offset
  elif offset >= start + engine.markedText.len:
    min(text.len, finish + (offset - start - engine.markedText.len))
  else:
    start

proc clearComposition*(engine: Engine) =
  engine.markedText.setLen(0)
  engine.markedKey = ""
  engine.markedSelectedStart = 0
  engine.markedSelectedLen = 0

proc cancelInput*(engine: Engine, composition: bool = true) =
  engine.pressedKey = ""
  engine.pressedDrag = nil
  engine.scrollbarDrag = InputScrollbarDrag()
  engine.selectingInput = ""
  if composition: engine.clearComposition()
  engine.notifyFrame()

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
    focusable: true, tabStop: true,
    onClick: onClick))

proc buttonBase*(c: Context, key: string, onClick: proc() {.closure.} = nil): Node {.discardable.} =
  addNode(c, Node(
    kind: nkButtonBase,
    key: key,
    center: true,
    focusable: true, tabStop: true,
    onClick: onClick))

proc spacer*(c: Context, grow: float32 = 1): Node {.discardable.} =
  addNode(c, Node(kind: nkColumn, grow: grow, w: 0, h: 0))

proc custom*(c: Context, key: string, w, h: float32,
             onPaint: proc(c: Context, r: Rect) {.closure.},
             onClick: proc() {.closure.} = nil): Node {.discardable.} =
  addNode(c, Node(
    kind: nkCustom,
    key: key,
    fixedW: w, fixedH: h,
    customPaint: onPaint,
    onClick: onClick,
    focusable: onClick != nil,
    tabStop: false))

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
    focusable: true, tabStop: true,
    onClick: onToggle))

proc switch*(c: Context, on: bool, onToggle: proc(),
             key: string = ""): Node {.discardable.} =
  addNode(c, Node(
    kind: nkSwitch,
    key: if key.len > 0: key else: "switch",
    checked: on,
    boxSize: 22,
    bg: defaultButton,
    focusable: true, tabStop: true,
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
    focusable: true, tabStop: true,
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
                size: float32 = 14, family: string = ""): Node {.discardable.} =
  let name = if key.len > 0: key else: "input"
  addNode(c, Node(
    kind: nkInput,
    key: name,
    text: value,
    displayText: displayTextFor(c.engine, name, value).text,
    onText: onText,
    placeholder: placeholder,
    fontSize: size,
    family: family,
    color: defaultText,
    bg: rgb(1, 1, 1),
    padX: 8, padY: 5,
    focusable: true, tabStop: true))

proc scrollView*(c: Context, key: string, height: float32 = 240): Node {.discardable.} =
  addNode(c, Node(kind: nkScroll, key: key,
                  fixedH: if height > 0: height else: 0))

proc overlay*(c: Context, key: string, modal = true): Node {.discardable.} =
  var n = Node(kind: nkRow, key: key, fill: true, modalOverlay: modal)
  c.overlays.add n
  n

proc image*(c: Context, path: string, width: float32 = 120,
            height: float32 = 120): Node {.discardable.} =
  addNode(c, Node(kind: nkImage, imagePath: path,
                  fixedW: width, fixedH: height))

proc richText*(c: Context, runs: openArray[TextRun], size: float32 = 14,
               family: string = "", bold: bool = false): Node {.discardable.} =
  addNode(c, Node(
    kind: nkRichText,
    richRuns: @runs,
    fontSize: size,
    family: family,
    bold: bold))

proc textArea*(c: Context, value: string, onText: proc(text: string),
               key: string = "", placeholder: string = "",
               size: float32 = 14, height: float32 = 120,
               family: string = ""): Node {.discardable.} =
  let name = if key.len > 0: key else: "textarea"
  addNode(c, Node(
    kind: nkInput,
    key: name,
    text: value,
    displayText: displayTextFor(c.engine, name, value).text,
    onText: onText,
    placeholder: placeholder,
    multiline: true,
    fixedH: height,
    fontSize: size,
    family: family,
    color: defaultText,
    bg: rgb(1, 1, 1),
    padX: 8, padY: 6,
    focusable: true, tabStop: true))

# --- fluent options --------------------------------------------------------

proc fill*(n: Node): Node {.discardable.} = (n.fill = true; n)
proc fillWidth*(n: Node): Node {.discardable.} = (n.fillW = true; n)
proc fillHeight*(n: Node): Node {.discardable.} = (n.fillH = true; n)
proc center*(n: Node): Node {.discardable.} = (n.center = true; n)
proc gap*(n: Node, px: float32): Node {.discardable.} = (n.gap = px; n)
proc padding*(n: Node, x, y: float32): Node {.discardable.} = (n.padX = x; n.padY = y; n)
proc width*(n: Node, px: float32): Node {.discardable.} = (n.fixedW = px; n)
proc height*(n: Node, px: float32): Node {.discardable.} = (n.fixedH = px; n)
proc fontSize*(n: Node, size: float32): Node {.discardable.} = (n.fontSize = size; n)
proc bold*(n: Node): Node {.discardable.} = (n.bold = true; n)
proc wrap*(n: Node): Node {.discardable.} = (n.wrap = true; n)
proc color*(n: Node, c: Color): Node {.discardable.} = (n.color = c; n)
proc background*(n: Node, c: Color): Node {.discardable.} = (n.bg = c; n)
proc radius*(n: Node, px: float32): Node {.discardable.} = (n.radius = px; n)
proc key*(n: Node, k: string): Node {.discardable.} = (n.key = k; n)
proc border*(n: Node, width: float32, color: Color): Node {.discardable.} =
  n.borderWidth = width; n.borderColor = color; n
proc margin*(n: Node, x, y: float32): Node {.discardable.} =
  n.marginL = x; n.marginR = x; n.marginT = y; n.marginB = y; n
proc margin*(n: Node, l, t, r, b: float32): Node {.discardable.} =
  n.marginL = l; n.marginT = t; n.marginR = r; n.marginB = b; n
proc marginLeft*(n: Node, px: float32): Node {.discardable.} = (n.marginL = px; n)
proc marginRight*(n: Node, px: float32): Node {.discardable.} = (n.marginR = px; n)
proc padding*(n: Node, l, t, r, b: float32): Node {.discardable.} =
  n.padL = l; n.padT = t; n.padR = r; n.padB = b; n
proc paddingLeft*(n: Node, px: float32): Node {.discardable.} = (n.padL = px; n)
proc paddingTop*(n: Node, px: float32): Node {.discardable.} = (n.padT = px; n)
proc paddingRight*(n: Node, px: float32): Node {.discardable.} = (n.padR = px; n)
proc paddingBottom*(n: Node, px: float32): Node {.discardable.} = (n.padB = px; n)
proc grow*(n: Node, factor: float32 = 1): Node {.discardable.} = (n.grow = factor; n)
proc basis*(n: Node, px: float32): Node {.discardable.} = (n.basis = px; n.basisSet = true; n)
proc minWidth*(n: Node, px: float32): Node {.discardable.} = (n.minW = px; n)
proc maxWidth*(n: Node, px: float32): Node {.discardable.} = (n.maxW = px; n)
proc minHeight*(n: Node, px: float32): Node {.discardable.} = (n.minH = px; n)
proc maxHeight*(n: Node, px: float32): Node {.discardable.} = (n.maxH = px; n)
proc alignItems*(n: Node, a: AlignItem): Node {.discardable.} =
  n.alignItems = a; n.alignItemsSet = true; n
proc justifyContent*(n: Node, j: Justify): Node {.discardable.} =
  n.justify = j; n.justifySet = true; n
proc alignSelf*(n: Node, a: AlignItem): Node {.discardable.} = (n.alignSelf = a; n)
proc clipChildren*(n: Node): Node {.discardable.} = (n.clipChildren = true; n)
proc whenClicked*(n: Node, fn: proc() {.closure.}): Node {.discardable.} = (n.onClick = fn; n)
proc whenDoubleClicked*(n: Node, fn: proc() {.closure.}): Node {.discardable.} = (n.onDoubleClick = fn; n)
proc whenActivated*(n: Node, fn: proc() {.closure.}): Node {.discardable.} = (n.onActivate = fn; n)
proc whenSpacePressed*(n: Node, fn: proc() {.closure.}): Node {.discardable.} = (n.onSpace = fn; n)
proc whenSubmitted*(n: Node, fn: proc() {.closure.}): Node {.discardable.} = (n.onSubmit = fn; n)
proc hoverBg*(n: Node, c: Color): Node {.discardable.} = (n.hoverBg = c; n)
proc accent*(n: Node, c: Color): Node {.discardable.} = (n.accent = c; n)
proc plain*(n: Node): Node {.discardable.} = (n.plain = true; n)
proc placeholderColor*(n: Node, c: Color): Node {.discardable.} = (n.placeholderColor = c; n)
proc pressedBg*(n: Node, c: Color): Node {.discardable.} = (n.pressedBg = c; n)
proc focusable*(n: Node, on = true): Node {.discardable.} = (n.focusable = on; n)
proc tabStop*(n: Node, on = true): Node {.discardable.} = (n.tabStop = on; n)
proc blockClicks*(n: Node): Node {.discardable.} = (n.blockClicks = true; n)
proc mono*(n: Node): Node {.discardable.} = (n.family = "mono"; n)
proc family*(n: Node, face: string): Node {.discardable.} = (n.family = face; n)
proc textAlign*(n: Node, align: TextAlign): Node {.discardable.} = (n.textAlign = align; n)
proc singleLine*(n: Node): Node {.discardable.} = (n.singleLine = true; n)
proc noWrap*(n: Node): Node {.discardable.} = (n.noWrap = true; n)
proc lineNumbers*(n: Node, color: Color): Node {.discardable.} =
  n.lineNumbers = true; n.lineNumberColor = color; n

proc children*(n: Node, c: Context, body: proc()) =
  let prev = c.parent
  c.parent = n
  body()
  c.parent = prev

proc shortcutKey*(key: string, modifiers: uint32): string =
  let mask = modifiers and (KeyShortcut or KeyShift or KeyAlt)
  key.toLowerAscii & "\x00" & $mask

proc registerShortcut*(c: Context, key: string, modifiers: uint32,
                       fn: proc() {.closure.}) =
  if c.engine != nil:
    c.engine.shortcuts[shortcutKey(key, modifiers)] = fn

proc pointerIn*(c: Context, key: string): bool =
  if c.engine == nil or key.len == 0:
    return false
  let r = c.engine.hoverRects.getOrDefault(key)
  if r.w <= 0 or r.h <= 0:
    return false
  c.engine.lastMouseX >= r.x and c.engine.lastMouseX < r.x + r.w and
    c.engine.lastMouseY >= r.y and c.engine.lastMouseY < r.y + r.h

proc requestFocus*(c: Context, key: string, selectAll = false) =
  if c.engine == nil:
    return
  c.engine.focusRequest = key
  c.engine.focusSelectAll = selectAll
  c.engine.notifyFrame()

proc revealListRow*(engine: Engine, key: string, index, count: int,
                    rowHeight, viewportHeight: float32) =
  if engine == nil or index < 0 or index >= count or rowHeight <= 0 or
      viewportHeight <= 0: return
  if classify(rowHeight) in {fcNan, fcInf, fcNegInf} or
      classify(viewportHeight) in {fcNan, fcInf, fcNegInf}: return
  let top = float32(index) * rowHeight
  let bottom = top + rowHeight
  let current = engine.scrollOffsets.getOrDefault(key, 0)
  var offset = current
  if top < current: offset = top
  elif bottom > current + viewportHeight: offset = bottom - viewportHeight
  engine.scrollOffsets[key] = clamp(offset, 0'f32,
    max(0'f32, float32(count) * rowHeight - viewportHeight))
  engine.notifyFrame()

proc virtualList*(c: Context, key: string, count: int, rowHeight, viewportHeight: float32,
                  buildRow: proc(c: Context, index: int), overscan: int = 2): Node {.discardable.} =
  if count < 0 or rowHeight <= 0 or viewportHeight <= 0 or
      classify(rowHeight) in {fcNan, fcInf, fcNegInf} or
      classify(viewportHeight) in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "Invalid virtual list dimensions")
  let extent = float32(count) * rowHeight
  if classify(extent) in {fcInf, fcNan}:
    raise newException(ValueError, "Virtual list extent overflow")
  let offset = clamp(c.engine.scrollOffsets.getOrDefault(key, 0),
                     0'f32, max(0'f32, extent - viewportHeight))
  c.engine.scrollOffsets[key] = offset
  let extra = clamp(overscan, 0, 100)
  let first = max(0, int(floor(offset / rowHeight)) - extra)
  let last = min(count, int(ceil((offset + viewportHeight) / rowHeight)) + extra)
  result = scrollView(c, key, viewportHeight)
  result.virtualList = true
  result.itemCount = count
  result.firstItem = first
  result.itemHeight = rowHeight
  let previous = c.parent
  c.parent = result
  defer: c.parent = previous
  for index in first ..< last:
    let row = column(c).fill().height(rowHeight)
    c.parent = row
    try: buildRow(c, index)
    finally: c.parent = result

# --- direct painting (custom views) ---------------------------------------

proc drawRect*(c: Context, x, y, w, h: float32, color: Color,
               radius: float32 = 0) =
  c.scene.rect(Rect(x: x, y: y, w: w, h: h), color, radius)

proc drawText*(c: Context, text: string, x, y: float32, size: float32,
               color: Color, bold: bool = false) =
  c.scene.text(text, x, y, size, color, bold)

# --- shared box & text geometry helpers ------------------------------------

proc leftPad*(n: Node): float32 {.inline.} = n.padX + n.padL
proc rightPad*(n: Node): float32 {.inline.} = n.padX + n.padR
proc topPad*(n: Node): float32 {.inline.} = n.padY + n.padT
proc bottomPad*(n: Node): float32 {.inline.} = n.padY + n.padB
proc innerW*(n: Node): float32 {.inline.} = n.w - leftPad(n) - rightPad(n)
proc innerH*(n: Node): float32 {.inline.} = n.h - topPad(n) - bottomPad(n)

proc applySizeLimits*(n: Node) =
  if n.minW > 0: n.w = max(n.w, n.minW)
  if n.maxW > 0: n.w = min(n.w, n.maxW)
  if n.minH > 0: n.h = max(n.h, n.minH)
  if n.maxH > 0: n.h = min(n.h, n.maxH)

proc inputGutter*(n: Node): float32 =
  if not n.lineNumbers:
    return 0
  let count = max(1, n.lines.len)
  let digits = max(2, ($count).len)
  let sample = repeat('0', digits)
  measureText(sample, n.fontSize, false, n.family).width + 10

proc layoutInput*(n: Node) =
  var wrapWidth =
    if n.noWrap: 0.0'f32
    else: max(1.0'f32, innerW(n) - n.gutterW)
  var layout = layoutText(n.displayText, n.fontSize, false, wrapWidth,
                          n.family)
  n.lines = layout.lines
  n.lineStarts = layout.lineStarts
  n.lineHeight = layout.lineHeight
  let gutter = n.inputGutter()
  n.gutterW = gutter
  if gutter > 0 and not n.noWrap:
    wrapWidth = max(1.0'f32, innerW(n) - gutter)
    layout = layoutText(n.displayText, n.fontSize, false, wrapWidth,
                        n.family)
    n.lines = layout.lines
    n.lineStarts = layout.lineStarts
    n.lineHeight = layout.lineHeight
  n.textWidth = layout.width

proc inputViewport*(n: Node): InputViewport =
  result.width = max(0'f32, innerW(n) - n.gutterW - 2)
  result.height = n.h
  result.contentH = topPad(n) + bottomPad(n) + n.lineHeight * float32(n.lines.len)
  if n.noWrap and result.width > 0:
    result.maxX = max(0'f32, n.textWidth + 2 - result.width)
    if result.maxX > 0 and n.h > 2 * inputScrollbarSize:
      result.height -= inputScrollbarSize + inputScrollbarInset
      result.horizontal = Rect(x: n.x + leftPad(n) + n.gutterW,
        y: n.y + result.height, w: result.width, h: inputScrollbarSize)
  if result.contentH > result.height and n.w > 12:
    result.vertical = Rect(x: n.x + n.w - 7, y: n.y + 2,
      w: 5, h: max(0'f32, result.height - 4))

proc inputThumb*(track: Rect, viewport, maximum, offset: float32,
                 horizontal: bool): Rect =
  let length = if horizontal: track.w else: track.h
  let size = min(length, max(18'f32, length * viewport / (viewport + maximum)))
  let position = max(0'f32, min(1'f32, offset / maximum)) * (length - size)
  result = track
  if horizontal:
    result.x += position
    result.w = size
  else:
    result.y += position
    result.h = size

proc caretLineCol*(lines: seq[string], starts: seq[int],
                   pos: int): tuple[line, col: int] =
  if lines.len == 0:
    return (0, 0)
  result = (0, max(0, min(pos, lines[0].len)))
  for i in 0 ..< min(lines.len, starts.len):
    if starts[i] <= pos:
      result = (i, max(0, min(pos - starts[i], lines[i].len)))
    else:
      break

proc lineOffset*(starts: seq[int], index: int): int =
  if starts.len == 0:
    return 0
  starts[max(0, min(index, starts.high))]

proc clampInt*(value, lo, hi: int): int =
  max(lo, min(value, hi))

proc selectionRange*(engine: Engine, key: string,
                     textLen: int): tuple[start, finish: int] =
  if engine.caretKey == key:
    let a = clampInt(engine.selectionAnchor, 0, textLen)
    let b = clampInt(engine.caretPos, 0, textLen)
    result = (min(a, b), max(a, b))
  else:
    result = (textLen, textLen)

proc intersect*(a, b: Rect): Rect =
  let x = max(a.x, b.x)
  let y = max(a.y, b.y)
  let r = min(a.x + a.w, b.x + b.w)
  let btm = min(a.y + a.h, b.y + b.h)
  if r <= x or btm <= y:
    result = Rect(x: x, y: y, w: 0, h: 0)
  else:
    result = Rect(x: x, y: y, w: r - x, h: btm - y)

proc contains*(r: Rect, x, y: float32): bool =
  x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
