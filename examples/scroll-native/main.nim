## Native ScrollView demo: a clipped viewport with a long button list.
##
##   nim c -r --path:src examples/scroll-native/main.nim
##   NIMI_SMOKE=scroll nim c -r --path:src examples/scroll-native/main.nim

import std/[tables, os]

import nimi
import nimi/ui

type
  State = ref object
    selected: int
    message: string

proc view(s: State, c: Context) =
  let muted = rgb(0.55, 0.55, 0.60)
  column(c).fill().padding(20, 20).gap(10).children(c, proc() =
    text(c, "ScrollView").fontSize(26).bold()
    text(c, "Mouse wheel or trackpad scrolls the clipped list.").
      fontSize(12).color(muted)
    scrollView(c, "list", height = 260).width(360).children(c, proc() =
      for i in 0 ..< 40:
        button(c, "Row " & $i, (proc() =
          s.selected = i
          s.message = "clicked row " & $i), key = "row" & $i)
    )
    text(c, s.message).fontSize(12)
  )

let state = State(selected: -1, message: "click a row or scroll")

app.name = "Nimi Scroll"
app.version = "0.1.0"

app.whenReady(proc() =
  let content = uiView(proc(c: Context) = view(state, c))
  let w = newWindow(WindowOptions(
    title: "Nimi Scroll",
    width: 520,
    height: 440,
    content: content
  ))
  w.invalidate()
  if existsEnv("NIMI_SMOKE"):
    discard renderContent(content, 520, 440)
    echo "scroll rows: ", content.engine.hits.len
    if content.engine.scrollRegions.len > 0:
      let r = content.engine.scrollRegions[0]
      echo "content height: ", int(r.contentH), " viewport: ", int(r.rect.h)
      content.handleScroll(r.rect.x + 10, r.rect.y + 10, 120)
      discard renderContent(content, 520, 440)
      echo "offset: ", int(content.engine.scrollOffsets.getOrDefault("list", 0))
    app.quit()
)

app.run()
