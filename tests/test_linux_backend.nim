import std/[os, strutils, tempfiles, times, unittest]

import nimi/platform/contract
import nimi/render/cairo
import nimi/scene/scene

when defined(linux):
  import nimi/platform/linux/app
  import nimi/platform/linux/shortcuts
  import nimi/platform/linux/tray

  proc pump(backend: Backend, condition: proc(): bool,
            timeoutMs = 3000): bool =
    let deadline = epochTime() + float64(timeoutMs) / 1000.0
    while epochTime() < deadline:
      backend.step()
      if condition():
        return true
      sleep(5)
    backend.step()
    condition()

  suite "linux GTK backend":
    test "window, drawing, input, menus and shutdown":
      var initialized = false
      var drawCount = 0
      var drawWidth, drawHeight: float32
      var mouseDowns, mouseUps: seq[(float32, float32)]
      var keys: seq[string]
      var texts: seq[string]
      var closed = false
      var menuCalls = 0

      let backend = newLinuxBackend()
      backend.init(AppHandler(), AppOptions(name: "Nimi Linux Test"))
      initialized = true
      try:
        let platformMenu = PlatformMenu(items: @[
          PlatformMenuItem(label: "Test", kind: pmiSubmenu, enabled: true,
            submenu: @[
              PlatformMenuItem(label: "Hit", kind: pmiNormal, id: 1,
                enabled: true, accelerator: "ctrl+k")])])
        backend.setMenu(platformMenu, MenuHandler(select: proc(id: uint32) =
          if id == 1:
            inc menuCalls))

        var surface = SurfaceHandler()
        surface.draw = proc(ctx: pointer, width, height: float32) =
          inc drawCount
          drawWidth = width
          drawHeight = height
          drawScene(ctx, Scene(width: width, height: height,
                               clear: rgb(0.2, 0.3, 0.4)))
        surface.mouseDown = proc(x, y: float32, clicks: int) =
          mouseDowns.add (x, y)
        surface.mouseUp = proc(x, y: float32) =
          mouseUps.add (x, y)
        surface.keyDown = proc(key: string, modifiers: uint32) =
          keys.add key
        surface.insertText = proc(text: string, replacement: TextRange) =
          texts.add text
        var windowHandler = WindowHandler(windowId: 42, surface: surface)
        windowHandler.closed = proc(id: uint64) = closed = true

        let win = backend.newWindow(
          PlatformWindowOptions(title: "Linux Test", width: 300, height: 200,
                                resizable: true, content: true, ime: true),
          windowHandler)
        check win != nil

        check pump(backend, proc(): bool = drawCount > 0)
        check drawCount > 0
        check drawWidth >= 100
        check drawHeight >= 100

        var width, height: int
        win.getSize(width, height)
        check width >= 100
        check height >= 100

        win.testClick(12, 18)
        check mouseDowns.len == 1
        check mouseDowns[0][0] == 12'f32
        check mouseDowns[0][1] == 18'f32
        check mouseUps.len == 1

        win.testKey(ord('a'))
        check "a" in keys
        win.testKeyText("中")
        check "中" in texts

        win.testMenuKey(ord('K'), KeyControl)
        check menuCalls == 1

        # Replacing the menu must replace its accelerator table too.
        var secondCalls = 0
        backend.setMenu(PlatformMenu(items: @[
          PlatformMenuItem(label: "Test", kind: pmiSubmenu, enabled: true,
            submenu: @[
              PlatformMenuItem(label: "Hit2", kind: pmiNormal, id: 2,
                enabled: true, accelerator: "ctrl+k")])]),
          MenuHandler(select: proc(id: uint32) =
            if id == 2:
              inc secondCalls))
        win.testMenuKey(ord('K'), KeyControl)
        check secondCalls == 1
        check menuCalls == 1

        check win.isVisible()
        check not win.isMinimized()
        check not win.isMaximized()
        check not win.isFullScreen()
        win.setSize(320, 220)
        check pump(backend, proc(): bool =
          block:
            var w, h: int
            win.getSize(w, h)
            w >= 320 or h >= 220)
        win.setTitle("Renamed")
        win.setAppearance(true)
        win.setAppearance(false)
        win.hide()
        check not win.isVisible()
        win.show()
        check win.isVisible()

        win.close()
        check pump(backend, proc(): bool = closed)
        check closed
      finally:
        if initialized:
          backend.shutdown()
          backend.shutdown() # idempotent

    test "quit before run skips the main loop":
      let backend = newLinuxBackend()
      backend.init(AppHandler(), AppOptions(name: "Nimi Quit Test"))
      try:
        backend.quit()
        backend.run()
      finally:
        backend.shutdown()

    test "clipboard text and HTML round-trip":
      let backend = newLinuxBackend()
      backend.init(AppHandler(), AppOptions(name: "Nimi Clipboard Test"))
      try:
        backend.clipboard.writeText("hello 世界 ✓")
        check backend.clipboard.readText() == "hello 世界 ✓"
        backend.clipboard.writeHTML("<b>bonjour</b>")
        check backend.clipboard.readHTML() == "<b>bonjour</b>"
        backend.clipboard.clear()
        check backend.clipboard.readText() == ""
      finally:
        backend.shutdown()

    test "screens, theme, notifications and shortcuts":
      let backend = newLinuxBackend()
      backend.init(AppHandler(), AppOptions(name: "Nimi Desktop Test"))
      try:
        let displays = backend.screens()
        check displays.len >= 1
        check displays[0].width > 0
        check displays[0].height > 0
        check displays[0].scale >= 1
        let theme = backend.themeInfo()
        check theme.accentB >= theme.accentR
        let point = backend.cursorPosition()
        check point.x >= 0
        var shortcutFired = 0
        let shortcutRegistered = backend.registerShortcut("ctrl+shift+f12",
          proc() = inc shortcutFired)
        if shortcutRegistered:
          check not backend.registerShortcut("ctrl+shift+f12",
                                             proc() = inc shortcutFired)
          if testShortcut("ctrl+shift+f12"):
            check pump(backend, proc(): bool = shortcutFired > 0, 2000)
            check shortcutFired == 1
          check backend.unregisterShortcut("ctrl+shift+f12")
        else:
          echo "X11 global shortcuts unavailable; skipping shortcut test"
        backend.notify(PlatformNotification(title: "Nimi",
                                            body: "Linux notification smoke"))
        let tray = backend.newTray(PlatformTrayOptions(title: "Nimi",
                                                       tooltip: "Linux tray"))
        check tray != nil
        tray.setTitle("Nimi")
        tray.setTooltip("Linux tray")
        var trayCalls = 0
        tray.setMenu(PlatformMenu(items: @[
          PlatformMenuItem(label: "Show", kind: pmiNormal, id: 1,
                           enabled: true)]),
          MenuHandler(select: proc(id: uint32) =
            if id == 1:
              inc trayCalls))
        check testTrayItem(tray.id, "Show")
        check trayCalls == 1
        tray.remove()
      finally:
        backend.shutdown()

    test "inotify file watching":
      let backend = newLinuxBackend()
      backend.init(AppHandler(), AppOptions(name: "Nimi Watch Test"))
      let directory = createTempDir("nimi-linux-watch-", "")
      try:
        var events: seq[PlatformFileEvent]
        let watcher = backend.watchFiles(directory,
          proc(e: PlatformFileEvent) = events.add e)
        check watcher != nil
        writeFile(directory / "a.txt", "hello")
        check pump(backend, proc(): bool = events.len > 0, 4000)
        check events.len > 0
        var found = false
        for event in events:
          if event.path.endsWith("a.txt"):
            found = true
        check found
        watcher.close()
        events.setLen(0)
        writeFile(directory / "b.txt", "after close")
        discard pump(backend, proc(): bool = events.len > 0, 200)
        check events.len == 0
      finally:
        removeDir(directory)
        backend.shutdown()

else:
  suite "linux GTK backend":
    test "requires Linux":
      check true
