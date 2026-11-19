import std/[unittest, widestrs]
import nimi/platform/contract
import nimi/platform/windows/app

{.compile: "windows_input_fixture.c".}
proc findWindow(className, title: WideCString): pointer {.stdcall, importc: "FindWindowW", header: "<windows.h>".}
proc send(window: pointer, message: cuint, wp: uint, lp: int): int {.stdcall, importc: "SendMessageW", header: "<windows.h>".}
proc formatAvailable(format: cuint): cint {.stdcall, importc: "IsClipboardFormatAvailable", header: "<windows.h>".}
proc lockClipboard(): cint {.cdecl, importc: "test_lock_clipboard".}
proc unlockClipboard() {.cdecl, importc: "test_unlock_clipboard".}
proc badClipboard(window: pointer): cint {.cdecl, importc: "test_bad_clipboard".}
proc startDialog(button: WideCString): cint {.cdecl, importc: "test_start_dialog".}
proc stopDialog(): cint {.cdecl, importc: "test_stop_dialog".}
proc scrollAtClientOrigin(window: pointer, message: cuint, delta: cint, modifiers: cuint): cint
  {.cdecl, importc: "test_scroll_at_client_origin".}

suite "Win32 native input boundaries":
  test "wheel and tilt route to the correct scroll axis in client coordinates":
    let backend = newWindowsBackend()
    backend.init(AppHandler(), AppOptions())
    defer: backend.shutdown()
    var vertical, horizontal: seq[float32]
    var allowHorizontal = true
    let title = newWideCString("Nimi wheel test")
    let window = backend.newWindow(PlatformWindowOptions(title: $title, width: 240, height: 160),
      WindowHandler(windowId: 74, surface: SurfaceHandler(
        scroll: (proc(x, y, delta: float32) =
          check x == 0 and y == 0
          vertical.add delta),
        scrollHorizontal: (proc(x, y, delta: float32): bool =
          check x == 0 and y == 0
          if allowHorizontal: horizontal.add delta
          allowHorizontal))))
    defer: window.destroy()
    let handle = findWindow(nil, title)
    require handle != nil
    check scrollAtClientOrigin(handle, 0x020a, -120, 0) != 0
    check scrollAtClientOrigin(handle, 0x020a, 120, 4) != 0 # MK_SHIFT
    check scrollAtClientOrigin(handle, 0x020e, 60, 0) != 0
    allowHorizontal = false
    check scrollAtClientOrigin(handle, 0x020a, -60, 4) != 0
    check vertical == @[40'f32, 20'f32]
    check horizontal == @[-40'f32, 20'f32]

  test "IME messages suppress duplicate text, cancellation and UTF-16 routing":
    let backend = newWindowsBackend()
    backend.init(AppHandler(), AppOptions())
    defer: backend.shutdown()
    var inserted, keys: seq[string]
    var unmarked, cancelled = 0
    let window = backend.newWindow(PlatformWindowOptions(title: "Nimi native input test",
      width: 320, height: 200, ime: true), WindowHandler(windowId: 71,
      surface: SurfaceHandler(
        insertText: (proc(text: string, replacement: TextRange) = inserted.add text),
        keyDown: (proc(key: string, mods: uint32) = keys.add key),
        unmarkText: (proc() = inc unmarked),
        textInputActive: (proc(): bool = true),
        cancelInput: (proc(composition: bool) =
          if composition: inc cancelled),
        caretRect: (proc(): PlatformRect = PlatformRect(x: 20, y: 30, w: 2, h: 18)))))
    let hwnd = findWindow(nil, newWideCString("Nimi native input test"))
    check hwnd != nil
    discard send(hwnd, 0x010d, 0, 0) # STARTCOMPOSITION
    discard send(hwnd, 0x0100, 32, 1) # Candidate-space must not edit the document.
    discard send(hwnd, 0x0102, 65, 1)
    discard send(hwnd, 0x0286, 0x4e2d, 1) # IME_CHAR is suppressed for custom IME.
    check inserted.len == 0
    check keys.len == 0
    discard send(hwnd, 0x010f, 0, 0) # Cancel with no GCS flags.
    discard send(hwnd, 0x010e, 0, 0)
    check unmarked >= 2
    discard send(hwnd, 0x0102, 0xd83d, 1)
    discard send(hwnd, 0x0102, 0xde00, 1)
    check inserted == @["😀"]
    check send(hwnd, 0x0109, 0xffff, 0) == 1 # UNICODE_NOCHAR capability query.
    discard send(hwnd, 0x0109, 0x1f642, 1)
    discard send(hwnd, 0x0109, 32, 1)
    check inserted == @["😀", "🙂", " "]
    discard send(hwnd, 0x0100, 32, 1)
    discard send(hwnd, 0x0102, 32, 1)
    check inserted == @["😀", "🙂", " ", " "]
    check keys.len == 0
    discard send(hwnd, 0x0102, 0xd83d, 1)
    discard send(hwnd, 0x0008, 0, 0)
    discard send(hwnd, 0x0102, 66, 1)
    check inserted[^1] == "B"
    check cancelled >= 1
    discard send(hwnd, 0x0100, 33, 1)
    discard send(hwnd, 0x0100, 112, 1)
    check keys == @["pageup", "f1"]
    window.destroy()

  test "clipboard distinguishes absent text, invalid data and contention":
    let backend = newWindowsBackend()
    expect ClipboardError: discard backend.clipboard.readText()
    backend.init(AppHandler(), AppOptions())
    defer: backend.shutdown()
    let window = backend.newWindow(PlatformWindowOptions(title: "Nimi clipboard test",
      width: 200, height: 120), WindowHandler(windowId: 72))
    let hwnd = findWindow(nil, newWideCString("Nimi clipboard test"))
    backend.clipboard.writeText("中文😀\r\ntext")
    check backend.clipboard.readText() == "中文😀\r\ntext"
    expect ClipboardError: backend.clipboard.writeText("bad\0text")
    expect ClipboardError: backend.clipboard.writeText("\xff")
    check backend.clipboard.readText() == "中文😀\r\ntext"
    check lockClipboard() != 0
    try:
      expect ClipboardError: discard backend.clipboard.readText()
      expect ClipboardError: backend.clipboard.writeText("blocked")
      expect ClipboardError: backend.clipboard.clear()
    finally: unlockClipboard()
    check backend.clipboard.readText() == "中文😀\r\ntext"
    check badClipboard(hwnd) != 0
    # Windows may zero-pad or normalize an unterminated CF_UNICODETEXT
    # handle. Require a safe read (no crash, no stale value) rather than a
    # particular raise/return split.
    try:
      let bad = backend.clipboard.readText()
      check bad != "中文😀\r\ntext"
    except ClipboardError:
      discard
    backend.clipboard.clear()
    check backend.clipboard.readText() == ""
    check formatAvailable(13) == 0
    backend.clipboard.writeText("")
    check backend.clipboard.readText() == ""
    check formatAvailable(13) != 0
    let html = "<strong>中文😀</strong>"
    backend.clipboard.writeHTML(html)
    check backend.clipboard.readHTML() == html
    check backend.clipboard.readText() == ""
    expect ClipboardError: backend.clipboard.writeHTML("\xff")
    check backend.clipboard.readHTML() == html
    check lockClipboard() != 0
    try:
      expect ClipboardError: discard backend.clipboard.readHTML()
      expect ClipboardError: backend.clipboard.writeHTML("blocked")
    finally: unlockClipboard()
    backend.clipboard.clear()
    check backend.clipboard.readHTML() == ""
    window.destroy()

  test "message dialog returns Unicode button index or cancellation":
    let backend = newWindowsBackend()
    backend.init(AppHandler(), AppOptions())
    defer: backend.shutdown()
    let window = backend.newWindow(PlatformWindowOptions(title: "Nimi dialog owner",
      width: 200, height: 120), WindowHandler(windowId: 73))
    defer: window.destroy()
    let label = newWideCString("放弃修改")
    let buttons = @["保存", "稍后", "放弃修改"]
    check startDialog(label) != 0
    try:
      check backend.dialogs.messageWith("Nimi custom dialog test", "请选择", buttons) == 2
    finally:
      check stopDialog() != 0
    check startDialog(nil) != 0
    try:
      check backend.dialogs.messageWith("Nimi custom dialog test", "请选择", buttons) == -1
    finally:
      check stopDialog() != 0
