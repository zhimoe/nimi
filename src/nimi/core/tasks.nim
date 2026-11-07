## Bounded background executor. Workers exchange owned strings through Channels;
## UI callbacks stay on the owning thread and run only from poll().
## Cancellation suppresses delivery, not an already running blocking operation.
import std/tables

type
  TaskWork* = proc(input: string): string {.nimcall, gcsafe.}
  TaskResult* = object
    id*: uint64
    value*, error*: string
  Request = object
    id: uint64
    input: string
    work: TaskWork
  Shared = object
    requests: Channel[Request]
    results: Channel[TaskResult]
  TaskExecutor* = ref object
    shared: ptr Shared
    worker: Thread[ptr Shared]
    callbacks: Table[uint64, proc(result: TaskResult)]
    nextId: uint64
    outstanding: int
    capacity: int

proc workerMain(shared: ptr Shared) {.thread.} =
  while true:
    let request = shared.requests.recv()
    if request.work == nil: break
    var result = TaskResult(id: request.id)
    try: result.value = request.work(request.input)
    except CatchableError as error: result.error = error.msg
    shared.results.send(result)

proc newTaskExecutor*(capacity = 64): TaskExecutor =
  ## Create on the UI thread; close explicitly before application shutdown.
  result = TaskExecutor(capacity: max(1, capacity))
  result.shared = cast[ptr Shared](allocShared0(sizeof(Shared)))
  result.shared.requests.open()
  result.shared.results.open()
  createThread(result.worker, workerMain, result.shared)

proc submit*(executor: TaskExecutor, input: string, work: TaskWork,
             callback: proc(result: TaskResult)): uint64 =
  ## Returns zero when closed/full. No UI closure is passed to the worker.
  if executor == nil or executor.shared == nil or work == nil or
      executor.outstanding >= executor.capacity: return 0
  inc executor.nextId
  result = executor.nextId
  executor.callbacks[result] = callback
  inc executor.outstanding
  executor.shared.requests.send(Request(id: result, input: input, work: work))

proc cancel*(executor: TaskExecutor, id: uint64) =
  if executor != nil: executor.callbacks.del(id)

proc pending*(executor: TaskExecutor): int =
  if executor != nil: executor.outstanding else: 0

proc poll*(executor: TaskExecutor) =
  ## Owning-thread only. Safe if a callback submits, cancels, or closes executor.
  if executor == nil: return
  while executor.shared != nil:
    let received = executor.shared.results.tryRecv()
    if not received.dataAvailable: break
    dec executor.outstanding
    let result = received.msg
    let callback = executor.callbacks.getOrDefault(result.id)
    executor.callbacks.del(result.id)
    if callback != nil: callback(result)

proc close*(executor: TaskExecutor) =
  ## Drops callbacks and joins the worker. Work MUST bound blocking I/O with a
  ## timeout; close waits for submitted work and never terminates a thread.
  if executor == nil or executor.shared == nil: return
  executor.callbacks.clear()
  executor.shared.requests.send(Request())
  joinThread(executor.worker)
  executor.shared.requests.close()
  executor.shared.results.close()
  deallocShared(executor.shared)
  executor.shared = nil
  executor.outstanding = 0
