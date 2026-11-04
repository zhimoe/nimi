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
