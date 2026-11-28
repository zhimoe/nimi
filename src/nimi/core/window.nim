## Core window model: WindowOptions, geometry persistence, bridge routing,
## native context menus, and thread-safe host -> page event/stream delivery.

import std/[json, os, strutils, sysrand, tables]

import ./[content, events, fileserver, ipc, ipcpool, loop, menu, pageevents, paths]
import ../platform/contract

type
  SessionMode* = enum
    smPersistent
    smEphemeral

  SavedWindowState* = object
    width*, height*: int
    x*, y*: int
    hasPosition*: bool
    maximized*: bool

  WindowOptions* = object
    title*: string
    width*, height*: int
    fixedSize*: bool
    html*: string
    url*: string
    content*: Content
    files*: FileServer
    session*: SessionMode
    userDataDir*: string
    autosaveName*: string
    ime*: bool
    consumeActivationClick*: bool
    onJsError*: proc(message: string) {.closure.}

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
    jsErrorListeners*: seq[proc(message: string)]
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
  windowStateSlug*: string = "nimi"

proc randomHex(n: int): string =
  for b in urandom(n):
    result.add toHex(b, 2)

# --- Window state persistence ----------------------------------------------

proc windowStatePath*(autosaveName: string, slug: string = ""): string =
  let cleanApp = sanitizeSlug(if slug.len > 0: slug else: windowStateSlug)
  let cleanWin = sanitizeSlug(autosaveName)
  appDataDir(cleanApp) / ("window-" & cleanWin & ".json")

proc loadSavedWindowState*(autosaveName: string,
                           slug: string = ""): tuple[found: bool, state: SavedWindowState] =
  if autosaveName.len == 0:
    return (false, SavedWindowState())
  let path = windowStatePath(autosaveName, slug)
  if not fileExists(path):
    return (false, SavedWindowState())
  try:
    let node = parseFile(path)
    if node.kind != JObject:
      return (false, SavedWindowState())
    let w = node{"width"}.getInt(0)
    let h = node{"height"}.getInt(0)
    if w <= 0 or h <= 0:
      return (false, SavedWindowState())
    result.found = true
    result.state = SavedWindowState(
      width: max(200, w),
      height: max(150, h),
      x: node{"x"}.getInt(0),
      y: node{"y"}.getInt(0),
      hasPosition: node.hasKey("x") and node.hasKey("y"),
      maximized: node{"maximized"}.getBool(false))
  except CatchableError:
    return (false, SavedWindowState())

proc saveWindowState*(autosaveName: string, state: SavedWindowState,
                      slug: string = "") =
  if autosaveName.len == 0 or state.width <= 0 or state.height <= 0:
    return
  var node = %*{
    "width": state.width,
    "height": state.height,
    "maximized": state.maximized,
  }
  if state.hasPosition:
    node["x"] = %state.x
    node["y"] = %state.y
  try:
    atomicWriteJson(windowStatePath(autosaveName, slug), node)
  except CatchableError:
    discard

proc clampToDisplays(x, y, w, h: int): tuple[ok: bool, x, y: int] =
  if currentBackend == nil or currentBackend.screens == nil:
    return (true, x, y)
  try:
    let list = currentBackend.screens()
    if list.len == 0:
      return (true, x, y)
    for d in list:
      let dw = if d.workWidth > 0: d.workWidth else: d.width
      let dh = if d.workHeight > 0: d.workHeight else: d.height
      let dx = if d.workWidth > 0: d.workX else: d.x
      let dy = if d.workHeight > 0: d.workY else: d.y
      # Accept if at least a 80x40 header strip of the window intersects a display.
      let overlapX = min(float32(x + w), dx + dw) - max(float32(x), dx)
      let overlapY = min(float32(y + 60), dy + dh) - max(float32(y), dy)
      if overlapX >= 80 and overlapY >= 24:
        return (true, x, y)
  except CatchableError:
    return (true, x, y)
  (false, 0, 0)

# --- Lifecycle & IPC completion --------------------------------------------

proc fireShouldClose*(w: Window): bool =
  if w.closed:
    return false
  var e = CloseEvent()
  for fn in w.closeListeners:
    fn(e)
  result = not e.prevented

proc captureAndSaveGeometry(w: Window) =
  if w == nil or w.closed or w.options.autosaveName.len == 0 or w.native == nil:
    return
  var width, height, x, y: int
  var maximized = false
  try:
    if w.native.isMaximized != nil:
      maximized = w.native.isMaximized()
    if w.native.getSize != nil:
      w.native.getSize(width, height)
    var hasPos = false
    if w.native.getPosition != nil:
      w.native.getPosition(x, y)
      hasPos = true
    if width > 0 and height > 0:
      saveWindowState(w.options.autosaveName, SavedWindowState(
        width: width, height: height, x: x, y: y,
        hasPosition: hasPos, maximized: maximized))
  except CatchableError:
    discard

