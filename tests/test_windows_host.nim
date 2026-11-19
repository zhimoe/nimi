import std/unittest
import nimi/platform/contract
import nimi/platform/windows/app

suite "Win32 host lifecycle":
  test "dispatch, veto close, destroy once, and terminate":
    let backend = newWindowsBackend()
    var window: NativeWindow
    var ready, dispatched, terminated = false
    var attempts, closed = 0
    backend.init(AppHandler(
      ready: proc() =
        ready = true
        check backend.isMainThread()
        window = backend.newWindow(PlatformWindowOptions(title: "Nimi Windows 测试",
          width: 640, height: 480, resizable: true), WindowHandler(windowId: 7,
          shouldClose: proc(id: uint64): bool =
            check id == 7
            inc attempts
            attempts > 1,
          closed: proc(id: uint64) =
            check id == 7
            inc closed
            backend.quit()))
        window.show()
        window.setTitle("Nimi 生命周期")
        window.setSize(720, 500)
        window.center()
        window.close()
        check closed == 0
        backend.signal(),
      dispatch: proc() =
        dispatched = true
        window.close()
        window.destroy(),
      terminated: proc() = terminated = true), AppOptions(name: "Host test"))
    backend.run()
    check ready and dispatched and terminated
    check attempts == 2
    check closed == 1
    expect BackendError: window.show()

  test "DIP client sizes, resize style and fullscreen restore":
    let backend = newWindowsBackend()
    backend.init(AppHandler(ready: proc() =
      let window = backend.newWindow(PlatformWindowOptions(title: "DPI/state test",
        width: 640, height: 480, resizable: true), WindowHandler(windowId: 8))
      check window.isVisible() and not window.isMinimized() and not window.isMaximized()
      window.hide()
      check not window.isVisible()
      window.show()
      window.minimize()
      check window.isMinimized() and not window.isVisible()
      window.deminimize()
      check window.isVisible() and not window.isMinimized()
      window.zoom()
      check window.isMaximized()
      window.zoom()
      check not window.isMaximized()
      let initial = clientSizeDip(8)
      check abs(initial.x - 640) <= 1
      check abs(initial.y - 480) <= 1
      window.setSize(720, 500)
      window.setResizable(false)
      let fixed = clientSizeDip(8)
      check abs(fixed.x - 720) <= 1
      check abs(fixed.y - 500) <= 1
      window.toggleFullScreen()
      check window.isFullScreen()
      window.setResizable(true)
      window.toggleFullScreen()
      check not window.isFullScreen()
      let restored = clientSizeDip(8)
      check abs(restored.x - 720) <= 1
      check abs(restored.y - 500) <= 1
      window.destroy()
      backend.quit()), AppOptions())
    backend.run()
    backend.shutdown()

  test "ready failure closes windows and permits fresh initialization":
    var closed, terminated = 0
    let backend = newWindowsBackend()
    backend.init(AppHandler(
      ready: proc() =
        discard backend.newWindow(PlatformWindowOptions(width: 300, height: 200),
          WindowHandler(closed: proc(id: uint64) = inc closed))
        raise newException(ValueError, "ready failure"),
      terminated: proc() = inc terminated), AppOptions())
    expect ValueError: backend.run()
    check closed == 1
    check terminated == 1
    backend.shutdown()
    check terminated == 1
    let next = newWindowsBackend()
    var dispatched = false
    next.init(AppHandler(ready: proc() = next.signal(), dispatch: proc() =
      dispatched = true
      next.quit()), AppOptions())
    next.run()
    check dispatched

  test "restored windows move back into the nearest work area":
    let backend = newWindowsBackend()
    backend.init(AppHandler(), AppOptions())
    defer: backend.shutdown()
    let window = backend.newWindow(PlatformWindowOptions(title: "Work area test",
      width: 320, height: 220, resizable: true), WindowHandler(windowId: 75))
    defer: window.destroy()
    window.setPosition(30000, 30000)
    fitWindowToWorkArea(window.id)
    var x, y, width, height: int
    window.getPosition(x, y)
    window.getSize(width, height)
    check x < 30000 and y < 30000
    check width > 0 and width <= 321
    check height > 0 and height <= 221
    fitWindowToWorkArea(window.id)
    var nextX, nextY: int
    window.getPosition(nextX, nextY)
    check (nextX, nextY) == (x, y)

  test "failed duplicate initialization cannot shut down another backend":
    let first = newWindowsBackend()
    first.init(AppHandler(), AppOptions())
    let second = newWindowsBackend()
    expect BackendError: second.init(AppHandler(), AppOptions())
    second.shutdown()
    check first.isMainThread()
    first.shutdown()
