## Real WebView2 window: injected bridge, page -> Nim call, Nim -> page resolve.
import nimi

type
  Greeter = ref object
  Shell = ref object

proc greet(self: Greeter, name: string): string =
  "Hello, " & name

var window: Window
var done = false
var ticks = 0

proc report(self: Shell, text: string) =
  doAssert text == "Hello, WebView2"
  done = true
  app.quit()

app.whenReady(proc() =
  let greeter = Greeter()
  let shell = Shell()
  bindService(greeter, greet)
  bindService(shell, report)
  let page = """<!doctype html><html><body><script>
    window.nimi.call("Greeter.greet", "WebView2").then(function (value) {
      window.nimi.call("Shell.report", value);
    });
  </script></body></html>"""
  window = newWindow(WindowOptions(title: "Nimi WebView2", width: 640,
                                  height: 480, html: page))
  # A watchdog: a WebView2 failure must fail rather than hang CI.
  window.startAnimation(2, proc(time, dt: float64) =
    inc ticks
    if done or ticks > 30:
      app.quit())
)

app.run()
doAssert done, "the WebView2 bridge did not complete the IPC round trip"
echo "Windows WebView2 bridge round trip passed"
