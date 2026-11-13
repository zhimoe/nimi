## A window's native content: a view function over the M2 Context.

import ../scene/scene
import ../ui/context
import ../platform/contract

export scene

type
  SceneRenderer* = proc(ctx: pointer, scene: Scene) {.closure.}

  Content* = ref object
    view*: proc(c: Context) {.closure.}
    engine*: Engine
    renderer*: SceneRenderer

var defaultContentRenderer*: SceneRenderer
  ## Composition-root hook. The platform bootstrap installs the default
  ## renderer (CoreGraphics on macOS); apps may override it per Content or
  ## globally to use a different backend.

proc uiView*(view: proc(c: Context)): Content =
  Content(view: view, engine: Engine())

proc renderContent*(content: Content, width, height: float32): Scene =
  result = content.engine.render(content.view, width, height)

proc drawContent*(content: Content, ctx: pointer, width,
                  height: float32): bool =
  ## Render the content scene through the per-content renderer or the
  ## composition-root default. Returns false when no renderer is installed.
  let renderer =
    if content.renderer != nil: content.renderer
    else: defaultContentRenderer
  if renderer == nil:
    return false
  renderer(ctx, content.engine.render(content.view, width, height))
  result = true

proc handleMouseDown*(content: Content, x, y: float32, clicks: int = 1) =
  content.engine.handleMouseDown(x, y, clicks)

proc handleMouseUp*(content: Content, x, y: float32) =
  content.engine.handleMouseUp(x, y)

proc cancelInput*(content: Content, composition: bool = true) =
  content.engine.cancelInput(composition)

proc handleMouseMove*(content: Content, x, y: float32) =
  content.engine.handleMouseMove(x, y)

proc handleScroll*(content: Content, x, y, dy: float32) =
  content.engine.handleScroll(x, y, dy)

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

proc undo*(content: Content) =
  content.engine.undo()

proc redo*(content: Content) =
  content.engine.redo()

proc insertText*(content: Content, text: string,
                 replacement: TextRange = NoTextRange) =
  content.engine.insertText(text, replacement)

proc setMarkedText*(content: Content, text: string,
                    selected: TextRange = NoTextRange,
                    replacement: TextRange = NoTextRange) =
  content.engine.setMarkedText(text, selected, replacement)

proc unmarkText*(content: Content) =
  content.engine.unmarkText()

proc hasMarkedText*(content: Content): bool =
  content.engine.hasMarkedText()

proc textInputActive*(content: Content): bool =
  content.engine.textInputActive()

proc markedRange*(content: Content): TextRange =
  content.engine.markedRange()

proc selectedRange*(content: Content): TextRange =
  content.engine.selectedRange()

proc attributedSubstring*(content: Content, range: TextRange): string =
  content.engine.attributedSubstring(range)

proc textLength*(content: Content): int =
  content.engine.textLength()

proc characterIndexAt*(content: Content, x, y: float32): int =
  content.engine.characterIndexAt(x, y)

proc caretRect*(content: Content): PlatformRect =
  let r = content.engine.caretRect()
  PlatformRect(x: r.x, y: r.y, w: r.w, h: r.h)

proc handleCommand*(content: Content, selector: string): bool =
  case selector
  of "moveLeft:", "moveBackward:": content.engine.handleKeyDown("left"); true
  of "moveRight:", "moveForward:": content.engine.handleKeyDown("right"); true
  of "moveUp:": content.engine.handleKeyDown("up"); true
  of "moveDown:": content.engine.handleKeyDown("down"); true
  of "moveLeftAndModifySelection:": content.engine.handleKeyDown("left", KeyShift); true
  of "moveRightAndModifySelection:": content.engine.handleKeyDown("right", KeyShift); true
  of "moveUpAndModifySelection:": content.engine.handleKeyDown("up", KeyShift); true
  of "moveDownAndModifySelection:": content.engine.handleKeyDown("down", KeyShift); true
  of "moveToBeginningOfLine:", "moveToBeginningOfDocument:",
     "scrollToBeginningOfDocument:": content.engine.handleKeyDown("home"); true
  of "moveToEndOfLine:", "moveToEndOfDocument:",
     "scrollToEndOfDocument:": content.engine.handleKeyDown("end"); true
  of "deleteBackward:", "deleteWordBackward:": content.engine.handleKeyDown("backspace"); true
  of "deleteForward:", "deleteWordForward:": content.engine.handleKeyDown("delete"); true
  of "insertNewline:", "insertParagraphSeparator:": content.engine.handleKeyDown("enter"); true
  of "pageUp:", "scrollPageUp:": content.engine.handleKeyDown("pageup"); true
  of "pageDown:", "scrollPageDown:": content.engine.handleKeyDown("pagedown"); true
  of "insertTab:", "insertBacktab:": content.engine.handleKeyDown("tab"); true
  of "cancelOperation:", "complete:": content.engine.handleKeyDown("escape"); true
  of "selectAll:": content.engine.selectAll(); true
  of "copy:": content.engine.copySelection(); true
  of "cut:": content.engine.cutSelection(); true
  of "paste:": content.engine.paste(); true
  of "undo:": content.engine.undo(); true
  of "redo:": content.engine.redo(); true
  else: false
