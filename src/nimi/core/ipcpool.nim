## Worker pool for background IPC methods.
##
## Requests and responses cross the thread boundary as `SharedBytes` (raw
## `allocShared` UTF-8 buffers) inside `SharedQueue`, completely avoiding
## GC/ARC heap sharing across threads.

import std/[atomics, monotimes, os, tables, times]

import ./[ipc, loop, sharedqueue]

type
  RawIpcRequest = object
    requestId: uint64
    windowId: uint64
    callId: int64
    args: SharedBytes
    work: IpcWork
    control: ptr Atomic[bool]

  RawIpcResult = object
    requestId: uint64
    windowId: uint64
    callId: int64
    value: SharedBytes
    error: SharedBytes
    timedOut: bool

  IpcResult* = object
    requestId*: uint64
    windowId*: uint64
    callId*: int64
    value*, error*: string
    timedOut*: bool

  WatchKind = enum
    wkAdd, wkRemove, wkStop

  WatchCommand = object
    kind: WatchKind
    requestId: uint64
    windowId: uint64
    callId: int64
    deadline: MonoTime
    control: ptr Atomic[bool]

  WatchItem = object
    windowId: uint64
    callId: int64
    deadline: MonoTime
    control: ptr Atomic[bool]

  Shared = object
    requests: SharedQueue[RawIpcRequest]
    results: SharedQueue[RawIpcResult]
    watch: SharedQueue[WatchCommand]
    inflight: Atomic[int]
    finished: Atomic[int]
    stopping: Atomic[bool]

  PendingCall = object
    windowId: uint64
    callId: int64
    control: ptr Atomic[bool]
    cancelled, timedOut: bool

  Pool = ref object
    shared: ptr Shared
    threads: seq[Thread[ptr Shared]]
    watchdog: Thread[ptr Shared]
    pending: Table[uint64, PendingCall]
    byWindow: Table[uint64, seq[uint64]]
    nextRequestId: uint64
    maxInflight: int
    closing: bool

var
  pool: Pool
  poolStopped = false
  completion: proc(result: IpcResult) {.closure.}

proc freeRawRequest(req: var RawIpcRequest) {.nimcall, gcsafe.} =
  freeSharedBytes(req.args)

proc freeRawResult(res: var RawIpcResult) {.nimcall, gcsafe.} =
  freeSharedBytes(res.value)
  freeSharedBytes(res.error)

proc setIpcCompletion*(fn: proc(result: IpcResult) {.closure.}) =
  ## Set from the UI thread. Pass nil on shutdown to drop late completions.
  completion = fn

proc drainIpcPool*() =
  ## UI thread only. Delivers completed results; workers and the watchdog wake
  ## the main thread.
  if pool == nil or pool.shared == nil:
    return
  while pool != nil and pool.shared != nil:
    var raw: RawIpcResult
    if not pool.shared.results.tryRecv(raw):
      break
    let result = IpcResult(
      requestId: raw.requestId,
      windowId: raw.windowId,
      callId: raw.callId,
      value: takeSharedString(raw.value),
      error: takeSharedString(raw.error),
      timedOut: raw.timedOut)
    if result.timedOut:
      if pool.pending.hasKey(result.requestId):
        var pending = pool.pending[result.requestId]
        if not pending.cancelled and not pending.timedOut:
          pending.timedOut = true
          pool.pending[result.requestId] = pending
          if completion != nil:
            completion(result)
      continue
    if pool.pending.hasKey(result.requestId):
      let pending = pool.pending[result.requestId]
      pool.pending.del(result.requestId)
      if pool.byWindow.hasKey(pending.windowId):
        var ids = pool.byWindow[pending.windowId]
        var index = -1
        for i, id in ids:
          if id == result.requestId:
            index = i
            break
        if index >= 0: ids.delete(index)
        if ids.len == 0: pool.byWindow.del(pending.windowId)
        else: pool.byWindow[pending.windowId] = ids
      if pending.control != nil:
        deallocShared(pending.control)
      if not pending.cancelled and not pending.timedOut:
        if completion != nil:
          completion(result)

