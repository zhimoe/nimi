## Playback order is independent of audio output and UI.
import std/random

type
  RepeatMode* = enum repeatOff, repeatAll, repeatOne
  PlaybackQueue* = object
    tracks*: seq[string]
    selected*: int
    repeatMode*: RepeatMode
    shuffle*: bool
    history: seq[int]
    random: Rand

proc initPlaybackQueue*(seed: int64 = 1): PlaybackQueue =
  PlaybackQueue(selected: -1, random: initRand(seed))

proc add*(q: var PlaybackQueue, path: string) =
  if path.len > 0 and path notin q.tracks: q.tracks.add(path)

proc select*(q: var PlaybackQueue, index: int): bool =
  if index < 0 or index >= q.tracks.len: return false
  if q.selected >= 0 and q.selected != index: q.history.add(q.selected)
  q.selected = index
  true

proc nextIndex*(q: var PlaybackQueue, automatic = false): int =
  ## Resolve a candidate; selection commits only after the track opens.
  if q.tracks.len == 0: return -1
  if q.selected < 0: return 0
  if automatic and q.repeatMode == repeatOne: return q.selected
  if q.shuffle and q.tracks.len > 1:
    let candidate = q.random.rand(q.tracks.len - 2)
    return if candidate >= q.selected: candidate + 1 else: candidate
  if q.selected + 1 < q.tracks.len: return q.selected + 1
  if q.repeatMode == repeatAll: return 0
  -1

proc previousIndex*(q: PlaybackQueue): int =
  if q.shuffle and q.history.len > 0: return q.history[^1]
  if q.selected > 0: return q.selected - 1
  if q.repeatMode == repeatAll and q.tracks.len > 0: return q.tracks.high
  -1

proc selectPrevious*(q: var PlaybackQueue, index: int) =
  ## Commit a successfully opened previous track without creating a history loop.
  if index < 0 or index >= q.tracks.len: return
  if q.shuffle and q.history.len > 0 and q.history[^1] == index:
    q.history.setLen(q.history.len - 1)
  q.selected = index

proc restoreSelection*(q: var PlaybackQueue, index: int) =
  ## Restoring a session does not create navigation history.
  q.history.setLen(0)
  q.selected = if index >= 0 and index < q.tracks.len: index else: -1