proc fireClosed*(w: Window) =
  ## Idempotent. Runs callbacks once, then drops every per-window listener so
  ## late native events or animation ticks cannot reach application code.
  if w.closed:
    return
  w.closed = true
  cancelIpcWindow(w.id)
  let callbacks = w.closedListeners
  w.closedListeners.setLen(0)
  for fn in callbacks:
    fn()
  w.closeListeners.setLen(0)
  w.titleListeners.setLen(0)
  w.focusListeners.setLen(0)
  w.jsErrorListeners.setLen(0)
  w.frameListeners.setLen(0)
  w.animationActive = false

proc isClosed*(w: Window): bool =
  w == nil or w.closed

proc deliverEventToWindow(w: Window, name, payloadJson: string) =
  if w == nil or w.closed or w.native == nil or w.native.eval == nil:
    return
  let body = if payloadJson.len > 0: payloadJson else: "null"
  w.native.eval("window.__nimi._event(" & $(%*name) & "," & body & ")")

proc deliverPageEventMain(windowId: uint64, name, payloadJson: string) =
  if windowId == 0:
    for w in windows.values:
      deliverEventToWindow(w, name, payloadJson)
  else:
    let w = windows.getOrDefault(windowId)
    deliverEventToWindow(w, name, payloadJson)

proc deliverStreamChunkMain(windowId: uint64, callId: int64, chunkJson: string) =
  let w = windows.getOrDefault(windowId)
  if w == nil or w.closed or w.native == nil or w.native.eval == nil:
    return
  let body = if chunkJson.len > 0: chunkJson else: "null"
  w.native.eval("window.__nimi._chunk(" & $callId & "," & body & ")")

setPageDeliveryHooks(deliverPageEventMain, deliverStreamChunkMain)

proc completeIpcCall*(result: IpcResult) =
  ## Main thread. Flush any pending stream chunks first so chunks always arrive
  ## before `_resolve` / `_reject`.
  drainPageEvents()
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
    let kind = node["t"].getStr
    case kind
    of "cancel":
      if node.hasKey("id"):
        discard cancelIpcCall(w.id, int64(node["id"].getInt))
      return
    of "jserror":
      let errMsg = node{"message"}.getStr("")
      if errMsg.len > 0:
        for fn in w.jsErrorListeners:
          fn(errMsg)
      return
    of "call":
      discard
    else:
      return

    let callId = node["id"].getInt
    let target = node["method"].getStr
    let args =
      if node.hasKey("args"): node["args"] else: newJArray()
    if hasBackgroundMethod(target):
      let work = backgroundWork(target)
      if not submitIpc(w.id, int64(callId), target, $args, work,
                       backgroundTimeout(target)):
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
    discard

proc invalidate*(w: Window) =
  if not w.closed and w.native != nil and w.native.requestFrame != nil:
    w.native.requestFrame()

proc newWindow*(opts: WindowOptions): Window =
  if currentBackend == nil:
    raise newException(BackendError, "newWindow called before App.Run")
  var o = opts
  let (hasSaved, saved) = loadSavedWindowState(o.autosaveName)
  if hasSaved and not o.fixedSize:
    o.width = saved.width
    o.height = saved.height
  if o.width <= 0: o.width = 800
  if o.height <= 0: o.height = 600
  if o.title.len == 0: o.title = "Nimi"
  if o.files != nil and o.url.len == 0 and o.html.len == 0:
    o.url = o.files.scheme & "://app/index.html"

  let id = nextWindowId
  inc nextWindowId
  let win = Window(id: id, options: o,
                   secret: randomHex(16), token: randomHex(8))
  if o.onJsError != nil:
    win.jsErrorListeners.add o.onJsError

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
    surface.scrollHorizontal = proc(x, y, dx: float32): bool =
      content.handleHorizontalScroll(x, y, dx)
    surface.keyDown = proc(key: string, modifiers: uint32) =
      content.handleKeyDown(key, modifiers)
    surface.copy = proc() = content.copySelection()
    surface.cut = proc() = content.cutSelection()
    surface.paste = proc() = content.paste()
    surface.selectAll = proc() = content.selectAll()
    surface.cancelInput = proc(composition: bool) = content.cancelInput(composition)
    surface.undo = proc() = content.undo()
    surface.redo = proc() = content.redo()
    surface.insertText = proc(text: string, replacement: TextRange) =
      content.insertText(text, replacement)
    surface.setMarkedText = proc(text: string, selected, replacement: TextRange) =
      content.setMarkedText(text, selected, replacement)
    surface.unmarkText = proc() = content.unmarkText()
    surface.hasMarkedText = proc(): bool = content.hasMarkedText()
    surface.textInputActive = proc(): bool = content.textInputActive()
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
        result = w.fireShouldClose()
        if result:
          w.captureAndSaveGeometry(),
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
        let count = w.frameListeners.len
        for i in 0 ..< count:
          if i < w.frameListeners.len:
            w.frameListeners[i](time, dt)
        w.invalidate(),
    surface: surface
  )

  var schemeCallback: PlatformSchemeHandler = nil
  if o.files != nil:
    let fs = o.files
    schemeCallback = proc(path: string): PlatformResource {.gcsafe.} =
      let r = fs.serve(path)
      PlatformResource(status: r.status, mime: r.mime, data: r.data)

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
    serveScheme: schemeCallback,
    userDataDir: o.userDataDir,
    ephemeral: o.session == smEphemeral,
    ime: o.ime,
    consumeActivationClick: o.consumeActivationClick)
  win.native = currentBackend.newWindow(popts, h)
  if hasSaved:
    if saved.hasPosition and win.native != nil and win.native.setPosition != nil:
      let clamped = clampToDisplays(saved.x, saved.y, o.width, o.height)
      if clamped.ok:
        try: win.native.setPosition(clamped.x, clamped.y)
        except CatchableError: discard
    if saved.maximized and not o.fixedSize and win.native != nil and win.native.zoom != nil:
      try: win.native.zoom()
      except CatchableError: discard
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

