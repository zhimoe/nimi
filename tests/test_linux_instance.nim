import std/[os, osproc, streams, times, unittest]

import nimi/platform/contract

when defined(linux):
  import nimi/platform/linux/app
  import nimi/platform/linux/instance

  proc pump(backend: Backend, condition: proc(): bool,
            timeoutMs = 3000): bool =
    let deadline = epochTime() + float64(timeoutMs) / 1000.0
    while epochTime() < deadline:
      backend.step()
      if condition():
        return true
      sleep(5)
    backend.step()
    condition()

  suite "linux instance and deep links":
    test "D-Bus OpenURL reaches the application":
      if getEnv("DBUS_SESSION_BUS_ADDRESS").len == 0 or
          findExe("gdbus").len == 0:
        echo "D-Bus session or gdbus unavailable; skipping"
        check true
      else:
        var received: seq[string]
        var handler = AppHandler()
        handler.openURL = proc(url: string) = received.add url
        let backend = newLinuxBackend()
        backend.init(handler, AppOptions(name: "Nimi Instance Test"))
        try:
          check not isSecondaryInstance()
          let busName = instanceBusName()
          check busName.len > 0
          let process = startProcess("gdbus", args = @[
            "call", "--session", "--dest", busName,
            "--object-path", "/org/nimi/Instance",
            "--method", "org.nimi.Instance.OpenURL",
            "nimi-test://open"], options = {poUsePath, poStdErrToStdOut})
          while running(process):
            backend.step()
            sleep(5)
          discard process.outputStream.readAll()
          close(process)
          check pump(backend, proc(): bool = received.len > 0)
          check received == @["nimi-test://open"]
        finally:
          backend.shutdown()

else:
  suite "linux instance and deep links":
    test "requires Linux":
      check true
