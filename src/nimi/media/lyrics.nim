## LRC line timestamps; enhanced word timing is a later layer.
import std/[strutils, algorithm, math]

type LyricLine* = object
  time*: float64
  text*: string

proc parseLrc*(source: string): seq[LyricLine] =
  var offset = 0.0
  for raw in source.splitLines:
    let line = raw.strip
    if line.startsWith("[offset:") and line.endsWith("]"):
      try: offset = parseFloat(line[8 ..< line.high]) / 1000
      except ValueError: discard
  if classify(offset) in {fcNan, fcInf, fcNegInf}: offset = 0
  for raw in source.splitLines:
    let line = raw.strip
    var cursor = 0
    var stamps: seq[float64]
    while cursor < line.len and line[cursor] == '[':
      let ending = line.find(']', cursor)
      if ending < 0: break
      let parts = line[cursor + 1 ..< ending].split(':')
      if parts.len != 2: break
      try:
        let minutes = parseInt(parts[0])
        let seconds = parseFloat(parts[1])
        if minutes < 0 or seconds < 0 or seconds >= 60 or
            classify(seconds) in {fcNan, fcInf, fcNegInf}: break
        stamps.add(float64(minutes) * 60 + seconds)
      except ValueError: break
      cursor = ending + 1
    for stamp in stamps:
      result.add(LyricLine(time: max(0.0, stamp + offset), text: line[cursor .. ^1]))
  result.sort(proc(a, b: LyricLine): int = cmp(a.time, b.time))

proc activeLine*(lines: openArray[LyricLine], position: float64): int =
  ## Last line at or before position, including after a backward seek.
  result = -1
  var low = 0
  var high = lines.len
  while low < high:
    let mid = (low + high) div 2
    if lines[mid].time <= position:
      result = mid
      low = mid + 1
    else: high = mid
