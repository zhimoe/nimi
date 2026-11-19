## Real Win32 paint through the core scene: WIC image decode, cached drawing,
## alpha polygon fill, and the GDI scene path.
import std/[base64, os, tempfiles]
import nimi
import nimi/ui
import nimi/scene/scene
import nimi/render/gdi

const icon = "examples/notes/resources/icon.png"
doAssert fileExists(icon), "run this test from the repository root"
proc getPixel(dc: pointer, x, y: cint): uint32
  {.stdcall, importc: "GetPixel", header: "<windows.h>".}

let directory = createTempDir("nimi-render-", "")
let texture = directory / "quad.png"
# Red opaque pixels on the left and green half-transparent pixels on the right.
writeFile(texture, decode("iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR4nGP4z8DwHwgbGGAMAEBXBvusDhdaAAAAAElFTkSuQmCC"))

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
  decorated.rect(Rect(x: 150, y: 10, w: 160, h: 175), rgb(1, 1, 1))
  decorated.clip(Rect(x: 175, y: 24, w: 50, h: 44))
  decorated.imageQuad(texture, Rect(x: 1, w: 1, h: 2), [
    Point(x: 180, y: 20), Point(x: 220, y: 20),
    Point(x: 235, y: 70), Point(x: 170, y: 61)])
  decorated.restoreClip()
  decorated.text("MMMM", 170, 88, 28, rgb(0, 0, 1, 0.5))
  decorated.text("MMMM", 170, 135, 28, rgb(0, 0, 0, 0))
  drawScene(dc, decorated)
  inc paints
  # WIC must have decoded the image during this paint, not merely skipped it.
  doAssert imageCacheStats().images == 2
  let inside = getPixel(dc, 195, 40)
  doAssert (inside and 255) in 126'u32..128'u32 and
    ((inside shr 8) and 255) == 255 and ((inside shr 16) and 255) in 126'u32..128'u32
  doAssert getPixel(dc, 226, 60) == 0x00ff_ffff'u32
  var foundText = false
  for y in 88..120:
    for x in 170..275:
      let pixel = getPixel(dc, cint(x), cint(y))
      if pixel != 0x00ff_ffff'u32:
        doAssert (pixel and 255) >= 126 and ((pixel shr 16) and 255) == 255
        foundText = true
  doAssert foundText
  for y in 135..166:
    for x in 170..275:
      doAssert getPixel(dc, cint(x), cint(y)) == 0x00ff_ffff'u32
  # ShowWindow can paint synchronously before newWindow returns; the posted
  # closure runs on the main loop after the window has been assigned.
  if paints == 1:
    discard postMain(proc() =
      if window != nil:
        window.close())
app.whenReady(proc() =
  window = newWindow(WindowOptions(title: "Nimi GDI image and polygon",
                                  width: 320, height: 200, content: content))
  window.invalidate()
)
try:
  app.run()
finally:
  clearImageCache()
  removeDir(directory)
doAssert paints > 0
doAssert window.isClosed()
echo "Windows GDI image and polygon paint passed (", paints, " paints)"
