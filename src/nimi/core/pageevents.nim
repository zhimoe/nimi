## Thread-safe host -> page event & streaming chunk queue.
##
## Worker threads push raw `SharedBytes` frames into an `allocShared`-backed
## queue and signal `wakeMainThread()`. The UI thread drains and delivers them
## through the window bridge during main-loop dispatch, eliminating any need for
## applications to hand-roll shared ring buffers or `pollEvents` RPCs.

import std/locks

import ./[loop, sharedqueue]

type
  PageFrameKind = enum
    pfkEvent
    pfkStreamChunk

  RawPageFrame = object
    kind: PageFrameKind
    windowId: uint64    ## 0 = broadcast to all open windows (for pfkEvent)
    callId: int64       ## used by pfkStreamChunk
    name: SharedBytes
    payload: SharedBytes

  EventDeliveryHook* = proc(windowId: uint64, name, payloadJson: string) {.closure.}
  ChunkDeliveryHook* = proc(windowId: uint64, callId: int64, chunkJson: string) {.closure.}

var
  initOnceLock: Lock
  frameQueueReady = false
  frameQueue: SharedQueue[RawPageFrame]
  deliverEventHook: EventDeliveryHook
  deliverChunkHook: ChunkDeliveryHook

initLock(initOnceLock)

proc ensureFrameQueue() {.gcsafe.} =
  acquire(initOnceLock)
  if not frameQueueReady:
    initSharedQueue(frameQueue, 128)
    frameQueueReady = true
  release(initOnceLock)

proc setPageDeliveryHooks*(onEvent: EventDeliveryHook,
                           onChunk: ChunkDeliveryHook) =
  ## Installed by `core/window.nim` on the main thread.
  ensureFrameQueue()
  deliverEventHook = onEvent
  deliverChunkHook = onChunk

proc queuePageEvent*(windowId: uint64, name, payloadJson: string) {.gcsafe.} =
  ## Safe from ANY thread (UI thread, IPC worker pool, file watcher thread).
  ## `windowId == 0` broadcasts to every open window.
  ensureFrameQueue()
  frameQueue.send(RawPageFrame(
    kind: pfkEvent,
    windowId: windowId,
    name: toSharedBytes(name),
    payload: toSharedBytes(payloadJson)))
  wakeMainThread()

proc queueStreamChunk*(windowId: uint64, callId: int64,
                       chunkJson: string) {.gcsafe.} =
  ## Safe from ANY thread. Pushes one streaming chunk to an in-flight call.
  if windowId == 0 or callId <= 0:
    return
  ensureFrameQueue()
  frameQueue.send(RawPageFrame(
    kind: pfkStreamChunk,
    windowId: windowId,
    callId: callId,
    payload: toSharedBytes(chunkJson)))
  wakeMainThread()

proc drainPageEvents*() =
  ## UI thread only. Drains queued events and streaming chunks in FIFO order.
  ensureFrameQueue()
  var raw: RawPageFrame
  while frameQueue.tryRecv(raw):
    let name = takeSharedString(raw.name)
    let payload = takeSharedString(raw.payload)
    case raw.kind
    of pfkEvent:
      if deliverEventHook != nil:
        try:
          deliverEventHook(raw.windowId, name, payload)
        except CatchableError:
          discard
    of pfkStreamChunk:
      if deliverChunkHook != nil:
        try:
          deliverChunkHook(raw.windowId, raw.callId, payload)
        except CatchableError:
          discard
