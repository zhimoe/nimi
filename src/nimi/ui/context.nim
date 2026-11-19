## M2 UI: a small per-frame node tree with column/row layout, text and
## buttons. The view function rebuilds the tree every frame; click handlers
## mutate the app's state and request another frame.
##
## This is intentionally a stepping stone toward the arena/Element design in
## docs/03-native-ui.md. It keeps the same view-function model and scene
## output, without the generation handles and layout cache yet.

import std/[strutils, tables, math]

import ../keys
import ../scene/scene
import ../text/[grapheme, measure, range]

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
      ## Input text with an active IME composition inserted at the caret.
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
    textWidth: float32
    singleLine*: bool
    textAlign*: TextAlign
    family*: string
    checked*: bool
    mixed*: bool
    value*, minValue*, maxValue*: float32
    boxSize*: float32
    x*, y*, w*, h*: float32
    prefW*, prefH*: float32
      ## Intrinsic size from the first measure pass. Arrangement uses it as
      ## the flex base so a second pass (after scroll clamping) is stable.

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
    textViewportW, textViewportH, maxScrollX: float32
    scrollbar: InputScrollbar

  InputScrollbar = object
    inputKey: string
    thumb: Rect
    maximum: float32
    horizontal: bool

  InputScrollbarDrag = object
    scrollbar: InputScrollbar
    trackStart, travel, grab: float32

  EditSnapshot = object
    text: string
    caret: int
    anchor: int

  ScrollRegion* = object
    key*: string
    rect*: Rect
    contentH*: float32
    viewportH: float32
    layer: int

  Engine* = ref object
    inputOffsets*: Table[string, float32]
    scrollOffsets*: Table[string, float32]
    scrollRegions*: seq[ScrollRegion]
    lastMouseX*, lastMouseY*: float32
    hoveredKey*: string
    hoverRects*: Table[string, Rect]
    pressedKey*: string
    pressedDrag*: proc(rect: Rect, x, y: float32) {.closure.}
    scrollbarDrag: InputScrollbarDrag
    pressedRect*: Rect
    focusedKey*: string
    focusRequest*: string
    focusSelectAll*: bool
    caretKey*: string
    caretPos*: int
    selectionAnchor*: int
    selectingInput*: string
    manuallyScrolledInput: string
    clipboardRead*: proc(): string {.closure.}
    clipboardWrite*: proc(text: string) {.closure.}
    undoStacks*: Table[string, seq[EditSnapshot]]
    redoStacks*: Table[string, seq[EditSnapshot]]
    markedText*: string
    markedKey*: string
    markedStart*: int
      ## Byte offset in the document where the composition replaces text.
    markedEnd*: int
    markedSelectedStart*: int
      ## UTF-16 offset and length of the selection inside markedText.
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
  ## Anonymous procs with no captures infer {.gcsafe.}. Allow them where a
  ## closure callback is expected without forcing every caller to annotate.
converter toPlainPaint*(fn: proc(c: Context, r: Rect) {.closure.}):
    proc(c: Context, r: Rect) {.closure.} = fn

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

# --- IME composition mapping ----------------------------------------------

proc markedActive*(engine: Engine, key: string): bool =
  engine != nil and engine.markedText.len > 0 and engine.markedKey == key

proc markedDocRange(engine: Engine, text: string): tuple[start, finish: int] =
  let start = max(0, min(engine.markedStart, text.len))
  result = (start, max(start, min(engine.markedEnd, text.len)))

proc displayTextFor*(engine: Engine, key, text: string):
                     tuple[text: string, markedStart, markedLen: int] =
  ## The document text with the active composition substituted in. The
  ## document itself stays untouched until insertText commits it.
  if not markedActive(engine, key):
    return (text, 0, 0)
  let (start, finish) = markedDocRange(engine, text)
  result.text = text[0 ..< start] & engine.markedText & text[finish .. ^1]
  result.markedStart = start
  result.markedLen = engine.markedText.len

proc displayCaretFor*(engine: Engine, key, text: string, docCaret: int): int =
  ## Map a document byte offset into the display text from displayTextFor.
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

proc clearComposition(engine: Engine) =
  engine.markedText.setLen(0)
  engine.markedKey = ""
  engine.markedSelectedStart = 0
  engine.markedSelectedLen = 0

proc cancelInput*(engine: Engine, composition: bool = true) =
  ## Losing capture must not synthesize a click or keep a drag alive. Losing
  ## window focus also discards uncommitted IME text, but preserves the document.
  engine.pressedKey = ""
  engine.pressedDrag = nil
  engine.scrollbarDrag = InputScrollbarDrag()
  engine.selectingInput = ""
  if composition: engine.clearComposition()
  if engine.requestFrame != nil: engine.requestFrame()

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
  ## A button without a built-in look: a row that holds arbitrary children,
  ## centers them, and handles hover/pressed/Enter/Space.
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
  ## height > 0 fixes the viewport; height = 0 lets grow/basis or the parent
  ## allocate it (use with .grow(1).basis(0)).
  addNode(c, Node(kind: nkScroll, key: key,
                  fixedH: if height > 0: height else: 0))