proc watchdogMain(shared: ptr Shared) {.thread.} =
  var items: Table[uint64, WatchItem]
  while true:
    var command: WatchCommand
    while shared.watch.tryRecv(command):
      case command.kind
      of wkAdd:
        items[command.requestId] = WatchItem(
          windowId: command.windowId, callId: command.callId,
          deadline: command.deadline, control: command.control)
      of wkRemove:
        items.del(command.requestId)
      of wkStop:
        return
    let now = getMonoTime()
    var expired: seq[uint64]
    for id, item in items:
      if now >= item.deadline:
        expired.add id
    for id in expired:
      let item = items[id]
      items.del(id)
      if item.control != nil:
        item.control[].store(true)
      shared.results.send(RawIpcResult(
        requestId: id,
        windowId: item.windowId,
        callId: item.callId,
        error: toSharedBytes("IPC call timed out"),
        timedOut: true))
      wakeMainThread()
    sleep(20)

proc workerMain(shared: ptr Shared) {.thread.} =
  while true:
    var request: RawIpcRequest
    if not shared.requests.recv(request):
      discard shared.finished.fetchAdd(1)
      break
    if request.work == nil:
      freeRawRequest(request)
      discard shared.finished.fetchAdd(1)
      break
    let argsStr = takeSharedString(request.args)
    var value, error: string
    if shared.stopping.load():
      error = "IPC worker pool is shutting down"
    elif request.control != nil and request.control[].load():
      error = "IPC call cancelled"
    else:
      try:
        value = request.work(argsStr,
          newIpcCallContext(request.control, request.windowId, request.callId))
      except CatchableError as e:
        error = e.msg
    discard shared.inflight.fetchSub(1)
    shared.results.send(RawIpcResult(
      requestId: request.requestId,
      windowId: request.windowId,
      callId: request.callId,
      value: toSharedBytes(value),
      error: toSharedBytes(error)))
    wakeMainThread()
    if shared.stopping.load():
      discard shared.finished.fetchAdd(1)
      break

proc startIpcPool*(workers = 4, maxInflight = 256) =
  ## UI thread only. Safe to call repeatedly; later calls do not resize.
  if pool != nil:
    return
  let count = max(1, workers)
  let instance = Pool(maxInflight: max(1, maxInflight))
  instance.shared = cast[ptr Shared](allocShared0(sizeof(Shared)))
  initSharedQueue(instance.shared.requests, max(16, maxInflight))
  initSharedQueue(instance.shared.results, max(16, maxInflight))
  initSharedQueue(instance.shared.watch, 64)
  instance.shared.inflight.store(0)
  instance.shared.finished.store(0)
  instance.shared.stopping.store(false)
  instance.threads.setLen(count)
  for i in 0 ..< count:
    createThread(instance.threads[i], workerMain, instance.shared)
  createThread(instance.watchdog, watchdogMain, instance.shared)
  pool = instance
  poolStopped = false

proc submitIpc*(windowId: uint64, callId: int64, methodName, args: string,
                work: IpcWork, timeoutMs: int = 0): bool =
  ## Returns false when the pool is closed/not on the UI thread or the
  ## in-flight limit is reached. Callers should reject the page promise.
  if work == nil or not isMainThread() or poolStopped:
    return false
  if pool == nil:
    startIpcPool()
  let instance = pool
  if instance == nil or instance.closing:
    return false
  let previous = instance.shared.inflight.fetchAdd(1)
  if previous >= instance.maxInflight:
    discard instance.shared.inflight.fetchSub(1)
    return false
  inc instance.nextRequestId
  let requestId = instance.nextRequestId
  let control = createShared(Atomic[bool])
  control[].store(false)
  instance.pending[requestId] = PendingCall(windowId: windowId,
    callId: callId, control: control)
  var ids = instance.byWindow.getOrDefault(windowId)
  ids.add requestId
  instance.byWindow[windowId] = ids
  if timeoutMs > 0:
    instance.shared.watch.send(WatchCommand(kind: wkAdd, requestId: requestId,
      windowId: windowId, callId: callId,
      deadline: getMonoTime() + initDuration(milliseconds = timeoutMs),
      control: control))
  instance.shared.requests.send(RawIpcRequest(
    requestId: requestId,
    windowId: windowId,
    callId: callId,
    args: toSharedBytes(args),
    work: work,
    control: control))
  true

