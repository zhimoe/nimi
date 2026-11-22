## Shared layout with platform font measurement: CoreText on macOS, GDI on
## Windows. Each platform renderer uses the same font and size as its
## measurement path.
##
## `family` is "" for the platform UI font or "mono" for its monospace font.
## Bounded caches keep per-frame table rendering from repeating expensive
## platform measurement calls.

import std/[strutils, tables, unicode]

when defined(macosx):
  import std/dynlib

type
  TextMetrics* = object
    width*, height*, ascent*, descent*, leading*: float32

  TextLayout* = object
    lines*: seq[string]
    lineStarts*: seq[int]
      ## Byte offset of each line in the source text. Wrapped lines are
      ## adjacent (no separator byte), unlike lines split at newlines.
    width*, height*, lineHeight*, ascent*: float32

const
  measureCacheLimit = 4096
  layoutCacheLimit = 2048
  layoutCacheTextLimit = 4096

proc monoFamily*(): string =
  ## The platform monospace face. Measurement and rendering both map the
  ## "mono" family marker to this face (and to CJK-capable fallbacks).
  when defined(windows): "Consolas"
  elif defined(linux): "Monospace"
  else: "Menlo"

when defined(windows):
  import ../platform/windows/graphics

  var measureCache: Table[string, TextMetrics]

  proc measureKey(text: string, size: float32, bold: bool,
                  family: string): string =
    text & "\x00" & $size & "\x00" & $bold & "\x00" & family

  proc measureText*(text: string, size: float32, bold: bool,
                    family: string = ""): TextMetrics =
    let key = measureKey(text, size, bold, family)
    if measureCache.hasKey(key):
      return measureCache[key]
    let wide = newWideCString(text)
    let face = newWideCString(family)
    var m: array[5, cfloat]
    gdiMeasure(wide, cint(wide.len), max(1'f32, size), cint(bold), face,
               addr m[0])
    result = TextMetrics(width: m[0], height: m[1], ascent: m[2],
                         descent: m[3], leading: m[4])
    if measureCache.len >= measureCacheLimit:
      measureCache.clear()
    measureCache[key] = result
elif defined(macosx):
  type CFRef = pointer

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

  proc faceName(family: string, bold: bool): string =
    if family == "mono":
      if bold: "Menlo-Bold" else: "Menlo"
    else:
      if bold: "Helvetica-Bold" else: "Helvetica"

  proc measureKey(text: string, size: float32, bold: bool,
                  family: string): string =
    text & "\x00" & $size & "\x00" & $bold & "\x00" & family

  proc measureText*(text: string, size: float32, bold: bool,
                    family: string = ""): TextMetrics =
    ## Advance width and line metrics for one line.
    let key = measureKey(text, size, bold, family)
    if cache.hasKey(key):
      return cache[key]

    let fontName = cfstr(faceName(family, bold))
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
    if cache.len >= measureCacheLimit:
      cache.clear()
    cache[key] = result

else:
  import ../platform/linux/pangohelper

  var cache: Table[string, TextMetrics]

  proc measureKey(text: string, size: float32, bold: bool,
                  family: string): string =
    text & "\x00" & $size & "\x00" & $bold & "\x00" & family

  proc measureText*(text: string, size: float32, bold: bool,
                    family: string = ""): TextMetrics =
    ## Advance width and line metrics for one line.
    let key = measureKey(text, size, bold, family)
    if cache.hasKey(key):
      return cache[key]
    let metrics = measurePango(text, size, bold, family)
    result = TextMetrics(
      width: metrics.width,
      height: metrics.height,
      ascent: metrics.ascent,
      descent: metrics.descent,
      leading: 0)
    if cache.len >= measureCacheLimit:
      cache.clear()
    cache[key] = result

var layoutCache: Table[string, TextLayout]

proc layoutKey(text: string, size: float32, bold: bool,
               maxWidth: float32, family: string): string =
  text & "\x00" & $size & "\x00" & $bold & "\x00" & $maxWidth & "\x00" & family

proc computeLayout(text: string, size: float32, bold: bool,
                   maxWidth: float32, family: string): TextLayout =
  ## M2 line breaking: split on newlines, then greedily wrap at spaces (or
  ## between runes for CJK/long words). Replace with CTTypesetter/Pango later.
  let sample = measureText("Ag", size, bold, family)
  result.lineHeight = sample.height
  result.ascent = sample.ascent

  if maxWidth <= 0:
    var start = 0
    for line in text.split('\n'):
      result.lines.add line
      result.lineStarts.add start
      start += line.len + 1
    if result.lines.len == 0:
      result.lines.add ""
      result.lineStarts.add 0
  else:
    var line = ""
    var start = 0
    for r in text.runes:
      let ch = $r
      if ch == "\n":
        result.lines.add line
        result.lineStarts.add start
        start += line.len + 1
        line = ""
        continue
      let candidate = line & ch
      if line.len == 0 or measureText(candidate, size, bold, family).width <= maxWidth:
        line = candidate
      else:
        let cut = line.rfind(' ')
        if cut > 0:
          result.lines.add line[0 ..< cut]
          result.lineStarts.add start
          line = line[cut + 1 .. ^1] & ch
          start += cut + 1
        else:
          result.lines.add line
          result.lineStarts.add start
          start += line.len
          line = ch
    if line.len > 0 or result.lines.len == 0 or
        (text.len > 0 and text[^1] == '\n'):
      result.lines.add line
      result.lineStarts.add start

  result.width = 0
  for line in result.lines:
    result.width = max(result.width, measureText(line, size, bold, family).width)
  result.height = result.lineHeight * float32(result.lines.len)

proc layoutText*(text: string, size: float32, bold: bool,
                 maxWidth: float32 = 0, family: string = ""): TextLayout =
  if text.len <= layoutCacheTextLimit:
    let key = layoutKey(text, size, bold, maxWidth, family)
    if layoutCache.hasKey(key):
      return layoutCache[key]
    result = computeLayout(text, size, bold, maxWidth, family)
    if layoutCache.len >= layoutCacheLimit:
      layoutCache.clear()
    layoutCache[key] = result
  else:
    result = computeLayout(text, size, bold, maxWidth, family)

proc ellipsizeText*(text: string, size: float32, bold: bool,
                    family: string, maxWidth: float32): string =
  ## Grapheme-aware single-line truncation. Returns `text` unchanged when it
  ## fits; otherwise the longest prefix plus U+2026.
  if maxWidth <= 0:
    return text
  if measureText(text, size, bold, family).width <= maxWidth:
    return text
  let ellipsis = "…"
  var prefix = ""
  for r in text.runes:
    let next = prefix & $r
    if measureText(next, size, bold, family).width +
        measureText(ellipsis, size, bold, family).width > maxWidth:
      return prefix & ellipsis
    prefix = next
  ellipsis
