## GC-free shared-memory byte buffers and thread-safe MPMC queues.
##
## Nim's legacy `system.Channel[T]` corrupts the heap under `--mm:arc` /
## `--mm:atomicArc` / `--mm:orc` when transferring GC-managed `string` payloads
## across worker threads inside `allocShared0` blocks.
##
## Every type `T` stored in `SharedQueue[T]` MUST be a plain value object with
## no Nim `string`, `seq`, `ref`, or `{.closure.}` fields. Strings cross thread
## boundaries exclusively as `SharedBytes` (`allocShared` UTF-8 buffers) and are
## materialized onto the receiving thread's heap via `takeSharedString`.

import std/locks

type
  SharedBytes* = object
    data*: ptr UncheckedArray[char]
    len*: int

  SharedQueue*[T] = object
    lock: Lock
    cond: Cond
    buf: ptr UncheckedArray[T]
    cap: int
    head: int
    count: int
    closed: bool

proc toSharedBytes*(s: string): SharedBytes {.inline.} =
  if s.len <= 0:
    return SharedBytes(data: nil, len: 0)
  let p = cast[ptr UncheckedArray[char]](allocShared(s.len))
  copyMem(p, unsafeAddr s[0], s.len)
  SharedBytes(data: p, len: s.len)

proc fromSharedBytes*(b: SharedBytes): string {.inline.} =
  if b.data == nil or b.len <= 0:
    return ""
  result = newString(b.len)
  copyMem(addr result[0], b.data, b.len)

proc freeSharedBytes*(b: var SharedBytes) {.inline.} =
  if b.data != nil:
    deallocShared(b.data)
    b.data = nil
  b.len = 0

proc takeSharedString*(b: var SharedBytes): string {.inline.} =
  result = fromSharedBytes(b)
  freeSharedBytes(b)

proc initSharedQueue*[T](q: var SharedQueue[T], initialCap: int = 32) =
  let c = max(4, initialCap)
  initLock(q.lock)
  initCond(q.cond)
  q.buf = cast[ptr UncheckedArray[T]](allocShared0(c * sizeof(T)))
  q.cap = c
  q.head = 0
  q.count = 0
  q.closed = false

proc growLocked[T](q: var SharedQueue[T]) =
  let nextCap = max(8, q.cap * 2)
  let nextBuf = cast[ptr UncheckedArray[T]](allocShared0(nextCap * sizeof(T)))
  for i in 0 ..< q.count:
    let idx = (q.head + i) mod q.cap
    nextBuf[i] = q.buf[idx]
  if q.buf != nil:
    deallocShared(q.buf)
  q.buf = nextBuf
  q.cap = nextCap
  q.head = 0

proc send*[T](q: var SharedQueue[T], item: T): bool {.discardable.} =
  acquire(q.lock)
  if q.closed:
    release(q.lock)
    return false
  if q.count >= q.cap:
    growLocked(q)
  let idx = (q.head + q.count) mod q.cap
  q.buf[idx] = item
  inc q.count
  signal(q.cond)
  release(q.lock)
  true

proc tryRecv*[T](q: var SharedQueue[T], outItem: var T): bool =
  acquire(q.lock)
  if q.count <= 0:
    release(q.lock)
    return false
  outItem = q.buf[q.head]
  zeroMem(addr q.buf[q.head], sizeof(T))
  q.head = (q.head + 1) mod q.cap
  dec q.count
  release(q.lock)
  true

proc recv*[T](q: var SharedQueue[T], outItem: var T): bool =
  acquire(q.lock)
  while q.count <= 0 and not q.closed:
    wait(q.cond, q.lock)
  if q.count <= 0:
    release(q.lock)
    return false
  outItem = q.buf[q.head]
  zeroMem(addr q.buf[q.head], sizeof(T))
  q.head = (q.head + 1) mod q.cap
  dec q.count
  release(q.lock)
  true

proc closeSharedQueue*[T](q: var SharedQueue[T]) =
  acquire(q.lock)
  q.closed = true
  broadcast(q.cond)
  release(q.lock)

proc deinitSharedQueue*[T](q: var SharedQueue[T],
                           freeElem: proc(item: var T) {.nimcall, gcsafe.} = nil) =
  acquire(q.lock)
  if freeElem != nil and q.buf != nil:
    for i in 0 ..< q.count:
      let idx = (q.head + i) mod q.cap
      freeElem(q.buf[idx])
  if q.buf != nil:
    deallocShared(q.buf)
    q.buf = nil
  q.cap = 0
  q.head = 0
  q.count = 0
  q.closed = true
  release(q.lock)
  deinitCond(q.cond)
  deinitLock(q.lock)
