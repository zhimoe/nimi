## Local-file audio playback. Main-thread API; close explicitly before shutdown.
## Streaming and alternate decoders will use a separate backend.
import std/[os, math]
when defined(macosx):
  import std/[dynlib, tables]
  import ./platform/darwin/objc
  let avFoundation = loadLib("/System/Library/Frameworks/AVFoundation.framework/AVFoundation")
  type InitAudio = proc(a: Id, s: SEL, url: Id, error: ptr Id): Id {.cdecl.}
  type SetFloat = proc(a: Id, s: SEL, value: float32) {.cdecl.}

type AudioPlayer* = ref object
  when defined(macosx):
    native: Id
  path*: string
  onFinished*: proc(success: bool) {.closure.}

when defined(macosx):
  var players: Table[Id, AudioPlayer]
  var audioDelegate: Id

  proc audioFinished(self: Id, command: SEL, native: Id, success: bool) {.cdecl.} =
    let player = players.getOrDefault(native)
    if player != nil and player.onFinished != nil:
      let callback = player.onFinished
      try: callback(success)
      except CatchableError as error:
        stderr.writeLine("Audio completion callback: " & error.msg)

  proc ensureDelegate() =
    if audioDelegate != nil: return
    let cls = registerClass("NimiAudioDelegate", loadClass("NSObject"), @[
      ("audioPlayerDidFinishPlaying:successfully:", cast[pointer](audioFinished), "v@:@B")])
    audioDelegate = send0(send0(cls, sel("alloc")), sel("init"))

proc close*(p: AudioPlayer) =
  if p == nil: return
  when defined(macosx):
    if p.native != nil:
      sendVoidId(p.native, sel("setDelegate:"), nil)
      players.del(p.native)
      sendVoid(p.native, sel("stop"))
      release(p.native)
      p.native = nil
  p.path = ""
  p.onFinished = nil

proc openAudio*(path: string): AudioPlayer =
  ## Decoding failure raises IOError; the caller's previous player is untouched.
  when defined(macosx):
    if avFoundation == nil: raise newException(IOError, "AVFoundation unavailable")
    if not fileExists(path): raise newException(IOError, "Audio file does not exist: " & path)
    var native: Id
    var message = "Unable to decode audio"
    withPool(proc() =
      let url = sendId1(loadClass("NSURL"), sel("fileURLWithPath:"), nsString(absolutePath(path)))
      var error: Id
      native = cast[InitAudio](msgSend)(send0(loadClass("AVAudioPlayer"), sel("alloc")),
        sel("initWithContentsOfURL:error:"), url, addr error)
      if error != nil: message = goString(send0(error, sel("localizedDescription")))
    )
    if native == nil: raise newException(IOError, message)
    result = AudioPlayer(native: native, path: absolutePath(path))
    ensureDelegate()
    players[native] = result
    sendVoidId(native, sel("setDelegate:"), audioDelegate)
  else:
    raise newException(IOError, "Audio backend is currently macOS-only")

proc playing*(p: AudioPlayer): bool =
  when defined(macosx):
    p != nil and p.native != nil and sendBool(p.native, sel("isPlaying"))
  else: false

proc duration*(p: AudioPlayer): float64 =
  when defined(macosx):
    if p != nil and p.native != nil: return sendDouble(p.native, sel("duration"))

proc position*(p: AudioPlayer): float64 =
  when defined(macosx):
    if p != nil and p.native != nil: return sendDouble(p.native, sel("currentTime"))

proc seek*(p: AudioPlayer, seconds: float64) =
  if classify(seconds) in {fcNan, fcInf, fcNegInf}: return
  when defined(macosx):
    if p != nil and p.native != nil:
      sendVoidDouble(p.native, sel("setCurrentTime:"), clamp(seconds, 0.0, p.duration))

proc setVolume*(p: AudioPlayer, volume: float32) =
  if classify(volume) in {fcNan, fcInf, fcNegInf}: return
  when defined(macosx):
    if p != nil and p.native != nil:
      cast[SetFloat](msgSend)(p.native, sel("setVolume:"), clamp(volume, 0'f32, 1'f32))

proc play*(p: AudioPlayer): bool =
  when defined(macosx):
    if p != nil and p.native != nil:
      return sendBool(p.native, sel("play"))

proc pause*(p: AudioPlayer) =
  when defined(macosx):
    if p != nil and p.native != nil: sendVoid(p.native, sel("pause"))
