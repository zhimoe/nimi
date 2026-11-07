## Main-thread queue.
##
## The platform backend installs two hooks: one that wakes the native run loop
## (dispatch_async on the main queue on macOS) and one that answers whether the
## current thread is the UI thread. Everything that touches UI state goes
## through postMain/onMain; bound IPC methods (later) run on a worker pool.

import std/[deques, locks]

var
  queue: Deque[proc() {.closure.}]
  queueLock: Lock
  signalHook: proc() {.closure.}
  mainHook: proc(): bool {.closure.}
  wakeHook: proc() {.nimcall, gcsafe.}
  initialized = false
  shuttingDown = false

proc initLoop*() =
  if not initialized:
    initLock(queueLock)
    initialized = true

proc setLoopHooks*(signal: proc(), isMain: proc(): bool) =
  ## Called once by the backend after it starts.
  signalHook = signal
  mainHook = isMain

proc setWakeHook*(hook: proc() {.nimcall, gcsafe.}) =
  ## Thread-safe wake primitive for workers that only touch Channels. It must
  ## not capture GC-managed state. Called once by the backend bootstrap.
  wakeHook = hook

proc wakeMainThread*() {.gcsafe.} =
  ## Safe from worker threads: signals the native main queue without touching
  ## the closure queue. The main dispatch drains IPC results on wake.
  if wakeHook != nil:
    try:
      wakeHook()
    except CatchableError:
      discard

proc isMainThread*(): bool =
  if mainHook == nil:
    return true
  mainHook()

proc postMain*(fn: proc()): bool =
  ## Queue fn and wake the native loop. Returns false after shutdown.
  initLoop()
  acquire(queueLock)
  if shuttingDown:
    release(queueLock)
    return false
  queue.addLast(fn)
  release(queueLock)
  if signalHook != nil:
    signalHook()
  true

proc drainMain*() =
  ## Run queued functions on the main thread. Re-entrant: a callback may post
  ## more work, and nested native loops must keep draining.
  while true:
    var fn: proc() {.closure.}
    acquire(queueLock)
    if queue.len == 0:
      release(queueLock)
      break
    fn = queue.popFirst()
    release(queueLock)
    fn()

proc onMain*(fn: proc()) =
  ## Run on the main thread and wait when called elsewhere.
  if isMainThread():
    fn()
    return

  type Waiter = ref object
    done: bool
    lock: Lock
    cond: Cond

  let w = Waiter()
  initLock(w.lock)
  initCond(w.cond)
  if not postMain(proc() =
      try:
        fn()
      finally:
        acquire(w.lock)
        w.done = true
        signal(w.cond)
        release(w.lock)):
    raise newException(CatchableError, "nimi: main loop is shut down")

  acquire(w.lock)
  while not w.done:
    wait(w.cond, w.lock)
  release(w.lock)
  deinitCond(w.cond)
  deinitLock(w.lock)

proc shutdownLoop*() =
  initLoop()
  acquire(queueLock)
  shuttingDown = true
  queue.clear()
  release(queueLock)
  deinitLock(queueLock)
  initialized = false
