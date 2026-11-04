## Nimi Notes — a local-first Markdown notebook.
##
## Demonstrates the WebView-first half of Nimi end to end:
##   WKWebView UI -> typed JSON IPC -> Nim storage
##   native menus -> page actions
##   native open/save panels -> Markdown import/export
##
## Run:   nim c -r --path:src examples/notes/main.nim
## Build: ./nimi build examples/notes

import std/[json, os, strutils, sysrand, times]

import nimi

const frontendHtml = staticRead("frontend/index.html")
const frontendCss = staticRead("frontend/style.css")
const frontendJs = staticRead("frontend/app.js")

const seedBody = """## 欢迎使用 Nimi Notes

这是一个用 **Nim + WKWebView** 写的本地 Markdown 笔记应用。

- 左侧搜索、选择笔记
- 中间编辑 Markdown
- 右侧实时预览
- 输入后自动保存
- 原生菜单支持新建、保存、导入和导出

试试在下面的文字里加一些 Markdown:

> 好的工具应该安静、快速,并且把数据留在你自己的机器上。

```nim
echo "Hello from Nimi Notes"
```

打开 `文件` 菜单,或者点右上角的 **导出**,把这篇笔记保存成 `.md` 文件。
"""

type
  Notes = ref object
    data: JsonNode
    path: string
    loaded: bool

  Shell = ref object

# --- storage ---------------------------------------------------------------

proc notesDir(): string =
  let override = getEnv("NIMI_NOTES_DIR")
  result =
    if override.len > 0: override
    else: getHomeDir() / "Library" / "Application Support" / "Nimi Notes"
  createDir(result)

proc nowStamp(): int64 =
  getTime().toUnix

proc newId(): string =
  result = $nowStamp() & "-"
  for b in urandom(6):
    result.add toHex(b, 2)

proc makeNote(title, body: string): JsonNode =
  result = newJObject()
  result["id"] = %newId()
  result["title"] = %title
  result["body"] = %body
  result["updatedAt"] = %nowStamp()

proc findNote(data: JsonNode, id: string): JsonNode =
  if data.kind != JObject or not data.hasKey("notes"):
    return nil
  for note in data["notes"]:
    if note.kind == JObject and note{"id"}.getStr("") == id:
      return note
  result = nil

proc persist(self: Notes) =
  let tmp = self.path & ".tmp"
  writeFile(tmp, pretty(self.data, 2))
  if fileExists(self.path):
    removeFile(self.path)
  moveFile(tmp, self.path)

proc load(self: Notes) =
  self.path = notesDir() / "notes.json"
  if fileExists(self.path):
    try:
      let root = parseFile(self.path)
      if root.kind == JObject and root.hasKey("notes") and
          root["notes"].kind == JArray:
        self.data = root
        return
    except CatchableError:
      discard
  self.data = newJObject()
  self.data["notes"] = newJArray()
  self.data["notes"].add makeNote("欢迎使用 Nimi Notes", seedBody)
  self.persist()

proc ensure(self: Notes) =
  if not self.loaded:
    self.loaded = true
    self.load()

proc safeFileName(title: string): string =
  result = title.strip()
  for i in 0 ..< result.len:
    if result[i] in {'/', '\\', ':', '*', '?', '"', '<', '>', '|'} or
        ord(result[i]) < 32:
      result[i] = '-'
  result = result.strip(chars = {'-', ' '})
  if result.len == 0:
    result = "note"

# --- IPC services ----------------------------------------------------------

proc listNotes(self: Notes): JsonNode =
  self.ensure()
  result = self.data["notes"]

proc createNote(self: Notes, title: string): JsonNode =
  self.ensure()
  let note = makeNote(if title.strip().len > 0: title.strip() else: "无标题笔记", "")
  self.data["notes"].add note
  self.persist()
  result = note

proc updateNote(self: Notes, id, title, body: string): JsonNode =
  self.ensure()
  let note = findNote(self.data, id)
  if note == nil:
    return newJNull()
  note["title"] = %title
  note["body"] = %body
  note["updatedAt"] = %nowStamp()
  self.persist()
  result = note

proc removeNote(self: Notes, id: string): bool =
  self.ensure()
  var kept = newJArray()
  for note in self.data["notes"]:
    if note{"id"}.getStr("") != id:
      kept.add note
  let changed = kept.len != self.data["notes"].len
  self.data["notes"] = kept
  if changed:
    self.persist()
  result = changed

