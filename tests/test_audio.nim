import std/[unittest, os, tempfiles, monotimes, times]
import nimi/audio
import nimi/platform/darwin/objc

proc wav(): string =
  # One second of silent mono PCM, no audio fixture dependency.
  proc le(value, bytes: int): string =
    for i in 0 ..< bytes: result.add(char((value shr (8 * i)) and 255))
  result = "RIFF" & le(16036, 4) & "WAVEfmt " & le(16, 4) &
    le(1, 2) & le(1, 2) & le(8000, 4) & le(16000, 4) &
    le(2, 2) & le(16, 2) & "data" & le(16000, 4) & newString(16000)

suite "local audio":
  test "decode, seek, pause and close a real WAV":
    let directory = createTempDir("nimi-audio-", "")
    defer: removeDir(directory)
    let path = directory / "silence.wav"
    writeFile(path, wav())
    let p = openAudio(path)
    defer: p.close()
    check abs(p.duration - 1.0) < 0.01
    p.seek(0.5)
    check abs(p.position - 0.5) < 0.01
    p.seek(-1)
    check p.position == 0
    p.seek(NaN)
    check p.position == 0
    p.setVolume(0)
    check p.play()
    p.pause()
    check not p.playing
    p.close()
    check not p.play()
    check p.duration == 0
    p.close()

  test "invalid files report decoding failure":
    let directory = createTempDir("nimi-audio-bad-", "")
    defer: removeDir(directory)
    let path = directory / "bad.wav"
    writeFile(path, "invalid")
    expect IOError: discard openAudio(path)
    expect IOError: discard openAudio(directory / "missing")

  test "native completion fires once and permits closing from callback":
    let directory = createTempDir("nimi-audio-end-", "")
    defer: removeDir(directory)
    let path = directory / "silence.wav"
    writeFile(path, wav())
    let p = openAudio(path)
    defer: p.close()
    var completions = 0
    p.onFinished = proc(success: bool) =
      check success
      inc completions
      p.close()
    p.setVolume(0)
    check p.play()
    let deadline = getMonoTime() + initDuration(seconds = 10)
    while completions == 0 and getMonoTime() < deadline:
      withPool(proc() =
        let date = sendIdDouble(loadClass("NSDate"), sel("dateWithTimeIntervalSinceNow:"), 0.01)
        sendVoidId(send0(loadClass("NSRunLoop"), sel("currentRunLoop")), sel("runUntilDate:"), date)
      )
    check completions == 1
    check not p.playing