proc overlay*(c: Context, key: string, modal = true): Node {.discardable.} =
  ## A full-window top layer painted and hit-tested after the root content.
  ## Use `.background(scrim)` and `.onClick(dismiss)` for a modal backdrop;
  ## `.modalOverlay = false` for a toast that lets clicks through.
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

proc fill*(n: Node): Node {.discardable.} =
  n.fill = true
  n

proc fillWidth*(n: Node): Node {.discardable.} =
  n.fillW = true
  n

proc fillHeight*(n: Node): Node {.discardable.} =
  n.fillH = true
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

proc radius*(n: Node, px: float32): Node {.discardable.} =
  n.radius = px
  n

proc key*(n: Node, k: string): Node {.discardable.} =
  n.key = k
  n

proc border*(n: Node, width: float32, color: Color): Node {.discardable.} =
  n.borderWidth = width
  n.borderColor = color
  n

proc margin*(n: Node, x, y: float32): Node {.discardable.} =
  n.marginL = x
  n.marginR = x
  n.marginT = y
  n.marginB = y
  n

proc margin*(n: Node, l, t, r, b: float32): Node {.discardable.} =
  n.marginL = l
  n.marginT = t
  n.marginR = r
  n.marginB = b
  n

proc marginLeft*(n: Node, px: float32): Node {.discardable.} =
  n.marginL = px
  n

proc marginRight*(n: Node, px: float32): Node {.discardable.} =
  n.marginR = px
  n

proc padding*(n: Node, l, t, r, b: float32): Node {.discardable.} =
  n.padL = l
  n.padT = t
  n.padR = r
  n.padB = b
  n

proc paddingLeft*(n: Node, px: float32): Node {.discardable.} =
  n.padL = px
  n

proc paddingTop*(n: Node, px: float32): Node {.discardable.} =
  n.padT = px
  n

proc paddingRight*(n: Node, px: float32): Node {.discardable.} =
  n.padR = px
  n

proc paddingBottom*(n: Node, px: float32): Node {.discardable.} =
  n.padB = px
  n

proc grow*(n: Node, factor: float32 = 1): Node {.discardable.} =
  n.grow = factor
  n

proc basis*(n: Node, px: float32): Node {.discardable.} =
  n.basis = px
  n.basisSet = true
  n

proc minWidth*(n: Node, px: float32): Node {.discardable.} =
  n.minW = px
  n

proc maxWidth*(n: Node, px: float32): Node {.discardable.} =
  n.maxW = px
  n

proc minHeight*(n: Node, px: float32): Node {.discardable.} =
  n.minH = px
  n

proc maxHeight*(n: Node, px: float32): Node {.discardable.} =
  n.maxH = px
  n

proc alignItems*(n: Node, a: AlignItem): Node {.discardable.} =
  n.alignItems = a
  n.alignItemsSet = true
  n

proc justifyContent*(n: Node, j: Justify): Node {.discardable.} =
  n.justify = j
  n.justifySet = true
  n

proc alignSelf*(n: Node, a: AlignItem): Node {.discardable.} =
  n.alignSelf = a
  n

proc clipChildren*(n: Node): Node {.discardable.} =
  n.clipChildren = true
  n

proc whenClicked*(n: Node, fn: proc() {.closure.}): Node {.discardable.} =
  n.onClick = fn
  n

proc whenDoubleClicked*(n: Node, fn: proc() {.closure.}): Node {.discardable.} =
  n.onDoubleClick = fn
  n

proc whenActivated*(n: Node, fn: proc() {.closure.}): Node {.discardable.} =
  n.onActivate = fn
  n

proc whenSpacePressed*(n: Node, fn: proc() {.closure.}): Node {.discardable.} =
  n.onSpace = fn
  n

proc whenSubmitted*(n: Node, fn: proc() {.closure.}): Node {.discardable.} =
  n.onSubmit = fn
  n

proc hoverBg*(n: Node, c: Color): Node {.discardable.} =
  n.hoverBg = c
  n

proc accent*(n: Node, c: Color): Node {.discardable.} =
  n.accent = c
  n

proc plain*(n: Node): Node {.discardable.} =
  n.plain = true
  n

proc placeholderColor*(n: Node, c: Color): Node {.discardable.} =
  n.placeholderColor = c
  n

proc pressedBg*(n: Node, c: Color): Node {.discardable.} =
  n.pressedBg = c
  n

