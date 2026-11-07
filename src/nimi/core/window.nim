## Core window model: WindowOptions, the window registry, page calls and
## bridge message routing.

import std/[json, strutils, sysrand, tables]

import ./[content, events, fileserver, ipc, ipcpool]
import ../platform/contract

type
  SessionMode* = enum
    smPersistent
    smEphemeral

  WindowOptions* = object
    title*: string
    width*, height*: int
    fixedSize*: bool
    html*: string
    url*: string
    content*: Content
    files*: FileServer
    session*: SessionMode
    ime*: bool

  CloseEvent* = object
    prevented*: bool

  Window* = ref object
    id*: uint64
    options*: WindowOptions
    native*: NativeWindow
    secret*: string
    token*: string
    closeListeners*: seq[proc(e: var CloseEvent)]
    closedListeners*: seq[proc()]
    titleListeners*: seq[proc(title: string)]
    focusListeners*: seq[proc(focused: bool)]
    frameListeners*: seq[proc(time, dt: float64)]
    animationActive*: bool
    animationFps*: int
    focused*: bool
    closed*: bool

  Page* = ref object
    window*: Window

var
  windows*: Table[uint64, Window]
  nextWindowId*: uint64 = 1
  focusedWindowId*: uint64
  allClosedHook*: proc() {.closure.}

proc randomHex(n: int): string =
  for b in urandom(n):
    result.add toHex(b, 2)

proc fireShouldClose*(w: Window): bool =
  if w.closed:
    return false
  var e = CloseEvent()
  for fn in w.closeListeners:
    fn(e)
  result = not e.prevented

proc fireClosed*(w: Window) =
  ## Idempotent. Runs callbacks once, then drops every per-window listener so
  ## late native events or animation ticks cannot reach application code.
  if w.closed:
    return
  w.closed = true
  let callbacks = w.closedListeners
  w.closedListeners.setLen(0)
  for fn in callbacks:
    fn()
  w.closeListeners.setLen(0)
  w.titleListeners.setLen(0)
  w.focusListeners.setLen(0)
  w.frameListeners.setLen(0)
  w.animationActive = false

proc isClosed*(w: Window): bool =
  w == nil or w.closed

proc completeIpcCall*(result: IpcResult) =
  ## Main thread. Resolve a page promise after a background worker finishes.
  let w = windows.getOrDefault(result.windowId)
  if w == nil or w.closed or w.native == nil or w.native.eval == nil:
    return
  if result.error.len > 0:
    w.native.eval("window.__nimi._reject(" & $result.callId & "," &
                  $(%*result.error) & ")")
    return
  try:
    let value = parseJson(result.value)
    w.native.eval("window.__nimi._resolve(" & $result.callId & "," &
                  $value & ")")
  except CatchableError:
    w.native.eval("window.__nimi._reject(" & $result.callId & "," &
                  $(%*"invalid background IPC response") & ")")

setIpcCompletion(completeIpcCall)

proc handleMessage*(w: Window, msg: string) =
  if w.closed:
    return
  try:
    if w.secret.len > 0:
      if msg.len <= w.secret.len or not msg.startsWith(w.secret):
        return
    let body =
      if w.secret.len > 0: msg[w.secret.len .. ^1] else: msg
    let node = parseJson(body)
    if w.token.len > 0 and
        (node.kind != JObject or not node.hasKey("k") or
         node["k"].getStr != w.token):
      return
    if node.kind != JObject or not node.hasKey("t"):
      return
    if node["t"].getStr != "call":
      return
    let callId = node["id"].getInt
    let target = node["method"].getStr
    let args =
      if node.hasKey("args"): node["args"] else: newJArray()
    if hasBackgroundMethod(target):
      let work = backgroundWork(target)
      if not submitIpc(w.id, int64(callId), target, $args, work):
        w.native.eval("window.__nimi._reject(" & $callId & "," &
                      $(%*"IPC queue is full or worker pool is closed") & ")")
      return
    try:
      let value = dispatch(target, args)
      w.native.eval("window.__nimi._resolve(" & $callId & "," & $value & ")")
    except CatchableError as e:
      let encoded = %*e.msg
      w.native.eval("window.__nimi._reject(" & $callId & "," & $encoded & ")")
  except CatchableError:
    # Malformed messages are ignored in M1; the secret/token checks and
    # diagnostics land with the full bridge.
    discard

