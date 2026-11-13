## Shared GUI view; storage and confirmations are supplied by the application.
import std/[strutils, sugar]
import nimi/ui
import ./editor
export editor

type EditorUI* = ref object
  state*: Editor
  filter*: string
  pathSelection*: int
  pathDraft*: string
  pathOriginal: string
  confirm*: proc(title, message: string): bool

proc newEditorUI*(state: Editor, confirm: proc(title, message: string): bool): EditorUI =
  EditorUI(state: state, confirm: confirm, pathSelection: -1)

proc attempt*(ui: EditorUI, action: proc()) =
  try: action()
  except CatchableError as e: ui.state.status = e.msg

proc resetPath(ui: EditorUI) =
  ui.pathSelection = -1
  ui.pathDraft = ""
  ui.pathOriginal = ""

proc pathDirty*(ui: EditorUI): bool =
  ui.pathDraft != ui.pathOriginal

proc save*(ui: EditorUI) =
  if ui.pathDirty:
    raise newException(EnvironmentError, "Use add or replace to apply the PATH entry draft before saving")
  ui.state.save()

proc editValue*(ui: EditorUI, value: string) =
  if ui.pathDirty:
    ui.state.status = "Apply or discard the PATH entry draft before editing the whole value"
    return
  ui.state.value = value
  ui.resetPath()

proc canDiscard*(ui: EditorUI): bool =
  not (ui.state.dirty or ui.pathDirty) or ui.confirm("Unsaved changes", "Discard unsaved changes?")

proc selectName*(ui: EditorUI, name: string) =
  if ui.canDiscard():
    ui.attempt(proc() =
      ui.state.choose(name)
      ui.resetPath())

proc switchScope*(ui: EditorUI, scope: EnvironmentScope) =
  if ui.canDiscard():
    ui.attempt(proc() =
      ui.state.switchScope(scope)
      ui.resetPath())

proc pathAction*(ui: EditorUI, action: string) =
  ui.attempt(proc() =
    if action == "discard":
      ui.pathDraft = ui.pathOriginal
      return
    if ui.pathDirty and action notin ["add", "replace"]:
      raise newException(EnvironmentError, "Apply or discard the PATH entry draft first")
    var entries = pathEntries(ui.state.value)
    var selected = ui.pathSelection
    case action
    of "add":
      entries.add ui.pathDraft
      selected = entries.high
    of "replace":
      if selected notin 0..<entries.len:
        raise newException(EnvironmentError, "Select a PATH entry to replace")
      entries[selected] = ui.pathDraft
    of "remove":
      if selected notin 0..<entries.len:
        raise newException(EnvironmentError, "Select a PATH entry to remove")
      entries.delete(selected)
      selected = -1
    of "up", "down":
      let target = selected + (if action == "up": -1 else: 1)
      if selected in 0..<entries.len and target in 0..<entries.len:
        swap(entries[selected], entries[target])
        selected = target
    else: return
    let value = pathValue(entries) # Validate before committing any UI state.
    ui.state.value = value
    ui.pathSelection = selected
    ui.pathDraft = if selected in 0..<entries.len: entries[selected] else: ""
    ui.pathOriginal = ui.pathDraft)

proc selectPath(ui: EditorUI, index: int, value: string) =
  if not ui.pathDirty or ui.confirm("Unsaved PATH entry", "Discard the PATH entry draft?"):
    ui.pathSelection = index
    ui.pathDraft = value
    ui.pathOriginal = value

