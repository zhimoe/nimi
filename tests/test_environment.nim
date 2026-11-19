import std/[options, tables, unittest]
import nimi/core/environment

suite "environment editing":
  test "PATH is lossless, including empty segments and expansion tokens":
    for path in ["", ";", "C:\\工具;;%SystemRoot%\\bin;C:\\工具;", " C:\\space "]:
      check pathValue(pathEntries(path)) == path
    expect EnvironmentError: discard pathValue(["a;b"])

  test "reject registry delimiters but preserve Unicode and empty values":
    validateEnvironmentName("工具_HOME")
    validateEnvironmentValue(EnvironmentValue(value: ""))
    for name in ["", "a=b", "a\0b"]:
      expect EnvironmentError: validateEnvironmentName(name)
    expect EnvironmentError:
      validateEnvironmentValue(EnvironmentValue(value: "a\0b"))

  test "create, update, conflict, delete and notification failure":
    var values: Table[string, EnvironmentValue]
    var notifications = 0
    let store = EnvironmentStore(
      read: proc(scope: EnvironmentScope, name: string): Option[EnvironmentValue] =
        if name in values: some(values[name]) else: none(EnvironmentValue),
      write: proc(scope: EnvironmentScope, name: string, value: EnvironmentValue) =
        values[name] = value,
      remove: proc(scope: EnvironmentScope, name: string) = values.del(name),
      notify: proc(): bool =
        inc notifications
        false)
    let original = EnvironmentValue(value: "%USERPROFILE%\\工具", kind: ekExpandString)
    check not store.applyEnvironmentEdit(esUser, "TEST", none(EnvironmentValue), some(original))
    check values["TEST"] == original
    check store.applyEnvironmentEdit(esUser, "TEST", some(original), some(original))
    check notifications == 1
    expect EnvironmentConflictError:
      discard store.applyEnvironmentEdit(esUser, "TEST", none(EnvironmentValue), some(original))
    check notifications == 1
    let empty = EnvironmentValue(value: "", kind: ekString)
    check not store.applyEnvironmentEdit(esUser, "TEST", some(original), some(empty))
    check values["TEST"] == empty
    check not store.applyEnvironmentEdit(esUser, "TEST", some(empty), none(EnvironmentValue))
    check "TEST" notin values
    check notifications == 3
