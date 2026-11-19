## End-to-end state/view tests with an in-memory registry backend.

import std/[os, tables, tempfiles, unittest]

import nimi/ui

import ../examples/environment/[model, state, storage, view]
import ./environment_fixture

suite "environment app":
  test "search, filters, selection and copy":
    let dir = createTempDir("nimi-env-app-", "")
    defer: removeDir(dir)
    let backend = fixture()
    let app = makeApp(backend, dir)
    let t = newTester(proc(c: Context) = app.appView(c), 1000, 700)
    discard t.render()

    check app.filteredRows(esUser).len == 4
    check app.missingVarCount(esUser) == 1
    check t.click("filter:path")
    check app.filteredRows(esUser).len == 1
    check t.click("filter:all")
    discard t.render()
    t.engine.handleKeyDown("k", KeyShortcut)
    discard t.render()
    check t.engine.focusedKey == "search"
    t.typeText("go")
    check app.query == "go"
    check app.filteredRows(esUser).len == 1
    app.setQuery("")
    discard t.render()
    check t.click("check:user:tmp")
    check t.click("check:user:path")
    check app.checkedCount(esUser) == 2
    check t.click("copy:checked")

  test "create, edit list entries, save and undo":
    let dir = createTempDir("nimi-env-app-", "")
    defer: removeDir(dir)
    let backend = fixture()
    let app = makeApp(backend, dir)
    let t = newTester(proc(c: Context) = app.appView(c), 1000, 700)
    discard t.render()

    check t.click("new")
    check app.sheet != nil
    check t.engine.focusedKey == "sheet:name"
    t.typeText("NEW_VAR")
    check t.click("sheet:value")
    t.typeText("hello")
    check app.sheet.name == "NEW_VAR"
    check app.sheet.value == "hello"
    check t.click("sheet:save")
    check app.sheet == nil
    check valueOf(backend, esUser, "NEW_VAR") == "hello"
    check backend.notifications == 1

    # Undo through the toast action.
    discard t.render()
    check t.click("toast:action")
    check valueOf(backend, esUser, "NEW_VAR") == ""

    # Edit Path entries (raw split) and save.
    let idx = findVariable(app.vars[esUser], "Path")
    app.openEdit(app.vars[esUser][idx])
    check app.sheet.mode == smList
    discard t.render()
    app.setSheetEntry(0, "C:\\B")
    discard t.render()
    check t.click("sheet:save")
    check valueOf(backend, esUser, "Path") == "C:\\B;C:\\Missing"

  test "delete confirmation removes the variable":
    let dir = createTempDir("nimi-env-app-", "")
    defer: removeDir(dir)
    let backend = fixture()
    let app = makeApp(backend, dir)
    let t = newTester(proc(c: Context) = app.appView(c), 1000, 700)
    discard t.render()

    check t.click("delete:user:gopath")
    check app.modal != nil
    discard t.render()
    check t.click("modal:cancel")
    check app.modal == nil
    check findVariable(app.vars[esUser], "GOPATH") >= 0

    check t.click("delete:user:gopath")
    discard t.render()
    check t.click("modal:confirm")
    check findVariable(app.vars[esUser], "GOPATH") < 0
    check valueOf(backend, esUser, "GOPATH") == ""

  test "batch editor applies normalized entries":
    let dir = createTempDir("nimi-env-app-", "")
    defer: removeDir(dir)
    let backend = fixture()
    let app = makeApp(backend, dir)
    let t = newTester(proc(c: Context) = app.appView(c), 1000, 700)
    discard t.render()

    check t.click("batch")
    check app.batch != nil
    check app.batch.target.sameName("Path")
    app.batch.text = "C:\\A\nC:\\C"
    discard t.render()
    check t.click("batch:apply")
    check valueOf(backend, esUser, "Path") == "C:\\A;C:\\C"

  test "batch target switch keeps the draft until confirmed":
    let dir = createTempDir("nimi-env-app-", "")
    defer: removeDir(dir)
    let backend = fixture()
    let app = makeApp(backend, dir)
    let t = newTester(proc(c: Context) = app.appView(c), 1000, 700)
    discard t.render()

    app.openBatch("Path")
    discard t.render()
    app.batch.text.add("\nC:\\C")
    discard t.render()
    check t.click("batch:target:pythonpath")
    check app.modal != nil
    discard t.render()
    check t.click("modal:confirm")
    check app.batch != nil
    check app.batch.target.sameName("PYTHONPATH")
    check app.batch.originalValue == "C:\\Py;C:\\Py2"

  test "backups restore and theme cycle":
    let dir = createTempDir("nimi-env-app-", "")
    defer: removeDir(dir)
    let backend = fixture()
    let app = makeApp(backend, dir)
    let t = newTester(proc(c: Context) = app.appView(c), 1000, 700)
    discard t.render()

    let idx = findVariable(app.vars[esUser], "GOPATH")
    app.openEdit(app.vars[esUser][idx])
    discard t.render()
    app.setSheetValue("C:\\Changed")
    discard t.render()
    check t.click("sheet:save")
    check app.snapshots.len == 1
    discard t.render()
    check t.click("backups")
    check app.backupsOpen
    discard t.render()
    check t.click("restore:" & app.snapshots[0].id)
    check app.modal != nil
    discard t.render()
    check t.click("modal:confirm")
    check valueOf(backend, esUser, "GOPATH") == "C:\\Users\\Ada\\go"
    discard t.render()
    check t.click("backups:close")
    check not app.backupsOpen
    discard t.render()

    let before = app.themeMode
    check t.click("theme")
    check app.themeMode != before

  test "dirty guard prevents silent discard":
    let dir = createTempDir("nimi-env-app-", "")
    defer: removeDir(dir)
    let backend = fixture()
    let app = makeApp(backend, dir)
    let t = newTester(proc(c: Context) = app.appView(c), 1000, 700)
    discard t.render()

    check t.click("new")
    t.typeText("DRAFT")
    check app.sheetDirty()
    check t.click("sheet:close")
    check app.modal != nil
    discard t.render()
    check t.click("modal:cancel")
    check app.sheet != nil
    check t.click("sheet:close")
    discard t.render()
    check t.click("modal:confirm")
    check app.sheet == nil

  test "system save prepares pending and elevated startup applies it":
    let dir = createTempDir("nimi-env-app-", "")
    defer: removeDir(dir)
    let backend = fixture()
    let app = makeApp(backend, dir)
    var relaunched = false
    var quitCalled = false
    app.relaunchElevated = proc(args: string): string =
      relaunched = true
      ""
    app.quit = proc() = quitCalled = true
    app.admin = false
    let t = newTester(proc(c: Context) = app.appView(c), 1000, 700)
    discard t.render()

    app.switchScope(esMachine)
    discard t.render()
    let idx = findVariable(app.vars[esMachine], "OS")
    app.openEdit(app.vars[esMachine][idx])
    discard t.render()
    app.setSheetValue("ChangedOS")
    discard t.render()
    check t.click("sheet:save")
    check app.modal != nil
    check app.modal.kind == mkElevation
    discard t.render()
    check t.click("modal:confirm")
    check relaunched
    check quitCalled
    check app.store.hasPending()
    let pending = app.store.readPending()
    check pending.scope == esMachine
    check pending.variables.findVariable("OS") >= 0
    check valueOf(backend, esMachine, "OS") == "Windows_NT"

    app.admin = true
    app.applyPending()
    check not app.store.hasPending()
    check valueOf(backend, esMachine, "OS") == "ChangedOS"
    check app.startupToast.len > 0

  test "keyboard focus reveals rows in a long table":
    let dir = createTempDir("nimi-env-app-", "")
    defer: removeDir(dir)
    let backend = fixture()
    for i in 0 ..< 40:
      backend.user.add entry("VAR_" & $i, "value" & $i)
    let app = makeApp(backend, dir)
    let t = newTester(proc(c: Context) = app.appView(c), 1000, 700)
    discard t.render()
    for i in 0 ..< 30:
      t.key("down")
    check app.focusIndex(esUser) == 30
    check t.engine.scrollOffsets.getOrDefault("table", 0) > 0

  test "narrow layout keeps every hit inside the viewport":
    let dir = createTempDir("nimi-env-app-", "")
    defer: removeDir(dir)
    let backend = fixture()
    let app = makeApp(backend, dir)
    let t = newTester(proc(c: Context) = app.appView(c), 900, 620)
    discard t.render()
    proc checkBounds() =
      for hit in t.engine.hits:
        check hit.rect.x >= 0
        check hit.rect.y >= 0
        check hit.rect.x + hit.rect.w <= t.width + 1
        check hit.rect.y + hit.rect.h <= t.height + 1
    checkBounds()

    let idx = findVariable(app.vars[esUser], "Path")
    app.openEdit(app.vars[esUser][idx])
    discard t.render()
    checkBounds()
    app.sheet = nil
    app.openBatch("Path")
    discard t.render()
    checkBounds()
