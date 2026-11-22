import std/[unittest]

import nimi/core/[app, window]
import nimi/platform/[contract, loginargs]

suite "window options":
  test "consumeActivationClick reaches the platform backend":
    let oldBackend = currentBackend
    defer: currentBackend = oldBackend
    var captured: PlatformWindowOptions
    currentBackend = Backend(
      newWindow: proc(opts: PlatformWindowOptions,
                      h: WindowHandler): NativeWindow =
        captured = opts
        NativeWindow(id: h.windowId))

    let window = newWindow(WindowOptions(
      title: "Activation", consumeActivationClick: true))
    check captured.title == "Activation"
    check captured.consumeActivationClick
    window.fireClosed()

    let ordinary = newWindow(WindowOptions(title: "Ordinary"))
    check not captured.consumeActivationClick
    ordinary.fireClosed()

suite "login launch marker":
  test "recognizes the marker as a whole argument":
    check hasOpenedAtLoginArg(["app", openedAtLoginArg])
    check not hasOpenedAtLoginArg(["app"])
    check not hasOpenedAtLoginArg(["app", openedAtLoginArg & "=1"])
    check not hasOpenedAtLoginArg([openedAtLoginArg & "-extra"])

  test "the app delegates login-item calls to the backend":
    let oldBackend = currentBackend
    defer: currentBackend = oldBackend
    var enabled = false
    currentBackend = Backend(
      setOpenAtLogin: proc(value: bool) = enabled = value,
      openAtLogin: proc(): bool = true,
      wasOpenedAtLogin: proc(): bool = true)
    let subject = App()
    subject.setOpenAtLogin(true)
    check enabled
    check subject.openAtLogin()
    check subject.wasOpenedAtLogin()
