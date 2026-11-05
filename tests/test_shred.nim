import std/[math, unittest]

import nimi/effects/shred

suite "shred simulation":
  test "feeds strips through the slot":
    let sim = newShredSim()
    check sim.strips.len == 36
    for _ in 0 ..< 18:
      sim.step(sim.config.step)
    check sim.strips[0].nodes.len > 0
    check sim.strips[^1].nodes.len > 0
    let segH = sim.config.height / float32(sim.config.segments)
    for i in 0 ..< sim.config.count:
      let nodes = sim.strips[i].nodes
      check nodes.len <= sim.config.segments + 1
      for k in 1 ..< nodes.len:
        let d = hypot(nodes[k].x - nodes[k - 1].x,
                      nodes[k].y - nodes[k - 1].y)
        check d > segH * 0.2
        check d < segH * 3.0
        check nodes[k].x == nodes[k].x
        check nodes[k].y == nodes[k].y

  test "advance uses fixed steps and reset clears state":
    let sim = newShredSim()
    check sim.advance(0.25) in 29 .. 30
    check sim.strips[0].nodes.len > 0
    let before = sim.strips[0].nodes.len
    discard sim.advance(0.5)
    check sim.strips[0].nodes.len >= before
    sim.reset()
    check sim.elapsed == 0
    check sim.strips[0].nodes.len == 0

  test "wind field is finite and time-varying":
    let a = windAt(10, 20, 1)
    let b = windAt(10, 20, 2)
    check a.x == a.x and a.y == a.y
    check b.x == b.x and b.y == b.y
    check a != b
