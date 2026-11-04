import std/[typedthreads, locks]

type Payload = ref object
  n: int
  text: string

var lock: Lock
var shared: seq[Payload]

proc worker(p: Payload) {.thread.} =
  {.gcsafe.}:
    acquire(lock)
    shared.add Payload(n: p.n + 1, text: p.text & " (from worker)")
    release(lock)

when isMainModule:
  initLock(lock)
  let p = Payload(n: 41, text: "hello")
  var t: Thread[Payload]
  createThread(t, worker, p)
  joinThread(t)
  echo "shared: ", shared[0].n, " ", shared[0].text
  deinitLock(lock)
