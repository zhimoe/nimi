## inotify-backed file watching, integrated into the GLib main context.

when not defined(linux):
  {.error: "The Linux file watcher requires Linux".}

import std/[os, posix, strutils, tables]

import ../contract
import ./[ffi, state]

const
  InModify = 0x00000002'u32
  InAttrib = 0x00000004'u32
  InCloseWrite = 0x00000008'u32
  InMovedFrom = 0x00000040'u32
  InMovedTo = 0x00000080'u32
  InCreate = 0x00000100'u32
  InDelete = 0x00000200'u32
  InDeleteSelf = 0x00000400'u32
  InMoveSelf = 0x00000800'u32
  InQOverflow = 0x00004000'u32
  InIgnored = 0x00008000'u32
  InIsDir = 0x40000000'u32
  InNonblock = 0x00000800
  InCloexec = 0x00080000
  InWatchMask = InModify or InAttrib or InCloseWrite or InMovedFrom or
                InMovedTo or InCreate or InDelete or InDeleteSelf or InMoveSelf

type
  InotifyEvent {.bycopy.} = object
    wd: cint
    mask: uint32
    cookie: uint32
    length: uint32

  WatchState = ref object
    fd: cint
    source: cuint
    root: string
    directory: bool
    handler: proc(e: PlatformFileEvent) {.closure.}
    watches: Table[cint, string]

proc inotify_init1(flags: cint): cint {.importc, header: "<sys/inotify.h>".}
proc inotify_add_watch(fd: cint, path: cstring, mask: uint32): cint
  {.importc, header: "<sys/inotify.h>".}
proc inotify_rm_watch(fd: cint, wd: cint): cint
  {.importc, header: "<sys/inotify.h>".}

var
  watchStates: seq[WatchState]
  nextWatchId = 1'u64

proc emit(state: WatchState, path: string, kind: PlatformFileEventKind) =
  if state.handler != nil:
    try:
      state.handler(PlatformFileEvent(path: path, kind: kind))
    except CatchableError:
      discard

proc addDirectory(state: WatchState, path: string) =
  if not dirExists(path):
    return
  let wd = inotify_add_watch(state.fd, path.cstring, InWatchMask)
  if wd >= 0:
    state.watches[cint(wd)] = path
  for kind, child in walkDir(path):
    if kind == pcDir:
      addDirectory(state, child)

proc forgetTree(state: WatchState, path: string) =
  var stale: seq[cint]
  for wd, watched in state.watches:
    if watched == path or watched.startsWith(path & "/"):
      stale.add wd
  for wd in stale:
    discard inotify_rm_watch(state.fd, wd)
    state.watches.del(wd)

proc drain(state: WatchState) =
  var buffer = newSeq[byte](65536)
  while true:
    let count = posix.read(state.fd, addr buffer[0], buffer.len)
    if count <= 0:
      break
    var offset = 0
    var modified: seq[string]
    while offset + sizeof(InotifyEvent) <= count:
      let event = cast[ptr InotifyEvent](addr buffer[offset])
      let nameLength = int(event.length)
      if offset + sizeof(InotifyEvent) + nameLength > count:
        break
      var name = ""
      if nameLength > 0:
        name = $cast[cstring](addr buffer[offset + sizeof(InotifyEvent)])
        # inotify pads the name; the cstring view still terminates correctly.
      offset += sizeof(InotifyEvent) + nameLength
      let mask = event.mask
      if (mask and InQOverflow) != 0:
        emit(state, state.root, pfeModified)
        continue
      let base = state.watches.getOrDefault(event.wd)
      if (mask and InIgnored) != 0:
        state.watches.del(event.wd)
        continue
      if base.len == 0:
        continue
      let path = if name.len > 0: base / name else: base
      if (mask and InCreate) != 0:
        emit(state, path, pfeCreated)
        if (mask and InIsDir) != 0:
          addDirectory(state, path)
      elif (mask and InDelete) != 0:
        emit(state, path, pfeRemoved)
        if (mask and InIsDir) != 0:
          forgetTree(state, path)
      elif (mask and InMovedTo) != 0:
        emit(state, path, pfeRenamed)
        if (mask and InIsDir) != 0:
          addDirectory(state, path)
      elif (mask and InMovedFrom) != 0:
        emit(state, path, pfeRemoved)
        if (mask and InIsDir) != 0:
          forgetTree(state, path)
      elif (mask and (InModify or InCloseWrite or InAttrib)) != 0:
        if path notin modified:
          modified.add path
          emit(state, path, pfeModified)
      elif (mask and (InDeleteSelf or InMoveSelf)) != 0:
        emit(state, path, pfeRemoved)

proc onReadable(fd: cint, condition: cint, data: pointer): cint {.cdecl.} =
  let state = cast[WatchState](data)
  if state != nil:
    try:
      drain(state)
    except CatchableError:
      discard
  1

proc closeWatch(state: WatchState) =
  if state == nil:
    return
  if state.source != 0:
    discard g_source_remove(state.source)
    state.source = 0
  if state.fd >= 0:
    discard posix.close(state.fd)
    state.fd = -1
  state.handler = nil
  state.watches.clear()
  var remaining: seq[WatchState]
  for item in watchStates:
    if item != state:
      remaining.add item
  watchStates = remaining

proc watchFiles*(path: string,
                 handler: proc(e: PlatformFileEvent)): NativeFileWatcher =
  ## Watch a file or a directory tree. Replaced directories are re-attached;
  ## buffer overflow is reported as a modification of the watched root.
  if linuxState == nil or not linuxState.initialized:
    raise newException(BackendError,
      "File watching requires an initialized backend")
  if path.len == 0 or (not fileExists(path) and not dirExists(path)):
    raise newException(BackendError, "Cannot watch a missing path: " & path)
  let fd = inotify_init1(InNonblock or InCloexec)
  if fd < 0:
    raise newException(BackendError, "inotify_init1 failed")
  let state = WatchState(fd: fd, root: absolutePath(path),
                         directory: dirExists(path), handler: handler)
  try:
    if state.directory:
      state.addDirectory(state.root)
    else:
      let wd = inotify_add_watch(fd, state.root.cstring, InWatchMask)
      if wd < 0:
        raise newException(BackendError, "inotify_add_watch failed")
      state.watches[cint(wd)] = state.root
    state.source = g_unix_fd_add(fd, 1, onReadable, cast[pointer](state))
    if state.source == 0:
      raise newException(BackendError, "Cannot watch the file descriptor")
  except:
    if state.fd >= 0:
      discard posix.close(state.fd)
      state.fd = -1
    raise
  watchStates.add state
  result = NativeFileWatcher(
    id: nextWatchId,
    close: proc() = closeWatch(state))
  inc nextWatchId

proc closeAllWatches*() =
  var remaining = watchStates
  watchStates = @[]
  for state in remaining:
    closeWatch(state)
