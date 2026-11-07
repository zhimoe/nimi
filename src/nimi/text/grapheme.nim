## UTF-8 decoding helpers, UTF-16 offset conversion, and a pragmatic UAX #29
## grapheme-cluster subset. The subset covers combining marks, variation
## selectors, emoji modifiers, ZWJ sequences, regional-indicator pairs, and
## CRLF. It deliberately avoids a full Unicode property database.

type
  DecodedRune = object
    code: int32
    size: int

proc decodeRune(text: string, index: int): DecodedRune =
  ## Invalid bytes decode as a one-byte rune with code -1 so callers never
  ## split at a byte that does not begin a code point.
  if index < 0 or index >= text.len:
    return
  let b0 = uint8(text[index])
  if b0 < 0x80'u8:
    return DecodedRune(code: int32(b0), size: 1)
  if b0 >= 0xC2'u8 and b0 <= 0xDF'u8:
    if index + 1 < text.len and (uint8(text[index + 1]) and 0xC0'u8) == 0x80'u8:
      return DecodedRune(
        code: (int32(b0 and 0x1F'u8) shl 6) or
              int32(uint8(text[index + 1]) and 0x3F'u8),
        size: 2)
  elif b0 >= 0xE0'u8 and b0 <= 0xEF'u8:
    if index + 2 < text.len and
        (uint8(text[index + 1]) and 0xC0'u8) == 0x80'u8 and
        (uint8(text[index + 2]) and 0xC0'u8) == 0x80'u8:
      return DecodedRune(
        code: (int32(b0 and 0x0F'u8) shl 12) or
              (int32(uint8(text[index + 1]) and 0x3F'u8) shl 6) or
              int32(uint8(text[index + 2]) and 0x3F'u8),
        size: 3)
  elif b0 >= 0xF0'u8 and b0 <= 0xF4'u8:
    if index + 3 < text.len and
        (uint8(text[index + 1]) and 0xC0'u8) == 0x80'u8 and
        (uint8(text[index + 2]) and 0xC0'u8) == 0x80'u8 and
        (uint8(text[index + 3]) and 0xC0'u8) == 0x80'u8:
      return DecodedRune(
        code: (int32(b0 and 0x07'u8) shl 18) or
              (int32(uint8(text[index + 1]) and 0x3F'u8) shl 12) or
              (int32(uint8(text[index + 2]) and 0x3F'u8) shl 6) or
              int32(uint8(text[index + 3]) and 0x3F'u8),
        size: 4)
  DecodedRune(code: -1, size: 1)

proc between(value: int32, low, high: int32): bool {.inline.} =
  value >= low and value <= high

proc isExtend(cp: int32): bool =
  ## Extend + ZWNJ + emoji modifiers + variation selectors.
  between(cp, 0x0300, 0x036F) or between(cp, 0x0483, 0x0489) or
  between(cp, 0x0591, 0x05BD) or cp == 0x05BF or between(cp, 0x05C1, 0x05C2) or
  between(cp, 0x05C4, 0x05C5) or cp == 0x05C7 or
  between(cp, 0x0610, 0x061A) or between(cp, 0x064B, 0x065F) or cp == 0x0670 or
  between(cp, 0x06D6, 0x06DC) or between(cp, 0x06DF, 0x06E4) or
  between(cp, 0x06E7, 0x06E8) or between(cp, 0x06EA, 0x06ED) or
  cp == 0x0711 or between(cp, 0x0730, 0x074A) or
  between(cp, 0x07A6, 0x07B0) or between(cp, 0x07EB, 0x07F3) or
  between(cp, 0x0816, 0x0819) or between(cp, 0x081B, 0x0823) or
  between(cp, 0x0825, 0x0827) or between(cp, 0x0829, 0x082D) or
  between(cp, 0x0859, 0x085B) or between(cp, 0x08D3, 0x08E1) or
  between(cp, 0x08E3, 0x0902) or cp == 0x093A or cp == 0x093C or
  between(cp, 0x0941, 0x0948) or cp == 0x094D or between(cp, 0x0951, 0x0957) or
  between(cp, 0x0962, 0x0963) or cp == 0x0981 or cp == 0x09BC or
  between(cp, 0x09C1, 0x09C4) or cp == 0x09CD or between(cp, 0x09E2, 0x09E3) or
  between(cp, 0x0A01, 0x0A02) or cp == 0x0A3C or between(cp, 0x0A41, 0x0A42) or
  between(cp, 0x0A47, 0x0A48) or between(cp, 0x0A4B, 0x0A4D) or cp == 0x0A51 or
  between(cp, 0x0A70, 0x0A71) or cp == 0x0A75 or
  between(cp, 0x0A81, 0x0A82) or cp == 0x0ABC or between(cp, 0x0AC1, 0x0AC5) or
  between(cp, 0x0AC7, 0x0AC8) or cp == 0x0ACD or between(cp, 0x0AE2, 0x0AE3) or
  cp == 0x0B01 or cp == 0x0B3C or cp == 0x0B3F or between(cp, 0x0B41, 0x0B44) or
  cp == 0x0B4D or cp == 0x0B56 or between(cp, 0x0B62, 0x0B63) or
  cp == 0x0B82 or cp == 0x0BC0 or cp == 0x0BCD or cp == 0x0C00 or
  cp == 0x0C04 or between(cp, 0x0C3E, 0x0C40) or between(cp, 0x0C46, 0x0C48) or
  between(cp, 0x0C4A, 0x0C4D) or between(cp, 0x0C55, 0x0C56) or
  between(cp, 0x0C62, 0x0C63) or cp == 0x0C81 or cp == 0x0CBC or
  cp == 0x0CBF or cp == 0x0CC6 or between(cp, 0x0CCC, 0x0CCD) or
  between(cp, 0x0CE2, 0x0CE3) or between(cp, 0x0D00, 0x0D01) or
  between(cp, 0x0D3B, 0x0D3C) or between(cp, 0x0D41, 0x0D44) or cp == 0x0D4D or
  between(cp, 0x0D62, 0x0D63) or cp == 0x0D81 or cp == 0x0DCA or
  between(cp, 0x0DD2, 0x0DD4) or cp == 0x0DD6 or cp == 0x0E31 or
  between(cp, 0x0E34, 0x0E3A) or between(cp, 0x0E47, 0x0E4E) or
  cp == 0x0EB1 or between(cp, 0x0EB4, 0x0EBC) or between(cp, 0x0EC8, 0x0ECD) or
  between(cp, 0x0F18, 0x0F19) or cp == 0x0F35 or cp == 0x0F37 or cp == 0x0F39 or
  between(cp, 0x0F71, 0x0F7E) or between(cp, 0x0F80, 0x0F84) or
  between(cp, 0x0F86, 0x0F87) or between(cp, 0x0F8D, 0x0F97) or
  between(cp, 0x0F99, 0x0FBC) or cp == 0x0FC6 or
  between(cp, 0x102D, 0x1030) or between(cp, 0x1032, 0x1037) or
  between(cp, 0x1039, 0x103A) or between(cp, 0x103D, 0x103E) or
  between(cp, 0x1058, 0x1059) or between(cp, 0x105E, 0x1060) or
  between(cp, 0x1071, 0x1074) or cp == 0x1082 or between(cp, 0x1085, 0x1086) or
  cp == 0x108D or cp == 0x109D or between(cp, 0x135D, 0x135F) or
  between(cp, 0x1712, 0x1714) or between(cp, 0x1732, 0x1734) or
  between(cp, 0x1752, 0x1753) or between(cp, 0x1772, 0x1773) or
  between(cp, 0x17B4, 0x17B5) or between(cp, 0x17B7, 0x17BD) or cp == 0x17C6 or
  between(cp, 0x17C9, 0x17D3) or cp == 0x17DD or
  between(cp, 0x180B, 0x180D) or cp == 0x18A9 or
  between(cp, 0x1920, 0x1922) or between(cp, 0x1927, 0x1928) or cp == 0x1932 or
  between(cp, 0x1939, 0x193B) or between(cp, 0x1A17, 0x1A18) or cp == 0x1A1B or
  cp == 0x1A56 or between(cp, 0x1A58, 0x1A5E) or cp == 0x1A60 or cp == 0x1A62 or
  between(cp, 0x1A65, 0x1A6C) or between(cp, 0x1A73, 0x1A7C) or cp == 0x1A7F or
  between(cp, 0x1AB0, 0x1AFF) or between(cp, 0x1B00, 0x1B03) or cp == 0x1B34 or
  between(cp, 0x1B36, 0x1B3A) or cp == 0x1B3C or cp == 0x1B42 or
  between(cp, 0x1B6B, 0x1B73) or between(cp, 0x1B80, 0x1B81) or
  between(cp, 0x1BA2, 0x1BA5) or between(cp, 0x1BA8, 0x1BA9) or
  between(cp, 0x1BAB, 0x1BAD) or cp == 0x1BE6 or between(cp, 0x1BE8, 0x1BE9) or
  cp == 0x1BED or between(cp, 0x1BEF, 0x1BF1) or
  between(cp, 0x1C2C, 0x1C33) or between(cp, 0x1C36, 0x1C37) or
  between(cp, 0x1CD0, 0x1CD2) or between(cp, 0x1CD4, 0x1CE0) or
  between(cp, 0x1CE2, 0x1CE8) or cp == 0x1CED or cp == 0x1CF4 or
  between(cp, 0x1CF8, 0x1CF9) or between(cp, 0x1DC0, 0x1DFF) or
  between(cp, 0x20D0, 0x20F0) or between(cp, 0x2CEF, 0x2CF1) or cp == 0x2D7F or
  between(cp, 0x2DE0, 0x2DFF) or between(cp, 0x302A, 0x302D) or
  between(cp, 0x3099, 0x309A) or cp == 0xA66F or between(cp, 0xA674, 0xA67D) or
  between(cp, 0xA69E, 0xA69F) or between(cp, 0xA6F0, 0xA6F1) or cp == 0xA802 or
  cp == 0xA806 or cp == 0xA80B or between(cp, 0xA825, 0xA826) or
  between(cp, 0xA8C4, 0xA8C5) or between(cp, 0xA8E0, 0xA8F1) or
  between(cp, 0xA926, 0xA92D) or between(cp, 0xA947, 0xA951) or
  between(cp, 0xA980, 0xA982) or cp == 0xA9B3 or between(cp, 0xA9B6, 0xA9B9) or
  cp == 0xA9BC or cp == 0xA9E5 or between(cp, 0xAA29, 0xAA2E) or
  between(cp, 0xAA31, 0xAA32) or between(cp, 0xAA35, 0xAA36) or cp == 0xAA43 or
  cp == 0xAA4C or cp == 0xAAB0 or between(cp, 0xAAB2, 0xAAB4) or
  between(cp, 0xAAB7, 0xAAB8) or between(cp, 0xAABE, 0xAABF) or cp == 0xAAC1 or
  between(cp, 0xAAEC, 0xAAED) or cp == 0xAAF6 or cp == 0xABE5 or cp == 0xABE8 or
  cp == 0xABED or cp == 0xFB1E or between(cp, 0xFE00, 0xFE0F) or
  between(cp, 0xFE20, 0xFE2F) or cp == 0x101FD or cp == 0x102E0 or
  between(cp, 0x10376, 0x1037A) or between(cp, 0x10A01, 0x10A03) or
  between(cp, 0x10A05, 0x10A06) or between(cp, 0x10A0C, 0x10A0F) or
  between(cp, 0x10A38, 0x10A3A) or cp == 0x10A3F or
  between(cp, 0x10AE5, 0x10AE6) or between(cp, 0x10D24, 0x10D27) or
  between(cp, 0x10EAB, 0x10EAC) or between(cp, 0x10F46, 0x10F50) or
  cp == 0x11001 or between(cp, 0x11038, 0x11046) or
  between(cp, 0x1107F, 0x11081) or between(cp, 0x110B3, 0x110B6) or
  between(cp, 0x110B9, 0x110BA) or cp == 0x110C2 or
  between(cp, 0x11100, 0x11102) or between(cp, 0x11127, 0x1112B) or
  between(cp, 0x1112D, 0x11134) or cp == 0x11173 or
  between(cp, 0x11180, 0x11181) or between(cp, 0x111B6, 0x111BE) or
  between(cp, 0x111C9, 0x111CC) or cp == 0x111CF or
  between(cp, 0x1122F, 0x11231) or cp == 0x11234 or
  between(cp, 0x11236, 0x11237) or cp == 0x1123E or cp == 0x112DF or
  between(cp, 0x112E3, 0x112EA) or between(cp, 0x11300, 0x11301) or
  between(cp, 0x1133B, 0x1133C) or cp == 0x11340 or
  between(cp, 0x11366, 0x1136C) or between(cp, 0x11370, 0x11374) or
  between(cp, 0x11438, 0x1143F) or between(cp, 0x11442, 0x11444) or
  cp == 0x11446 or cp == 0x1145E or between(cp, 0x114B3, 0x114B8) or
  cp == 0x114BA or between(cp, 0x114BF, 0x114C0) or
  between(cp, 0x114C2, 0x114C3) or between(cp, 0x115B2, 0x115B5) or
  between(cp, 0x115BC, 0x115BD) or between(cp, 0x115BF, 0x115C0) or
  between(cp, 0x115DC, 0x115DD) or between(cp, 0x11633, 0x1163A) or
  cp == 0x1163D or between(cp, 0x1163F, 0x11640) or cp == 0x116AB or
  cp == 0x116AD or between(cp, 0x116B0, 0x116B5) or cp == 0x116B7 or
  between(cp, 0x1171D, 0x1171F) or between(cp, 0x11722, 0x11725) or
  between(cp, 0x11727, 0x1172B) or between(cp, 0x1182F, 0x11837) or
  between(cp, 0x11839, 0x1183A) or between(cp, 0x1193B, 0x1193C) or
  cp == 0x1193E or cp == 0x11943 or between(cp, 0x119D4, 0x119D7) or
  between(cp, 0x119DA, 0x119DB) or cp == 0x119E0 or
  between(cp, 0x11A01, 0x11A0A) or between(cp, 0x11A33, 0x11A38) or
  between(cp, 0x11A3B, 0x11A3E) or cp == 0x11A47 or
  between(cp, 0x11A51, 0x11A56) or between(cp, 0x11A59, 0x11A5B) or
  between(cp, 0x11A8A, 0x11A96) or between(cp, 0x11A98, 0x11A99) or
  between(cp, 0x11C30, 0x11C36) or between(cp, 0x11C38, 0x11C3D) or
  cp == 0x11C3F or between(cp, 0x11C92, 0x11CA7) or
  between(cp, 0x11CAA, 0x11CB0) or between(cp, 0x11CB2, 0x11CB3) or
  between(cp, 0x11CB5, 0x11CB6) or between(cp, 0x11D31, 0x11D36) or
  cp == 0x11D3A or between(cp, 0x11D3C, 0x11D3D) or
  between(cp, 0x11D3F, 0x11D45) or cp == 0x11D47 or
  between(cp, 0x11D90, 0x11D91) or cp == 0x11D95 or cp == 0x11D97 or
  between(cp, 0x11EF3, 0x11EF4) or between(cp, 0x16AF0, 0x16AF4) or
  between(cp, 0x16B30, 0x16B36) or cp == 0x16F4F or
  between(cp, 0x16F8F, 0x16F92) or cp == 0x16FE4 or
  between(cp, 0x1BC9D, 0x1BC9E) or between(cp, 0x1D165, 0x1D169) or
  between(cp, 0x1D16D, 0x1D172) or between(cp, 0x1D17B, 0x1D182) or
  between(cp, 0x1D185, 0x1D18B) or between(cp, 0x1D1AA, 0x1D1AD) or
  between(cp, 0x1D242, 0x1D244) or between(cp, 0x1DA00, 0x1DA36) or
  between(cp, 0x1DA3B, 0x1DA6C) or cp == 0x1DA75 or cp == 0x1DA84 or
  between(cp, 0x1DA9B, 0x1DA9F) or between(cp, 0x1DAA1, 0x1DAAF) or
  between(cp, 0x1E000, 0x1E02A) or between(cp, 0x1E130, 0x1E136) or
  between(cp, 0x1E2EC, 0x1E2EF) or between(cp, 0x1E8D0, 0x1E8D6) or
  between(cp, 0x1E944, 0x1E94A) or between(cp, 0xE0020, 0xE007F) or
  between(cp, 0xE0100, 0xE01EF) or between(cp, 0x1F3FB, 0x1F3FF) or
  cp == 0x200C

proc isRegionalIndicator(cp: int32): bool =
  between(cp, 0x1F1E6, 0x1F1FF)

proc isPictographic(cp: int32): bool =
  between(cp, 0x1F000, 0x1FAFF) or between(cp, 0x2600, 0x27BF) or
  between(cp, 0x2B00, 0x2BFF) or between(cp, 0x2190, 0x21FF) or
  between(cp, 0x2300, 0x23FF) or between(cp, 0x25A0, 0x25FF) or
  between(cp, 0x2900, 0x297F) or cp == 0x00A9 or cp == 0x00AE or
  cp == 0x203C or cp == 0x2049 or cp == 0x2122 or cp == 0x2139 or
  cp == 0x3030 or cp == 0x303D or cp == 0x3297 or cp == 0x3299

proc isControl(cp: int32): bool =
  cp >= 0 and (cp <= 0x1F or between(cp, 0x7F, 0x9F) or
    cp == 0x2028 or cp == 0x2029)

proc graphemeBoundaries*(text: string): seq[int] =
  ## Byte offsets where a new grapheme cluster starts, always including 0 and
  ## text.len. Invalid UTF-8 bytes each form their own cluster.
  result = @[0]
  if text.len == 0:
    return
  var index = 0
  var previous: DecodedRune
  var hasPrevious = false
  var regionalRun = 0
  while index < text.len:
    let current = decodeRune(text, index)
    var boundary = true
    if hasPrevious:
      let prev = previous.code
      if prev == 0x0D and current.code == 0x0A:
        boundary = false
      elif isControl(prev) or isControl(current.code):
        boundary = true
      elif isExtend(current.code) or current.code == 0x200D:
        boundary = false
      elif prev == 0x200D and
          (isExtend(current.code) or isPictographic(current.code)):
        boundary = false
      elif isRegionalIndicator(prev) and isRegionalIndicator(current.code):
        boundary = regionalRun mod 2 == 0
    if boundary and index > 0:
      result.add index
    if isRegionalIndicator(current.code):
      inc regionalRun
    else:
      regionalRun = 0
    previous = current
    hasPrevious = true
    index += max(1, current.size)
  if result[^1] != text.len:
    result.add text.len

proc graphemeStartAt*(text: string, offset: int): int =
  ## Largest cluster boundary at or before `offset`.
  let limit = max(0, min(offset, text.len))
  result = 0
  for boundary in graphemeBoundaries(text):
    if boundary <= limit: result = boundary
    else: break

proc graphemeStartBefore*(text: string, offset: int): int =
  ## Largest cluster boundary strictly before `offset`.
  let limit = max(0, min(offset, text.len))
  result = 0
  for boundary in graphemeBoundaries(text):
    if boundary < limit: result = boundary
    else: break

proc graphemeEndAfter*(text: string, offset: int): int =
  ## Smallest cluster boundary strictly after `offset`.
  let limit = max(0, min(offset, text.len))
  result = text.len
  for boundary in graphemeBoundaries(text):
    if boundary > limit:
      return boundary

proc graphemeCeil*(text: string, offset: int): int =
  ## Smallest cluster boundary at or after `offset`.
  let limit = max(0, min(offset, text.len))
  for boundary in graphemeBoundaries(text):
    if boundary >= limit:
      return boundary
  text.len

proc utf16Length*(text: string): int =
  ## UTF-16 code units, matching AppKit's NSRange coordinates.
  var index = 0
  while index < text.len:
    let rune = decodeRune(text, index)
    result += (if rune.code > 0xFFFF: 2 else: 1)
    index += max(1, rune.size)

proc utf8OffsetForUtf16*(text: string, location: int): int =
  ## Round down when a UTF-16 offset falls inside a surrogate pair.
  if location <= 0:
    return 0
  var index = 0
  var units = 0
  while index < text.len:
    let rune = decodeRune(text, index)
    let width = if rune.code > 0xFFFF: 2 else: 1
    if units + width > location:
      return index
    units += width
    index += max(1, rune.size)
    if units == location:
      return index
  text.len

proc utf16OffsetForUtf8*(text: string, offset: int): int =
  ## Round down when `offset` points inside a multi-byte code point.
  let limit = max(0, min(offset, text.len))
  var index = 0
  while index < text.len:
    let rune = decodeRune(text, index)
    let width = max(1, rune.size)
    if index + width > limit:
      return result
    result += (if rune.code > 0xFFFF: 2 else: 1)
    index += width
  result
