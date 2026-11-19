## End-to-end Windows slice: real Win32 paint, the new environment app and
## HKCU. It only touches a unique disposable variable, never PATH or HKLM.
import std/[options, os, tempfiles, times]

import nimi
import nimi/ui
import nimi/render/gdi
import nimi/platform/windows/environment

import ../examples/environment/[model, service, state, storage, view]

proc require(condition: bool, message: string) =
  if not condition: raise newException(ValueError, message)

proc runTest() =
  let real = newWindowsEnvironmentStore()
  let name = "NIMI_GUI_TEST_" & $getCurrentProcessId() & "_" &
    $int64(epochTime())
  require(real.read(esUser, name).isNone,
          "Temporary test variable already exists")
  let dir = createTempDir("nimi-env-win-gui-", "")
  defer:
    real.remove(esUser, name)
    discard real.notify()
    removeDir(dir)
  let store = EnvironmentStore(
    read: real.read, write: real.write, remove: real.remove,
    notify: real.notify,
    list: (proc(scope: EnvironmentScope): seq[EnvironmentEntry] =
      let value = real.read(scope, name)
      if value.isSome:
        result.add EnvironmentEntry(name: name, data: value.get)))
  let backups = newStore(dir)
  let state = newAppState(newService(store, backups), backups, dir)
  state.now = proc(): float64 = epochTime()
  state.pathExists = proc(path: string): bool = false
  state.initApp()

  let ownedContent = uiView(proc(c: Context) = state.appView(c))
  let content {.cursor.} = ownedContent
  defer: ownedContent.renderer = nil
  var window: Window
  var painted = false
  var completed = false
  let keyEdit = "edit:user:" & lowerName(name)
  let keyDelete = "delete:user:" & lowerName(name)

  proc click(key: string) =
    discard renderContent(content, 1000, 700)
    require(content.clickKey(key), "Missing GUI control: " & key)
    discard renderContent(content, 1000, 700)

  content.renderer = proc(dc: pointer, scene: Scene) =
    drawScene(dc, scene)
    if not painted:
      painted = true
      discard postMain(proc() =
        click("new")
        content.insertText(name)
        click("sheet:value")
        content.insertText("%USERPROFILE%\\工具😀;;")
        click("sheet:save")
        require(real.read(esUser, name) == some(EnvironmentValue(
          value: "%USERPROFILE%\\工具😀;;", kind: ekExpandString)),
          "GUI creation failed")

        click(keyEdit)
        click("sheet:value")
        content.handleKeyDown("a", KeyControl)
        content.insertText("changed")
        click("sheet:save")
        require(real.read(esUser, name).get.value == "changed",
                "GUI update failed")

        click("backups")
        require(state.snapshots.len >= 2, "Missing snapshots")
        click("restore:" & state.snapshots[0].id)
        click("modal:confirm")
        require(real.read(esUser, name).get.value ==
          "%USERPROFILE%\\工具😀;;", "GUI restore failed")
        click("backups:close")

        click(keyDelete)
        click("modal:confirm")
        require(real.read(esUser, name).isNone, "GUI deletion failed")
        completed = true
        window.close())

  app.whenReady(proc() =
    window = newWindow(WindowOptions(
      title: "Nimi environment integration test",
      width: 1000, height: 700, content: content))
    state.window = window
    window.setDarkAppearance(true)
    window.setDarkAppearance(false)
    let size = window.getSize()
    require(size.width > 0 and size.height > 0, "Window client size is invalid")
    let position = window.getPosition()
    discard position
    window.invalidate())
  app.run()
  require(painted and completed, "GUI test did not complete")
  require(window.isClosed(), "Window did not close")
  echo "PASS: Windows paint + environment app + registry CRUD/restore"

runTest()
