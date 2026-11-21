## Local-file audio playback. Main-thread API; close explicitly before shutdown.
## Streaming and alternate decoders will use a separate backend.
import std/[os, math]
when defined(macosx):
  import std/[dynlib, tables]
  import ./platform/darwin/objc
  let avFoundation = loadLib("/System/Library/Frameworks/AVFoundation.framework/AVFoundation")
  type InitAudio = proc(a: Id, s: SEL, url: Id, error: ptr Id): Id {.cdecl.}
  type SetFloat = proc(a: Id, s: SEL, value: float32) {.cdecl.}
elif defined(linux):
  import ./platform/linux/gst

type AudioPlayer* = ref object
  when defined(macosx):
    native: Id
  elif defined(linux):
    gstPlayer, gstBus: pointer
    finished: bool
  path*: string
  onFinished*: proc(success: bool) {.closure.}

when defined(linux):
  proc pollGst(p: AudioPlayer) =
    ## Drain EOS/error messages without needing a GLib main loop. Called from
    ## the public query methods, which are main-thread only.
    if p == nil or p.gstBus == nil or p.finished:
      return
    let eos = gst.gst_bus_timed_pop_filtered(p.gstBus, 0, gst.GstMessageEos)
    if eos != nil:
      gst.gst_message_unref(eos)
      p.finished = true
      discard gst.gst_element_set_state(p.gstPlayer, gst.GstStatePaused)
      if p.onFinished != nil:
        let callback = p.onFinished
        try:
          callback(true)
        except CatchableError as error:
          stderr.writeLine("Audio completion callback: " & error.msg)
      return
    let failure = gst.gst_bus_timed_pop_filtered(p.gstBus, 0,
                                                 gst.GstMessageError)
    if failure != nil:
      gst.gst_message_unref(failure)
      p.finished = true
      discard gst.gst_element_set_state(p.gstPlayer, gst.GstStateNull)
      if p.onFinished != nil:
        let callback = p.onFinished
        try:
          callback(false)
        except CatchableError as error:
          stderr.writeLine("Audio completion callback: " & error.msg)

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
  elif defined(linux):
    if p.gstPlayer != nil:
      discard gst.gst_element_set_state(p.gstPlayer, gst.GstStateNull)
    if p.gstBus != nil:
      gst.gst_object_unref(p.gstBus)
      p.gstBus = nil
    if p.gstPlayer != nil:
      gst.gst_object_unref(p.gstPlayer)
      p.gstPlayer = nil
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
  elif defined(linux):
    if not gst.ensureGst():
      raise newException(IOError,
        "GStreamer runtime is unavailable; install gstreamer1.0-plugins-base")
    if not fileExists(path):
      raise newException(IOError, "Audio file does not exist: " & path)
    var player = gst.gst_element_factory_make("playbin".cstring, nil)
    if player == nil:
      player = gst.gst_element_factory_make("playbin3".cstring, nil)
    if player == nil:
      raise newException(IOError, "GStreamer playbin is unavailable")
    let bus = gst.gst_element_get_bus(player)
    if bus == nil:
      gst.gst_object_unref(player)
      raise newException(IOError, "GStreamer bus is unavailable")
    var opened = false
    try:
      let sinkName = getEnv("NIMI_AUDIO_SINK")
      if sinkName.len > 0:
        let sink = gst.gst_element_factory_make(sinkName.cstring, nil)
        if sink != nil:
          if sinkName == "fakesink":
            gst.g_object_set(sink, "sync".cstring, cint(1), nil)
          # playbin takes over the sink reference passed through the
          # audio-sink property; unref'ing the factory reference here can free
          # the sink while the pipeline still holds it.
          gst.g_object_set(player, "audio-sink".cstring, sink, nil)
      let uri = gst.gst_filename_to_uri(absolutePath(path).cstring, nil)
      if uri == nil:
        raise newException(IOError, "Cannot build a file URI for " & path)
      gst.g_object_set(player, "uri".cstring, uri, nil)
      gst.g_free(cast[pointer](uri))
      let changed = gst.gst_element_set_state(player, gst.GstStatePaused)
      if changed == gst.GstStateChangeFailure:
        raise newException(IOError, "Unable to decode audio: " & path)
      var state: cint
      let resultState = gst.gst_element_get_state(player, addr state, nil,
                                                  5_000_000_000'u64)
      if resultState == gst.GstStateChangeFailure or
          resultState == gst.GstStateChangeAsync:
        raise newException(IOError, "Timed out opening audio: " & path)
      opened = true
    finally:
      if not opened:
        discard gst.gst_element_set_state(player, gst.GstStateNull)
        gst.gst_object_unref(bus)
        gst.gst_object_unref(player)
    result = AudioPlayer(gstPlayer: player, gstBus: bus,
                         path: absolutePath(path))
  else:
    raise newException(IOError, "No local audio backend for this platform")

proc playing*(p: AudioPlayer): bool =
  when defined(macosx):
    p != nil and p.native != nil and sendBool(p.native, sel("isPlaying"))
  elif defined(linux):
    if p == nil or p.gstPlayer == nil:
      return false
    p.pollGst()
    if p.gstPlayer == nil:
      return false
    var state: cint
    discard gst.gst_element_get_state(p.gstPlayer, addr state, nil, 0)
    state == gst.GstStatePlaying and not p.finished
  else: false

proc duration*(p: AudioPlayer): float64 =
  when defined(macosx):
    if p != nil and p.native != nil: return sendDouble(p.native, sel("duration"))
  elif defined(linux):
    if p == nil or p.gstPlayer == nil:
      return 0.0
    p.pollGst()
    if p.gstPlayer == nil:
      return 0.0
    var nanoseconds: int64
    if gst.gst_element_query_duration(p.gstPlayer, gst.GstFormatTime,
                                      addr nanoseconds) != 0 and
        nanoseconds > 0:
      return float64(nanoseconds) / 1_000_000_000.0
    0.0

proc position*(p: AudioPlayer): float64 =
  when defined(macosx):
    if p != nil and p.native != nil: return sendDouble(p.native, sel("currentTime"))
  elif defined(linux):
    if p == nil or p.gstPlayer == nil:
      return 0.0
    p.pollGst()
    if p.gstPlayer == nil:
      return 0.0
    var nanoseconds: int64
    if gst.gst_element_query_position(p.gstPlayer, gst.GstFormatTime,
                                      addr nanoseconds) != 0 and
        nanoseconds > 0:
      return float64(nanoseconds) / 1_000_000_000.0
    0.0

proc seek*(p: AudioPlayer, seconds: float64) =
  if classify(seconds) in {fcNan, fcInf, fcNegInf}: return
  when defined(macosx):
    if p != nil and p.native != nil:
      sendVoidDouble(p.native, sel("setCurrentTime:"), clamp(seconds, 0.0, p.duration))
  elif defined(linux):
    if p != nil and p.gstPlayer != nil:
      let target = clamp(seconds, 0.0, max(0.0, p.duration))
      if p.gstPlayer != nil:
        if gst.gst_element_seek_simple(p.gstPlayer, gst.GstFormatTime,
            cint(gst.GstSeekFlagFlush or gst.GstSeekFlagAccurate),
            int64(target * 1_000_000_000.0)) != 0:
          var state: cint
          discard gst.gst_element_get_state(p.gstPlayer, addr state, nil,
                                            1_000_000_000'u64)

proc setVolume*(p: AudioPlayer, volume: float32) =
  if classify(volume) in {fcNan, fcInf, fcNegInf}: return
  when defined(macosx):
    if p != nil and p.native != nil:
      cast[SetFloat](msgSend)(p.native, sel("setVolume:"), clamp(volume, 0'f32, 1'f32))
  elif defined(linux):
    if p != nil and p.gstPlayer != nil:
      gst.g_object_set(p.gstPlayer, "volume".cstring,
                       cdouble(clamp(volume, 0'f32, 1'f32)), nil)

proc play*(p: AudioPlayer): bool =
  when defined(macosx):
    if p != nil and p.native != nil:
      return sendBool(p.native, sel("play"))
  elif defined(linux):
    if p == nil or p.gstPlayer == nil:
      return false
    p.pollGst()
    if p.gstPlayer == nil:
      return false
    if p.finished:
      p.finished = false
      discard gst.gst_element_seek_simple(p.gstPlayer, gst.GstFormatTime,
        cint(gst.GstSeekFlagFlush), 0)
    let changed = gst.gst_element_set_state(p.gstPlayer, gst.GstStatePlaying)
    return changed != gst.GstStateChangeFailure
  else:
    false

proc pause*(p: AudioPlayer) =
  when defined(macosx):
    if p != nil and p.native != nil: sendVoid(p.native, sel("pause"))
  elif defined(linux):
    if p != nil and p.gstPlayer != nil:
      p.pollGst()
      if p.gstPlayer != nil:
        discard gst.gst_element_set_state(p.gstPlayer, gst.GstStatePaused)
        var state: cint
        discard gst.gst_element_get_state(p.gstPlayer, addr state, nil,
                                          1_000_000_000'u64)
