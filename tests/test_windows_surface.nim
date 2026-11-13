## Real Win32 paint -> Nimi scene -> GDI, then dispatch and close.
import nimi
import nimi/ui
import nimi/render/gdi
import nimi/text/measure

var window: Window
var paints = 0
var clicks = 0
var edited = "工具😀"
let content = uiView(proc(c: Context) =
  column(c).fill().padding(20, 20).gap(12).children(c, proc() =
    text(c, "Windows 环境变量 / Environment").fontSize(20)
    button(c, "Click", (proc() = inc clicks), key = "button")
    textInput(c, edited, (proc(value: string) = edited = value), key = "value")
  ))
content.renderer = proc(dc: pointer, scene: Scene) =
  drawScene(dc, scene)
  inc paints
  if paints == 1:
    discard postMain(proc() = window.close())
app.whenReady(proc() =
  let metrics = measureText("工具😀", 16, false)
  doAssert metrics.width > 0 and metrics.height > 0
  window = newWindow(WindowOptions(title: "Nimi surface integration", width: 600,
                                  height: 400, content: content))
  discard renderContent(content, 600, 400)
  doAssert content.clickKey("button")
  doAssert clicks == 1
  doAssert content.clickKey("value")
  content.handleKeyDown("a", KeyControl)
  content.insertText("中文 replacement")
  doAssert edited == "中文 replacement"
  window.invalidate()
)
app.run()
doAssert paints > 0
doAssert window.isClosed()
echo "Windows core lifecycle, GDI paint and Ctrl editing passed"
