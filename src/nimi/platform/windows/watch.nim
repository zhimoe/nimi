## Overlapped directory notifications. The wait thread only posts a Win32
## message. Path decoding and application callbacks run on the owning thread.
import std/[os, strutils, tables, widestrs]
import ../contract

const header = (currentSourcePath.parentDir / "watch.h").replace('\\', '/')
{.compile: "watch.c".}

type
  Change = proc(context: pointer, name: WideCString, length, action: cint) {.cdecl.}
  Watch = ref object
    handle: pointer
    path: string
    isDirectory: bool
    draining, notified: bool
    callback: proc(event: PlatformFileEvent)
    events: seq[PlatformFileEvent]

proc openWatch(directory, file: WideCString, id: uint): pointer
  {.cdecl, importc: "nimi_watch_open", header: header.}
proc readWatch(watch: pointer, change: Change, context: pointer): cint
  {.cdecl, importc: "nimi_watch_read", header: header.}
proc closeWatch(watch: pointer)
  {.cdecl, importc: "nimi_watch_close", header: header.}

var watches: Table[uint, Watch]
var nextId: uint

proc closeWatch(id: uint) =
  let watcher = watches.getOrDefault(id)
  if watcher != nil:
    watches.del(id)
    closeWatch(watcher.handle)
    watcher.handle = nil

proc watchFiles*(path: string, callback: proc(event: PlatformFileEvent)): NativeFileWatcher =
  if path.len == 0 or '\0' in path or callback == nil:
    raise newException(BackendError, "Watch requires a path and a callback")
  let fullPath = absolutePath(path).normalizedPath()
  let isDirectory = dirExists(fullPath)
  let directory = if isDirectory: fullPath else: parentDir(fullPath)
  let file = if isDirectory: "" else: lastPathPart(fullPath)
  inc nextId
  let id = nextId
  let handle = openWatch(newWideCString(directory), newWideCString(file), id)
  if handle == nil:
    raise newException(BackendError, "Cannot watch Windows path " & fullPath)
  watches[id] = Watch(handle: handle, path: fullPath, isDirectory: isDirectory,
                      callback: callback)
  result = NativeFileWatcher(id: uint64(id), close: proc() = closeWatch(id))

proc collect(context: pointer, name: WideCString, length, action: cint) {.cdecl.} =
  let watcher = cast[Watch](context)
  let kind = case action
    of 1: pfeCreated
    of 2: pfeRemoved
    of 4, 5: pfeRenamed
    else: pfeModified
  var path = watcher.path
  if watcher.isDirectory and length > 0:
    let wide = newWideCString(int(length))
    copyMem(cast[pointer](WideCString(wide)), cast[pointer](name),
            int(length) * sizeof(Utf16Char))
    path = path / $wide
  watcher.events.add PlatformFileEvent(path: path, kind: kind)

proc dispatchWatch*(id: uint) =
  let watcher = watches.getOrDefault(id)
  if watcher == nil: return
  if watcher.draining:
    watcher.notified = true
    return
  watcher.draining = true
  defer: watcher.draining = false
  while watcher.handle != nil:
    watcher.notified = false
    let active = readWatch(watcher.handle, collect, cast[pointer](watcher)) != 0
    let events = move(watcher.events)
    defer:
      if not active: closeWatch(id)
    for event in events:
      if watcher.handle == nil: break
      watcher.callback(event)
    if not active or not watcher.notified: break

proc closeWatches*() =
  while watches.len > 0:
    var id: uint
    for key in watches.keys:
      id = key
      break
    closeWatch(id)