proc focusable*(n: Node, on = true): Node {.discardable.} =
  n.focusable = on
  n

proc tabStop*(n: Node, on = true): Node {.discardable.} =
  n.tabStop = on
  n

proc blockClicks*(n: Node): Node {.discardable.} =
  n.blockClicks = true
  n

proc mono*(n: Node): Node {.discardable.} =
  n.family = "mono"
  n

proc family*(n: Node, face: string): Node {.discardable.} =
  n.family = face
  n

proc textAlign*(n: Node, align: TextAlign): Node {.discardable.} =
  n.textAlign = align
  n

proc singleLine*(n: Node): Node {.discardable.} =
  n.singleLine = true
  n

proc noWrap*(n: Node): Node {.discardable.} =
  n.noWrap = true
  n

proc lineNumbers*(n: Node, color: Color): Node {.discardable.} =
  n.lineNumbers = true
  n.lineNumberColor = color
  n

proc children*(n: Node, c: Context, body: proc()) =
  let prev = c.parent
  c.parent = n
  body()
  c.parent = prev

proc shortcutKey(key: string, modifiers: uint32): string =
  let mask = modifiers and (KeyShortcut or KeyShift or KeyAlt)
  key.toLowerAscii & "\x00" & $mask

proc registerShortcut*(c: Context, key: string, modifiers: uint32,
                       fn: proc() {.closure.}) =
  ## Register for this frame. Modifier shortcuts fire before text editing, so
  ## Ctrl+S/Ctrl+K work while an input is focused. Register only keys that
  ## should not reach editInput; Ctrl+A/C/X/V/Z/Y keep their editing roles.
  if c.engine != nil:
    c.engine.shortcuts[shortcutKey(key, modifiers)] = fn

proc pointerIn*(c: Context, key: string): bool =
  ## Whether the pointer is inside the named node from the previous frame.
  ## Lets a row keep its hover style while a child action is hovered.
  if c.engine == nil or key.len == 0:
    return false
  let r = c.engine.hoverRects.getOrDefault(key)
  if r.w <= 0 or r.h <= 0:
    return false
  c.engine.lastMouseX >= r.x and c.engine.lastMouseX < r.x + r.w and
    c.engine.lastMouseY >= r.y and c.engine.lastMouseY < r.y + r.h

proc requestFocus*(c: Context, key: string, selectAll = false) =
  ## Apply focus after the current frame's hits are collected. For a text
  ## input, selectAll places the caret at the end and anchors at the start.
  if c.engine == nil:
    return
  c.engine.focusRequest = key
  c.engine.focusSelectAll = selectAll
  if c.engine.requestFrame != nil:
    c.engine.requestFrame()

proc revealListRow*(engine: Engine, key: string, index, count: int,
                    rowHeight, viewportHeight: float32) =
  ## Make a fixed-height row visible without moving an already visible row.
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
  if engine.requestFrame != nil: engine.requestFrame()

proc virtualList*(c: Context, key: string, count: int, rowHeight, viewportHeight: float32,
                  buildRow: proc(c: Context, index: int), overscan: int = 2): Node {.discardable.} =
  ## Fixed-height rows. Builder runs only for the viewport plus overscan.
  ## Keep row contents within rowHeight; use stable keys for interactive children.
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

# --- box helpers -----------------------------------------------------------

proc leftPad(n: Node): float32 {.inline.} = n.padX + n.padL
proc rightPad(n: Node): float32 {.inline.} = n.padX + n.padR
proc topPad(n: Node): float32 {.inline.} = n.padY + n.padT
proc bottomPad(n: Node): float32 {.inline.} = n.padY + n.padB
proc innerW(n: Node): float32 {.inline.} = n.w - leftPad(n) - rightPad(n)
proc innerH(n: Node): float32 {.inline.} = n.h - topPad(n) - bottomPad(n)

proc applySizeLimits(n: Node) =
  if n.minW > 0: n.w = max(n.w, n.minW)
  if n.maxW > 0: n.w = min(n.w, n.maxW)
  if n.minH > 0: n.h = max(n.h, n.minH)
  if n.maxH > 0: n.h = min(n.h, n.maxH)

