version       = "0.1.0"
author        = "Nimi contributors"
description   = "Desktop apps in Nim, with native UI or a web frontend."
license       = "MIT"
srcDir        = "src"
bin           = @[]

requires "nim >= 2.4.0"

task test, "Run the full unit test suite":
  exec "./scripts/test.sh"
