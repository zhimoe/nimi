## Real Win32 paint through the core scene: WIC image decode, cached drawing,
## alpha polygon fill, and the GDI scene path.
import std/os
import nimi
import nimi/ui
import nimi/scene/scene
import nimi/render/gdi

const icon = "examples/notes/resources/icon.png"
doAssert fileExists(icon), "run this test from the repository root"

var window: Window
var paints = 0
let content = uiView(proc(c: Context) =
  column(c).fill().padding(12, 12).children(c, proc() =
    image(c, icon, 64, 64)
  ))
content.renderer = proc(dc: pointer, scene: Scene) =
  var decorated = scene
  decorated.polygon(@[
    Point(x: 120, y: 20),
    Point(x: 230, y: 60),
    Point(x: 140, y: 130),
  ], rgb(0.2, 0.7, 0.3, 0.5))
  drawScene(dc, decorated)
  inc paints
  # WIC must have decoded the image during this paint, not merely skipped it.
  doAssert imageCacheStats().images == 1
  # ShowWindow can paint synchronously before newWindow returns; close on a
  # later paint so the window handle has been assigned.
  if paints >= 2:
    discard postMain(proc() = window.close())
app.whenReady(proc() =
  window = newWindow(WindowOptions(title: "Nimi GDI image and polygon",
                                  width: 320, height: 200, content: content))
  window.invalidate()
)
app.run()
doAssert paints > 0
doAssert window.isClosed()
echo "Windows GDI image and polygon paint passed (", paints, " paints)"
