## Real WebView2 custom scheme: nimi://app/ is served from a local folder
## through SetVirtualHostNameToFolderMapping, then the page calls Nim.
import std/os
import nimi

type Shell = ref object

var window: Window
var done = false
var ticks = 0

proc report(self: Shell, text: string) =
  doAssert text == "served through nimi://"
  done = true
  app.quit()

let root = getTempDir() / "nimi-webview2-protocol"
createDir(root)
writeFile(root / "index.html", """<!doctype html><html><body><script>
  window.nimi.call("Shell.report", "served through nimi://");
</script></body></html>""")

app.whenReady(proc() =
  let shell = Shell()
  bindService(shell, report)
  window = newWindow(WindowOptions(
    title: "Nimi WebView2 protocol",
    width: 640,
    height: 480,
    url: "nimi://app/index.html",
    files: newFileServer(root, "nimi")))
  window.startAnimation(2, proc(time, dt: float64) =
    inc ticks
    if done or ticks > 30:
      app.quit())
)

app.run()
doAssert done, "the nimi:// page did not reach the Nim service"
echo "Windows WebView2 custom scheme round trip passed"
