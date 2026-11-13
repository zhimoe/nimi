import std/[strutils, unittest]
import nimi/platform/[contract, unsupported]

suite "partial platform contract":
  test "every callback has a safe explicit default":
    let backend = newUnsupportedBackend("test-platform")
    let window = newUnsupportedNativeWindow("test-platform")
    for name, field in fieldPairs(backend[]):
      when field isnot string and field isnot uint64: check field != nil
    for name, field in fieldPairs(window[]):
      when field isnot string and field isnot uint64: check field != nil
    for name, field in fieldPairs(backend.dialogs[]):
      when field isnot string and field isnot uint64: check field != nil
    for name, field in fieldPairs(backend.clipboard[]):
      when field isnot string and field isnot uint64: check field != nil
    expect UnsupportedBackendError: discard backend.dialogs.open("", "", false, false)
    expect UnsupportedBackendError: discard backend.newTray(PlatformTrayOptions())
    expect UnsupportedBackendError: window.toggleFullScreen()
    expect UnsupportedBackendError: window.eval("1 + 1")
    expect UnsupportedBackendError: backend.clipboard.writeHTML("<b>text</b>")
    try:
      discard backend.screens()
      check false
    except UnsupportedBackendError as e:
      check "test-platform" in e.msg
      check "Backend.screens" in e.msg

  test "implementations replace defaults without swallowing application errors":
    let backend = newUnsupportedBackend("test-platform")
    backend.dialogs.save = proc(title, path: string): string = path
    check backend.dialogs.save("Save", "a.txt") == "a.txt"
    backend.dialogs.save = proc(title, path: string): string =
      raise newException(IOError, "disk unavailable")
    expect IOError: discard backend.dialogs.save("Save", "a.txt")
