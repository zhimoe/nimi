## Text ranges shared by the UI engine and platform backends. Locations and
## lengths are counted in UTF-16 code units to match AppKit's NSRange.

type
  TextRange* = object
    location*: int
    length*: int

const NoTextRange* = TextRange(location: -1, length: 0)
  ## AppKit's NSNotFound sentinel: "use the current selection".

proc valid*(r: TextRange): bool =
  r.location >= 0 and r.length >= 0

proc finish*(r: TextRange): int =
  r.location + r.length