proc cancelIpcCall*(windowId: uint64, callId: int64): bool =
  ## UI thread only. Marks one in-flight call cancelled and rejects its promise.
  if pool == nil or not pool.byWindow.hasKey(windowId):
    return false
  let instance = pool
  for id in instance.byWindow[windowId]:
    if not instance.pending.hasKey(id):
      continue
    var pending = instance.pending[id]
    if pending.callId == callId and not pending.cancelled and not pending.timedOut:
      pending.cancelled = true
      if pending.control != nil:
        pending.control[].store(true)
      instance.pending[id] = pending
      instance.shared.watch.send(WatchCommand(kind: wkRemove, requestId: id))
      if completion != nil:
        completion(IpcResult(requestId: id, windowId: windowId, callId: callId,
          error: "IPC call cancelled"))
      return true
  false

proc cancelIpcWindow*(windowId: uint64) =
  ## UI thread only. Stops delivery and asks all in-flight work for this
  ## window to stop; late results are discarded when they arrive.
  if pool == nil or not pool.byWindow.hasKey(windowId):
    return
  let instance = pool
  let ids = instance.byWindow[windowId]
  instance.byWindow.del(windowId)
  for id in ids:
    if not instance.pending.hasKey(id):
      continue
    var pending = instance.pending[id]
    if pending.cancelled:
      continue
    pending.cancelled = true
    if pending.control != nil:
      pending.control[].store(true)
    instance.pending[id] = pending
    instance.shared.watch.send(WatchCommand(kind: wkRemove, requestId: id))

proc shutdownIpcPool*(timeoutMs: int = 1000) =
  ## UI thread only. Stops admission, cancels pending work, wakes idle workers,
  ## and joins them. A worker still stuck past timeoutMs is abandoned like
  ## TaskExecutor.
  if pool == nil or pool.closing:
    return
  let instance = pool
  instance.closing = true
  instance.shared.stopping.store(true)
  var ids: seq[uint64]
  for id in instance.pending.keys:
    ids.add id
  for id in ids:
    var pending = instance.pending[id]
    pending.cancelled = true
    if pending.control != nil:
      pending.control[].store(true)
    instance.pending[id] = pending
    instance.shared.watch.send(WatchCommand(kind: wkRemove, requestId: id))
  instance.shared.watch.send(WatchCommand(kind: wkStop))
  joinThread(instance.watchdog)
  for _ in 0 ..< instance.threads.len:
    instance.shared.requests.send(RawIpcRequest())
  closeSharedQueue(instance.shared.requests)
  let deadline = getMonoTime() +
    initDuration(milliseconds = max(0, timeoutMs))
  while instance.shared.finished.load() < instance.threads.len and
      getMonoTime() < deadline:
    drainIpcPool()
    sleep(1)
  if instance.shared.finished.load() >= instance.threads.len:
    for thread in instance.threads:
      joinThread(thread)
    drainIpcPool()
    for _, pending in instance.pending:
      if pending.control != nil:
        deallocShared(pending.control)
    instance.pending.clear()
    instance.byWindow.clear()
    deinitSharedQueue(instance.shared.requests, freeRawRequest)
    deinitSharedQueue(instance.shared.results, freeRawResult)
    deinitSharedQueue(instance.shared.watch)
    deallocShared(instance.shared)
    instance.shared = nil
  pool = nil
  poolStopped = true

proc resetIpcPoolForTests*() =
  ## Allows test suites to restart the pool cleanly after `shutdownIpcPool()`.
  if pool == nil:
    poolStopped = false
