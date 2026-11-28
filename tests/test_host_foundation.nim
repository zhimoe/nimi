## Comprehensive regression suite for down-sunk Knit host capabilities and
## Nimi architectural fixes (ARC/atomicArc SharedQueue IPC stress, loop lock
## initialization, streaming IPC chunks, thread-safe page events, typed
## bindBackground + rich TS schema generation, VFS FileServer, paths/portable,
## shell URL safety, redacted rotating logger, watch filters, window autosave,
## popup menus, and capability probes).

import std/[json, monotimes, options, os, strutils, tables, times, unittest]

import nimi
import nimi/[log, paths, shell]
import nimi/platform/[contract, unsupported]

type
  RepoState* = enum
    rsClean
    rsDirty
    rsConflicted

  DiffSummary* = object
    repoId*: string
    filesChanged*: int
    state*: RepoState
    branch*: Option[string]
    paths*: seq[string]

proc summarizeRepo(repoId: string, paths: seq[string],
                   ctx: IpcCallContext): DiffSummary {.gcsafe.} =
  discard ctx.sendChunk($(%*{"step": "scanning", "count": paths.len}))
  ctx.emit("repo:progress", $(%*{"repoId": repoId}))
  DiffSummary(
    repoId: repoId,
    filesChanged: paths.len,
    state: (if paths.len > 0: rsDirty else: rsClean),
    branch: some("main"),
    paths: paths)

proc stressEcho(payload: string, ctx: IpcCallContext): string {.gcsafe.} =
  if ctx.isCancelled():
    return ""
  result = payload & ":" & $payload.len

proc cancellableSpin(tag: string, ctx: IpcCallContext): string {.gcsafe.} =
  while not ctx.isCancelled():
    sleep(2)
  "cancelled:" & tag

bindBackground("TypedBg", summarizeRepo, stressEcho, cancellableSpin)