proc invalidate*(w: Window) =
  if not w.closed and w.native != nil and w.native.requestFrame != nil:
    w.native.requestFrame()

proc newWindow*(opts: WindowOptions): Window =
  if currentBackend == nil:
    raise newException(BackendError, "newWindow called before App.Run")
  var o = opts
  if o.width <= 0: o.width = 800
  if o.height <= 0: o.height = 600
  if o.title.len == 0: o.title = "Nimi"
  if o.files != nil and o.url.len == 0 and o.html.len == 0:
    o.url = o.files.scheme & "://app/index.html"

  let id = nextWindowId
  inc nextWindowId
  let win = Window(id: id, options: o,
                   secret: randomHex(16), token: randomHex(8))

  var surface = SurfaceHandler(windowId: id)
  if o.content != nil:
    let content = o.content
    surface.draw = proc(ctx: pointer, width, height: float32) =
      discard drawContent(content, ctx, width, height)
    surface.mouseDown = proc(x, y: float32, clicks: int) =
      content.handleMouseDown(x, y, clicks)
    surface.mouseUp = proc(x, y: float32) = content.handleMouseUp(x, y)
    surface.mouseMoved = proc(x, y: float32) = content.handleMouseMove(x, y)
    surface.scroll = proc(x, y, dy: float32) = content.handleScroll(x, y, dy)
    surface.keyDown = proc(key: string, modifiers: uint32) =
      content.handleKeyDown(key, modifiers)
    surface.copy = proc() = content.copySelection()
    surface.cut = proc() = content.cutSelection()
    surface.paste = proc() = content.paste()
    surface.selectAll = proc() = content.selectAll()
    surface.undo = proc() = content.undo()
    surface.redo = proc() = content.redo()
    surface.insertText = proc(text: string, replacement: TextRange) =
      content.insertText(text, replacement)
    surface.setMarkedText = proc(text: string, selected, replacement: TextRange) =
      content.setMarkedText(text, selected, replacement)
    surface.unmarkText = proc() = content.unmarkText()
    surface.hasMarkedText = proc(): bool = content.hasMarkedText()
    surface.markedRange = proc(): TextRange = content.markedRange()
    surface.selectedRange = proc(): TextRange = content.selectedRange()
    surface.attributedSubstring = proc(range: TextRange): string =
      content.attributedSubstring(range)
    surface.textLength = proc(): int = content.textLength()
    surface.characterIndexAt = proc(x, y: float32): int =
      content.characterIndexAt(x, y)
    surface.caretRect = proc(): PlatformRect = content.caretRect()
    surface.command = proc(selector: string): bool = content.handleCommand(selector)

  let h = WindowHandler(
    windowId: id,
    shouldClose: proc(wid: uint64): bool =
      let w = windows.getOrDefault(wid)
      if w == nil:
        result = true
      else:
        result = w.fireShouldClose(),
    closed: proc(wid: uint64) =
      let w = windows.getOrDefault(wid)
      if w != nil:
        if focusedWindowId == wid:
          focusedWindowId = 0
        w.focused = false
        w.fireClosed()
        windows.del(wid)
        if windows.len == 0 and allClosedHook != nil:
          allClosedHook(),
    message: proc(wid: uint64, msg: string) =
      let w = windows.getOrDefault(wid)
      if w != nil:
        w.handleMessage(msg),
    titleChanged: proc(wid: uint64, title: string) =
      let w = windows.getOrDefault(wid)
      if w != nil:
        for fn in w.titleListeners:
          fn(title),
    focused: proc(wid: uint64) =
      let w = windows.getOrDefault(wid)
      if w != nil and not w.focused:
        focusedWindowId = wid
        w.focused = true
        for fn in w.focusListeners:
          fn(true),
    blurred: proc(wid: uint64) =
      let w = windows.getOrDefault(wid)
      if w != nil and w.focused:
        if focusedWindowId == wid:
          focusedWindowId = 0
        w.focused = false
        for fn in w.focusListeners:
          fn(false),
    frame: proc(wid: uint64, time, dt: float64) =
      let w = windows.getOrDefault(wid)
      if w != nil:
        for fn in w.frameListeners:
          fn(time, dt)
        w.invalidate(),
    surface: surface
  )

  let popts = PlatformWindowOptions(
    title: o.title,
    width: o.width,
    height: o.height,
    resizable: not o.fixedSize,
    html: o.html,
    url: o.url,
    secret: win.secret,
    token: win.token,
    content: o.content != nil,
    scheme: if o.files != nil: o.files.scheme else: "",
    fileRoot: if o.files != nil: o.files.root else: "",
    ephemeral: o.session == smEphemeral,
    ime: o.ime)
  win.native = currentBackend.newWindow(popts, h)
  if o.content != nil:
    let wid = win.id
    o.content.engine.requestFrame = proc() =
      let w = windows.getOrDefault(wid)
      if w != nil:
        w.invalidate()
    if currentBackend.clipboard != nil:
      o.content.engine.clipboardRead = proc(): string =
        currentBackend.clipboard.readText()
      o.content.engine.clipboardWrite = proc(text: string) =
        currentBackend.clipboard.writeText(text)
  windows[id] = win
  # AppKit may not deliver the first key-window notification when the app is
  # launched from a terminal; treat the newly created window as focused and
  # let blur/focus delegate events correct it later.
  focusedWindowId = id
  win.focused = true
  result = win

