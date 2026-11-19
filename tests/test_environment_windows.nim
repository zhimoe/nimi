## Windows integration: only a unique temporary HKCU value is touched.
import std/[os, times, strutils, unittest]
import nimi/platform/windows/environment

suite "Windows environment registry":
  test "Unicode, expansion type, empty value, case-insensitive lookup and deletion":
    let store = newWindowsEnvironmentStore()
    let name = "NIMI_TEST_ENV_" & $getCurrentProcessId() & "_" & $int64(epochTime())
    require store.read(esUser, name).isNone
    defer:
      store.remove(esUser, name)
      discard store.notify()
    let value = EnvironmentValue(value: "%USERPROFILE%\\工具;;", kind: ekExpandString)
    store.write(esUser, name, value)
    check store.read(esUser, name) == some(value)
    check store.read(esUser, name.toLowerAscii) == some(value)
    var listed = false
    for entry in store.list(esUser):
      if entry.name == name:
        check entry.data == value
        listed = true
    check listed
    let empty = EnvironmentValue(kind: ekString)
    discard store.applyEnvironmentEdit(esUser, name, some(value), some(empty))
    check store.read(esUser, name) == some(empty)
    discard store.applyEnvironmentEdit(esUser, name, some(empty), none(EnvironmentValue))
    check store.read(esUser, name).isNone
