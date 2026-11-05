## Shredder effect demo, adapted from MyGo's strip physics into a Nimi WebView
## canvas. The effect is rendered in the page; Nim owns the window, resources
## and a small lifecycle service.
##
##   nim c -r --path:src examples/shredder/main.nim

import std/base64
import std/os

import nimi

type
  Shell = ref object

proc report(self: Shell, text: string) =
  echo text

proc snapshot(self: Shell, data: string) =
  let comma = data.find(',')
  if comma < 0:
    return
  let path = getEnv("NIMI_SNAPSHOT", "/tmp/nimi-shredder.png")
  writeFile(path, decode(data[comma + 1 .. ^1]))
  echo "shredder snapshot: ", path

proc quit(self: Shell) =
  discard postMain(proc() = app.quit())

proc frontendRoot(): string =
  let bundled = parentDir(getAppDir()) / "Resources" / "frontend"
  if dirExists(bundled):
    return bundled
  let cwd = getCurrentDir()
  for candidate in [cwd / "frontend", cwd / "examples" / "shredder" / "frontend"]:
    if dirExists(candidate):
      return candidate
  result = cwd / "frontend"

let shell = Shell()
bindService(shell, report, snapshot, quit)

app.name = "Nimi Shredder"
app.version = "0.1.0"

app.whenReady(proc() =
  let url =
    if existsEnv("NIMI_SMOKE"): "nimi://app/index.html?smoke=1"
    else: "nimi://app/index.html"
  discard newWindow(WindowOptions(
    title: "Nimi Shredder",
    width: 860,
    height: 720,
    url: url,
    files: newFileServer(frontendRoot(), "nimi")
  ))
)

app.run()