proc isVisible*(w: Window): bool =
  not w.isClosed() and w.native != nil and w.native.isVisible != nil and w.native.isVisible()

proc isMinimized*(w: Window): bool =
  not w.isClosed() and w.native != nil and w.native.isMinimized != nil and w.native.isMinimized()

proc isMaximized*(w: Window): bool =
  not w.isClosed() and w.native != nil and w.native.isMaximized != nil and w.native.isMaximized()

proc setSize*(w: Window, width, height: int) =
  if w.native != nil and w.native.setSize != nil:
    w.native.setSize(width, height)

proc setPosition*(w: Window, x, y: int) =
  if w.native != nil and w.native.setPosition != nil:
    w.native.setPosition(x, y)

proc setResizable*(w: Window, resizable: bool) =
  if w.native != nil and w.native.setResizable != nil:
    w.native.setResizable(resizable)

proc getSize*(w: Window): tuple[width, height: int] =
  if not w.closed and w.native != nil and w.native.getSize != nil:
    w.native.getSize(result.width, result.height)

proc getPosition*(w: Window): tuple[x, y: int] =
  if not w.closed and w.native != nil and w.native.getPosition != nil:
    w.native.getPosition(result.x, result.y)

proc setDarkAppearance*(w: Window, dark: bool) =
  if not w.closed and w.native != nil and w.native.setAppearance != nil:
    w.native.setAppearance(dark)

proc setAlwaysOnTop*(w: Window, always: bool) =
  if w.native != nil and w.native.setAlwaysOnTop != nil:
    w.native.setAlwaysOnTop(always)

proc popupMenu*(w: Window, m: Menu, x: int = -1, y: int = -1) =
  ## Open a native context menu anchored at `(x, y)` in logical client coordinates
  ## (or at the current pointer position when `x < 0` or `y < 0`).
  if w == nil or w.closed or m == nil or w.native == nil or w.native.popupMenu == nil:
    return
  let (pm, handler) = toPlatformMenu(m)
  w.native.popupMenu(pm, handler, x, y)

proc close*(w: Window) =
  if not w.closed and w.native != nil:
    w.captureAndSaveGeometry()
    w.native.close()

proc destroy*(w: Window) =
  if w.closed:
    return
  w.captureAndSaveGeometry()
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

proc onJsError*(w: Window, fn: proc(message: string)) =
  if not w.closed:
    w.jsErrorListeners.add fn

proc emitPage*(w: Window, name: string, payload: JsonNode) =
  ## Send a typed event to the page on the UI thread (`window.nimi.on(name, fn)`).
  if isMainThread():
    if w != nil:
      deliverEventToWindow(w, name, $payload)
  else:
    if w != nil:
      queuePageEvent(w.id, name, $payload)

proc emitPage*[T](e: Event[T], w: Window, payload: T) =
  w.emitPage(e.name, e.encode(payload))

proc emitWindow*(windowId: uint64, name: string, payloadJson: string = "{}") {.gcsafe.} =
  ## Thread-safe event delivery to one window (`windowId`) from ANY thread.
  {.cast(gcsafe).}:
    if isMainThread():
      deliverPageEventMain(windowId, name, payloadJson)
      return
  queuePageEvent(windowId, name, payloadJson)

proc broadcastPage*(name: string, payloadJson: string = "{}") {.gcsafe.} =
  ## Thread-safe event broadcast to all open windows from ANY thread.
  {.cast(gcsafe).}:
    if isMainThread():
      deliverPageEventMain(0, name, payloadJson)
      return
  queuePageEvent(0, name, payloadJson)

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
