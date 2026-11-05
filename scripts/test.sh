#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
nim c -r --hints:off --path:src -o:/tmp/nimi_test_ipc tests/test_ipc.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_loop tests/test_loop.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_ui tests/test_ui.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_render tests/test_render.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_desktop tests/test_desktop.nim
