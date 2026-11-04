## M2 first slice: a window drawn by Nimi itself, with no HTML/WKWebView.
##
##   nim c -r --path:src examples/native-smoke/main.nim

import nimi
import nimi/ui

proc view(c: Context) =
  c.drawRect(0, 0, c.width, c.height, rgb(0.06, 0.06, 0.08))
  c.drawText("Native UI from Nim", 40, 44, 34, rgb(1, 1, 1), true)
  c.drawText("CoreGraphics + CoreText, no HTML", 40, 92, 16, rgb(0.7, 0.7, 0.75))
  c.drawRect(40, 136, 260, 84, rgb(0.16, 0.4, 0.9), 14)
  c.drawText("surface view", 66, 166, 18, rgb(1, 1, 1), true)

app.whenReady(proc() =
  let w = newWindow(WindowOptions(
    title: "Native Smoke",
    width: 640,
    height: 400,
    content: uiView(view)
  ))
  w.invalidate()
)
app.run()
