import std/unittest

import nimi
import nimi/core/app as coreApp
import nimi/render/cairo
import nimi/ui

when defined(linux):
  import nimi/platform/linux/ffi

  var contentDraws = 0
  var frames = 0
  var windowCreated = false

  proc forceQuit(data: pointer): cint {.cdecl.} =
    if not coreApp.app.quitting:
      coreApp.app.quit()
    0

  suite "linux app lifecycle":
    test "ready, native window, animation frames and shutdown":
      coreApp.app.setName("Nimi Linux App")
      coreApp.app.whenReady(proc() =
        let content = uiView(proc(c: Context) =
          column(c).fill().center().gap(4).children(c, proc() =
            text(c, "Linux 你好").fontSize(20).bold()))
        content.renderer = proc(ctx: pointer, scene: Scene) =
          inc contentDraws
          drawScene(ctx, scene)
        let win = newWindow(WindowOptions(title: "Nimi Linux App",
                                          width: 320, height: 200,
                                          content: content))
        windowCreated = win != nil
        win.startAnimation(60, proc(time, dt: float64) =
          inc frames
          if frames >= 3 and not coreApp.app.quitting:
            coreApp.app.quit())
        discard g_timeout_add(5000, cast[GTimeoutFunc](forceQuit), nil))
      coreApp.app.run()
      check windowCreated
      check frames >= 3
      check contentDraws > 0
else:
  suite "linux app lifecycle":
    test "requires Linux":
      check true
