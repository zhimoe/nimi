## Versioned local session. Restore never starts playback automatically.
## Version 2 stores track metadata; version 1 files (plain paths) still load.
import std/[json, math, os]

import nimi/media/queue
import nimi/core/document

type MusicSession* = object
  queue*: PlaybackQueue
  position*: float64
  volume*: float32

proc trackJson(track: Track): JsonNode =
  %*{"path": track.path, "title": track.title, "artist": track.artist,
     "album": track.album, "source": track.source,
     "remoteId": track.remoteId, "coverId": track.coverId,
     "duration": track.duration}

proc parseTrack(node: JsonNode): Track =
  if node.kind == JString:
    return localTrack(node.getStr)
  if node.kind != JObject:
    raise newException(ValueError, "Invalid track")
  let path = if node.hasKey("path"): node["path"].getStr else: ""
  if path.len == 0:
    raise newException(ValueError, "Track has no path")
  let duration = if node.hasKey("duration"): node["duration"].getFloat else: 0.0
  if classify(duration) in {fcNan, fcInf, fcNegInf} or duration < 0:
    raise newException(ValueError, "Invalid track duration")
  Track(path: path,
        title: if node.hasKey("title"): node["title"].getStr else: "",
        artist: if node.hasKey("artist"): node["artist"].getStr else: "",
        album: if node.hasKey("album"): node["album"].getStr else: "",
        source: if node.hasKey("source"): node["source"].getStr else: "local",
        remoteId: if node.hasKey("remoteId"): node["remoteId"].getStr else: "",
        coverId: if node.hasKey("coverId"): node["coverId"].getStr else: "",
        duration: duration)

proc loadSession*(path: string): MusicSession =
  result.queue = initPlaybackQueue()
  result.volume = 0.5
  if not fileExists(path): return
  try:
    let root = parseFile(path)
    let version = root["version"].getInt
    if version notin [1, 2]: return
    var restored = initPlaybackQueue()
    for item in root["tracks"]:
      if version == 1:
        if item.kind != JString: raise newException(ValueError, "Invalid track")
        restored.add(item.getStr)
      else:
        restored.add(parseTrack(item))
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
    var tracks = newJArray()
    for track in session.queue.tracks:
      tracks.add(trackJson(track))
    let doc = newDocument()
    defer: doc.close()
    doc.setText($(%*{
      "version": 2, "tracks": tracks,
      "selected": session.queue.selected, "repeat": ord(session.queue.repeatMode),
      "shuffle": session.queue.shuffle, "position": session.position,
      "volume": session.volume}))
    result = doc.save(path)
  except CatchableError:
    result = false