proc view*(ui: EditorUI, c: Context) =
  let available = max(280'f32, c.width - 48)
  let narrow = c.width < 780
  let listWidth = if narrow: available else: 260'f32
  let editWidth = if narrow: available else: available - listWidth - 20
  scrollView(c, "editor-page", height = c.height).width(c.width).padding(20, 20).gap(10).children(c, proc() =
    text(c, "Environment Manager").fontSize(24).bold()
    row(c).gap(8).children(c, proc() =
      button(c, (if ui.state.scope == esUser: "● User" else: "User"), (proc() = ui.switchScope(esUser)), key = "user")
      button(c, (if ui.state.scope == esMachine: "● System" else: "System"), (proc() = ui.switchScope(esMachine)), key = "system")
      button(c, "Refresh", (proc() =
        if ui.canDiscard():
          ui.attempt(proc() =
            ui.state.refresh()
            ui.state.newVariable()
            ui.resetPath())), key = "refresh")
      button(c, "New variable", (proc() =
        if ui.canDiscard():
          ui.state.newVariable()
          ui.resetPath()), key = "new")
    )
    if ui.state.scope == esMachine:
      text(c, "System changes require an administrator process. Reading does not.").fontSize(12).width(available).wrap()
    textInput(c, ui.filter, (proc(v: string) = ui.filter = v), key = "filter", placeholder = "Filter variable names")
    let panels = if narrow: column(c) else: row(c)
    panels.gap(20).children(c, proc() =
      scrollView(c, "variables", height = (if narrow: 150 else: 360)).width(listWidth).children(c, proc() =
        for entry in ui.state.entries:
          if ui.filter.toLowerAscii notin entry.name.toLowerAscii: continue
          let name = entry.name
          capture name:
            discard button(c, (if name == ui.state.selected: "› " else: "") & name,
              (proc() = ui.selectName(name)), key = "var-" & name).width(listWidth - 15).background(
                if name == ui.state.selected: rgb(0.16, 0.40, 0.90) else: rgb(0.30, 0.34, 0.40))
      )
      column(c).gap(8).children(c, proc() =
        if ui.state.selected.len > 0:
          text(c, ui.state.selected).fontSize(18).bold().width(editWidth).wrap()
        else:
          textInput(c, ui.state.name, (proc(v: string) = ui.state.name = v), key = "name", placeholder = "New variable name").width(editWidth)
        checkbox(c, "Expand %VARIABLE% (REG_EXPAND_SZ)", ui.state.kind == ekExpandString,
          (proc() = ui.state.kind = if ui.state.kind == ekString: ekExpandString else: ekString), key = "expand")
        textArea(c, ui.state.value, (proc(v: string) = ui.editValue(v)), key = "value", height = 100).width(editWidth)
        if ui.state.name.toLowerAscii == "path":
          scrollView(c, "path-entries", height = 110).width(editWidth).children(c, proc() =
            for i, entry in pathEntries(ui.state.value):
              let index = i
              let value = entry
              capture index, value:
                discard button(c, $index & ": " & (if value.len == 0: "(empty)" else: value),
                  (proc() = ui.selectPath(index, value)), key = "path-" & $index).width(editWidth - 15)
          )
          textInput(c, ui.pathDraft, (proc(v: string) = ui.pathDraft = v), key = "path-entry", placeholder = "PATH entry").width(editWidth)
          row(c).gap(5).children(c, proc() =
            for action in ["add", "replace", "remove", "up", "down"]:
              let operation = action
              capture operation:
                discard button(c, operation, (proc() = ui.pathAction(operation)), key = "path-" & operation)
          )
          if ui.pathDirty:
            button(c, "Discard entry draft", (proc() = ui.pathAction("discard")), key = "path-discard")
        row(c).gap(8).children(c, proc() =
          button(c, "Save", (proc() = ui.attempt(proc() = ui.save())), key = "save")
          button(c, "Delete", (proc() =
            if ui.state.selected.len > 0 and ui.confirm("Delete variable", "Delete " & ui.state.selected & "? A backup will be kept."):
              ui.attempt(proc() =
                ui.state.deleteSelected()
                ui.resetPath())), key = "delete")
        )
      )
    )
    text(c, ui.state.status).fontSize(12).width(available).wrap()
    text(c, "Backup / restore (backups contain the original variable values)").fontSize(12).width(available).wrap()
    textInput(c, ui.state.backupPath, (proc(v: string) = ui.state.backupPath = v), key = "backup", placeholder = "Path to a saved backup .json").width(available)
    button(c, "Restore backup…", (proc() =
      if ui.canDiscard() and ui.confirm("Restore backup", "Restore this variable from the selected backup? External changes will not be overwritten."):
        let path = ui.state.backupPath
        ui.attempt(proc() =
          ui.state.restore(path)
          ui.resetPath())), key = "restore")
  )

