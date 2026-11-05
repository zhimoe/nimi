import std/[os, unittest]

import nimi/ui
import nimi/render/cg

suite "render":
  test "offscreen png":
    var n = 3
    proc view(c: Context) =
      column(c).fill().center().gap(8).padding(12, 12).children(c, proc() =
        text(c, $n).fontSize(40).bold()
        button(c, "+", (proc() = inc n), key = "inc")
      )

    let t = newTester(view, 240, 180)
    discard t.render()
    let path = "/tmp/nimi_test_render.png"
    if fileExists(path):
      removeFile(path)
    check renderSceneToPng(t.scene, path)
    check fileExists(path)
    check getFileSize(path) > 100

  test "image png":
    let icon = "examples/notes/resources/icon.png"
    if fileExists(icon):
      proc view(c: Context) =
        column(c).fill().padding(12, 12).children(c, proc() =
          image(c, icon, 64, 64)
          text(c, "image")
        )

      let t = newTester(view, 160, 120)
      discard t.render()
      let path = "/tmp/nimi_test_image.png"
      if fileExists(path):
        removeFile(path)
      check renderSceneToPng(t.scene, path)
      check fileExists(path)
      check getFileSize(path) > 100

  test "image quad png":
    let icon = "examples/notes/resources/icon.png"
    if fileExists(icon):
      var s = Scene(width: 240, height: 180, clear: rgb(0.9, 0.9, 0.9))
      s.imageQuad(icon, Rect(x: 0, y: 0, w: 32, h: 32), [
        Point(x: 40, y: 30),
        Point(x: 180, y: 10),
        Point(x: 200, y: 150),
        Point(x: 30, y: 120),
      ])
      let path = "/tmp/nimi_test_image_quad.png"
      if fileExists(path):
        removeFile(path)
      check renderSceneToPng(s, path)
      check fileExists(path)
      check getFileSize(path) > 100

  test "wrapped text png":
    proc view(c: Context) =
      column(c).fill().padding(12, 12).children(c, proc() =
        text(c, "The quick brown fox jumps over the lazy dog. 你好世界,这是自动换行。").fontSize(16).wrap()
      )

    let t = newTester(view, 220, 160)
    discard t.render()
    let path = "/tmp/nimi_test_wrap.png"
    if fileExists(path):
      removeFile(path)
    check renderSceneToPng(t.scene, path)
    check fileExists(path)
    check getFileSize(path) > 100
