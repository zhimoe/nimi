## Real Win32 timer -> core frame listener -> stop, on Windows.
import nimi

var window: Window
var frames = 0
app.whenReady(proc() =
  window = newWindow(WindowOptions(title: "Nimi frame timer", width: 320,
                                  height: 200))
  window.startAnimation(60, proc(time, dt: float64) =
    doAssert time > 0
    doAssert dt >= 0 and dt <= 0.25
    inc frames
    if frames >= 3:
      window.stopAnimation()
      doAssert not window.isAnimating()
      window.close()
  )
)
app.run()
doAssert frames >= 3
doAssert window.isClosed()
echo "Windows frame timer delivered ", frames, " frames"
