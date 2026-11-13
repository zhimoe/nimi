import std/[options, os, tables, tempfiles, unittest]
import ../examples/environment/editor

suite "environment editor controller":
  test "backup, update, restore, conflict, deletion and failed write":
    let dir = createTempDir("nimi-env-", "")
    defer: removeDir(dir)
    var values: Table[string, EnvironmentValue]
    var fail = false
    let store = EnvironmentStore(
      read: proc(scope: EnvironmentScope, name: string): Option[EnvironmentValue] =
        if name in values: some(values[name]) else: none(EnvironmentValue),
      write: proc(scope: EnvironmentScope, name: string, value: EnvironmentValue) =
        if fail: raise newException(EnvironmentError, "Access denied")
        values[name] = value,
      remove: proc(scope: EnvironmentScope, name: string) = values.del(name),
      list: (proc(scope: EnvironmentScope): seq[EnvironmentEntry] =
        for name, value in values:
          result.add EnvironmentEntry(name: name, data: value)),
      notify: proc(): bool = true)
    let e = Editor(store: store, backupDir: dir, name: "TEST", value: "%中文%", kind: ekExpandString)
    check e.dirty
    e.save()
    check not e.dirty
    let creationBackup = e.backupPath
    check fileExists(creationBackup)
    e.value = ""
    e.kind = ekString
    e.save()
    let editBackup = e.backupPath
    check values["TEST"].value == ""
    e.restore(editBackup)
    check values["TEST"] == EnvironmentValue(value: "%中文%", kind: ekExpandString)
    values["TEST"] = EnvironmentValue(value: "external")
    expect EnvironmentConflictError: e.restore(creationBackup)
    check values["TEST"].value == "external"
    e.choose("TEST")
    e.value = "draft"
    fail = true
    expect EnvironmentError: e.save()
    check e.value == "draft"
    check e.dirty
    check values["TEST"].value == "external"
    fail = false
    e.deleteSelected()
    check "TEST" notin values
    let deletionBackup = e.backupPath
    e.restore(deletionBackup)
    check values["TEST"].value == "external"
    e.scope = esMachine
    expect EnvironmentError: e.restore(deletionBackup)

  test "scope read failure preserves scope, list and unsaved editor state":
    let store = EnvironmentStore(list: proc(scope: EnvironmentScope): seq[EnvironmentEntry] =
      raise newException(EnvironmentError, "Cannot read scope"))
    let e = Editor(store: store, scope: esUser, selected: "Path", name: "Path", value: "draft",
      entries: @[EnvironmentEntry(name: "Path", data: EnvironmentValue(value: "original"))],
      expected: some(EnvironmentValue(value: "original")))
    expect EnvironmentError: e.switchScope(esMachine)
    check e.scope == esUser
    check e.entries[0].name == "Path"
    check e.selected == "Path"
    check e.value == "draft"
    check e.expected.get.value == "original"
