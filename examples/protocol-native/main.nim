## Custom WKWebView scheme demo: assets are served from a local directory
## through `nimi://app/...`, then the page talks back to Nim over typed IPC.
##
##   nim c -r --path:src examples/protocol-native/main.nim
##   NIMI_SMOKE=protocol nim c -r --path:src examples/protocol-native/main.nim

import std/os

import nimi

type
  Greeter = ref object
  Shell = ref object

proc greet(self: Greeter, name: string): string =
  "Hello, " & name & " — served through nimi:// and decoded in Nim " & NimVersion

proc report(self: Shell, text: string) =
  echo text

proc quit(self: Shell) =
  discard postMain(proc() = app.quit())

proc frontendRoot(): string =
  let bundled = parentDir(getAppDir()) / "Resources" / "frontend"
  if dirExists(bundled):
    return bundled
  let cwd = getCurrentDir()
  for candidate in [cwd / "frontend", cwd / "examples" / "protocol-native" / "frontend"]:
    if dirExists(candidate):
      return candidate
  result = cwd / "frontend"

let greeter = Greeter()
let shell = Shell()
bindService(greeter, greet)
bindService(shell, report, quit)

app.name = "Nimi Protocol"
app.version = "0.1.0"

app.onOpenURL(proc(url: string) =
  echo "open url: ", url)

app.whenReady(proc() =
  let smoke = existsEnv("NIMI_SMOKE")
  let url =
    if smoke: "nimi://app/index.html?smoke=1"
    else: "nimi://app/index.html"
  discard newWindow(WindowOptions(
    title: "Nimi Protocol",
    width: 900,
    height: 620,
    url: url,
    files: newFileServer(frontendRoot(), "nimi")
  ))
)

app.run()