proc windowById*(id: uint64): Window =
  windows.getOrDefault(id, nil)

proc focusedWindow*(): Window =
  if focusedWindowId != 0:
    let w = windows.getOrDefault(focusedWindowId, nil)
    if w != nil:
      return w
  for w in windows.values:
    return w
  result = nil

# --- Window methods --------------------------------------------------------

proc startAnimation*(w: Window, fps: int = 60,
                     fn: proc(time, dt: float64)) =
  ## Add a main-thread frame callback, start the native frame timer, and
  ## invalidate the surface immediately. Repeating the call adds another
  ## listener; changing `fps` restarts the timer at the new rate. The callback
  ## is not tied to the WebView or to a particular renderer.
  if w.closed:
    return
  if fn != nil:
    w.frameListeners.add(fn)
  let rate = if fps > 0: fps else: 60
  let restart = w.animationActive and rate != w.animationFps
  w.animationFps = rate
  if w.native != nil:
    if restart and w.native.stopAnimation != nil:
      w.native.stopAnimation()
    if (restart or not w.animationActive) and
        w.native.startAnimation != nil:
      w.native.startAnimation(rate)
  w.animationActive = true
  w.invalidate()

proc stopAnimation*(w: Window) =
  ## Stop the native frame timer and remove all frame listeners. Safe to call
  ## when no animation is running.
  w.frameListeners.setLen(0)
  w.animationActive = false
  if w.native != nil and w.native.stopAnimation != nil:
    w.native.stopAnimation()

proc isAnimating*(w: Window): bool =
  not w.closed and w.animationActive

proc setTitle*(w: Window, title: string) =
  if w.closed:
    return
  w.options.title = title
  if w.native != nil:
    w.native.setTitle(title)

proc title*(w: Window): string =
  w.options.title

proc show*(w: Window) =
  if not w.closed and w.native != nil:
    w.native.show()

