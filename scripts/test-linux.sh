#!/bin/sh
# Linux regression suite. Without a display it re-executes itself under
# xvfb-run + dbus-run-session when those tools are available.
set -eu
cd "$(dirname "$0")/.."
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] &&
    command -v xvfb-run >/dev/null 2>&1 &&
    command -v dbus-run-session >/dev/null 2>&1; then
  exec xvfb-run -a dbus-run-session -- "$0" "$@"
fi
NIM="${NIM:-nim}"

tests="
test_windows_input
test_windows_menu_plan
test_menu_callbacks
test_platform_contract
test_cli_windows
test_environment
test_environment_model
test_environment_storage
test_environment_app
test_environment_ui
test_ipc
test_ipc_pool
test_loop
test_unicode
test_ui
test_layout_legacy
test_ui_layout
test_ui_widgets
test_ime
test_render
test_desktop
test_fileserver
test_document
test_shred
test_audio
test_queue
test_music_session
test_virtual_list
test_tasks
test_lyrics
test_linux_render
test_linux_backend
test_linux_app
test_linux_webview
test_linux_mpris
test_linux_instance
"

failed=""
for test in $tests; do
  echo "=== $test ==="
  if ! "$NIM" c -r --hints:off --path:src -o:"/tmp/nimi_linux_$test" \
      "tests/$test.nim"; then
    failed="$failed $test"
  fi
done

"$NIM" c --hints:off --path:src -o:/tmp/nimi_test_subsonic tests/test_subsonic.nim
python3 tests/subsonic_fixture.py

if [ -n "$failed" ]; then
  echo "FAILED TESTS:$failed"
  exit 1
fi
