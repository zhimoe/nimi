## M3 widgets: checkbox, switch, slider, progress, divider.
##
##   nim c -r --path:src examples/widgets-native/main.nim

import nimi
import nimi/ui

type
  State = ref object
    remember: bool
    dark: bool
    volume: float32

proc view(s: State, c: Context) =
  let muted = rgb(0.55, 0.55, 0.60)
  column(c).fill().padding(24, 24).gap(14).children(c, proc() =
    text(c, "Native widgets").fontSize(24).bold()
    text(c, "Checkbox / switch / slider / progress / divider").fontSize(12).color(muted)
    divider(c)
    checkbox(c, "Remember me", s.remember,
             proc() = s.remember = not s.remember, key = "remember")
    switch(c, s.dark, proc() = s.dark = not s.dark, key = "dark")
    slider(c, s.volume, proc(v: float32) = s.volume = v,
           minValue = 0, maxValue = 1, key = "volume")
    progress(c, s.volume, 1)
    text(c, "volume: " & $int(s.volume * 100) & "%").fontSize(12).color(muted)
  )

let state = State(volume: 0.35)
let content = uiView(proc(c: Context) = view(state, c))

app.whenReady(proc() =
  let w = newWindow(WindowOptions(
    title: "Widgets",
    width: 420,
    height: 360,
    content: content
  ))
  w.invalidate()
)
app.run()
