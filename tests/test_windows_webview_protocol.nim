## Real WebView2 custom scheme: nimi://app/ is served from a local folder
## through SetVirtualHostNameToFolderMapping, then the page calls Nim.
import std/[os, tempfiles]
import nimi

type Shell = ref object

var window: Window
var done = false
var ticks = 0
const cookieName = "nimi_framework_test"

proc containsTestCookie(items: seq[Cookie]): bool =
  for cookie in items:
    if cookie.name == cookieName:
      doAssert cookie.value == "aligned" and cookie.domain == "app.local"
      doAssert cookie.path == "/" and cookie.secure and not cookie.httpOnly
      return true

proc report(self: Shell, text: string) =
  doAssert text == "served through nimi://"
  cookies(proc(items: seq[Cookie]) =
    doAssert containsTestCookie(items)
    clearCookies(proc() =
      cookies(proc(afterClear: seq[Cookie]) =
        doAssert not containsTestCookie(afterClear)
        done = true
        app.quit())))

let temporary = createTempDir("nimi-webview2-protocol-", "")
let root = temporary / "www"
putEnv("WEBVIEW2_USER_DATA_FOLDER", temporary / "profile")
createDir(root)
writeFile(root / "index.html", """<!doctype html><html><body><script>
  document.cookie = "nimi_framework_test=aligned; Path=/; Secure";
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

try:
  app.run()
finally:
  # The WebView2 browser process can still hold its profile open during exit.
  try: removeDir(temporary)
  except OSError: discard
doAssert done, "the nimi:// page or WebView2 cookie callback timed out"
echo "Windows WebView2 custom scheme and cookie round trip passed"
