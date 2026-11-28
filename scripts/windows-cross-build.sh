#!/bin/sh
# Cross-compile Windows smoke tests with Nim and Zig; does not run them.
set -eu
cd "$(dirname "$0")/.."
command -v zig >/dev/null
case "${1:-amd64}" in
  amd64) cpu=amd64; target=x86_64-windows-gnu; loader=x64; output=dist/windows-tests ;;
  arm64) cpu=arm64; target=aarch64-windows-gnu; loader=arm64; output=dist/windows-tests-arm64 ;;
  *) echo "usage: $0 [amd64|arm64]" >&2; exit 2 ;;
esac
compiler_dir=$(mktemp -d)
trap 'rm -rf "$compiler_dir"' EXIT HUP INT TERM
cat > "$compiler_dir/cc" <<WRAPPER
#!/bin/sh
exec zig cc -target "$target" "\$@"
WRAPPER
chmod +x "$compiler_dir/cc"
mkdir -p "$output"
cp "src/nimi/platform/windows/webview2/sdk/$loader/WebView2Loader.dll" "$output/"
for test in test_windows_input test_windows_input_native test_windows_menu_plan test_menu_callbacks test_windows_menu test_platform_contract test_cli_windows test_host_foundation test_environment test_environment_model test_environment_storage test_environment_app test_environment_ui test_environment_app_windows test_environment_windows test_windows_host test_windows_surface test_windows_webview test_windows_webview_protocol test_windows_desktop test_windows_animation test_windows_render test_layout_legacy test_ui test_ui_layout test_ui_widgets; do
  nim c --os:windows --cpu:"$cpu" --cc:clang \
    --clang.exe:"$compiler_dir/cc" --clang.linkerexe:"$compiler_dir/cc" \
    --nimcache:"$output/nimcache/$test" --hints:off -o:"$output/$test.exe" "tests/$test.nim"
done
nim c --os:windows --cpu:"$cpu" --cc:clang --passL:-Wl,--subsystem,windows \
  --clang.exe:"$compiler_dir/cc" --clang.linkerexe:"$compiler_dir/cc" \
  --nimcache:"$output/nimcache/environment" --hints:off \
  -o:"$output/NimiEnvironment.exe" examples/environment/main.nim
nim c --os:windows --cpu:"$cpu" --cc:clang \
  --clang.exe:"$compiler_dir/cc" --clang.linkerexe:"$compiler_dir/cc" \
  --nimcache:"$output/nimcache/nimi" --hints:off -o:"$output/nimi.exe" src/nimi/cli.nim
