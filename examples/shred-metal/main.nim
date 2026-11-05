## Native Metal shredder. The visual path is entirely Metal:
##   - strip/card geometry is rasterized into a UV mask texture;
##   - a LayerEffect fragment shader samples the mask and the paper texture;
##   - slot hardware is drawn as solid geometry.
##
##   nim c -r --path:src examples/shred-metal/main.nim
##   NIMI_SMOKE=metal nim c -r --path:src examples/shred-metal/main.nim
##   NIMI_SMOKE=metal-live nim c -r --path:src examples/shred-metal/main.nim

import std/[dynlib, os, times]

import nimi
import nimi/ui
import nimi/effects/shred
import nimi/render/[cg, metal]
import nimi/platform/darwin/objc
import nimi/text/measure

const
  StageW = 900.0'f32
  StageH = 720.0'f32
  PaperW = 260
  PaperH = 190

var
  gSim: ShredSim
  gRenderer: MetalShred
  gLayer: Id
  gWindow: Id
  gTimerTarget: Id
  gLastTime: float64
  gFrames: int
  gLiveSmoke: bool

proc paperPixels(): tuple[pixels: seq[uint8], width, height: int] =
  var s = Scene(width: PaperW.float32, height: PaperH.float32,
                clear: rgb(1, 1, 1))
  let label = "Hello, Nimi"
  let m = measureText(label, 22, true)
  s.text(label, (float32(PaperW) - m.width) / 2,
         (float32(PaperH) - m.height) / 2, 22,
         rgb(0.13, 0.13, 0.15), true)
  let px = renderSceneToPixels(s)
  result = (pixels: px.pixels, width: px.width, height: px.height)

proc renderFrame() =
  let now = epochTime()
  let dt = if gLastTime == 0: 0.0 else: now - gLastTime
  gLastTime = now
  discard gSim.advance(float32(min(dt, 0.12)))
  let slot = StageH * 0.49
  let cardTop = min(slot, slot + gSim.top())
  discard gRenderer.renderToLayer(gSim, gLayer, StageW, StageH, slot, cardTop)
  inc gFrames
  if gLiveSmoke and gFrames == 30:
    echo "metal animation frames: ", gFrames,
         " elapsed: ", gSim.elapsed,
         " drawable: ", gLayer != nil
    app.quit()

proc metalTick(self: Id, cmd: SEL, timer: Id) {.cdecl.} =
  renderFrame()

proc metalWindowShouldClose(self: Id, cmd: SEL, sender: Id): bool {.cdecl.} =
  app.quit()
  result = true

proc createMetalWindow() =
  let frame = NSRect(x: 120, y: 120, w: StageW, h: StageH)
  gWindow = cast[MsgSendInitWindow](msgSend)(
    send0(loadClass("NSWindow"), sel("alloc")),
    sel("initWithContentRect:styleMask:backing:defer:"),
    frame, NSWindowStyleMaskTitled or NSWindowStyleMaskClosable or
    NSWindowStyleMaskMiniaturizable, NSBackingStoreBuffered, false)
  sendVoidId(gWindow, sel("setTitle:"), nsString("Nimi Shred Metal"))
  let delegateClass = registerClass("NimiMetalWindowDelegate",
    loadClass("NSObject"), [
      ("windowShouldClose:", cast[pointer](metalWindowShouldClose), "c@:@"),
    ])
  let delegate = send0(delegateClass, sel("new"))
  sendVoidId(gWindow, sel("setDelegate:"), delegate)

  let view = cast[MsgSendInitView](msgSend)(
    send0(loadClass("NSView"), sel("alloc")),
    sel("initWithFrame:"), NSRect(x: 0, y: 0, w: StageW, h: StageH))
  sendVoidBool(view, sel("setWantsLayer:"), true)
  gLayer = send0(loadClass("CAMetalLayer"), sel("layer"))
  sendVoidId(gLayer, sel("setDevice:"), gRenderer.device)
  sendVoidUInt(gLayer, sel("setPixelFormat:"), 80)
  sendVoidSize(gLayer, sel("setDrawableSize:"),
               NSSize(w: CGFloat(StageW), h: CGFloat(StageH)))
  sendVoidDouble(gLayer, sel("setContentsScale:"), 1.0)
  sendVoidId(view, sel("setLayer:"), gLayer)
  sendVoidId(gWindow, sel("setContentView:"), view)
  sendVoidId(gWindow, sel("makeKeyAndOrderFront:"), nil)
  let nsApp = send0(loadClass("NSApplication"), sel("sharedApplication"))
  sendVoidBool(nsApp, sel("activateIgnoringOtherApps:"), true)

  let timerClass = registerClass("NimiMetalTimer", loadClass("NSObject"), [
    ("tick:", cast[pointer](metalTick), "v@:@"),
  ])
  gTimerTarget = send0(timerClass, sel("new"))
  discard scheduledTimer(1.0 / 60.0, gTimerTarget, "tick:", true)

discard loadLib("/System/Library/Frameworks/QuartzCore.framework/QuartzCore")
let paper = paperPixels()
gSim = newShredSim()
gRenderer = newMetalShred(paper.pixels, paper.width, paper.height)
app.name = "Nimi Shred Metal"
app.version = "0.1.0"

app.whenReady(proc() =
  if not gRenderer.ok:
    echo "metal unavailable: ", gRenderer.error
    app.quit()
    return
  if getEnv("NIMI_SMOKE") == "metal":
    for _ in 0 ..< 160:
      gSim.step(gSim.config.step)
    let slot = StageH * 0.49
    let cardTop = min(slot, slot + gSim.top())
    let pixels = gRenderer.renderOffscreen(gSim, int(StageW), int(StageH),
                                           slot, cardTop)
    let path = getEnv("NIMI_SNAPSHOT", "/tmp/nimi-metal-shred.png")
    let ok = writeRgbaPng(pixels, int(StageW), int(StageH), path)
    echo "metal png: ", ok, " path: ", path, " bytes: ", pixels.len
    app.quit()
    return
  gLiveSmoke = getEnv("NIMI_SMOKE") == "metal-live"
  createMetalWindow()
  gLastTime = epochTime()
)

app.run()
