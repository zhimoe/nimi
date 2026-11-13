## Native Nimi Windows environment-variable editor.
import std/os
import nimi
import nimi/ui
import nimi/platform/windows/environment
import ./view

let state = Editor(store: newWindowsEnvironmentStore(),
  backupDir: getEnv("LOCALAPPDATA", getHomeDir()) / "Nimi" / "Environment" / "backups")
let editorUI = newEditorUI(state, proc(title, message: string): bool = dialog.confirm(title, message))
var window: Window

app.whenReady(proc() =
  editorUI.attempt(proc() = state.refresh())
  window = newWindow(WindowOptions(title: "Nimi Environment Manager", width: 940, height: 790,
    content: uiView(proc(c: Context) = editorUI.view(c)), ime: true))
  window.onClose(proc(e: var CloseEvent) =
    if not editorUI.canDiscard(): e.prevented = true)
  window.invalidate())
app.run()
