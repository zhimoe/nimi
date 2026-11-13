## End-to-end application slice: real Win32 paint, shared editor GUI and HKCU.
## This test only touches a unique disposable variable, never PATH or HKLM.
import std/[os, tempfiles, times]
import nimi
import nimi/ui
import nimi/render/gdi
import nimi/platform/windows/environment
import ../examples/environment/view

proc require(condition: bool, message: string) =
  if not condition: raise newException(ValueError, message)

proc runTest() =
  let real = newWindowsEnvironmentStore()
  let name = "NIMI_GUI_TEST_" & $getCurrentProcessId() & "_" & $int64(epochTime())
  require(real.read(esUser, name).isNone, "Temporary test variable already exists")
  let dir = createTempDir("nimi-env-win-gui-", "")
  defer:
    real.remove(esUser, name)
    discard real.notify()
    removeDir(dir)
  # Restrict the visible list to the disposable fixture while retaining the
  # production registry read/write/delete/notification implementations.
  let store = EnvironmentStore(read: real.read, write: real.write, remove: real.remove,
    notify: real.notify, list: (proc(scope: EnvironmentScope): seq[EnvironmentEntry] =
      let value = real.read(scope, name)
      if value.isSome: result.add EnvironmentEntry(name: name, data: value.get)))
  let state = Editor(store: store, backupDir: dir)
  let gui = newEditorUI(state, proc(title, message: string): bool = true)
  let ownedContent = uiView(proc(c: Context) = gui.view(c))
  defer: ownedContent.renderer = nil
  let content {.cursor.} = ownedContent
  var window: Window
  var painted = false
  var completed = false
  proc click(key: string) =
    discard renderContent(content, 940, 790)
    require(content.clickKey(key), "Missing GUI control: " & key)
    discard renderContent(content, 940, 790)
  content.renderer = proc(dc: pointer, scene: Scene) =
    drawScene(dc, scene)
    if not painted:
      painted = true
      discard postMain(proc() =
        click("name")
        content.insertText(name)
        click("value")
        content.insertText("%USERPROFILE%\\工具😀;;")
        click("expand")
        click("save")
        require(real.read(esUser, name) == some(EnvironmentValue(
          value: "%USERPROFILE%\\工具😀;;", kind: ekExpandString)), "GUI creation failed")
        click("value")
        content.handleKeyDown("a", KeyControl)
        content.insertText("changed")
        click("save")
        require(real.read(esUser, name).get.value == "changed", "GUI update failed")
        click("restore")
        require(real.read(esUser, name).get.value == "%USERPROFILE%\\工具😀;;", "GUI restore failed")
        click("var-" & name)
        click("delete")
        require(real.read(esUser, name).isNone, "GUI deletion failed")
        completed = true
        window.close())
  app.whenReady(proc() =
    state.refresh()
    window = newWindow(WindowOptions(title: "Nimi environment integration test",
      width: 940, height: 790, content: content))
    window.invalidate())
  app.run()
  require(painted and completed, "GUI test did not complete")
  require(window.isClosed(), "Window did not close")
  echo "PASS: Windows paint + environment GUI + registry CRUD/restore"

runTest()
