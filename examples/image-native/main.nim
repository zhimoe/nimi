## Native Image widget demo. Uses the Nimi Notes app icon as a local PNG.
##
##   nim c -r --path:src examples/image-native/main.nim
##   NIMI_SMOKE=image nim c -r --path:src examples/image-native/main.nim

import std/os

import nimi
import nimi/ui
import nimi/render/cg

proc iconPath(): string =
  let cwd = getCurrentDir()
  for candidate in [cwd / "examples" / "notes" / "resources" / "icon.png",
                    cwd / "notes" / "resources" / "icon.png"]:
    if fileExists(candidate):
      return candidate
  result = ""

type
  State = ref object
    path: string

proc view(s: State, c: Context) =
  let muted = rgb(0.55, 0.55, 0.60)
  column(c).fill().padding(28, 28).gap(12).center().children(c, proc() =
    image(c, s.path, 128, 128)
    text(c, "Native image").fontSize(22).bold()
    text(c, "PNG decoded by ImageIO and drawn into the scene.").
      fontSize(12).color(muted)
  )

let state = State(path: iconPath())
let content = uiView(proc(c: Context) = view(state, c))

app.name = "Nimi Image"
app.version = "0.1.0"

app.whenReady(proc() =
  let w = newWindow(WindowOptions(
    title: "Nimi Image",
    width: 480,
    height: 420,
    content: content
  ))
  w.invalidate()
  if existsEnv("NIMI_SMOKE"):
    let scene = renderContent(content, 480, 420)
    let ok = renderSceneToPng(scene, "/tmp/nimi_image_widget.png")
    echo "image path: ", state.path
    echo "png written: ", ok
    app.quit()
)

app.run()
