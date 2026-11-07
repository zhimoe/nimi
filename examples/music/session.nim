## Versioned local session. Restore never starts playback automatically.
import std/[json, os, math]
import nimi/media/queue
import nimi/core/document

type MusicSession* = object
  queue*: PlaybackQueue
  position*: float64
  volume*: float32

proc loadSession*(path: string): MusicSession =
  result.queue = initPlaybackQueue()
  result.volume = 0.5
  if not fileExists(path): return
  try:
    let root = parseFile(path)
    if root["version"].getInt != 1: return
    var restored = initPlaybackQueue()
    for item in root["tracks"]:
      if item.kind != JString: raise newException(ValueError, "Invalid track")
      restored.add(item.getStr)
    restored.restoreSelection(root["selected"].getInt)
    let mode = root["repeat"].getInt
    if mode < 0 or mode > ord(high(RepeatMode)):
      raise newException(ValueError, "Invalid repeat mode")
    restored.repeatMode = RepeatMode(mode)
    restored.shuffle = root["shuffle"].getBool
    let position = root["position"].getFloat
    let volume = root["volume"].getFloat
    if classify(position) in {fcNan, fcInf, fcNegInf} or
       classify(volume) in {fcNan, fcInf, fcNegInf}:
      raise newException(ValueError, "Invalid playback value")
    result.queue = restored
    result.position = max(0.0, position)
    result.volume = float32(clamp(volume, 0.0, 1.0))
  except CatchableError:
    discard # Preserve corrupt file for inspection; start with safe defaults.

proc saveSession*(path: string, session: MusicSession): bool =
  try:
    createDir(parentDir(path))
    let doc = newDocument()
    defer: doc.close()
    doc.setText($(%*{
      "version": 1, "tracks": session.queue.tracks,
      "selected": session.queue.selected, "repeat": ord(session.queue.repeatMode),
      "shuffle": session.queue.shuffle, "position": session.position,
      "volume": session.volume}))
    result = doc.save(path)
  except CatchableError:
    result = false
