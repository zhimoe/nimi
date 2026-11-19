import std/unittest
import nimi/core/[app, menu]
import nimi/platform/contract

suite "menu callback lifetime":
  test "old and new native menu versions retain their own callback maps":
    let oldBackend = currentBackend
    defer: currentBackend = oldBackend
    var handlers: seq[MenuHandler]
    currentBackend = Backend(setMenu: proc(menu: PlatformMenu, handler: MenuHandler) =
      handlers.add handler)
    var first, second = 0
    let subject = App(name: "Test")
    subject.setMenu(newMenu(@[menuItem("First", proc() = inc first)]))
    subject.installMenu()
    subject.setMenu(newMenu(@[menuItem("Second", proc() = inc second)]))
    subject.installMenu()
    handlers[0].select(1)
    check first == 1 and second == 0
    handlers[1].select(1)
    check first == 1 and second == 1

  test "failed install cannot change callbacks on the previous menu":
    let oldBackend = currentBackend
    defer: currentBackend = oldBackend
    var installed: MenuHandler
    var fail = false
    currentBackend = Backend(setMenu: proc(menu: PlatformMenu, handler: MenuHandler) =
      if fail: raise newException(BackendError, "native failure")
      installed = handler)
    var count = 0
    let subject = App(name: "Test")
    subject.setMenu(newMenu(@[menuItem("Keep", proc() = inc count)]))
    subject.installMenu()
    let original = subject.menu
    subject.ready = true
    fail = true
    expect BackendError:
      subject.setMenu(newMenu(@[menuItem("Replace", proc() = count += 100)]))
    check subject.menu == original
    installed.select(1)
    check count == 1
