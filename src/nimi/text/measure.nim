## CoreText text measurement for layout. This is the macOS M2 implementation;
## a platform-abstract text engine replaces it when Windows/Linux land.
##
## The renderer uses the same font names ("Helvetica"/"Helvetica-Bold"), so
## layout and paint agree.

import std/[dynlib, strutils, tables, unicode]

type
  TextMetrics* = object
    width*, height*, ascent*, descent*, leading*: float32

  TextLayout* = object
    lines*: seq[string]
    width*, height*, lineHeight*, ascent*: float32

  CFRef = pointer

let
  cf = loadLib("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
  ct = loadLib("/System/Library/Frameworks/CoreText.framework/CoreText")

template fn(lib: LibHandle, name: string, T: untyped): untyped =
  cast[T](symAddr(lib, name))

let
  CFStringCreateWithCString = fn(cf, "CFStringCreateWithCString",
    proc(a: CFRef, s: cstring, e: uint32): CFRef {.cdecl.})
  CFDictionaryCreateMutable = fn(cf, "CFDictionaryCreateMutable",
    proc(a: CFRef, cap: int, k: pointer, v: pointer): CFRef {.cdecl.})
  CFDictionaryAddValue = fn(cf, "CFDictionaryAddValue",
    proc(d: CFRef, k, v: CFRef) {.cdecl.})
  CFAttributedStringCreate = fn(cf, "CFAttributedStringCreate",
    proc(a: CFRef, s: CFRef, attrs: CFRef): CFRef {.cdecl.})
  CFRelease = fn(cf, "CFRelease", proc(x: CFRef) {.cdecl.})

  CTFontCreateWithName = fn(ct, "CTFontCreateWithName",
    proc(n: CFRef, size: float64, m: pointer): CFRef {.cdecl.})
  CTLineCreateWithAttributedString = fn(ct, "CTLineCreateWithAttributedString",
    proc(s: CFRef): CFRef {.cdecl.})
  CTLineGetTypographicBounds = fn(ct, "CTLineGetTypographicBounds",
    proc(l: CFRef, ascent, descent, leading: ptr float64): float64 {.cdecl.})

let
  kCTFontAttributeName = cast[ptr CFRef](
    symAddr(ct, "kCTFontAttributeName"))[]
  kCFTypeDictionaryKeyCallBacks = cast[pointer](
    symAddr(cf, "kCFTypeDictionaryKeyCallBacks"))
  kCFTypeDictionaryValueCallBacks = cast[pointer](
    symAddr(cf, "kCFTypeDictionaryValueCallBacks"))

var cache: Table[string, TextMetrics]

proc cfstr(s: string): CFRef =
  CFStringCreateWithCString(nil, s.cstring, 0x08000100'u32)

proc measureText*(text: string, size: float32, bold: bool): TextMetrics =
  ## Advance width and line metrics for one line.
  let key = text & "\x00" & $size & "\x00" & $bold
  if cache.hasKey(key):
    return cache[key]

  let fontName = cfstr(if bold: "Helvetica-Bold" else: "Helvetica")
  defer: CFRelease(fontName)
  let font = CTFontCreateWithName(fontName, float64(max(size, 1.0'f32)), nil)
  defer: CFRelease(font)

  let attrs = CFDictionaryCreateMutable(nil, 1,
    kCFTypeDictionaryKeyCallBacks, kCFTypeDictionaryValueCallBacks)
  defer: CFRelease(attrs)
  CFDictionaryAddValue(attrs, kCTFontAttributeName, font)

  let str = cfstr(text)
  defer: CFRelease(str)
  let attrStr = CFAttributedStringCreate(nil, str, attrs)
  defer: CFRelease(attrStr)
  let line = CTLineCreateWithAttributedString(attrStr)
  defer: CFRelease(line)

  var ascent, descent, leading: float64
  let width = CTLineGetTypographicBounds(line, addr ascent, addr descent,
                                        addr leading)
  result = TextMetrics(
    width: float32(width),
    height: float32(ascent + descent + leading),
    ascent: float32(ascent),
    descent: float32(descent),
    leading: float32(leading))
  cache[key] = result


proc layoutText*(text: string, size: float32, bold: bool,
                 maxWidth: float32 = 0): TextLayout =
  ## M2 line breaking: split on newlines, then greedily wrap at spaces (or
  ## between runes for CJK/long words). Replace with CTTypesetter/Pango later.
  let sample = measureText("Ag", size, bold)
  result.lineHeight = sample.height
  result.ascent = sample.ascent

  if maxWidth <= 0:
    for line in text.split('\n'):
      result.lines.add line
    if result.lines.len == 0:
      result.lines.add ""
  else:
    var line = ""
    for r in text.runes:
      let ch = $r
      if ch == "\n":
        result.lines.add line
        line = ""
        continue
      let candidate = line & ch
      if line.len == 0 or measureText(candidate, size, bold).width <= maxWidth:
        line = candidate
      else:
        let cut = line.rfind(' ')
        if cut > 0:
          result.lines.add line[0 ..< cut]
          line = line[cut + 1 .. ^1] & ch
        else:
          result.lines.add line
          line = ch
    if line.len > 0 or result.lines.len == 0:
      result.lines.add line

  result.width = 0
  for line in result.lines:
    result.width = max(result.width, measureText(line, size, bold).width)
  result.height = result.lineHeight * float32(result.lines.len)
