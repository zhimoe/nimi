## The platform contract. Every backend implements this; core policy lives
## above it. Calls and callbacks are main-thread only.

type
  AppOptions* = object
    name*: string

  PlatformWindowOptions* = object
    title*: string
    width*, height*: int
    resizable*: bool
    html*: string
    url*: string
    secret*: string
    token*: string
    content*: bool

  SurfaceHandler* = object
    windowId*: uint64
    draw*: proc(ctx: pointer, width, height: float32) {.closure.}
    mouseDown*: proc(x, y: float32) {.closure.}
    mouseUp*: proc(x, y: float32) {.closure.}
    mouseMoved*: proc(x, y: float32) {.closure.}
    keyDown*: proc(key: string) {.closure.}

  WindowHandler* = object
    windowId*: uint64
    shouldClose*: proc(id: uint64): bool {.closure.}
    closed*: proc(id: uint64) {.closure.}
    message*: proc(id: uint64, msg: string) {.closure.}
    titleChanged*: proc(id: uint64, title: string) {.closure.}
    surface*: SurfaceHandler

  AppHandler* = object
    ready*: proc() {.closure.}
    quitRequested*: proc(): bool {.closure.}
    terminated*: proc() {.closure.}
    dispatch*: proc() {.closure.}

  PlatformMenuItemKind* = enum
    pmiNormal
    pmiSeparator
    pmiSubmenu
    pmiCheckbox

  PlatformMenuItem* = object
    label*: string
    kind*: PlatformMenuItemKind
    role*: string
    accelerator*: string
    id*: uint32
    checked*: bool
    enabled*: bool
    submenu*: seq[PlatformMenuItem]

  PlatformMenu* = object
    items*: seq[PlatformMenuItem]

  MenuHandler* = object
    select*: proc(id: uint32) {.closure.}

  Dialogs* = ref object
    open*: proc(title, defaultPath: string, multiple, directory: bool): seq[string] {.closure.}
    save*: proc(title, defaultPath: string): string {.closure.}
    message*: proc(title, text: string): int {.closure.}

  Clipboard* = ref object
    readText*: proc(): string {.closure.}
    writeText*: proc(text: string) {.closure.}
    readHTML*: proc(): string {.closure.}
    writeHTML*: proc(html: string) {.closure.}
    clear*: proc() {.closure.}

  NativeWindow* = ref object
    id*: uint64
    setTitle*: proc(title: string) {.closure.}
    show*: proc() {.closure.}
    close*: proc() {.closure.}
    loadHTML*: proc(html: string, baseURL: string) {.closure.}
    loadURL*: proc(url: string) {.closure.}
    eval*: proc(js: string) {.closure.}
    requestFrame*: proc() {.closure.}
    testClick*: proc(x, y: float32) {.closure.}
    testKey*: proc(keyCode: int) {.closure.}
    testKeyText*: proc(text: string) {.closure.}
    destroy*: proc() {.closure.}

  Backend* = ref object
    name*: string
    init*: proc(h: AppHandler, opts: AppOptions) {.closure.}
    run*: proc() {.closure.}
    quit*: proc() {.closure.}
    signal*: proc() {.closure.}
    step*: proc() {.closure.}
    wake*: proc() {.closure.}
    isMainThread*: proc(): bool {.closure.}
    newWindow*: proc(opts: PlatformWindowOptions,
                     h: WindowHandler): NativeWindow {.closure.}
    setMenu*: proc(menu: PlatformMenu, h: MenuHandler) {.closure.}
    dialogs*: Dialogs
    clipboard*: Clipboard

  BackendError* = object of CatchableError

var currentBackend*: Backend
