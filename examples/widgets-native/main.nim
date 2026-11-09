## M3 native widgets: checkbox, switch, slider, progress, divider, Image and
## ScrollView. ImageIO/PNG and the clipped scrolling list live here so the
## retired image-native/scroll-native examples keep their acceptance path.
##
##   nim c -r --path:src examples/widgets-native/main.nim
##   NIMI_SMOKE=image nim c -r --path:src examples/widgets-native/main.nim
##   NIMI_SMOKE=scroll nim c -r --path:src examples/widgets-native/main.nim

import std/[os, tables]

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
    remember: bool
    dark: bool
    volume: float32
    selected: int
    message: string
    imagePath: string

proc view(s: State, c: Context) =
  let muted = rgb(0.55, 0.55, 0.60)
  column(c).fill().padding(20, 20).gap(10).children(c, proc() =
    text(c, "Native widgets").fontSize(24).bold()
    text(c, "Checkbox / switch / slider / progress / divider / Image / ScrollView").
      fontSize(12).color(muted)
    divider(c)
    checkbox(c, "Remember me", s.remember,
             proc() = s.remember = not s.remember, key = "remember")
    switch(c, s.dark, proc() = s.dark = not s.dark, key = "dark")
    slider(c, s.volume, proc(v: float32) = s.volume = v,
           minValue = 0, maxValue = 1, key = "volume")
    progress(c, s.volume, 1)
    text(c, "volume: " & $int(s.volume * 100) & "%").fontSize(12).color(muted)
    divider(c)
    row(c).gap(14).children(c, proc() =
      image(c, s.imagePath, 96, 96)
      column(c).gap(4).children(c, proc() =
        text(c, "Image").fontSize(16).bold()
        text(c, "PNG decoded by ImageIO and drawn into the scene.").
          fontSize(12).color(muted)
        text(c, extractFilename(s.imagePath)).fontSize(11).color(muted)
      )
    )
    divider(c)
    text(c, "ScrollView").fontSize(16).bold()
    text(c, "Mouse wheel or trackpad scrolls the clipped list.").
      fontSize(12).color(muted)
    scrollView(c, "list", height = 190).width(480).children(c, proc() =
      for i in 0 ..< 40:
        button(c, "Row " & $i, (proc() =
          s.selected = i
          s.message = "clicked row " & $i), key = "row" & $i)
    )
    text(c, s.message).fontSize(12)
  )

let state = State(volume: 0.35, selected: -1,
                  message: "click a row or scroll", imagePath: iconPath())

app.name = "Nimi Widgets"
app.version = "0.1.0"

proc runSmoke(content: Content, mode: string) =
  let width = 640.0'f32
  let height = 760.0'f32
  case mode
  of "image":
    let scene = renderContent(content, width, height)
    let ok = renderSceneToPng(scene, "/tmp/nimi_image_widget.png")
    echo "image path: ", state.imagePath
    echo "png written: ", ok
  of "scroll":
    discard renderContent(content, width, height)
    echo "scroll hits: ", content.engine.hits.len
    if content.engine.scrollRegions.len > 0:
      let r = content.engine.scrollRegions[0]
      echo "content height: ", int(r.contentH), " viewport: ", int(r.rect.h)
      content.handleScroll(r.rect.x + 10, r.rect.y + 10, 120)
      discard renderContent(content, width, height)
      echo "offset: ", int(content.engine.scrollOffsets.getOrDefault("list", 0))
  else:
    let scene = renderContent(content, width, height)
    let ok = renderSceneToPng(scene, "/tmp/nimi_widgets.png")
    echo "png written: ", ok
  app.quit()

app.whenReady(proc() =
  let content = uiView(proc(c: Context) = view(state, c))
  let w = newWindow(WindowOptions(
    title: "Widgets",
    width: 640,
    height: 760,
    content: content
  ))
  w.invalidate()
  if existsEnv("NIMI_SMOKE"):
    runSmoke(content, getEnv("NIMI_SMOKE"))
)
app.run()
