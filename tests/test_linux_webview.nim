import std/[os, tempfiles, times, unittest]

import nimi/platform/contract

when defined(linux):
  import nimi/platform/linux/[app, ffi]

  proc pump(backend: Backend, condition: proc(): bool,
            timeoutMs = 8000): bool =
    let deadline = epochTime() + float64(timeoutMs) / 1000.0
    while epochTime() < deadline:
      backend.step()
      if condition():
        return true
      sleep(10)
    backend.step()
    condition()

  suite "linux WebKitGTK":
    test "script messages, evaluation and custom scheme":
      if not ensureWebKit():
        echo "WebKitGTK runtime unavailable; skipping"
        check true
      else:
        # WebKitGTK's sandbox and DMA-BUF renderer are unreliable in
        # containers and Xvfb. Tests opt out; applications keep the defaults.
        putEnv("WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS", "1")
        putEnv("WEBKIT_DISABLE_DMABUF_RENDERER", "1")

        let backend = newLinuxBackend()
        backend.init(AppHandler(), AppOptions(name: "Nimi WebKit Test"))
        let directory = createTempDir("nimi-linux-scheme-", "")
        try:
          var messages: seq[string]
          var pageHandler = WindowHandler(windowId: 7)
          pageHandler.message = proc(id: uint64, msg: string) =
            messages.add msg
          pageHandler.surface = SurfaceHandler()
          let page = backend.newWindow(
            PlatformWindowOptions(
              title: "WebView", width: 320, height: 240, resizable: true,
              html: """<!doctype html><html><body><h1>Nimi</h1>
<script>
window.webkit.messageHandlers.nimi.postMessage("page-ready");
</script></body></html>"""),
            pageHandler)
          check page != nil
          check pump(backend, proc(): bool = "page-ready" in messages)
          check "page-ready" in messages

          page.eval("""window.webkit.messageHandlers.nimi.postMessage("eval-ok")""")
          check pump(backend, proc(): bool = "eval-ok" in messages)
          check "eval-ok" in messages

          writeFile(directory / "index.html", """<!doctype html>
<html><body><p>scheme</p><script>
window.webkit.messageHandlers.nimi.postMessage("scheme-ok");
</script></body></html>""")
          var schemeMessages: seq[string]
          var schemeHandler = WindowHandler(windowId: 8)
          schemeHandler.message = proc(id: uint64, msg: string) =
            schemeMessages.add msg
          schemeHandler.surface = SurfaceHandler()
          let schemeWindow = backend.newWindow(
            PlatformWindowOptions(
              title: "Scheme", width: 320, height: 240, resizable: true,
              url: "nimitest://app/index.html", scheme: "nimitest",
              fileRoot: directory),
            schemeHandler)
          check schemeWindow != nil
          check pump(backend, proc(): bool = "scheme-ok" in schemeMessages)
          check "scheme-ok" in schemeMessages

          if webkit_cookie_manager_get_all_cookies != nil:
            let manager = webkit_web_context_get_cookie_manager(
              webkit_web_context_get_default())
            let cookie = soup_cookie_new("nimiTest", "42", "example.com",
                                         "/", -1)
            check cookie != nil
            webkit_cookie_manager_add_cookie(manager, cookie, nil, nil, nil)
            discard pump(backend, proc(): bool = false, 200)
            var found = false
            for attempt in 0 ..< 4:
              var cookies: seq[PlatformCookie]
              var cookiesDone = false
              backend.getCookies(proc(list: seq[PlatformCookie]) =
                cookies = list
                cookiesDone = true)
              if not pump(backend, proc(): bool = cookiesDone, 2000):
                continue
              for cookieValue in cookies:
                if cookieValue.name == "nimiTest" and cookieValue.value == "42":
                  found = true
              if found:
                break
            check found
            var cleared = false
            backend.clearCookies(proc() = cleared = true)
            check cleared
            soup_cookie_free(cookie)

          page.close()
          schemeWindow.close()
          discard pump(backend, proc(): bool = false, 100)
        finally:
          removeDir(directory)
          backend.shutdown()

else:
  suite "linux WebKitGTK":
    test "requires Linux":
      check true
