## Pure Windows input decoding, shared by the native bridge and regression tests.
import std/unicode
import ../contract
export contract

type Utf16Input* = object
  high: uint32

proc reset*(input: var Utf16Input) = input.high = 0

proc feed*(input: var Utf16Input, unit: uint32): string =
  if input.high != 0:
    let high = input.high
    input.high = 0
    if unit in 0xdc00'u32..0xdfff'u32:
      return $Rune(0x10000 + ((high - 0xd800) shl 10) + unit - 0xdc00)
    result = $Rune(0xfffd)
  if unit in 0xd800'u32..0xdbff'u32:
    input.high = unit
  elif unit in 0xdc00'u32..0xdfff'u32 or unit > 0x10ffff:
    result.add $Rune(0xfffd)
  else:
    result.add $Rune(unit)

proc decodeUtf16*(units: openArray[uint16]): string =
  var input: Utf16Input
  for unit in units: result.add input.feed(uint32(unit))
  if input.high != 0: result.add $Rune(0xfffd)

proc compositionSelection*(units, cursor: int, attributes: openArray[uint8]): TextRange =
  ## IMM attributes and cursor positions are indexed in UTF-16 code units.
  let count = max(0, units)
  result = TextRange(location: max(0, min(cursor, count)))
  for i in 0 ..< min(count, attributes.len):
    if attributes[i] in [1'u8, 3'u8]: # TARGET_CONVERTED / TARGET_NOTCONVERTED
      result.location = i
      while i + result.length < min(count, attributes.len) and
          attributes[i + result.length] in [1'u8, 3'u8]:
        inc result.length
      return

proc keyName*(virtualKey: uint, modifiers: uint32): string =
  case virtualKey
  of 8: "backspace"
  of 9: "tab"
  of 13: "enter"
  of 27: "escape"
  of 32: "space"
  of 33: "pageup"
  of 34: "pagedown"
  of 35: "end"
  of 36: "home"
  of 37: "left"
  of 38: "up"
  of 39: "right"
  of 40: "down"
  of 45: "insert"
  of 46: "delete"
  of 112..135: "f" & $(virtualKey - 111)
  else:
    # AltGr produces Ctrl+Alt; let WM_CHAR deliver the keyboard-layout text.
    if (modifiers and KeyControl) != 0 and (modifiers and KeyAlt) == 0 and
        virtualKey in 65'u..90'u: $char(virtualKey + 32)
    else: ""
