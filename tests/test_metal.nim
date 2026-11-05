import std/[os, unittest]

import nimi/ui
import nimi/effects/shred
import nimi/render/[cg, metal]

suite "metal layer effect":
  test "mask texture and layer effect produce a non-empty frame":
    var paper = Scene(width: 260, height: 190, clear: rgb(1, 1, 1))
    paper.text("Hello, Nimi", 76, 82, 22, rgb(0.13, 0.13, 0.15), true)
    let px = renderSceneToPixels(paper)
    let m = newMetalShred(px.pixels, px.width, px.height)
    if not m.ok:
      echo "metal unavailable: ", m.error
      check true
    else:
      let sim = newShredSim()
      for _ in 0 ..< 160:
        sim.step(sim.config.step)
      let slot = 720.0'f32 * 0.49'f32
      let cardTop = min(slot, slot + sim.top())
      let frame = m.renderOffscreen(sim, 900, 720, slot, cardTop)
      check frame.len == 900 * 720 * 4
      var paperPixels = 0
      for i in 0 ..< 900 * 720:
        if frame[i * 4] > 180:
          inc paperPixels
      check paperPixels > 1000
      let path = "/tmp/nimi_test_metal.png"
      if fileExists(path):
        removeFile(path)
      check writeRgbaPng(frame, 900, 720, path)
      check fileExists(path)
      check getFileSize(path) > 100
      m.close()
      check not m.ok