proc exportNote(self: Notes, id: string): string =
  self.ensure()
  let note = findNote(self.data, id)
  if note == nil:
    return ""
  let name = safeFileName(note{"title"}.getStr("note")) & ".md"
  let path = dialog.save("导出 Markdown", getHomeDir() / name)
  if path.len > 0:
    writeFile(path, note{"body"}.getStr(""))
  result = path

proc importNote(self: Notes): JsonNode =
  self.ensure()
  let paths = dialog.open("导入 Markdown", false, false, getHomeDir())
  if paths.len == 0:
    return newJNull()
  let path = paths[0]
  var body = ""
  try:
    body = readFile(path)
  except CatchableError as e:
    echo "import failed: ", e.msg
    return newJNull()
  let title =
    if splitFile(path).name.len > 0: splitFile(path).name else: "导入的笔记"
  let note = makeNote(title, body)
  self.data["notes"].add note
  self.persist()
  result = note

proc setTitle(self: Shell, title: string) =
  let w = focusedWindow()
  if w != nil:
    w.setTitle(if title.strip().len > 0: title.strip() & " — Nimi Notes"
               else: "Nimi Notes")

proc quit(self: Shell) =
  discard postMain(proc() = app.quit())

proc report(self: Shell, text: string) =
  echo text

# --- page/menu wiring ------------------------------------------------------

proc pageHtml(): string =
  result = frontendHtml
  result = result.replace("__NIMI_CSS__", frontendCss)
  result = result.replace("__NIMI_JS__", frontendJs)

proc evalPage(js: string) =
  let w = focusedWindow()
  if w != nil:
    w.eval(js)

proc runPage(action: string) =
  evalPage("window.nimiNotes && window.nimiNotes." & action & "()")

proc appMenu(): Menu =
  newMenu(@[
    submenu("Nimi Notes", @[
      menuItem("关于 Nimi Notes", role = "about"),
      separator(),
      menuItem("隐藏 Nimi Notes", role = "hide", accelerator = "cmd+h"),
      menuItem("隐藏其他", role = "hideOthers", accelerator = "cmd+alt+h"),
      menuItem("显示全部", role = "showAll"),
      separator(),
      menuItem("退出 Nimi Notes", role = "quit", accelerator = "cmd+q"),
    ]),
    submenu("文件", @[
      menuItem("新建笔记", accelerator = "cmd+n",
               onSelect = proc() = runPage("newNote")),
      menuItem("保存", accelerator = "cmd+s",
               onSelect = proc() = runPage("saveNow")),
      separator(),
      menuItem("导入 Markdown…", accelerator = "cmd+o",
               onSelect = proc() = runPage("importNote")),
      menuItem("导出 Markdown…", accelerator = "shift+cmd+s",
               onSelect = proc() = runPage("exportNote")),
      separator(),
      menuItem("关闭窗口", role = "close", accelerator = "cmd+w"),
    ]),
    submenu("编辑", @[
      menuItem("撤销", role = "undo", accelerator = "cmd+z"),
      menuItem("重做", role = "redo", accelerator = "shift+cmd+z"),
      separator(),
      menuItem("剪切", role = "cut", accelerator = "cmd+x"),
      menuItem("复制", role = "copy", accelerator = "cmd+c"),
      menuItem("粘贴", role = "paste", accelerator = "cmd+v"),
      menuItem("全选", role = "selectAll", accelerator = "cmd+a"),
    ]),
    submenu("窗口", @[
      menuItem("最小化", role = "minimize", accelerator = "cmd+m"),
      menuItem("缩放", role = "zoom"),
      separator(),
      menuItem("前置全部窗口", role = "bringAllToFront"),
    ]),
    submenu("帮助", @[
      menuItem("聚焦搜索", accelerator = "cmd+f",
               onSelect = proc() = runPage("focusSearch")),
      menuItem("关于 Nimi Notes", role = "about"),
    ]),
  ])

