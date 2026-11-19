## Native UI smoke tests and macOS screenshots for the new environment app.

import std/[os, strutils, tables, tempfiles, unittest]

import nimi/ui
when defined(macosx):
  import nimi/render/cg

import ../examples/environment/[model, state, storage, theme, view]
import ./environment_fixture

proc checkHits(t: Tester) =
  for hit in t.engine.hits:
    check hit.rect.x >= 0
    check hit.rect.y >= 0
    check hit.rect.x + hit.rect.w <= t.width + 1
    check hit.rect.y + hit.rect.h <= t.height + 1

proc requireKey(t: Tester, key: string) =
  var found = false
  for hit in t.engine.hits:
    if hit.key == key:
      found = true
  check found

suite "environment UI":
  test "main, sheet, batch and backups render with reachable controls":
    let dir = createTempDir("nimi-env-ui-", "")
    defer: removeDir(dir)
    let backend = fixture()
    let app = makeApp(backend, dir)
    let t = newTester(proc(c: Context) = app.appView(c), 1000, 700)
    discard t.render()
    requireKey(t, "search")
    requireKey(t, "new")
    requireKey(t, "batch")
    requireKey(t, "row:user:path")
    requireKey(t, "edit:user:path")
    checkHits(t)
    when defined(macosx):
      discard renderSceneToPng(t.scene, "/tmp/nimi-env-ui-main.png")

    let idx = findVariable(app.vars[esUser], "Path")
    app.openEdit(app.vars[esUser][idx])
    discard t.render()
    requireKey(t, "sheet:entry:0")
    requireKey(t, "sheet:cancel")
    app.setSheetEntry(0, "C:\\B")
    discard t.render()
    requireKey(t, "sheet:save")
    checkHits(t)
    when defined(macosx):
      discard renderSceneToPng(t.scene, "/tmp/nimi-env-ui-sheet.png")

    app.closeSheet()
    app.sheet = nil
    app.openBatch("Path")
    discard t.render()
    requireKey(t, "batch:text")
    requireKey(t, "batch:back")
    app.batch.text.add("\nC:\\C")
    app.batch.text.add("\nC:\\" & repeat("very-long-directory\\", 25) & "bin")
    discard t.render()
    requireKey(t, "batch:apply")
    requireKey(t, "__textscrollx:batch:text")
    checkHits(t)
    when defined(macosx):
      discard renderSceneToPng(t.scene, "/tmp/nimi-env-ui-batch.png")

    app.batch = nil
    discard app.store.saveSnapshot(esUser, "smoke", app.vars[esUser])
    app.openBackups()
    discard t.render()
    requireKey(t, "backups:close")
    requireKey(t, "restore:" & app.snapshots[0].id)
    checkHits(t)
    when defined(macosx):
      discard renderSceneToPng(t.scene, "/tmp/nimi-env-ui-backups.png")

  test "dark theme renders":
    let dir = createTempDir("nimi-env-ui-", "")
    defer: removeDir(dir)
    let backend = fixture()
    let app = makeApp(backend, dir)
    app.themeMode = tmDark
    app.systemDark = true
    let t = newTester(proc(c: Context) = app.appView(c), 1000, 700)
    discard t.render()
    checkHits(t)
    when defined(macosx):
      discard renderSceneToPng(t.scene, "/tmp/nimi-env-ui-dark.png")

  test "narrow batch keeps the editor, preview and target selection reachable":
    let dir = createTempDir("nimi-env-narrow-", "")
    defer: removeDir(dir)
    let app = makeApp(fixture(), dir)
    app.openBatch("Path")
    let t = newTester(proc(c: Context) = app.appView(c), 640, 480)
    discard t.render()
    requireKey(t, "batch:pick")
    requireKey(t, "batch:cancel")
    app.batch.text.add("\nC:\\" & repeat("folder\\", 120) & "bin")
    discard t.render()
    requireKey(t, "batch:apply")
    requireKey(t, "__textscrollx:batch:text")
    checkHits(t)
    let editor = t.engine.hoverRects.getOrDefault("batch:text")
    let preview = t.engine.hoverRects.getOrDefault("batch:diff")
    check editor.h > 0 and preview.h > 0
    check editor.y + editor.h < preview.y
    check t.click("batch:pick")
    check app.batch.targetPickerOpen
    check t.engine.focusedKey == "batch:target:path"
    let draft = app.batch.text
    t.key("escape")
    check not app.batch.targetPickerOpen
    check app.batch.text == draft
    check t.engine.focusedKey == "batch:pick"
    check t.click("batch:pick")
    check t.click("batch:target:pythonpath")
    check app.modal != nil
    check t.click("modal:cancel")
    check app.batch.text == draft
    check t.click("batch:pick")
    check t.click("batch:target:pythonpath")
    check t.click("modal:confirm")
    check app.batch.target == "PYTHONPATH"
    check app.batch.text == "C:\\Py\nC:\\Py2"
