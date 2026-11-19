import std/unittest
import nimi/platform/windows/menuplan

suite "Windows menu planning":
  test "native IDs preserve wide callback IDs and role routing":
    let plan = planMenu(PlatformMenu(items: @[
      PlatformMenuItem(label: "File", kind: pmiSubmenu, enabled: true, submenu: @[
        PlatformMenuItem(label: "打开", enabled: true, id: 100000, accelerator: "ctrl+o"),
        PlatformMenuItem(label: "Close", enabled: true, role: "close", accelerator: "cmd+w"),
        PlatformMenuItem(label: "Checked", kind: pmiCheckbox, checked: true, enabled: true, id: 8)])]))
    check plan.commands.len == 3
    check plan.commands[0].callbackId == 100000
    check plan.commands[1].role == "close"
    check plan.shortcuts[0].key == uint16(ord('O'))
    check plan.shortcuts[0].flags == 9
    check plan.shortcuts[1].flags == 9 # cmd is the portable Ctrl alias on Windows
    check plan.nodes[0].children[2].checked

  test "disabled parents disable commands and accelerators":
    let plan = planMenu(PlatformMenu(items: @[
      PlatformMenuItem(kind: pmiSubmenu, enabled: false, submenu: @[
        PlatformMenuItem(label: "Hidden action", enabled: true, id: 9, accelerator: "ctrl+x")])]))
    check not plan.commands[0].enabled
    check plan.shortcuts.len == 0

  test "invalid and ambiguous bindings fail before installing anything":
    for binding in ["ctrl", "ctrl+", "ctrl+a+b", "f25"]:
      expect BackendError: discard parseShortcut(binding)
    check parseShortcut("ctrl+shift+F12").key == 123
    check parseShortcut("alt+enter").flags == 17
    expect BackendError:
      discard planMenu(PlatformMenu(items: @[
        PlatformMenuItem(enabled: true, id: 1, accelerator: "ctrl+x"),
        PlatformMenuItem(enabled: true, id: 2, accelerator: "cmd+x")]))
    expect UnsupportedBackendError:
      discard planMenu(PlatformMenu(items: @[
        PlatformMenuItem(enabled: true, role: "hideOthers")]))
