version       = "0.1.0"
author        = "Nimi contributors"
description   = "Desktop apps in Nim, with native UI or a web frontend."
license       = "MIT"
srcDir        = "src"
bin           = @[]

requires "nim >= 2.4.0"

task test, "Run the M1 unit tests":
  exec "nim c -r --hints:off --path:src -o:/tmp/nimi_test_ipc tests/test_ipc.nim"
  exec "nim c -r --hints:off --path:src -o:/tmp/nimi_test_loop tests/test_loop.nim"
  exec "nim c -r --hints:off --path:src -o:/tmp/nimi_test_ui tests/test_ui.nim"
  exec "nim c -r --hints:off --path:src -o:/tmp/nimi_test_render tests/test_render.nim"
