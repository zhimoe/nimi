import std/[math, os, unittest]

import nimi/ui
import nimi/render/cairo
import nimi/text/measure

when defined(linux):
  suite "linux cairo render":
    test "offscreen pixels keep scene coordinates":
      var scene = Scene(width: 120, height: 80, clear: rgb(0.1, 0.2, 0.3))
      scene.rect(Rect(x: 10, y: 10, w: 40, h: 20), rgb(1, 0, 0))
      let pixels = renderSceneToPixels(scene)
      check pixels.width == 120
      check pixels.height == 80
      # Clear color, straight alpha.
      check abs(int(pixels.pixels[0]) - 26) <= 3
      check abs(int(pixels.pixels[1]) - 51) <= 3
      check abs(int(pixels.pixels[2]) - 76) <= 3
      # Interior of the red rectangle.
      let offset = (15 * 120 + 20) * 4
      check pixels.pixels[offset] > 240
      check pixels.pixels[offset + 1] < 8
      check pixels.pixels[offset + 2] < 8
      # Outside remains the clear color.
      let outside = (60 * 120 + 100) * 4
      check pixels.pixels[outside + 1] < 80

    test "clips and rounded rectangles render":
      var scene = Scene(width: 100, height: 60, clear: rgb(0, 0, 0))
      scene.clip(Rect(x: 10, y: 10, w: 30, h: 30))
      scene.rect(Rect(x: 0, y: 0, w: 100, h: 60), rgb(0, 1, 0))
      scene.restoreClip()
      scene.rect(Rect(x: 60, y: 10, w: 20, h: 20), rgb(1, 1, 1), 6)
      let pixels = renderSceneToPixels(scene)
      # Inside clip is green.
      var green = ((15 * 100) + 15) * 4
      check pixels.pixels[green] < 8
      check pixels.pixels[green + 1] > 240
      # Outside clip stays black.
      var black = ((5 * 100) + 5) * 4
      check pixels.pixels[black + 1] < 8
      # Rounded rectangle center is white.
      var white = ((20 * 100) + 70) * 4
      check pixels.pixels[white] > 240

    test "pango text metrics and drawing":
      let metrics = measureText("Héllo 世界", 16, false)
      check metrics.width > 30
      check metrics.height > 10
      check metrics.ascent > 0
      var scene = Scene(width: 160, height: 60, clear: rgb(1, 1, 1))
      scene.text("Hello", 8, 8, 20, rgb(0, 0, 0))
      let pixels = renderSceneToPixels(scene)
      var dark = 0
      for i in 0 ..< pixels.width * pixels.height:
        if pixels.pixels[i * 4] < 100:
          inc dark
      check dark > 20

    test "png output":
      var scene = Scene(width: 80, height: 60, clear: rgb(0.95, 0.95, 0.95))
      scene.rect(Rect(x: 10, y: 10, w: 30, h: 20), rgb(0.2, 0.4, 0.9), 4)
      let path = "/tmp/nimi_linux_render.png"
      if fileExists(path):
        removeFile(path)
      check renderSceneToPng(scene, path)
      check fileExists(path)
      check getFileSize(path) > 100

    test "image quad preserves source orientation":
      var source = newSeq[uint8](4 * 4 * 4)
      for y in 0 ..< 4:
        for x in 0 ..< 4:
          let offset = (y * 4 + x) * 4
          if x < 2:
            source[offset] = 255
            source[offset + 3] = 255
          else:
            source[offset + 2] = 255
            source[offset + 3] = 255
      let sourcePath = "/tmp/nimi_linux_quad_source.png"
      check writeRgbaPng(source, 4, 4, sourcePath)
      var scene = Scene(width: 100, height: 100, clear: rgb(0, 0, 0))
      scene.imageQuad(sourcePath, Rect(x: 0, y: 0, w: 4, h: 4),
        [Point(x: 10, y: 10), Point(x: 90, y: 10),
         Point(x: 90, y: 90), Point(x: 10, y: 90)])
      let frame = renderSceneToPixels(scene)
      let left = (50 * 100 + 30) * 4
      let right = (50 * 100 + 70) * 4
      check frame.pixels[left] > 200 and frame.pixels[left + 2] < 50
      check frame.pixels[right + 2] > 200 and frame.pixels[right] < 50

    test "image drawing and image quad":
      let icon = "examples/notes/resources/icon.png"
      if fileExists(icon):
        var scene = Scene(width: 100, height: 100, clear: rgb(0, 0, 0))
        scene.image(icon, Rect(x: 4, y: 4, w: 48, h: 48))
        var quad = Scene(width: 100, height: 100, clear: rgb(0, 0, 0))
        quad.imageQuad(icon, Rect(x: 256, y: 256, w: 256, h: 256),
          [Point(x: 50, y: 4), Point(x: 96, y: 10),
           Point(x: 90, y: 60), Point(x: 52, y: 54)])
        let first = renderSceneToPixels(scene)
        let second = renderSceneToPixels(quad)
        var painted = 0
        for i in 0 ..< 100 * 100:
          if first.pixels[i * 4] > 10 or first.pixels[i * 4 + 1] > 10 or
              first.pixels[i * 4 + 2] > 10:
            inc painted
        check painted > 100
        var quadPainted = 0
        for i in 0 ..< 100 * 100:
          if second.pixels[i * 4] > 10 or second.pixels[i * 4 + 1] > 10 or
              second.pixels[i * 4 + 2] > 10:
            inc quadPainted
        check quadPainted > 100
else:
  suite "linux cairo render":
    test "requires Linux":
      check true
