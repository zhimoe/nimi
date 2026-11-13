#!/bin/sh
# Cross-compile Windows smoke tests with Nim and Zig; does not run them.
set -eu
cd "$(dirname "$0")/.."
command -v zig >/dev/null
compiler_dir=$(mktemp -d)
trap 'rm -rf "$compiler_dir"' EXIT HUP INT TERM
cat > "$compiler_dir/cc" <<'WRAPPER'
#!/bin/sh
exec zig cc -target x86_64-windows-gnu "$@"
WRAPPER
chmod +x "$compiler_dir/cc"
mkdir -p dist/windows-tests
for test in test_windows_input test_windows_input_native test_windows_menu_plan test_menu_callbacks test_windows_menu test_platform_contract test_environment test_environment_editor test_environment_ui test_environment_app_windows test_environment_windows test_windows_host test_windows_surface; do
  nim c --os:windows --cpu:amd64 --cc:clang \
    --clang.exe:"$compiler_dir/cc" --clang.linkerexe:"$compiler_dir/cc" \
    --hints:off -o:"dist/windows-tests/$test.exe" "tests/$test.nim"
done
nim c --os:windows --cpu:amd64 --cc:clang --passL:-Wl,--subsystem,windows \
  --clang.exe:"$compiler_dir/cc" --clang.linkerexe:"$compiler_dir/cc" \
  --hints:off -o:dist/windows-tests/NimiEnvironment.exe examples/environment/main.nim
