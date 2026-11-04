## Typed events. A page can subscribe once TS generation lands; for M1 the
## runtime is Nim-side only and is used by the bridge/tests.

import std/json

import ./ipc

type
  Listener[T] = object
    id: uint64
    fn: proc(payload: T) {.closure.}

  Event*[T] = ref object
    name*: string
    encode*: proc(payload: T): JsonNode {.closure.}
    nextId: uint64
    listeners: seq[Listener[T]]

proc newEvent*[T](name: string): Event[T] =
  Event[T](
    name: name,
    encode: proc(payload: T): JsonNode = encodeResult(payload))

proc on*[T](e: Event[T], fn: proc(payload: T)): proc() =
  ## Subscribe. The returned proc removes the listener.
  let id = e.nextId
  inc e.nextId
  e.listeners.add Listener[T](id: id, fn: fn)
  result = proc() =
    for i in 0 ..< e.listeners.len:
      if e.listeners[i].id == id:
        e.listeners.delete(i)
        break

proc emit*[T](e: Event[T], payload: T) =
  for l in e.listeners:
    l.fn(payload)
