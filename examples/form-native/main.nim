## A small native GUI app: text input, widgets, menu bar, file/message dialogs.
##
##   nim c -r --path:src examples/form-native/main.nim

import std/[os, strutils]

import nimi
import nimi/ui

type
  State = ref object
    name: string
    remember: bool
    volume: float32
    notes: string
    status: string

proc saveTo(s: State, path: string) =
  writeFile(path, s.name & "\n" & $s.remember & "\n" & $s.volume &
            "\n" & s.notes)

proc loadFrom(s: State, path: string) =
  let lines = readFile(path).split('\n', maxsplit = 3)
  if lines.len >= 3:
    s.name = lines[0]
    s.remember = lines[1] == "true"
    try:
      s.volume = parseFloat(lines[2])
    except ValueError:
      discard
    if lines.len >= 4:
      s.notes = lines[3]
    s.status = "Loaded " & path

proc saveState(s: State) =
  let path = dialog.save("Save form", "form.txt")
  if path.len == 0:
    return
  saveTo(s, path)
  s.status = "Saved to " & path

proc loadState(s: State) =
  let paths = dialog.open("Open form")
  if paths.len == 0:
    return
  loadFrom(s, paths[0])
  s.status = "Loaded " & paths[0]

proc about(s: State) =
  discard dialog.message("About Form", "A small native Nimi app.")

proc view(s: State, c: Context) =
  let muted = rgb(0.55, 0.55, 0.60)
  column(c).fill().padding(24, 24).gap(12).children(c, proc() =
    text(c, "Nimi Form").fontSize(24).bold()
    text(c, "TextInput + menus + dialogs + native widgets").fontSize(12).color(muted)
    divider(c)
    text(c, "Name").fontSize(12).color(muted)
    textInput(c, s.name, proc(v: string) = s.name = v,
              key = "name", placeholder = "Your name")
    checkbox(c, "Remember me", s.remember,
             proc() = s.remember = not s.remember, key = "remember")
    text(c, "Volume").fontSize(12).color(muted)
    slider(c, s.volume, proc(v: float32) = s.volume = v, key = "volume").width(240)
    progress(c, s.volume, 1).width(240)
    text(c, "Notes").fontSize(12).color(muted)
    textArea(c, s.notes, proc(v: string) = s.notes = v,
             key = "notes", placeholder = "Write a note…", height = 96)
    row(c).gap(8).children(c, proc() =
      button(c, "Save…", proc() = saveState(s), key = "save")
      button(c, "Open…", proc() = loadState(s), key = "open")
      button(c, "About", proc() = about(s), key = "about")
    )
    text(c, s.status).fontSize(12).color(muted).wrap()
  )

let state = State(volume: 0.4)
let content = uiView(proc(c: Context) = view(state, c))

app.setMenu(newMenu(@[
  submenu("Form", @[
    menuItem("About Form", proc() = about(state)),
    separator(),
    menuItem("Quit Form", role = "quit", accelerator = "cmd+q"),
  ]),
  submenu("File", @[
    menuItem("Open…", proc() = loadState(state), accelerator = "cmd+o"),
    menuItem("Save…", proc() = saveState(state), accelerator = "cmd+s"),
    separator(),
    menuItem("Close", role = "close", accelerator = "cmd+w"),
  ]),
  submenu("Edit", @[
    menuItem("Undo", role = "undo", accelerator = "cmd+z"),
    menuItem("Redo", role = "redo", accelerator = "shift+cmd+z"),
    separator(),
    menuItem("Cut", role = "cut", accelerator = "cmd+x"),
    menuItem("Copy", role = "copy", accelerator = "cmd+c"),
    menuItem("Paste", role = "paste", accelerator = "cmd+v"),
    menuItem("Select All", role = "selectAll", accelerator = "cmd+a"),
  ]),
  submenu("Window", @[
    menuItem("Minimize", role = "minimize", accelerator = "cmd+m"),
    menuItem("Zoom", role = "zoom"),
  ]),
]))

app.whenReady(proc() =
  let w = newWindow(WindowOptions(
    title: "Nimi Form",
    width: 520,
    height: 640,
    content: content,
    ime: true
  ))
  w.invalidate()
  let mode = getEnv("NIMI_SMOKE")
  if mode == "serialize":
    let path = "/tmp/nimi_form_state.txt"
    state.name = "Ada"
    state.remember = true
    state.volume = 0.75
    state.notes = "line one\nline two"
    saveTo(state, path)
    state.name = ""
    state.volume = 0
    state.notes = ""
    loadFrom(state, path)
    echo "form: ", state.name, " ", state.remember, " ", state.volume,
         " notes=", state.notes
    app.quit()
  elif mode == "type":
    discard renderContent(content, 520, 640)
    var hit: Rect
    for h in content.engine.hits:
      if h.key == "name":
        hit = h.rect
    w.native.testClick(hit.x + 10, hit.y + hit.h / 2)
    w.native.testKeyText("Ada")
    echo "form name: ", state.name
    app.quit()
  elif mode == "undo":
    discard renderContent(content, 520, 640)
    var hit: Rect
    for h in content.engine.hits:
      if h.key == "name":
        hit = h.rect
    w.native.testClick(hit.x + 10, hit.y + hit.h / 2)
    w.native.testKeyText("hello")
    content.handleKeyDown("z", KeyCommand)
    echo "after undo: ", state.name
    content.handleKeyDown("z", KeyCommand or KeyShift)
    echo "after redo: ", state.name
    app.quit()
  elif mode == "select":
    discard renderContent(content, 520, 640)
    var hit: Rect
    for h in content.engine.hits:
      if h.key == "name":
        hit = h.rect
    w.native.testClick(hit.x + 10, hit.y + hit.h / 2)
    let previousClipboard = clipboard.readText()
    w.native.testKeyText("hello world")
    content.handleKeyDown("a", KeyCommand)
    content.handleKeyDown("c", KeyCommand)
    echo "clipboard: ", clipboard.readText()
    content.handleKeyDown("end")
    content.handleKeyDown("v", KeyCommand)
    echo "form name after paste: ", state.name
    clipboard.writeText(previousClipboard)
    app.quit()
  elif mode == "textarea":
    discard renderContent(content, 520, 640)
    var hit: Rect
    for h in content.engine.hits:
      if h.key == "notes":
        hit = h.rect
    w.native.testClick(hit.x + 10, hit.y + 20)
    w.native.testKeyText("hello")
    w.native.testKey(36) # enter
    w.native.testKeyText("world")
    echo "form notes: ", state.notes
    app.quit()
  elif mode == "dialog":
    discard renderContent(content, 520, 640)
    var hit: Rect
    for h in content.engine.hits:
      if h.key == "about":
        hit = h.rect
    w.native.testClick(hit.x + hit.w / 2, hit.y + hit.h / 2)
    echo "dialog returned"
  elif mode == "savedialog":
    discard renderContent(content, 520, 640)
    var hit: Rect
    for h in content.engine.hits:
      if h.key == "save":
        hit = h.rect
    w.native.testClick(hit.x + hit.w / 2, hit.y + hit.h / 2)
    echo "save dialog returned"
)

app.run()