proc textLayoutFor(n: Node, width: float32) =
  let available = max(1.0'f32, width - leftPad(n) - rightPad(n))
  if n.singleLine:
    let layout = layoutText(n.text, n.fontSize, n.bold, 0, n.family)
    n.lineHeight = layout.lineHeight
    n.lines = @[ellipsizeText(n.text, n.fontSize, n.bold, n.family, available)]
    n.lineStarts = @[0]
  else:
    let wrapWidth = if n.wrap: available else: 0.0'f32
    let layout = layoutText(n.text, n.fontSize, n.bold, wrapWidth, n.family)
    n.lines = layout.lines
    n.lineStarts = layout.lineStarts
    n.lineHeight = layout.lineHeight

proc richMetrics(n: Node): tuple[width, height: float32] =
  for run in n.richRuns:
    let m = measureText(run.text, n.fontSize, run.bold or n.bold, n.family)
    result.width += m.width
    result.height = max(result.height, m.height)
  if n.richRuns.len == 0:
    let m = measureText("", n.fontSize, n.bold, n.family)
    result.height = m.height

proc innerWidthOf(n: Node, slot: float32): float32 =
  max(0.0'f32, slot - leftPad(n) - rightPad(n))

proc inputGutter(n: Node): float32 =
  if not n.lineNumbers:
    return 0
  let count = max(1, n.lines.len)
  let digits = max(2, ($count).len)
  let sample = repeat('0', digits)
  measureText(sample, n.fontSize, false, n.family).width + 10

proc layoutInput(n: Node) =
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

type InputViewport = object
  width, height, maxX, contentH: float32
  horizontal, vertical: Rect

const
  inputScrollbarSize = 8.0'f32
  inputScrollbarInset = 2.0'f32

proc inputViewport(n: Node): InputViewport =
  result.width = max(0'f32, innerW(n) - n.gutterW - 2)
  result.height = n.h
  result.contentH = topPad(n) + bottomPad(n) + n.lineHeight * float32(n.lines.len)
  if n.noWrap and result.width > 0:
    # Include room for the caret at the document's right edge.
    result.maxX = max(0'f32, n.textWidth + 2 - result.width)
    if result.maxX > 0 and n.h > 2 * inputScrollbarSize:
      result.height -= inputScrollbarSize + inputScrollbarInset
      result.horizontal = Rect(x: n.x + leftPad(n) + n.gutterW,
        y: n.y + result.height, w: result.width, h: inputScrollbarSize)
  if result.contentH > result.height and n.w > 12:
    result.vertical = Rect(x: n.x + n.w - 7, y: n.y + 2,
      w: 5, h: max(0'f32, result.height - 4))

proc inputThumb(track: Rect, viewport, maximum, offset: float32,
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

# --- measurement -----------------------------------------------------------

proc measure(n: Node, availW, availH: float32) =
  case n.kind
  of nkText:
    let pad = leftPad(n) + rightPad(n)
    let wrapWidth =
      if n.fixedW > 0: max(1.0'f32, n.fixedW - pad)
      elif n.singleLine: 0.0'f32
      elif n.wrap and availW > pad: availW - pad
      else: 0.0'f32
    let layout = layoutText(n.text, n.fontSize, n.bold, wrapWidth, n.family)
    n.lines = layout.lines
    n.lineStarts = layout.lineStarts
    n.lineHeight = layout.lineHeight
    n.w = if n.fixedW > 0: n.fixedW else: layout.width + pad
    n.h = if n.fixedH > 0: n.fixedH
          else: layout.height + topPad(n) + bottomPad(n)
  of nkRichText:
    let m = richMetrics(n)
    n.w = if n.fixedW > 0: n.fixedW
          else: m.width + leftPad(n) + rightPad(n)
    n.h = if n.fixedH > 0: n.fixedH
          else: m.height + topPad(n) + bottomPad(n)
  of nkButton:
    let m = measureText(n.text, n.fontSize, n.bold, n.family)
    n.w = if n.fixedW > 0: n.fixedW
          else: m.width + leftPad(n) + rightPad(n)
    n.h = if n.fixedH > 0: n.fixedH
          else: m.height + topPad(n) + bottomPad(n)
  of nkCheckbox:
    let m = measureText(n.text, n.fontSize, false, n.family)
    n.w = if n.fixedW > 0: n.fixedW
          else: (if n.text.len > 0: n.boxSize + 8 + m.width else: n.boxSize) +
                leftPad(n) + rightPad(n)
    n.h = if n.fixedH > 0: n.fixedH
          else: max(n.boxSize, m.height) + topPad(n) + bottomPad(n)
  of nkSwitch:
    n.w = if n.fixedW > 0: n.fixedW else: 40 + leftPad(n) + rightPad(n)
    n.h = if n.fixedH > 0: n.fixedH else: 22 + topPad(n) + bottomPad(n)
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
      n.layoutInput()
    else:
      let sample = if n.displayText.len > 0: n.displayText else: n.placeholder
      let m = measureText(sample, n.fontSize, false, n.family)
      n.w = if n.fixedW > 0: n.fixedW
            else: max(200.0'f32, m.width + leftPad(n) + rightPad(n))
      n.h = if n.fixedH > 0: n.fixedH
            else: max(28.0'f32, m.height + topPad(n) + bottomPad(n))
  of nkImage:
    n.w = if n.fixedW > 0: n.fixedW else: 120
    n.h = if n.fixedH > 0: n.fixedH else: 120
  of nkCustom:
    n.w = if n.fixedW > 0: n.fixedW else: 24
    n.h = if n.fixedH > 0: n.fixedH else: 24
  of nkScroll:
    n.w = if n.fixedW > 0: n.fixedW
          elif availW > 0: availW
          else: 320.0'f32
    n.h = if n.fixedH > 0: n.fixedH
          elif availH > 0: availH
          else: 240.0'f32
    let contentW = max(1.0'f32, innerW(n))
    var sumH, maxW: float32
    for ch in n.children:
      measure(ch, max(0.0'f32, contentW - ch.marginL - ch.marginR),
              1_000_000'f32)
      sumH += ch.h + ch.marginT + ch.marginB
      maxW = max(maxW, ch.w + ch.marginL + ch.marginR)
    if n.children.len > 1:
      sumH += n.gap * float32(n.children.len - 1)
    n.contentH = if n.virtualList: max(float32(n.itemCount) * n.itemHeight, n.h)
                 else: max(sumH + topPad(n) + bottomPad(n), n.h)
    if n.fixedW <= 0 and maxW > 0:
      n.w = max(n.w, maxW + leftPad(n) + rightPad(n))
  of nkColumn, nkRow, nkButtonBase:
    let padX = leftPad(n) + rightPad(n)
    let padY = topPad(n) + bottomPad(n)
    var maxW, maxH, sumW, sumH: float32
    let childAvailW = (if n.fixedW > 0: n.fixedW else: availW) - padX
    let childAvailH = (if n.fixedH > 0: n.fixedH else: availH) - padY
    for ch in n.children:
      measure(ch, max(0.0'f32, childAvailW - ch.marginL - ch.marginR),
              max(0.0'f32, childAvailH - ch.marginT - ch.marginB))
      let cw = ch.w + ch.marginL + ch.marginR
      let chh = ch.h + ch.marginT + ch.marginB
      maxW = max(maxW, cw)
      maxH = max(maxH, chh)
      sumW += cw
      sumH += chh
      if n.kind == nkColumn and ch.basisSet:
        sumH += ch.basis - ch.prefH
      elif n.kind != nkColumn and ch.basisSet:
        sumW += ch.basis - ch.prefW
    if n.children.len > 1:
      let gaps = n.gap * float32(n.children.len - 1)
      sumW += gaps
      sumH += gaps
    let fillW = n.fill or n.fillW
    let fillH = n.fill or n.fillH
    if n.kind == nkColumn:
      n.w = if fillW and availW > 0: availW else: maxW + padX
      n.h = if fillH and availH > 0: availH else: sumH + padY
    else:
      n.w = if fillW and availW > 0: availW else: sumW + padX
      n.h = if fillH and availH > 0: availH else: maxH + padY
    if n.fixedW > 0: n.w = n.fixedW
    if n.fixedH > 0: n.h = n.fixedH
  if n.fixedW > 0: n.w = n.fixedW
  if n.fixedH > 0: n.h = n.fixedH
  n.applySizeLimits()
  n.prefW = n.w
  n.prefH = n.h

# --- arrangement -----------------------------------------------------------

proc remeasureAllocated(n: Node, w, h: float32) =
  if abs(n.w - w) < 0.01 and abs(n.h - h) < 0.01:
    return
  let prefW = n.prefW
  let prefH = n.prefH
  defer:
    n.prefW = prefW
    n.prefH = prefH
  case n.kind
  of nkText:
    n.w = w
    n.h = h
    n.textLayoutFor(w)
  of nkRichText, nkCustom, nkImage, nkDivider, nkButton, nkCheckbox,
     nkSwitch, nkSlider, nkProgress:
    n.w = w
    n.h = h
  of nkInput:
    n.w = w
    n.h = h
    if n.multiline:
      n.layoutInput()
  else:
    measure(n, w, h)
    n.w = w
    n.h = h

proc arrange(n: Node, x, y, slotW, slotH: float32)

proc arrangeContainer(n: Node, x, y, w, h: float32) =
  let vertical = n.kind == nkColumn
  let contentX = x + leftPad(n)
  let contentY = y + topPad(n)
  let contentW = max(0.0'f32, w - leftPad(n) - rightPad(n))
  let contentH = max(0.0'f32, h - topPad(n) - bottomPad(n))
  let contentMain = if vertical: contentH else: contentW
  let contentCross = if vertical: contentW else: contentH
  let count = n.children.len
  if count == 0:
    return
  var bases = newSeq[float32](count)
  var total: float32
  for i, ch in n.children:
    let base = if ch.basisSet: ch.basis
               elif vertical: ch.prefH
               else: ch.prefW
    bases[i] = base
    total += base + (if vertical: ch.marginT + ch.marginB
                     else: ch.marginL + ch.marginR)
  if count > 1:
    total += n.gap * float32(count - 1)
  let free = contentMain - total
  var sumGrow: float32
  for ch in n.children:
    if ch.grow > 0:
      sumGrow += ch.grow
  var extras = newSeq[float32](count)
  var distributed: float32
  if free > 0 and sumGrow > 0:
    for i, ch in n.children:
      if ch.grow > 0:
        extras[i] = free * ch.grow / sumGrow
        distributed += extras[i]
  let alignment =
    if n.alignItemsSet: n.alignItems
    elif n.center: aiCenter
    else: aiStart
  let justification =
    if n.justifySet: n.justify
    elif n.center: jcCenter
    else: jcStart
  let remainder = free - distributed
  var start = if vertical: contentY else: contentX
  var extraGap = 0.0'f32
  case justification
  of jcCenter:
    if remainder > 0: start += remainder / 2
  of jcEnd:
    if remainder > 0: start += remainder
  of jcSpaceBetween:
    if count > 1 and remainder > 0:
      extraGap = remainder / float32(count - 1)
  of jcStart:
    discard
  var cursor = start
  for i, ch in n.children:
    let mainStart = if vertical: ch.marginT else: ch.marginL
    let mainEnd = if vertical: ch.marginB else: ch.marginR
    var mainSize = bases[i] + extras[i]
    if vertical:
      if ch.minH > 0: mainSize = max(mainSize, ch.minH)
      if ch.maxH > 0: mainSize = min(mainSize, ch.maxH)
    else:
      if ch.minW > 0: mainSize = max(mainSize, ch.minW)
      if ch.maxW > 0: mainSize = min(mainSize, ch.maxW)
    let align = if ch.alignSelf != aiAuto: ch.alignSelf else: alignment
    let crossStart = if vertical: ch.marginL else: ch.marginT
    let crossEnd = if vertical: ch.marginR else: ch.marginB
    let crossAvail = max(0.0'f32, contentCross - crossStart - crossEnd)
    var crossSize = if vertical: ch.prefW else: ch.prefH
    let crossFixed = if vertical: ch.fixedW > 0 else: ch.fixedH > 0
    if align == aiStretch and not crossFixed:
      crossSize = crossAvail
    var crossPos = (if vertical: contentX else: contentY) + crossStart
    case align
    of aiCenter:
      crossPos += (crossAvail - crossSize) / 2
    of aiEnd:
      crossPos += crossAvail - crossSize
    of aiAuto, aiStart, aiStretch:
      discard
    let childX = if vertical: crossPos else: cursor + mainStart
    let childY = if vertical: cursor + mainStart else: crossPos
    let allocW = if vertical: crossSize else: mainSize
    let allocH = if vertical: mainSize else: crossSize
    remeasureAllocated(ch, allocW, allocH)
    arrange(ch, childX, childY, allocW, allocH)
    cursor += mainSize + mainStart + mainEnd + n.gap + extraGap

proc arrangeScroll(n: Node, x, y, w, h: float32) =
  let contentW = max(1.0'f32, w - leftPad(n) - rightPad(n))
  var sumH, maxW: float32
  for ch in n.children:
    measure(ch, max(0.0'f32, contentW - ch.marginL - ch.marginR),
            1_000_000'f32)
    sumH += ch.h + ch.marginT + ch.marginB
    maxW = max(maxW, ch.w + ch.marginL + ch.marginR)
  if n.children.len > 1:
    sumH += n.gap * float32(n.children.len - 1)
  n.contentH = if n.virtualList: max(float32(n.itemCount) * n.itemHeight, h)
               else: max(sumH + topPad(n) + bottomPad(n), h)
  var cy = y + topPad(n) - n.scrollY
  if n.virtualList: cy += float32(n.firstItem) * n.itemHeight
  for ch in n.children:
    let cw = max(1.0'f32, contentW - ch.marginL - ch.marginR)
    measure(ch, cw, 1_000_000'f32)
    arrange(ch, x + leftPad(n) + ch.marginL, cy + ch.marginT, cw, ch.h)
    cy += ch.h + ch.marginT + ch.marginB + n.gap

proc arrange(n: Node, x, y, slotW, slotH: float32) =
  var w = if slotW >= 0: slotW else: n.w
  var h = if slotH >= 0: slotH else: n.h
  if n.fixedW > 0: w = n.fixedW
  if n.fixedH > 0: h = n.fixedH
  if n.minW > 0: w = max(w, n.minW)
  if n.maxW > 0: w = min(w, n.maxW)
  if n.minH > 0: h = max(h, n.minH)
  if n.maxH > 0: h = min(h, n.maxH)
  n.x = x
  n.y = y
  n.w = w
  n.h = h
  case n.kind
  of nkText:
    n.textLayoutFor(w)
  of nkRichText, nkImage, nkCustom, nkDivider, nkButton, nkCheckbox,
     nkSwitch, nkSlider, nkProgress:
    discard
  of nkInput:
    if n.multiline:
      n.layoutInput()
  of nkScroll:
    n.arrangeScroll(x, y, w, h)
  of nkColumn, nkRow, nkButtonBase:
    n.arrangeContainer(x, y, w, h)

# --- painting and hit regions ---------------------------------------------

proc lighten(c: Color, amount: float32): Color =
  Color(r: min(c.r + amount, 1), g: min(c.g + amount, 1),
        b: min(c.b + amount, 1), a: c.a)

proc darken(c: Color, amount: float32): Color =
  Color(r: max(c.r - amount, 0), g: max(c.g - amount, 0),
        b: max(c.b - amount, 0), a: c.a)

proc caretLineCol(lines: seq[string], starts: seq[int],
                  pos: int): tuple[line, col: int] =
  if lines.len == 0:
    return (0, 0)
  result = (0, max(0, min(pos, lines[0].len)))
  for i in 0 ..< min(lines.len, starts.len):
    if starts[i] <= pos:
      result = (i, max(0, min(pos - starts[i], lines[i].len)))
    else:
      break

proc lineOffset(starts: seq[int], index: int): int =
  if starts.len == 0:
    return 0
  starts[max(0, min(index, starts.high))]

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

proc paintFocus(n: Node, c: Context, radius: float32 = 6) =
  if c.engine != nil and c.engine.focusedKey == n.key:
    var color = rgb(0.35, 0.62, 1.0)
    if n.accent.a > 0:
      color = Color(r: n.accent.r, g: n.accent.g, b: n.accent.b, a: 0.55)
    c.scene.rect(Rect(x: n.x - 3, y: n.y - 3, w: n.w + 6, h: n.h + 6),
                 color, radius)

const compositionColor = Color(r: 0.22, g: 0.47, b: 0.95)

proc paintInputLine(n: Node, c: Context, line: string, x, y: float32,
                    lineStart, markedStart, markedLen: int) =
  ## Draw one laid-out line, coloring and underlining the composition range.
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

proc paintContainerBox(n: Node, c: Context) =
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

proc paintRichText(n: Node, c: Context) =
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

proc paint(n: Node, c: Context) =
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

proc intersect(a, b: Rect): Rect =
  let x = max(a.x, b.x)
  let y = max(a.y, b.y)
  let r = min(a.x + a.w, b.x + b.w)
  let btm = min(a.y + a.h, b.y + b.h)
  if r <= x or btm <= y:
    result = Rect(x: x, y: y, w: 0, h: 0)
  else:
    result = Rect(x: x, y: y, w: r - x, h: btm - y)

proc contains(r: Rect, x, y: float32): bool =
  x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h

proc collectHits(n: Node, engine: Engine, clip: Rect, layer: int = 0) =
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
        if engine.requestFrame != nil:
          engine.requestFrame())

# --- frame and input -------------------------------------------------------

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
    if engine.requestFrame != nil:
      engine.requestFrame()
  result = c.scene

proc hitIndex(engine: Engine, x, y: float32): int =
  for i in countdown(engine.hits.len - 1, 0):
    let r = engine.hits[i].rect
    let c = engine.hits[i].clip
    if c.w <= 0 or c.h <= 0 or
        x < c.x or x >= c.x + c.w or y < c.y or y >= c.y + c.h:
      continue
    if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h:
      return i
  result = -1

proc requestFrame(engine: Engine) =
  if engine.requestFrame != nil:
    engine.requestFrame()

proc manualScrollX(engine: Engine, key: string, offset: float32) =
  engine.manuallyScrolledInput = key
  engine.inputOffsets[key] = offset

proc moveScrollbar(engine: Engine, x, y: float32) =
  let drag = engine.scrollbarDrag
  let bar = drag.scrollbar
  let position = if bar.horizontal: x else: y
  let offset = clamp((position - drag.trackStart - drag.grab) / drag.travel,
                     0'f32, 1'f32) * bar.maximum
  if bar.horizontal: engine.manualScrollX(bar.inputKey, offset)
  else: engine.scrollOffsets[bar.inputKey] = offset

proc beginScrollbarDrag(engine: Engine, hit: Hit, x, y: float32) =
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

proc caretIndexLine(text: string, x, left, fontSize: float32,
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

proc hitText(hit: Hit): string =
  if hit.displayText.len > 0: hit.displayText else: hit.text

proc caretIndex(hit: Hit, x: float32): int =
  result = caretIndexLine(hitText(hit), x,
    hit.rect.x + hit.padX - hit.scrollX, hit.fontSize, hit.family)

proc caretIndexAt(hit: Hit, x, y: float32, scrollY: float32 = 0): int =
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

proc selectWordOrLine(engine: Engine, hit: Hit, clicks: int) =
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
      requestFrame(engine)
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
  requestFrame(engine)

proc handleMouseUp*(engine: Engine, x, y: float32) =
  let i = hitIndex(engine, x, y)
  if i >= 0 and engine.pressedKey == engine.hits[i].key:
    if engine.hits[i].onClick != nil:
      engine.hits[i].onClick()
  engine.pressedKey = ""
  engine.pressedDrag = nil
  engine.scrollbarDrag = InputScrollbarDrag()
  engine.selectingInput = ""
  requestFrame(engine)

proc handleMouseMove*(engine: Engine, x, y: float32) =
  engine.lastMouseX = x
  engine.lastMouseY = y
  if engine.scrollbarDrag.travel > 0:
    engine.moveScrollbar(x, y)
    requestFrame(engine)
    return
  if engine.pressedDrag != nil:
    engine.pressedDrag(engine.pressedRect, x, y)
    requestFrame(engine)
    return
  if engine.selectingInput.len > 0:
    for hit in engine.hits:
      if hit.key == engine.selectingInput and hit.input:
        let displayCaret = caretIndexAt(
          hit, x, y, engine.scrollOffsets.getOrDefault(hit.key, 0))
        engine.caretPos = displayByteToDoc(engine, hit.key, hit.text, displayCaret)
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

proc ensureCaretVisible(engine: Engine, index: int) =
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
  engine.clearComposition()
  engine.hits[index].text = text
  engine.caretKey = hit.key
  engine.caretPos = caret
  engine.selectionAnchor = anchor
  if hit.onText != nil:
    hit.onText(text)
  engine.ensureCaretVisible(index)
  requestFrame(engine)

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
  requestFrame(engine)

proc replacementDocRange(engine: Engine, hit: Hit,
                         replacement: TextRange):
                         tuple[start, finish: int, overlaps: bool] =
  ## Resolve an AppKit range (UTF-16, in the document including composition)
  ## into document byte offsets. `overlaps` means "replace the composition".
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
      requestFrame(engine)
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
    requestFrame(engine)
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
  requestFrame(engine)

proc unmarkText*(engine: Engine) =
  engine.clearComposition()
  requestFrame(engine)

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
  let index = hitIndex(engine, x, y)
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

proc editInput(engine: Engine, index: int, key: string, modifiers: uint32) =
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
      # Unbound control shortcuts must never become literal document text.
      if key notin ["backspace", "delete", "left", "right", "home", "end", "up", "down"]:
        return

  var text = hit.text
  let beforeText = text
  var caret =
    if engine.caretKey == hit.key: max(0, min(engine.caretPos, text.len))
    else: text.len
  let sel = engine.selectionRangeFor(hit.key, text.len)
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
    requestFrame(engine)
    return
  of "enter", "\n":
    if hit.multiline:
      text = text[0 ..< sel.start] & "\n" & text[sel.finish .. ^1]
      caret = sel.start + 1
    else:
      if hit.onSubmit != nil:
        engine.clearComposition()
        hit.onSubmit()
        requestFrame(engine)
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

proc pageScroll*(engine: Engine, pages: float32)

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
      requestFrame(engine)
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
      requestFrame(engine)
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
          requestFrame(engine)
        break
    return
  engine.pendingKeys.add key
  requestFrame(engine)

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
    requestFrame(engine)

proc handleScroll*(engine: Engine, x, y, dy: float32) =
  for i in countdown(engine.scrollRegions.len - 1, 0):
    let r = engine.scrollRegions[i]
    if r.layer >= engine.topModalLayer and r.rect.contains(x, y):
      let maxOff = max(0.0'f32, r.contentH - r.viewportH)
      let old = engine.scrollOffsets.getOrDefault(r.key, 0)
      let next = max(0.0'f32, min(old + dy, maxOff))
      if next != old:
        engine.scrollOffsets[r.key] = next
        requestFrame(engine)
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
        requestFrame(engine)
      return true

proc clickKey*(engine: Engine, key: string): bool =
  ## Test/dev hook: click a control by its key in the last built frame.
  for hit in engine.hits:
    if hit.key == key:
      let x = hit.rect.x + hit.rect.w / 2
      let y = hit.rect.y + hit.rect.h / 2
      engine.handleMouseDown(x, y)
      engine.handleMouseUp(x, y)
      return true
  result = false
