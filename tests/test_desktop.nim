import std/unittest

import nimi/core/screen
import nimi/core/theme
import nimi/core/menu
import nimi/core/shortcut
import nimi/platform/contract
import nimi/scene/scene

var displayChanged: proc() {.closure.}
var themeChanged: proc() {.closure.}

proc fakeBackend(): Backend =
  result = Backend(name: "fake")
  result.screens = proc(): seq[PlatformDisplay] =
    @[
      PlatformDisplay(
        id: "0", name: "Built-in", x: 0, y: 0, width: 1440, height: 900,
        workX: 0, workY: 25, workWidth: 1440, workHeight: 850,
        scale: 2.0, primary: true),
      PlatformDisplay(
        id: "1", name: "External", x: 1440, y: 0, width: 1920, height: 1080,
        workX: 1440, workY: 0, workWidth: 1920, workHeight: 1080,
        scale: 1.0, primary: false),
    ]
  result.cursorPosition = proc(): PlatformPoint = PlatformPoint(x: 120, y: 80)
  result.themeInfo = proc(): PlatformTheme =
    PlatformTheme(dark: true, accentR: 0.25, accentG: 0.5, accentB: 0.75)
  result.onDisplayChanged = proc(cb: proc()) = displayChanged = cb
  result.onThemeChanged = proc(cb: proc()) = themeChanged = cb

suite "desktop":
  test "screens and primary display":
    currentBackend = fakeBackend()
    let all = screens()
    check all.len == 2
    check all[0].name == "Built-in"
    check all[0].scale == 2.0
    check all[1].primary == false
    let primary = primaryDisplay()
    check primary.name == "Built-in"
    check primary.workHeight == 850
    let cursor = cursorPosition()
    check cursor.x == 120
    check cursor.y == 80

  test "theme snapshot":
    currentBackend = fakeBackend()
    let t = themeInfo()
    check t.dark
    check t.accent.r == 0.25
    check t.accent.g == 0.5
    check t.accent.b == 0.75
    check isDark()

  test "global shortcut delegates":
    var registered = ""
    var unregistered = ""
    let b = fakeBackend()
    b.registerShortcut = proc(accel: string, fn: proc()): bool =
      registered = accel
      true
    b.unregisterShortcut = proc(accel: string): bool =
      unregistered = accel
      true
    currentBackend = b
    check registerGlobalShortcut("ctrl+alt+n", proc() = discard)
    check registered == "ctrl+alt+n"
    check unregisterGlobalShortcut("ctrl+alt+n")
    check unregistered == "ctrl+alt+n"

  test "display and theme listeners":
    currentBackend = fakeBackend()
    var screenHits = 0
    var themeHits = 0
    onScreensChanged(proc() = inc screenHits)
    onThemeChanged(proc() = inc themeHits)
    check displayChanged != nil
    check themeChanged != nil
    displayChanged()
    themeChanged()
    check screenHits == 1
    check themeHits == 1

suite "menu state":
  test "find, enable and check items":
    let item = checkItem("Always on Top", false)
    let m = newMenu(@[
      submenu("Window", @[item, menuItem("Center")]),
    ])
    check findItem(m, "Always on Top") == item
    check setChecked(m, "Always on Top", true)
    check item.checked
    check setEnabled(m, "Center", false)
    check not findItem(m, "Center").enabled
    check not setEnabled(m, "missing", false)
