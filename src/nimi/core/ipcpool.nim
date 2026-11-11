## Worker pool for background IPC methods. Requests and responses cross the
## thread boundary as JSON strings; the UI thread only receives completed
## results through postMain(). The pool is bounded by maxInflight, cancels
## calls when their window closes, and rejects calls that pass their deadline.
import std/[atomics, monotimes, os, tables, times]

import ./[ipc, loop]

type
  IpcRequest = object
    requestId: uint64
    windowId: uint64
    callId: int64
    args: string
    work: IpcWork
    control: ptr Atomic[bool]

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
    requests: Channel[IpcRequest]
    results: Channel[IpcResult]
    watch: Channel[WatchCommand]
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

proc setIpcCompletion*(fn: proc(result: IpcResult) {.closure.}) =
  ## Set from the UI thread. Pass nil on shutdown to drop late completions.
  completion = fn

proc drainIpcPool*() =
  ## UI thread only. Delivers completed results; workers and the watchdog wake
  ## the main thread.
  if pool == nil:
    return
  while pool != nil:
    let received = pool.shared.results.tryRecv()
    if not received.dataAvailable:
      break
    let result = received.msg
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
    # A result without a pending entry is a late delivery after cancellation
    # or shutdown; drop it.

proc watchdogMain(shared: ptr Shared) {.thread.} =
  var items: Table[uint64, WatchItem]
  while true:
    while true:
      let received = shared.watch.tryRecv()
      if not received.dataAvailable:
        break
      let command = received.msg
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
      shared.results.send(IpcResult(requestId: id,
        windowId: item.windowId, callId: item.callId,
        error: "IPC call timed out", timedOut: true))
      wakeMainThread()
    sleep(20)

proc workerMain(shared: ptr Shared) {.thread.} =
  while true:
    let request = shared.requests.recv()
    if request.work == nil:
      discard shared.finished.fetchAdd(1)
      break
    var value, error: string
    if shared.stopping.load():
      error = "IPC worker pool is shutting down"
    elif request.control != nil and request.control[].load():
      error = "IPC call cancelled"
    else:
      try:
        value = request.work(request.args,
          newIpcCallContext(request.control))
      except CatchableError as e:
        error = e.msg
    discard shared.inflight.fetchSub(1)
    shared.results.send(IpcResult(requestId: request.requestId,
      windowId: request.windowId, callId: request.callId,
      value: value, error: error))
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
  instance.shared.requests.open()
  instance.shared.results.open()
  instance.shared.watch.open()
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
  instance.shared.requests.send(IpcRequest(requestId: requestId,
    windowId: windowId, callId: callId, args: args,
    work: work, control: control))
  true

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
    instance.shared.requests.send(IpcRequest())
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
    instance.shared.requests.close()
    instance.shared.results.close()
    instance.shared.watch.close()
    deallocShared(instance.shared)
  # else: a worker is still inside user work. Leak the shared state rather
  # than freeing it under the live thread; this path is for application exit.
  pool = nil
  poolStopped = true
