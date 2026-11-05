## FSEvents file watching with kFSEventStreamCreateFlagFileEvents.

import std/[dynlib, tables]

import ../contract
import ./[objc, types]

type
  FSEventStreamRef = pointer
  FSEventStreamContext {.bycopy.} = object
    version: int
    info: pointer
    retain: pointer
    release: pointer
    copyDescription: pointer
  FSEventStreamCallback = proc(streamRef: pointer, clientInfo: pointer,
                               numEvents: uint, eventPaths: pointer,
                               eventFlags: ptr uint32,
                               eventIds: ptr uint64) {.cdecl.}
  FSEventStreamCreateProc = proc(allocator: pointer,
                                 callback: FSEventStreamCallback,
                                 context: ptr FSEventStreamContext,
                                 pathsToWatch: Id, sinceWhen: uint64,
                                 latency: float64, flags: uint32): pointer {.cdecl.}

const
  KFSEventStreamCreateFlagNoDefer = 0x00000002'u32
  KFSEventStreamCreateFlagFileEvents = 0x00000010'u32
  KFSEventStreamEventFlagItemCreated = 0x00000100'u32
  KFSEventStreamEventFlagItemRemoved = 0x00000200'u32
  KFSEventStreamEventFlagItemRenamed = 0x00000800'u32
  KFSEventStreamEventFlagItemModified = 0x00001000'u32
  KFSEventStreamEventIdSinceNow = 0xFFFFFFFFFFFFFFFF'u64

let
  createStream = cast[FSEventStreamCreateProc](
    symAddr(fsevents, "FSEventStreamCreate"))
  setQueue = cast[proc(streamRef: pointer, q: pointer) {.cdecl.}](
    symAddr(fsevents, "FSEventStreamSetDispatchQueue"))
  startStream = cast[proc(streamRef: pointer): bool {.cdecl.}](
    symAddr(fsevents, "FSEventStreamStart"))
  stopStream = cast[proc(streamRef: pointer) {.cdecl.}](
    symAddr(fsevents, "FSEventStreamStop"))
  invalidateStream = cast[proc(streamRef: pointer) {.cdecl.}](
    symAddr(fsevents, "FSEventStreamInvalidate"))
  releaseStream = cast[proc(streamRef: pointer) {.cdecl.}](
    symAddr(fsevents, "FSEventStreamRelease"))

proc eventCallback(streamRef: pointer, clientInfo: pointer, numEvents: uint,
                   eventPaths: pointer, eventFlags: ptr uint32,
                   eventIds: ptr uint64) {.cdecl.} =
  if gState == nil or clientInfo == nil:
    return
  let id = cast[uint64](clientInfo)
  let handler = gState.watchHandlers.getOrDefault(id)
  if handler == nil:
    return
  let paths = cast[ptr UncheckedArray[cstring]](eventPaths)
  let flagsArray = cast[ptr UncheckedArray[uint32]](eventFlags)
  for i in 0 ..< int(numEvents):
    let flags = flagsArray[i]
    let kind =
      if (flags and KFSEventStreamEventFlagItemCreated) != 0: pfeCreated
      elif (flags and KFSEventStreamEventFlagItemRemoved) != 0: pfeRemoved
      elif (flags and KFSEventStreamEventFlagItemRenamed) != 0: pfeRenamed
      else: pfeModified
    let path = if paths != nil and paths[i] != nil: $paths[i] else: ""
    handler(PlatformFileEvent(path: path, kind: kind))

proc watchFiles*(path: string, handler: proc(e: PlatformFileEvent)): NativeFileWatcher =
  if gState == nil:
    return nil
  let paths = sendId1(loadClass("NSArray"), sel("arrayWithObject:"), nsString(path))
  if paths == nil:
    return nil
  let id = gState.nextWatchId
  inc gState.nextWatchId
  var context = FSEventStreamContext(version: 0, info: cast[pointer](id))
  let stream = createStream(nil, eventCallback, addr context, paths,
                            KFSEventStreamEventIdSinceNow, 0.12,
                            KFSEventStreamCreateFlagFileEvents or
                            KFSEventStreamCreateFlagNoDefer)
  if stream == nil:
    return nil
  setQueue(stream, mainDispatchQueue())
  if not startStream(stream):
    releaseStream(stream)
    return nil
  gState.watchStreams[id] = stream
  gState.watchHandlers[id] = handler
  result = NativeFileWatcher(id: id)
  result.close = proc() =
    let s = gState.watchStreams.getOrDefault(id)
    if s != nil:
      stopStream(s)
      invalidateStream(s)
      releaseStream(s)
    gState.watchStreams.del(id)
    gState.watchHandlers.del(id)