suite "atomicArc background IPC stress & cancellation":
  test "drainMain is safe immediately after shutdownLoop without postMain":
    shutdownLoop()
    drainMain()
    var ran = false
    check postMain(proc() = ran = true)
    drainMain()
    check ran

  test "600 concurrent background calls under atomicArc without heap corruption":
    startIpcPool(workers = 6, maxInflight = 1024)
    setIpcCompletion(completeIpcCall)
    var resolved = 0
    let w = Window(id: 901, secret: "", token: "",
      native: NativeWindow(eval: proc(js: string) =
        if "_resolve(" in js:
          inc resolved))
    windows[901'u64] = w
    defer:
      windows.del(901'u64)
      shutdownIpcPool()

    const totalCalls = 600
    for i in 1 .. totalCalls:
      let text = "payload-" & $i & "-" & repeat('x', (i mod 37) * 19)
      let msg = $(%*{"t": "call", "id": i, "method": "TypedBg.stressEcho", "args": [text]})
      w.handleMessage(msg)

    let deadline = getMonoTime() + initDuration(seconds = 10)
    while resolved < totalCalls and getMonoTime() < deadline:
      drainIpcPool()
      drainPageEvents()
      sleep(1)
    check resolved == totalCalls

  test "typed bindBackground streams chunks, emits events, and decodes/encodes objects":
    startIpcPool(workers = 2, maxInflight = 32)
    setIpcCompletion(completeIpcCall)
    var frames: seq[string]
    let w = Window(id: 902, secret: "", token: "",
      native: NativeWindow(eval: proc(js: string) = frames.add js))
    windows[902'u64] = w
    defer:
      windows.del(902'u64)
      shutdownIpcPool()

    let msg = $(%*{"t": "call", "id": 42, "method": "TypedBg.summarizeRepo",
                   "args": ["repo-1", ["a.nim", "b.nim"]]})
    w.handleMessage(msg)
    let deadline = getMonoTime() + initDuration(seconds = 5)
    var gotResolve = false
    while not gotResolve and getMonoTime() < deadline:
      drainIpcPool()
      drainPageEvents()
      for f in frames:
        if "_resolve(42," in f:
          gotResolve = true
      if not gotResolve:
        sleep(1)
    check gotResolve
    var chunkIdx = -1
    var eventIdx = -1
    var resolveIdx = -1
    for idx, f in frames:
      if "_chunk(42," in f: chunkIdx = idx
      if "_event(\"repo:progress\"" in f: eventIdx = idx
      if "_resolve(42," in f: resolveIdx = idx
    check chunkIdx >= 0
    check eventIdx >= 0
    check resolveIdx > chunkIdx
    check "\"filesChanged\":2" in frames[resolveIdx]
    check "\"rsDirty\"" in frames[resolveIdx]

  test "page cancel message aborts a single in-flight background call":
    startIpcPool(workers = 2, maxInflight = 16)
    setIpcCompletion(completeIpcCall)
    var frames: seq[string]
    let w = Window(id: 903, secret: "", token: "",
      native: NativeWindow(eval: proc(js: string) = frames.add js))
    windows[903'u64] = w
    defer:
      windows.del(903'u64)
      shutdownIpcPool()

    w.handleMessage($(%*{"t": "call", "id": 77, "method": "TypedBg.cancellableSpin", "args": ["job"]}))
    sleep(15)
    w.handleMessage($(%*{"t": "cancel", "id": 77}))
    check frames.len == 1
    check "_reject(77," in frames[0]
    check "cancelled" in frames[0]

  test "rich TypeScript schema generation emits interfaces, enums, arrays, and nullable options":
    let ts = generateTypeScript()
    check "export type RepoState = \"rsClean\" | \"rsDirty\" | \"rsConflicted\";" in ts
    check "export interface DiffSummary {" in ts
    check "repoId: string;" in ts
    check "filesChanged: number;" in ts
    check "branch?: string | null;" in ts
    check "paths: string[];" in ts
    check "summarizeRepo(repoId: string, paths: string[]): Promise<DiffSummary>" in ts

suite "VFS FileServer, multi-mount, and SPA fallback":
  test "in-memory VFS, dynamic disk/memory mounts, and SPA fallback":
    let blobsDir = getTempDir() / ("nimi_vfs_blobs_" & $getCurrentProcessId())
    removeDir(blobsDir)
    createDir(blobsDir)
    defer: removeDir(blobsDir)
    writeFile(blobsDir / "chunk-1.json", "{\"chunk\":1}")

    let fs = newMemoryFileServer([
      ("index.html", "<!doctype html><title>VFS</title>"),
      ("styles/app.css", "body{margin:0}"),
    ], scheme = "nimi", spaFallback = true)
    fs.mount("/blobs", blobsDir)
    fs.mountMemory("/static", [("logo.svg", "<svg/>")])

    check fs.serve("/").status == 200
    check fs.serve("/").data == "<!doctype html><title>VFS</title>"
    check fs.serve("/styles/app.css").mime == "text/css"
    check fs.serve("/blobs/chunk-1.json").data == "{\"chunk\":1}"
    check fs.serve("/static/logo.svg").mime == "image/svg+xml"
    # SPA fallback serves index.html for extensionless routes, 404 for missing assets.
    check fs.serve("/repos/knit/commits").status == 200
    check fs.serve("/repos/knit/commits").data == "<!doctype html><title>VFS</title>"
    check fs.serve("/missing.js").status == 404
    check fs.serve("/../etc/passwd").status == 404

    # compile-time embedAssets macro test against examples/hello
    const embedded = embedAssets("../examples/hello")
    check embedded.len > 0

suite "paths, atomic writes, shell safety, logger redaction, watch, window autosave & popup":
  test "atomicWriteFile, window autosave round-trip, and logger secret/path redaction":
    let tmpData = getTempDir() / ("nimi_host_data_" & $getCurrentProcessId())
    removeDir(tmpData)
    createDir(tmpData)
    putEnv("NIMI_DATA_DIR", tmpData)
    defer:
      putEnv("NIMI_DATA_DIR", "")
      removeDir(tmpData)

    check appDataDir("knit") == tmpData
    let cfgFile = tmpData / "settings.json"
    atomicWriteJson(cfgFile, %*{"ok": true})
    check parseFile(cfgFile)["ok"].getBool() == true

    # Logger redaction & rotation
    configureLogger(LoggerConfig(
      slug: "knit",
      fileName: "knit.log",
      level: llDebug,
      maxBytes: 256,
      maxFiles: 3,
      redactSecrets: true,
      redactHome: true))
    logInfo("git", "pushing /secret/workspace/repo with token ghp_1234567890abcdef and sk-proj9999",
            ["/secret/workspace/repo"])
    let written = readFile(currentLogPath())
    check "/secret/workspace/repo" notin written
    check "path#" in written
    check "ghp_[REDACTED]" in written
    check "sk-[REDACTED]" in written
    for i in 0 ..< 10:
      logInfo("rot", repeat('a', 80))
    check fileExists(currentLogPath() & ".1")

    let crashPath = writeCrashLog("unit_test", "simulated crash Bearer secretToken123", "knit")
    check fileExists(crashPath)
    check "Bearer [REDACTED]" in readFile(crashPath)

    # Window autosave + popupMenu + capabilities
    let oldBackend = currentBackend
    defer: currentBackend = oldBackend
    var poppedItems = 0
    currentBackend = newUnsupportedBackend("mock")
    currentBackend.capabilities = proc(): set[PlatformCapability] =
      {pcWebView, pcPopupMenu}
    currentBackend.screens = proc(): seq[PlatformDisplay] =
      @[PlatformDisplay(x: 0, y: 0, width: 1920, height: 1080,
                        workX: 0, workY: 0, workWidth: 1920, workHeight: 1040,
                        scale: 2.0, primary: true)]
    currentBackend.newWindow = proc(opts: PlatformWindowOptions,
                                    h: WindowHandler): NativeWindow =
      let nw = newUnsupportedNativeWindow("mock")
      nw.id = h.windowId
      var cw = opts.width
      var ch = opts.height
      var cx = 120
      var cy = 80
      nw.getSize = proc(w, h: var int) = (w = cw; h = ch)
      nw.setSize = proc(w, h: int) = (cw = w; ch = h)
      nw.getPosition = proc(x, y: var int) = (x = cx; y = cy)
      nw.setPosition = proc(x, y: int) = (cx = x; cy = y)
      nw.isMaximized = proc(): bool = false
      nw.close = proc() =
        if h.shouldClose == nil or h.shouldClose(h.windowId):
          if h.closed != nil: h.closed(h.windowId)
      nw.popupMenu = proc(pm: PlatformMenu, mh: MenuHandler, x, y: int) =
        poppedItems = pm.items.len
        if pm.items.len > 0 and mh.select != nil:
          mh.select(pm.items[0].id)
      nw

    check app.supports(pcPopupMenu)
    check not app.supports(pcLoginItem)

    let w1 = newWindow(WindowOptions(title: "Autosave", width: 900, height: 600,
                                     autosaveName: "main-workbench"))
    w1.setSize(1420, 860)
    var menuPicked = false
    w1.popupMenu(newMenu(@[
      menuItem("Stage File", proc() = menuPicked = true),
      separator(),
      menuItem("Discard"),
    ]), 40, 50)
    check poppedItems == 3
    check menuPicked
    w1.close()

    let w2 = newWindow(WindowOptions(title: "Autosave", width: 800, height: 500,
                                     autosaveName: "main-workbench"))
    check w2.getSize() == (width: 1420, height: 860)
    w2.fireClosed()
    windows.del(w2.id)

  test "shell external URL allowlist and watch noise filtering":
    check isSafeExternalUrl("https://nimi.zhi.moe/docs?x=1")
    check isSafeExternalUrl("mailto:dev@nimi.zhi.moe")
    check not isSafeExternalUrl("javascript:alert(1)")
    check not isSafeExternalUrl("file:///etc/passwd")
    check not isSafeExternalUrl("cmd://calc.exe")
    check not isSafeExternalUrl("https://evil.com\ncalc")

    let wopts = defaultWatchOptions(minIntervalMs = 50, extraIgnores = [".git/knit/"])
    check shouldIgnoreWatchPath("/repo/.git/objects/aa/bb", wopts)
    check shouldIgnoreWatchPath("/repo/node_modules/pkg/index.js", wopts)
    check shouldIgnoreWatchPath("/repo/.git/knit/session/1", wopts)
    check not shouldIgnoreWatchPath("/repo/src/main.nim", wopts)
