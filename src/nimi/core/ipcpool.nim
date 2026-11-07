## Worker pool for background IPC methods. Requests and responses cross the
## thread boundary as JSON strings; the UI thread only receives completed
## results through postMain(). The pool is bounded by maxInflight, so a slow
## service cannot grow memory without limit.
import std/[atomics, monotimes, os, times]

import ./[ipc, loop]

type
  IpcRequest = object
    windowId: uint64
    callId: int64
    methodName: string
    args: string
    work: IpcWork

  IpcResult* = object
    windowId*: uint64
    callId*: int64
    value*, error*: string

  Shared = object
    requests: Channel[IpcRequest]
    results: Channel[IpcResult]
    inflight: Atomic[int]
    finished: Atomic[int]
    stopping: Atomic[bool]

  Pool = ref object
    shared: ptr Shared
    threads: seq[Thread[ptr Shared]]
    workers: int
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
  ## UI thread only. Delivers completed results; workers postMain this proc.
  if pool == nil:
    return
  while pool != nil:
    let received = pool.shared.results.tryRecv()
    if not received.dataAvailable:
      break
    if completion != nil:
      completion(received.msg)

proc workerMain(shared: ptr Shared) {.thread.} =
  while true:
    let request = shared.requests.recv()
    if request.work == nil:
      discard shared.finished.fetchAdd(1)
      break
    var value, error: string
    if shared.stopping.load():
      error = "IPC worker pool is shutting down"
    else:
      try:
        value = request.work(request.args)
      except CatchableError as e:
        error = e.msg
    discard shared.inflight.fetchSub(1)
    shared.results.send(IpcResult(windowId: request.windowId,
      callId: request.callId, value: value, error: error))
    wakeMainThread()
    if shared.stopping.load():
      # Do not wait for a per-worker sentinel; shutdown is already waiting on
      # the finished counter. Unused sentinels are discarded with the channel.
      discard shared.finished.fetchAdd(1)
      break

proc startIpcPool*(workers = 4, maxInflight = 256) =
  ## UI thread only. Safe to call repeatedly; later calls do not resize.
  if pool != nil:
    return
  let count = max(1, workers)
  let instance = Pool(workers: count, maxInflight: max(1, maxInflight))
  instance.shared = cast[ptr Shared](allocShared0(sizeof(Shared)))
  instance.shared.requests.open()
  instance.shared.results.open()
  instance.shared.inflight.store(0)
  instance.shared.finished.store(0)
  instance.shared.stopping.store(false)
  instance.threads.setLen(count)
  for i in 0 ..< count:
    createThread(instance.threads[i], workerMain, instance.shared)
  pool = instance
  poolStopped = false

proc submitIpc*(windowId: uint64, callId: int64, methodName, args: string,
                work: IpcWork): bool =
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
  instance.shared.requests.send(IpcRequest(windowId: windowId,
    callId: callId, methodName: methodName, args: args, work: work))
  true

proc shutdownIpcPool*(timeoutMs: int = 1000) =
  ## UI thread only. Stops admission, wakes idle workers, and joins them.
  ## A worker still stuck past timeoutMs is abandoned like TaskExecutor.
  if pool == nil or pool.closing:
    return
  let instance = pool
  instance.closing = true
  instance.shared.stopping.store(true)
  for _ in 0 ..< instance.workers:
    instance.shared.requests.send(IpcRequest())
  let deadline = getMonoTime() +
    initDuration(milliseconds = max(0, timeoutMs))
  while instance.shared.finished.load() < instance.workers and
      getMonoTime() < deadline:
    drainIpcPool()
    sleep(1)
  if instance.shared.finished.load() >= instance.workers:
    for thread in instance.threads:
      joinThread(thread)
    drainIpcPool()
    instance.shared.requests.close()
    instance.shared.results.close()
    deallocShared(instance.shared)
  # else: a worker is still inside user work. Leak the shared state rather
  # than freeing it under the live thread; this path is for application exit.
  pool = nil
  poolStopped = true
