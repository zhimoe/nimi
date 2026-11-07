## Bounded background executor. Workers exchange owned strings through
## Channels; UI callbacks stay on the owning thread and run only from poll().
## Cancellation is cooperative: work receives a TaskContext and should stop at
## the next safe point. A close with a timeout may abandon a stuck worker so
## application shutdown never waits indefinitely.
import std/[atomics, monotimes, os, tables, times]

type
  TaskContext* = object
    control: ptr Atomic[bool]

  TaskWork* = proc(input: string, context: TaskContext): string
    {.nimcall, gcsafe.}

  TaskResult* = object
    id*: uint64
    value*, error*: string

  Pending = object
    callback: proc(result: TaskResult)
    control: ptr Atomic[bool]
    deadline: MonoTime
    hasDeadline, timedOut: bool

  Request = object
    id: uint64
    input: string
    work: TaskWork
    control: ptr Atomic[bool]

  Shared = object
    requests: Channel[Request]
    results: Channel[TaskResult]
    finished: Atomic[bool]

  TaskExecutor* = ref object
    shared: ptr Shared
    worker: Thread[ptr Shared]
    pending: Table[uint64, Pending]
    nextId: uint64
    outstanding: int
    capacity: int
    closing: bool

proc isCancelled*(context: TaskContext): bool {.inline.} =
  context.control != nil and context.control[].load()

proc newControl(): ptr Atomic[bool] =
  result = createShared(Atomic[bool])
  result[].store(false)

proc workerMain(shared: ptr Shared) {.thread.} =
  while true:
    let request = shared.requests.recv()
    if request.work == nil:
      shared.finished.store(true)
      break
    if request.control != nil and request.control[].load():
      shared.results.send(TaskResult(id: request.id, error: "Task cancelled"))
      continue
    var result = TaskResult(id: request.id)
    try:
      result.value = request.work(
        request.input, TaskContext(control: request.control))
    except CatchableError as error:
      result.error = error.msg
    shared.results.send(result)

proc newTaskExecutor*(capacity = 64): TaskExecutor =
  ## Create on the UI thread; close explicitly before application shutdown.
  result = TaskExecutor(capacity: max(1, capacity))
  result.shared = cast[ptr Shared](allocShared0(sizeof(Shared)))
  result.shared.requests.open()
  result.shared.results.open()
  result.shared.finished.store(false)
  createThread(result.worker, workerMain, result.shared)

proc submit*(executor: TaskExecutor, input: string, work: TaskWork,
             callback: proc(result: TaskResult),
             timeoutMs: int = 0): uint64 =
  ## Returns zero when closed/full. No UI closure is passed to the worker.
  ## A positive timeout reports an error from poll() and requests cooperative
  ## cancellation; the worker is not interrupted preemptively.
  if executor == nil or executor.shared == nil or executor.closing or
      work == nil or executor.outstanding >= executor.capacity:
    return 0
  inc executor.nextId
  result = executor.nextId
  let control = newControl()
  if timeoutMs > 0:
    executor.pending[result] = Pending(
      callback: callback, control: control,
      deadline: getMonoTime() + initDuration(milliseconds = timeoutMs),
      hasDeadline: true)
  else:
    executor.pending[result] = Pending(callback: callback, control: control)
  inc executor.outstanding
  executor.shared.requests.send(Request(
    id: result, input: input, work: work, control: control))

proc cancel*(executor: TaskExecutor, id: uint64) =
  ## Suppresses delivery and asks the worker to stop. Capacity is released
  ## only when the worker returns the cancelled result.
  if executor == nil or executor.shared == nil: return
  if executor.pending.hasKey(id):
    var pending = executor.pending[id]
    if pending.control != nil:
      pending.control[].store(true)
    pending.callback = nil
    executor.pending[id] = pending

proc pending*(executor: TaskExecutor): int =
  if executor != nil: executor.outstanding else: 0

proc poll*(executor: TaskExecutor) =
  ## Owning-thread only. Safe if a callback submits, cancels, or closes executor.
  if executor == nil or executor.shared == nil: return
  while executor.shared != nil:
    let received = executor.shared.results.tryRecv()
    if not received.dataAvailable:
      break
    let result = received.msg
    if executor.outstanding > 0:
      dec executor.outstanding
    if executor.pending.hasKey(result.id):
      let pending = executor.pending[result.id]
      executor.pending.del(result.id)
      let expired = pending.hasDeadline and getMonoTime() > pending.deadline
      let callback = pending.callback
      if pending.control != nil:
        deallocShared(pending.control)
      if pending.timedOut:
        discard
      elif expired:
        if callback != nil:
          callback(TaskResult(id: result.id, error: "Task timed out"))
      elif callback != nil:
        callback(result)
  if executor.shared == nil:
    return
  var expired: seq[uint64]
  let now = getMonoTime()
  for id, item in executor.pending:
    if item.hasDeadline and not item.timedOut and now >= item.deadline:
      expired.add id
  for id in expired:
    if executor.shared == nil:
      return
    if not executor.pending.hasKey(id):
      continue
    var item = executor.pending[id]
    if item.timedOut:
      continue
    item.timedOut = true
    if item.control != nil:
      item.control[].store(true)
    let callback = item.callback
    item.callback = nil
    executor.pending[id] = item
    if callback != nil:
      callback(TaskResult(id: id, error: "Task timed out"))

proc close*(executor: TaskExecutor, timeoutMs: int = 1000) =
  ## Drops callbacks, cancels pending work, and joins the worker. If a stuck
  ## task ignores cancellation past `timeoutMs`, the executor abandons the
  ## worker (and its shared state) instead of blocking shutdown forever.
  if executor == nil or executor.shared == nil:
    return
  executor.closing = true
  var ids: seq[uint64]
  for id in executor.pending.keys:
    ids.add id
  for id in ids:
    var item = executor.pending[id]
    if item.control != nil:
      item.control[].store(true)
    item.callback = nil
    executor.pending[id] = item
  executor.shared.requests.send(Request())
  let deadline = getMonoTime() + initDuration(milliseconds = max(0, timeoutMs))
  while executor.shared != nil and not executor.shared.finished.load() and
      getMonoTime() < deadline:
    executor.poll()
    sleep(1)
  if executor.shared == nil:
    return
  if executor.shared.finished.load():
    joinThread(executor.worker)
    executor.poll()
    executor.shared.requests.close()
    executor.shared.results.close()
    deallocShared(executor.shared)
    executor.shared = nil
    for _, item in executor.pending:
      if item.control != nil:
        deallocShared(item.control)
    executor.pending.clear()
  else:
    # The worker may still touch Shared and its controls later. Leak them
    # rather than freeing memory under a live thread; the process is exiting.
    executor.shared = nil
    executor.pending.clear()
  executor.outstanding = 0
