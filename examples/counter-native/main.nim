## Counter in native UI: no HTML, no webview. Click +/- or Reset.
##
##   nim c -r --path:src examples/counter-native/main.nim

import std/os

import nimi
import nimi/ui

type
  Counter = ref object
    n: int

proc decValue(s: Counter) = dec s.n
proc incValue(s: Counter) = inc s.n
proc resetValue(s: Counter) = s.n = 0

proc view(s: Counter, c: Context) =
  while c.keyPressed("up"): inc s.n
  while c.keyPressed("down"): dec s.n
  let muted = rgb(0.55, 0.55, 0.60)
  column(c).fill().center().gap(16).children(c, proc() =
    text(c, $s.n).fontSize(56).bold()
    row(c).gap(8).children(c, proc() =
      button(c, "-", (proc() = decValue(s)), key = "dec")
      button(c, "Reset", (proc() = resetValue(s)), key = "reset")
      button(c, "+", (proc() = incValue(s)), key = "inc")
    )
    text(c, "click, ↑/↓, or Tab + Enter").fontSize(12).color(muted)
  )

let counter = Counter()
let content = uiView(proc(c: Context) = view(counter, c))

app.whenReady(proc() =
  let w = newWindow(WindowOptions(
    title: "Counter",
    width: 360,
    height: 260,
    content: content
  ))
  w.invalidate()
  if existsEnv("NIMI_SMOKE"):
    # Build hit regions without waiting for the first present, then click.
    discard renderContent(content, 360, 260)
    for _ in 0 ..< 3:
      discard content.clickKey("inc")
    echo "counter after clicks: ", counter.n
    let mode = getEnv("NIMI_SMOKE")
    if mode == "mouse":
      # Coordinates of the + button in the 360x260 scene.
      content.handleMouseDown(235, 158)
      content.handleMouseUp(235, 158)
      echo "counter after mouse: ", counter.n
    if mode == "appkit":
      # Synthesize NSEvents through NSApp: validates the AppKit callback chain.
      w.native.testClick(235, 158)
      echo "counter after appkit click: ", counter.n
    if mode == "keys":
      content.handleKeyDown("up")
      content.handleKeyDown("up")
      content.handleKeyDown("down")
      discard renderContent(content, 360, 260)
      echo "counter after keys: ", counter.n
    if mode == "appkitkey":
      w.native.testKey(126) # up
      w.native.testKey(126)
      w.native.testKey(125) # down
      discard renderContent(content, 360, 260)
      echo "counter after appkit keys: ", counter.n
    if mode == "appkitfocus":
      # Three Tabs: dec -> reset -> inc; Enter activates the focused button.
      w.native.testKey(48)
      w.native.testKey(48)
      w.native.testKey(48)
      w.native.testKey(36)
      discard renderContent(content, 360, 260)
      echo "counter after appkit focus: ", counter.n
    if mode == "clipboard":
      let previous = clipboard.readText()
      clipboard.writeText("nimi clipboard test")
      echo "clipboard: ", clipboard.readText()
      clipboard.writeText(previous)
      app.quit()
    if mode in ["check", "mouse", "appkit", "keys", "appkitkey",
                "appkitfocus", "clipboard"]:
      app.quit()
)
app.run()
