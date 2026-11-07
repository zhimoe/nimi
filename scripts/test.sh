#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
nim c -r --hints:off --path:src -o:/tmp/nimi_test_ipc tests/test_ipc.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_loop tests/test_loop.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_unicode tests/test_unicode.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_ui tests/test_ui.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_ime tests/test_ime.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_render tests/test_render.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_desktop tests/test_desktop.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_fileserver tests/test_fileserver.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_document tests/test_document.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_shred tests/test_shred.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_metal tests/test_metal.nim

nim c -r --hints:off --path:src -o:/tmp/nimi_test_audio tests/test_audio.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_queue tests/test_queue.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_music_session tests/test_music_session.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_virtual_list tests/test_virtual_list.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_tasks tests/test_tasks.nim
nim c -r --hints:off --path:src -o:/tmp/nimi_test_lyrics tests/test_lyrics.nim
nim c --hints:off --path:src -o:/tmp/nimi_test_subsonic tests/test_subsonic.nim
python3 tests/subsonic_fixture.py
