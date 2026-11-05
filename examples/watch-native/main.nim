## FSEvents file watching demo.
##
##   nim c -r --path:src examples/watch-native/main.nim
##   NIMI_SMOKE=watch nim c -r --path:src examples/watch-native/main.nim

import std/[os, times]

import nimi
import nimi/ui

type
  WatchState = ref object
    dir: string
    watcher: FileWatcher
    count: int
    last: string
    message: string
    win: Window

proc eventText(e: FileEvent): string =
  result = $e.kind & "  " & e.path

proc touchFile(s: WatchState) =
  try:
    writeFile(s.dir / "watched.txt", "tick " & $getTime().toUnix & "\n")
    s.message = "wrote watched.txt"
  except CatchableError as e:
    s.message = "write failed: " & e.msg
  if s.win != nil:
    s.win.invalidate()

proc view(s: WatchState, c: Context) =
  let muted = rgb(0.55, 0.55, 0.60)
  let accent = rgb(0.88, 0.48, 0.33)
  column(c).fill().padding(24, 24).gap(10).children(c, proc() =
    text(c, "FSEvents watcher").fontSize(26).bold()
    text(c, "Nim observes a directory; FSEvents delivers changes on the main queue.").
      fontSize(12).color(muted)
    divider(c)
    text(c, "watching: " & s.dir).fontSize(12).color(muted)
    text(c, "events: " & $s.count).fontSize(14)
    text(c, if s.last.len > 0: s.last else: "waiting for a change…").
      fontSize(12).color(if s.last.len > 0: accent else: muted)
    divider(c)
    row(c).gap(8).children(c, proc() =
      button(c, "Touch file", proc() = touchFile(s), key = "touch")
    )
    text(c, s.message).fontSize(12).color(accent)
  )

let state = WatchState(
  dir: getEnv("NIMI_WATCH_DIR", getTempDir() / "nimi-watch-demo"),
  message: "ready")
createDir(state.dir)

app.name = "Nimi Watch"
app.version = "0.1.0"

app.whenReady(proc() =
  let content = uiView(proc(c: Context) = view(state, c))
  let w = newWindow(WindowOptions(
    title: "Nimi Watch",
    width: 760,
    height: 460,
    content: content
  ))
  state.win = w
  state.watcher = watch(state.dir, proc(e: FileEvent) =
    inc state.count
    state.last = eventText(e)
    state.message = "change received"
    if existsEnv("NIMI_SMOKE"):
      echo "watch: ", state.last
      app.quit()
    elif w != nil:
      w.invalidate())
  if state.watcher == nil:
    state.message = "watcher could not start"
  w.invalidate()

  if existsEnv("NIMI_SMOKE"):
    touchFile(state)
)

app.run()