proc hide*(w: Window) =
  if not w.closed and w.native != nil and w.native.hide != nil:
    w.native.hide()

proc focus*(w: Window) =
  if w.native != nil and w.native.focus != nil:
    w.native.focus()

proc center*(w: Window) =
  if w.native != nil and w.native.center != nil:
    w.native.center()

proc minimize*(w: Window) =
  if w.native != nil and w.native.minimize != nil:
    w.native.minimize()

proc deminimize*(w: Window) =
  if w.native != nil and w.native.deminimize != nil:
    w.native.deminimize()

proc zoom*(w: Window) =
  if w.native != nil and w.native.zoom != nil:
    w.native.zoom()

proc toggleFullScreen*(w: Window) =
  if w.native != nil and w.native.toggleFullScreen != nil:
    w.native.toggleFullScreen()

proc isFullScreen*(w: Window): bool =
  if not w.closed and w.native != nil and w.native.isFullScreen != nil:
    result = w.native.isFullScreen()

proc isFocused*(w: Window): bool =
  if not w.closed and w.native != nil and w.native.isFocused != nil:
    result = w.native.isFocused()

proc setSize*(w: Window, width, height: int) =
  if w.native != nil and w.native.setSize != nil:
    w.native.setSize(width, height)

proc setPosition*(w: Window, x, y: int) =
  if w.native != nil and w.native.setPosition != nil:
    w.native.setPosition(x, y)

proc setResizable*(w: Window, resizable: bool) =
  if w.native != nil and w.native.setResizable != nil:
    w.native.setResizable(resizable)

proc setAlwaysOnTop*(w: Window, always: bool) =
  if w.native != nil and w.native.setAlwaysOnTop != nil:
    w.native.setAlwaysOnTop(always)

proc close*(w: Window) =
  if not w.closed and w.native != nil:
    w.native.close()

proc destroy*(w: Window) =
  if w.closed:
    return
  if w.native != nil:
    w.native.destroy()
  w.fireClosed()
  windows.del(w.id)

proc eval*(w: Window, js: string) =
  if not w.closed and w.native != nil:
    w.native.eval(js)

proc loadHTML*(w: Window, html: string, baseURL: string = "") =
  if not w.closed and w.native != nil:
    w.native.loadHTML(html, baseURL)

proc loadURL*(w: Window, url: string) =
  if not w.closed and w.native != nil:
    w.native.loadURL(url)

proc page*(w: Window): Page =
  Page(window: w)

proc onClose*(w: Window, fn: proc(e: var CloseEvent)) =
  if not w.closed:
    w.closeListeners.add fn

proc onClosed*(w: Window, fn: proc()) =
  if w.closed:
    fn()
  else:
    w.closedListeners.add fn

proc onTitleChanged*(w: Window, fn: proc(title: string)) =
  if not w.closed:
    w.titleListeners.add fn

proc onFocusChanged*(w: Window, fn: proc(focused: bool)) =
  if not w.closed:
    w.focusListeners.add fn

proc emitPage*(w: Window, name: string, payload: JsonNode) =
  ## Send a typed event to the page. `window.nimi.on(name, fn)` receives it.
  if not w.closed and w.native != nil:
    let encodedName = %*name
    w.native.eval("window.__nimi._event(" & $encodedName & "," & $payload & ")")

proc emitPage*[T](e: Event[T], w: Window, payload: T) =
  w.emitPage(e.name, e.encode(payload))

# --- Page methods ----------------------------------------------------------

proc loadURL*(p: Page, url: string) =
  p.window.loadURL(url)

proc loadHTML*(p: Page, html: string, baseURL: string = "") =
  p.window.loadHTML(html, baseURL)

proc eval*(p: Page, js: string) =
  p.window.eval(js)

proc reload*(p: Page) =
  p.window.eval("location.reload()")

proc url*(p: Page): string =
  p.window.options.url
