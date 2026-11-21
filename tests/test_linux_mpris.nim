import std/[os, osproc, streams, strutils, times, unittest]

import nimi/platform/contract

when defined(linux):
  import nimi/platform/linux/app
  import nimi/platform/linux/nowplaying

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

  suite "linux MPRIS":
    test "publishes metadata and receives media commands":
      if getEnv("DBUS_SESSION_BUS_ADDRESS").len == 0 or
          findExe("gdbus").len == 0:
        echo "D-Bus session or gdbus unavailable; skipping"
        check true
      else:
        let backend = newLinuxBackend()
        backend.init(AppHandler(), AppOptions(name: "Nimi MPRIS Test"))
        try:
          var commands: seq[PlatformMediaCommand]
          var positions: seq[float64]
          backend.setMediaCommandHandler(proc(cmd: PlatformMediaCommand,
                                              position: float64) =
            commands.add cmd
            positions.add position)
          backend.setNowPlaying(PlatformNowPlayingInfo(
            title: "Song", artist: "Artist", album: "Album",
            duration: 180.0, position: 12.0, playing: true,
            commands: {pmcPlay, pmcPause, pmcTogglePlayPause, pmcStop,
                       pmcNext, pmcPrevious, pmcSeek}))
          check mprisActive()
          discard pump(backend, proc(): bool = false, 400)

          proc gdbusCall(args: seq[string]): string =
            let process = startProcess("gdbus", args = args,
                                       options = {poUsePath, poStdErrToStdOut})
            while running(process):
              backend.step()
              sleep(5)
            result = process.outputStream.readAll()
            close(process)

          let base = @["call", "--session", "--dest",
                       "org.mpris.MediaPlayer2.nimi", "--object-path",
                       "/org/mpris/MediaPlayer2", "--method"]

          let status = gdbusCall(base & @[
            "org.freedesktop.DBus.Properties.Get",
            "org.mpris.MediaPlayer2.Player", "PlaybackStatus"])
          check "Playing" in status

          let metadata = gdbusCall(base & @[
            "org.freedesktop.DBus.Properties.Get",
            "org.mpris.MediaPlayer2.Player", "Metadata"])
          check "Song" in metadata
          check "Artist" in metadata
          check "Album" in metadata

          let play = gdbusCall(base & @["org.mpris.MediaPlayer2.Player.Play"])
          check play.len >= 0
          check pmcPlay in commands

          let seek = gdbusCall(base & @["org.mpris.MediaPlayer2.Player.Seek",
                                        "5000000"])
          check seek.len >= 0
          check commands.len >= 2
          check commands[^1] == pmcSeek
          check abs(positions[^1] - 17.0) < 0.01

          backend.clearNowPlaying()
          discard pump(backend, proc(): bool = false, 100)
          let stopped = gdbusCall(base & @[
            "org.freedesktop.DBus.Properties.Get",
            "org.mpris.MediaPlayer2.Player", "PlaybackStatus"])
          check "Stopped" in stopped
        finally:
          backend.shutdown()

else:
  suite "linux MPRIS":
    test "requires Linux":
      check true
