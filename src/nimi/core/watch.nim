## File/directory watching with built-in noise-path ignore filters and
## per-path debounce coalescing.

import std/[monotimes, strutils, tables, times]

import ./../platform/contract

type
  FileEventKind* = enum
    feCreated, feModified, feRemoved, feRenamed

  FileEvent* = object
    path*: string
    kind*: FileEventKind

  WatchOptions* = object
    ignoreSubstrings*: seq[string]
    ignoreDefaults*: bool
    minIntervalMs*: int

  FileWatcher* = ref object
    native*: NativeFileWatcher

const DefaultWatchIgnores* = [
  ".git/objects/",
  ".git/logs/",
  "/node_modules/",
  "/.venv/",
  "/target/",
  "/vendor/",
  "/dist/",
  "/build/",
  "/nimcache/",
  "/.DS_Store",
]

proc defaultWatchOptions*(minIntervalMs: int = 0,
                          extraIgnores: openArray[string] = []): WatchOptions =
  result = WatchOptions(
    ignoreSubstrings: @extraIgnores,
    ignoreDefaults: true,
    minIntervalMs: minIntervalMs)

proc shouldIgnoreWatchPath*(rawPath: string, opts: WatchOptions): bool =
  let p = rawPath.replace('\\', '/')
  if opts.ignoreDefaults:
    for pat in DefaultWatchIgnores:
      if pat in p or p.endsWith(pat.strip(chars = {'/'})):
        return true
  for pat in opts.ignoreSubstrings:
    if pat.len > 0:
      let norm = pat.replace('\\', '/')
      if norm in p:
        return true
  false

proc watch*(path: string, opts: WatchOptions,
            fn: proc(e: FileEvent)): FileWatcher =
  if currentBackend == nil or currentBackend.watchFiles == nil:
    return nil
  var lastSeen = initTable[string, MonoTime]()
  let minDur = initDuration(milliseconds = max(0, opts.minIntervalMs))
  let native = currentBackend.watchFiles(path, proc(e: PlatformFileEvent) =
    if shouldIgnoreWatchPath(e.path, opts):
      return
    let normPath = e.path.replace('\\', '/')
    if opts.minIntervalMs > 0:
      let now = getMonoTime()
      if lastSeen.hasKey(normPath) and (now - lastSeen[normPath]) < minDur:
        return
      if lastSeen.len > 4096:
        lastSeen.clear()
      lastSeen[normPath] = now
    let kind =
      case e.kind
      of pfeCreated: feCreated
      of pfeModified: feModified
      of pfeRemoved: feRemoved
      of pfeRenamed: feRenamed
    fn(FileEvent(path: e.path, kind: kind)))
  if native != nil:
    result = FileWatcher(native: native)

proc watch*(path: string, fn: proc(e: FileEvent)): FileWatcher =
  watch(path, WatchOptions(), fn)

proc close*(w: FileWatcher) =
  if w != nil and w.native != nil:
    if w.native.close != nil:
      w.native.close()
    w.native = nil
