import std/unittest

import nimi/core/[events, loop]
import nimi/platform/contract

suite "loop":
  test "postMain and drainMain":
    var seen = 0
    check postMain(proc() = inc seen)
    drainMain()
    check seen == 1

  test "onMain runs directly on the main thread":
    var seen = 0
    onMain(proc() = inc seen)
    check seen == 1

  test "postMain keeps FIFO order":
    var order: seq[int]
    proc addLater(value: int) =
      discard postMain(proc() = order.add value)
    for i in 0 ..< 3:
      addLater(i)
    drainMain()
    check order == @[0, 1, 2]

suite "events":
  test "emit and remove":
    let e = newEvent[int]("n")
    var seen: seq[int]
    let off = e.on(proc(v: int) = seen.add v)
    e.emit(1)
    e.emit(2)
    off()
    e.emit(3)
    check seen == @[1, 2]

suite "contract":
  test "a backend can be constructed":
    let b = Backend(name: "fake")
    check b.name == "fake"
