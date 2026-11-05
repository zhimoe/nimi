## Native paper-shredding demo. The Verlet simulation lives in
## `effects/shred`; the scene renderer samples the card image through textured
## quads. The frame loop is driven by the native animation timer.
##
##   nim c -r --path:src examples/shred-native/main.nim
##   NIMI_SMOKE=shred NIMI_SNAPSHOT=/tmp/nimi-shred-native.png \
##     nim c -r --path:src examples/shred-native/main.nim

import std/[math, os]

import nimi
import nimi/ui
import nimi/render/cg
import nimi/text/measure

const
  PaperW = 260.0'f32
  PaperH = 190.0'f32
  SegmentCount = 24

type
  State = ref object
    sim: ShredSim
    paperPath: string
    win: Window
    liveFrames: int

proc makePaper(path: string) =
  var s = Scene(width: PaperW, height: PaperH, clear: rgb(1, 1, 1))
  let label = "Hello, Nimi"
  let m = measureText(label, 22, true)
  s.text(label, (PaperW - m.width) / 2, (PaperH - m.height) / 2,
         22, rgb(0.13, 0.13, 0.15), true)
  discard renderSceneToPng(s, path)

proc reset(s: State) =
  s.sim.reset()

proc buildScene(s: State, width, height: float32): Scene =
  result = Scene(width: width, height: height, clear: rgb(0.125, 0.125, 0.125))
  let slot = height * 0.49
  let stageX = width / 2
  let paperX = stageX - PaperW / 2
  let top = min(slot, slot + s.sim.top())
  let cfg = s.sim.config
  let stripW = cfg.width / float32(cfg.count)
  let segH = cfg.height / float32(cfg.segments)

  # The part of the sheet that has not entered the slot yet.
  result.clip(Rect(x: 0, y: 0, w: width, h: slot))
  result.image(s.paperPath, Rect(x: paperX, y: top, w: PaperW, h: PaperH))
  result.restoreClip()

  # Textured paper strips below the slot. Each segment is a quad with shared
  # edge vertices, so the text is sampled continuously.
  result.clip(Rect(x: 0, y: slot, w: width, h: height - slot))
  for i in 0 ..< cfg.count:
    let nodes = s.sim.strips[i].nodes
    if nodes.len < 2:
      continue
    let half = stripW * 0.46
    var left = newSeq[Point](nodes.len)
    var right = newSeq[Point](nodes.len)
    for k in 0 ..< nodes.len:
      let before = nodes[max(0, k - 1)]
      let after = nodes[min(nodes.len - 1, k + 1)]
      var tx = after.x - before.x
      var ty = after.y - before.y
      let tl = max(0.0001'f32, hypot(tx, ty))
      tx /= tl
      ty /= tl
      left[k] = Point(x: paperX + nodes[k].x - ty * half,
                      y: slot + nodes[k].y + tx * half)
      right[k] = Point(x: paperX + nodes[k].x + ty * half,
                       y: slot + nodes[k].y - tx * half)
    # A white ribbon base hides the antialiased seams between the two
    # textured triangles used by the CPU renderer.
    var base = newSeq[Point](nodes.len * 2)
    for k in 0 ..< nodes.len:
      base[k] = left[k]
      base[base.len - 1 - k] = right[k]
    result.polygon(base, rgb(1, 1, 1))
    for k in 0 ..< nodes.len - 1:
      let sx = float32(i) * stripW
      let sy = float32(SegmentCount - 1 - k) * segH
      let src = Rect(x: sx, y: sy, w: stripW, h: segH)
      result.imageQuad(s.paperPath, src, [
        left[k + 1],
        right[k + 1],
        right[k],
        left[k],
      ])
  result.restoreClip()

  # Slot hardware.
  let slotW = PaperW + 110
  let sx = stageX - slotW / 2
  result.rect(Rect(x: sx, y: slot - 10, w: slotW, h: 20),
              rgb(0.333, 0.333, 0.333), 10)
  result.rect(Rect(x: sx + 14, y: slot - 2, w: slotW - 28, h: 4),
              rgb(0.067, 0.067, 0.067), 2)

let state = State(
  sim: newShredSim(),
  paperPath: getEnv("NIMI_SHRED_PAPER", getTempDir() / "nimi-shred-paper.png")
)
makePaper(state.paperPath)

proc view(s: State, c: Context) =
  c.scene = buildScene(s, c.width, c.height)
  let root = column(c).fill()
  root.onClick = proc() = reset(s)

let content = uiView(proc(c: Context) = view(state, c))
app.name = "Nimi Shred Native"
app.version = "0.1.0"

app.whenReady(proc() =
  let w = newWindow(WindowOptions(
    title: "Nimi Shred Native",
    width: 900,
    height: 720,
    content: content
  ))
  state.win = w
  w.startAnimation(60, proc(time, dt: float64) =
    discard state.sim.advance(float32(min(dt, 0.12)))
    inc state.liveFrames
    if getEnv("NIMI_SMOKE") == "live" and state.liveFrames == 12:
      echo "native animation frames: ", state.liveFrames,
           " elapsed: ", state.sim.elapsed
      app.quit())
  w.invalidate()

  if getEnv("NIMI_SMOKE") == "shred":
    for _ in 0 ..< 160:
      state.sim.step(state.sim.config.step)
    let scene = buildScene(state, 900, 720)
    let snapshot = getEnv("NIMI_SNAPSHOT", "/tmp/nimi-shred-native.png")
    let ok = renderSceneToPng(scene, snapshot)
    echo "native shred png: ", ok, " path: ", snapshot
    echo "strips: ", state.sim.strips.len,
         " nodes: ", state.sim.strips[0].nodes.len
    app.quit()
)

app.run()
