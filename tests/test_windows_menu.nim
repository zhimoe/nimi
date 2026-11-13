import std/unittest
import nimi/platform/contract
import nimi/platform/windows/app

suite "Win32 native menus":
  test "per-window menus, native accelerators, roles and replacement":
    let backend = newWindowsBackend()
    var custom, copied, closed = 0
    let menu = PlatformMenu(items: @[
      PlatformMenuItem(label: "File", kind: pmiSubmenu, enabled: true, submenu: @[
        PlatformMenuItem(label: "Action", enabled: true, id: 70000, accelerator: "ctrl+k"),
        PlatformMenuItem(label: "Copy", enabled: true, role: "copy", accelerator: "ctrl+c"),
        PlatformMenuItem(label: "Close", enabled: true, role: "close", accelerator: "ctrl+w")])])
    backend.init(AppHandler(ready: proc() =
      let first = backend.newWindow(PlatformWindowOptions(title: "First", width: 400, height: 300),
        WindowHandler(windowId: 10, surface: SurfaceHandler(copy: proc() = inc copied),
          closed: proc(id: uint64) = inc closed))
      let before = clientSizeDip(10)
      backend.setMenu(menu, MenuHandler(select: proc(id: uint32) =
        check id == 70000
        inc custom))
      let after = clientSizeDip(10)
      check abs(before.x - after.x) <= 1
      check abs(before.y - after.y) <= 1
      let second = backend.newWindow(PlatformWindowOptions(title: "Second", width: 400, height: 300),
        WindowHandler(windowId: 11, closed: proc(id: uint64) = inc closed))
      first.testMenuKey(ord('K'), KeyControl)
      second.testMenuKey(ord('K'), KeyControl)
      check custom == 2
      first.testMenuKey(ord('C'), KeyControl)
      check copied == 1
      var disabled = menu
      disabled.items[0].enabled = false
      backend.setMenu(disabled, MenuHandler(select: proc(id: uint32) = custom += 100))
      first.testMenuKey(ord('K'), KeyControl)
      check custom == 2
      backend.setMenu(menu, MenuHandler(select: proc(id: uint32) = custom += 10))
      second.testMenuKey(ord('K'), KeyControl)
      check custom == 12
      first.testMenuKey(ord('W'), KeyControl)
      check closed == 1
      second.testMenuKey(ord('W'), KeyControl)
      check closed == 2
      backend.quit()), AppOptions())
    backend.run()
