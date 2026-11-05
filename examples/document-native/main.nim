## Document controller demo: TextArea + save/reload + external change events.
##
##   nim c -r --path:src examples/document-native/main.nim
##   NIMI_SMOKE=document nim c -r --path:src examples/document-native/main.nim

import std/[os, strutils]

import nimi
import nimi/ui

type
  State = ref object
    doc: Document
    message: string
    win: Window

let path = getEnv("NIMI_DOC_PATH",
                  getTempDir() / "nimi-document-demo.txt")
let doc = if fileExists(path): openDocument(path) else: newDocument(path)
if doc.text.len == 0:
  doc.setText("# Nimi document\n\nEdit this file, save it, or change it from another app.")

let state = State(doc: doc, message: "ready")

proc saveDoc(s: State) =
  if s.doc.save():
    s.message = "saved " & s.doc.path
  else:
    s.message = "save failed"
  if s.win != nil: s.win.invalidate()

proc reloadDoc(s: State) =
  s.doc.reload()
  s.message = "reloaded"
  if s.win != nil: s.win.invalidate()

proc view(s: State, c: Context) =
  let muted = rgb(0.55, 0.55, 0.60)
  let accent = rgb(0.88, 0.48, 0.33)
  column(c).fill().padding(20, 20).gap(10).children(c, proc() =
    text(c, "Document").fontSize(26).bold()
    text(c, s.doc.path).fontSize(11).color(muted)
    textArea(c, s.doc.text, proc(t: string) =
      s.doc.setText(t)
      s.message = if s.doc.dirty: "unsaved" else: "saved"
      if s.win != nil: s.win.invalidate(),
      key = "body", height = 260)
    row(c).gap(8).children(c, proc() =
      button(c, "Save", proc() = saveDoc(s), key = "save")
      button(c, "Reload", proc() = reloadDoc(s), key = "reload")
    )
    text(c, s.message).fontSize(12).color(
      if s.doc.conflict: accent else: muted)
  )

let content = uiView(proc(c: Context) = view(state, c))

app.name = "Nimi Document"
app.version = "0.1.0"

app.whenReady(proc() =
  let w = newWindow(WindowOptions(
    title: "Nimi Document",
    width: 720,
    height: 560,
    content: content
  ))
  state.win = w
  state.doc.onChanged(proc(d: Document) =
    state.message = "external change detected"
    if state.win != nil: state.win.invalidate())
  state.doc.onConflict(proc(d: Document) =
    state.message = "external change conflicts with unsaved edit"
    if state.win != nil: state.win.invalidate())
  w.invalidate()
  if existsEnv("NIMI_SMOKE"):
    state.doc.setText("# Smoke\n\nline two")
    echo "document saved: ", state.doc.save()
    echo "document text: ", state.doc.text.replace("\n", " / ")
    echo "dirty: ", state.doc.dirty, " conflict: ", state.doc.conflict
    app.quit()
)

app.run()