proc smokeScript(mode: string): string =
  if mode == "crud":
    result = """
<script>
setTimeout(async function () {
  try {
    const before = await window.nimi.call("Notes.listNotes");
    const note = await window.nimi.call("Notes.createNote", "Smoke note");
    await window.nimi.call("Notes.updateNote", note.id, "Smoke note", "# hello");
    const after = await window.nimi.call("Notes.listNotes");
    const found = after.find(function (n) {
      return n.id === note.id && n.title === "Smoke note" && n.body === "# hello";
    });
    const removed = await window.nimi.call("Notes.removeNote", note.id);
    await window.nimi.call("Shell.report",
      "smoke crud: " + (found && removed ? "ok" : "FAILED") +
      " (" + before.length + " -> " + after.length + ")");
  } catch (e) {
    await window.nimi.call("Shell.report", "smoke crud error: " + e.message);
  }
  await window.nimi.call("Shell.quit");
}, 900);
</script>
"""
  elif mode == "typing":
    result = """
<script>
setTimeout(async function () {
  try {
    const title = document.getElementById("title");
    const editor = document.getElementById("editor");
    title.value = "Smoke UI";
    title.dispatchEvent(new Event("input", { bubbles: true }));
    editor.value = "# typed content";
    editor.dispatchEvent(new Event("input", { bubbles: true }));
    await new Promise(function (resolve) { setTimeout(resolve, 1300); });
    const notes = await window.nimi.call("Notes.listNotes");
    const note = notes.find(function (n) {
      return n.title === "Smoke UI" && n.body === "# typed content";
    });
    await window.nimi.call("Shell.report",
      "smoke typing: " + (note ? "ok" : "FAILED"));
  } catch (e) {
    await window.nimi.call("Shell.report", "smoke typing error: " + e.message);
  }
  await window.nimi.call("Shell.quit");
}, 900);
</script>
"""
  elif mode == "switch":
    result = """
<script>
setTimeout(async function () {
  try {
    await window.nimiNotes.newNote();
    const title = document.getElementById("title");
    const editor = document.getElementById("editor");
    title.value = "Switch smoke";
    title.dispatchEvent(new Event("input", { bubbles: true }));
    editor.value = "unsaved body";
    editor.dispatchEvent(new Event("input", { bubbles: true }));
    const items = Array.from(document.querySelectorAll(".note-item[data-id]"));
    const other = items.find(function (el) {
      return el.dataset.id !== window.nimiNotes.state.selectedId;
    });
    if (other) other.click();
    await new Promise(function (resolve) { setTimeout(resolve, 1200); });
    const notes = await window.nimi.call("Notes.listNotes");
    const saved = notes.find(function (n) {
      return n.title === "Switch smoke" && n.body === "unsaved body";
    });
    await window.nimi.call("Shell.report",
      "smoke switch: " + (saved ? "ok" : "FAILED"));
  } catch (e) {
    await window.nimi.call("Shell.report", "smoke switch error: " + e.message);
  }
  await window.nimi.call("Shell.quit");
}, 900);
</script>
"""
  elif mode == "delete":
    result = """
<script>
setTimeout(async function () {
  try {
    await window.nimiNotes.newNote();
    const id = window.nimiNotes.state.selectedId;
    document.getElementById("delete").click();
    await new Promise(function (resolve) { setTimeout(resolve, 120); });
    document.getElementById("confirm-ok").click();
    await new Promise(function (resolve) { setTimeout(resolve, 800); });
    const notes = await window.nimi.call("Notes.listNotes");
    const gone = !notes.some(function (n) { return n.id === id; });
    await window.nimi.call("Shell.report",
      "smoke delete: " + (gone ? "ok" : "FAILED"));
  } catch (e) {
    await window.nimi.call("Shell.report", "smoke delete error: " + e.message);
  }
  await window.nimi.call("Shell.quit");
}, 900);
</script>
"""
  elif mode == "quit":
    result = """
<script>
setTimeout(function () { window.nimi.call("Shell.quit"); }, 700);
</script>
"""
  elif mode == "title":
    result = """
<script>
setTimeout(async function () {
  const notes = await window.nimi.call("Notes.listNotes");
  await window.nimi.call("Shell.report", "smoke notes: " + notes.length);
  await window.nimi.call("Shell.quit");
}, 800);
</script>
"""
  else:
    result = ""

# --- app -------------------------------------------------------------------

app.name = "Nimi Notes"
app.version = "0.1.0"

let notes = Notes()
let shell = Shell()
bindService(notes, listNotes, createNote, updateNote, removeNote,
            exportNote, importNote)
bindService(shell, setTitle, quit, report)

app.whenReady(proc() =
  app.setMenu(appMenu())
  var html = pageHtml()
  if existsEnv("NIMI_SMOKE"):
    html.add smokeScript(getEnv("NIMI_SMOKE"))
  discard newWindow(WindowOptions(
    title: "Nimi Notes",
    width: 1180,
    height: 760,
    html: html
  ))
)

app.run()
