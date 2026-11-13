import std/[os, tables, tempfiles, unittest]
import nimi/ui
import ../examples/environment/view
when defined(macosx):
  import nimi/render/cg

suite "environment GUI":
  test "select, edit PATH, save, restore, and protect unsaved changes":
    let dir = createTempDir("nimi-env-ui-", "")
    defer: removeDir(dir)
    var values = {"Path": EnvironmentValue(value: "C:\\工具;%USERPROFILE%\\bin;;C:\\Windows", kind: ekExpandString),
                  "DEMO_HOME": EnvironmentValue(value: "C:\\Projects\\demo")}.toTable
    let store = EnvironmentStore(
      read: proc(scope: EnvironmentScope, name: string): Option[EnvironmentValue] =
        if name in values: some(values[name]) else: none(EnvironmentValue),
      write: proc(scope: EnvironmentScope, name: string, value: EnvironmentValue) = values[name] = value,
      remove: proc(scope: EnvironmentScope, name: string) = values.del(name),
      list: (proc(scope: EnvironmentScope): seq[EnvironmentEntry] =
        for name, data in values: result.add EnvironmentEntry(name: name, data: data)),
      notify: proc(): bool = true)
    let state = Editor(store: store, backupDir: dir)
    var accept = false
    var confirms = 0
    let gui = newEditorUI(state, proc(title, message: string): bool =
      inc confirms
      accept)
    state.refresh()
    let t = newTester(proc(c: Context) = gui.view(c), 940, 790)
    discard t.render()
    check t.click("var-Path")
    check state.kind == ekExpandString
    check t.click("path-1")
    check gui.pathDraft == "%USERPROFILE%\\bin"
    check t.click("path-up")
    check state.value == "%USERPROFILE%\\bin;C:\\工具;;C:\\Windows"
    check t.click("var-DEMO_HOME")
    check confirms == 1
    check state.selected == "Path"
    check t.click("save")
    check values["Path"].value == state.value
    check fileExists(state.backupPath)
    check not state.dirty
    let updated = state.value
    check t.click("path-2")
    check t.click("path-remove")
    check state.dirty
    accept = true
    check t.click("var-DEMO_HOME")
    check state.selected == "DEMO_HOME"
    check t.click("restore")
    check values["Path"].value != updated
    check values["Path"].value == "C:\\工具;%USERPROFILE%\\bin;;C:\\Windows"
    check t.click("var-Path")
    for key in ["save", "delete", "backup", "restore", "path-entry", "path-down"]:
      var found = false
      for hit in t.engine.hits:
        if hit.key == key:
          found = true
          check hit.rect.x >= 0
          check hit.rect.y >= 0
          check hit.rect.x + hit.rect.w <= t.width
          check hit.rect.y + hit.rect.h <= t.height
      check found
    when defined(macosx):
      check renderSceneToPng(t.scene, "/tmp/nimi-environment-preview.png")

    t.resize(640, 480)
    discard t.render()
    for hit in t.engine.hits:
      check hit.rect.x + hit.rect.w <= t.width
    t.scrollAt(10, 10, 5000)
    var restoreVisible = false
    for hit in t.engine.hits:
      if hit.key == "restore":
        restoreVisible = hit.rect.y >= 0 and hit.rect.y + hit.rect.h <= t.height
    check restoreVisible
    when defined(macosx):
      check renderSceneToPng(t.scene, "/tmp/nimi-environment-narrow.png")

    # The entry field is a draft until add/replace; Save and navigation must
    # never silently ignore it or replace another row with stale selection.
    t.resize(940, 790)
    t.engine.scrollOffsets["editor-page"] = 0
    discard t.render()
    check t.click("path-0")
    let original = state.value
    let originalEntry = gui.pathDraft
    accept = false
    gui.pathDraft = "C:\\pending"
    discard t.render()
    check gui.pathDirty
    check not gui.canDiscard()
    check t.click("save")
    check state.value == original
    check values["Path"].value == original
    check t.click("path-1")
    check gui.pathSelection == 0
    gui.editValue("unexpected raw edit")
    check state.value == original
    check gui.pathDraft == "C:\\pending"
    gui.pathDraft = "invalid;entry"
    check t.click("path-replace")
    check state.value == original
    check gui.pathSelection == 0
    check t.click("path-discard")
    check gui.pathDraft == originalEntry
    check not gui.pathDirty
    gui.pathDraft = ""
    discard t.render()
    check gui.pathDirty
    check t.click("path-replace")
    check pathEntries(state.value)[0] == ""
    check not gui.pathDirty
    check state.dirty
    accept = true
    check t.click("refresh")
    check gui.pathDraft == ""
    check gui.pathSelection == -1
    check not state.dirty
