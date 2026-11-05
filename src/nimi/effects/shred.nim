## Paper-shredding simulation, ported from MyGo's Verlet strip model.
##
## This is renderer-independent: a native scene/Metal renderer or a WebView
## canvas can consume `ShredSim.strips`. Coordinates are in a local paper
## space; x spans 0..width, y is measured downward from the slot.

import std/math

type
  ShredPoint* = object
    x*, y*: float32
    px*, py*: float32

  ShredStrip* = object
    nodes*: seq[ShredPoint]
    center*: float32

  ShredConfig* = object
    width*: float32
    height*: float32
    lead*: float32
    speed*: float32
    count*: int
    segments*: int
    gravity*: float32
    damping*: float32
    step*: float32

  ShredSim* = ref object
    config*: ShredConfig
    strips*: seq[ShredStrip]
    elapsed*: float32
    lag*: float32

proc defaultShredConfig*(): ShredConfig =
  ShredConfig(
    width: 260.0,
    height: 190.0,
    lead: 24.0,
    speed: 175.0,
    count: 36,
    segments: 24,
    gravity: 700.0,
    damping: 0.994,
    step: 1.0 / 120.0,
  )

proc newShredSim*(config = defaultShredConfig()): ShredSim =
  result = ShredSim(config: config)
  result.strips.setLen(config.count)
  for i in 0 ..< config.count:
    result.strips[i].center =
      (float32(i) + 0.5) * config.width / float32(config.count)

proc reset*(sim: ShredSim) =
  for strip in sim.strips.mitems:
    strip.nodes.setLen(0)
  sim.elapsed = 0
  sim.lag = 0

proc top*(sim: ShredSim): float32 =
  -sim.config.height - sim.config.lead + sim.config.speed * sim.elapsed

proc windAt*(x, y, t: float32): tuple[x, y: float32] =
  result.x = 280.0 * sin(t * 1.8) +
    180.0 * sin(y * 0.018 - t * 2.4) +
    70.0 * sin(x * 0.025 + t * 3.1) +
    58.0 * sin(x * 0.23 + t * 4.6)
  result.y = 85.0 * sin(x * 0.018 + y * 0.009 + t * 2.2)

proc constrainAnchor(n: var ShredPoint, x, length: float32) =
  let dx = n.x - x
  let dy = n.y
  let d = hypot(dx, dy)
  if d < 0.0001:
    n.x = x
    n.y = length
  else:
    n.x = x + dx * length / d
    n.y = dy * length / d

proc constrainPair(a, b: var ShredPoint, length: float32) =
  var dx = b.x - a.x
  var dy = b.y - a.y
  var d = hypot(dx, dy)
  if d < 0.0001:
    dx = 0
    dy = 1
    d = 1
  let correction = (d - length) / (2 * d)
  a.x += dx * correction
  a.y += dy * correction
  b.x -= dx * correction
  b.y -= dy * correction

proc step*(sim: ShredSim, dt: float32) =
  ## Advance one fixed physics step. Callers normally use `advance`.
  let c = sim.config
  if c.count <= 0 or c.segments <= 0 or dt <= 0:
    return
  sim.elapsed += dt
  let top = sim.top()
  let attached = top < 0
  let segH = c.height / float32(c.segments)
  for i in 0 ..< c.count:
    let strip = addr sim.strips[i]
    let center = strip.center
    while strip.nodes.len < c.segments + 1 and
        top + c.height - float32(strip.nodes.len) * segH >= 0:
      let flutter = sin(float32(i) * 1.71 +
                        float32(strip.nodes.len) * 0.53) * 30.0
      strip.nodes.add ShredPoint(
        x: center,
        y: 0,
        px: center - flutter * dt,
        py: -c.speed * dt,
      )
    for n in strip.nodes.mitems:
      let vx = (n.x - n.px) * c.damping
      let vy = (n.y - n.py) * c.damping
      n.px = n.x
      n.py = n.y
      var wind = windAt(n.x, n.y, sim.elapsed)
      if not attached:
        wind.x += sin(sim.elapsed * 3.1 + float32(i) * 0.9) * 160.0 +
          sin(sim.elapsed * 7.7 + float32(i) * 2.3) * 55.0
      n.x += vx + wind.x * dt * dt
      n.y += vy + (c.gravity + wind.y) * dt * dt
    for pass in 0 ..< 7:
      if attached and strip.nodes.len > 0:
        let tail = min(segH, max(0.0,
          top + c.height - float32(strip.nodes.len - 1) * segH))
        constrainAnchor(strip.nodes[^1], center, tail)
      for k in countdown(strip.nodes.len - 1, 1):
        constrainPair(strip.nodes[k], strip.nodes[k - 1], segH)

proc advance*(sim: ShredSim, dt: float32): int =
  ## Accumulate wall-clock time and run fixed 120 Hz substeps.
  if dt > 0:
    sim.lag += dt
  while sim.lag >= sim.config.step:
    sim.step(sim.config.step)
    sim.lag -= sim.config.step
    inc result
