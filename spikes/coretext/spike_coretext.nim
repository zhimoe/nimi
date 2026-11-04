## Feasibility spike 3: CoreText shaping + CoreGraphics rasterization + PNG out,
## all from Nim through C FFI (no cgo, no Objective-C source).
##   nim c -r --mm:orc spike_coretext.nim
## Writes coretext.png next to the binary.

import std/[dynlib]

type
  CFRef = pointer
  CGFloat = float64
  CGPoint {.bycopy.} = object
    x, y: CGFloat
  CGSize {.bycopy.} = object
    w, h: CGFloat
  CGRect {.bycopy.} = object
    x, y, w, h: CGFloat
  CGAffineTransform {.bycopy.} = object
    a, b, c, d, tx, ty: CGFloat

let
  cf = loadLib("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
  ct = loadLib("/System/Library/Frameworks/CoreText.framework/CoreText")
  cg = loadLib("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
  io = loadLib("/System/Library/Frameworks/ImageIO.framework/ImageIO")

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
  CFURLCreateFromFileSystemRepresentation = fn(cf, "CFURLCreateFromFileSystemRepresentation",
    proc(a: CFRef, b: pointer, n: int, dir: bool): CFRef {.cdecl.})
  CFRelease = fn(cf, "CFRelease", proc(x: CFRef) {.cdecl.})

  CTFontCreateWithName = fn(ct, "CTFontCreateWithName",
    proc(n: CFRef, size: CGFloat, m: pointer): CFRef {.cdecl.})
  CTLineCreateWithAttributedString = fn(ct, "CTLineCreateWithAttributedString",
    proc(s: CFRef): CFRef {.cdecl.})
  CTLineGetTypographicBounds = fn(ct, "CTLineGetTypographicBounds",
    proc(l: CFRef, ascent, descent, leading: ptr CGFloat): float64 {.cdecl.})
  CTLineDraw = fn(ct, "CTLineDraw", proc(l: CFRef, c: CFRef) {.cdecl.})

  CGColorSpaceCreateDeviceRGB = fn(cg, "CGColorSpaceCreateDeviceRGB",
    proc(): CFRef {.cdecl.})
  CGBitmapContextCreate = fn(cg, "CGBitmapContextCreate",
    proc(data: pointer, w, h: int, bpc, bpr: int, space: CFRef, info: uint32): CFRef {.cdecl.})
  CGContextSetRGBFillColor = fn(cg, "CGContextSetRGBFillColor",
    proc(c: CFRef, r, g, b, a: CGFloat) {.cdecl.})
  CGContextFillRect = fn(cg, "CGContextFillRect",
    proc(c: CFRef, r: CGRect) {.cdecl.})
  CGContextSetTextMatrix = fn(cg, "CGContextSetTextMatrix",
    proc(c: CFRef, t: CGAffineTransform) {.cdecl.})
  CGContextSetTextPosition = fn(cg, "CGContextSetTextPosition",
    proc(c: CFRef, x, y: CGFloat) {.cdecl.})
  CGBitmapContextCreateImage = fn(cg, "CGBitmapContextCreateImage",
    proc(c: CFRef): CFRef {.cdecl.})

  CGImageDestinationCreateWithURL = fn(io, "CGImageDestinationCreateWithURL",
    proc(url: CFRef, typ: CFRef, count: int, opts: pointer): CFRef {.cdecl.})
  CGImageDestinationAddImage = fn(io, "CGImageDestinationAddImage",
    proc(d: CFRef, img: CFRef, props: pointer) {.cdecl.})
  CGImageDestinationFinalize = fn(io, "CGImageDestinationFinalize",
    proc(d: CFRef): bool {.cdecl.})
  CGColorCreateGenericRGB = fn(cg, "CGColorCreateGenericRGB",
    proc(r, g, b, a: CGFloat): CFRef {.cdecl.})

proc cfstr(s: string): CFRef =
  CFStringCreateWithCString(nil, s.cstring, 0x08000100'u32) # UTF-8

when isMainModule:
  const w = 1040
  const h = 200
  let pixels = alloc0(w * h * 4)
  let space = CGColorSpaceCreateDeviceRGB()
  # RGBA8, premultiplied last, big endian
  let ctx = CGBitmapContextCreate(pixels, w, h, 8, w * 4, space,
                                  (4'u32 shl 12) or 1'u32)
  doAssert ctx != nil, "bitmap context"

  let bg = CGRect(x: 0, y: 0, w: CGFloat(w), h: CGFloat(h))
  CGContextSetRGBFillColor(ctx, 0.055, 0.055, 0.075, 1)
  CGContextFillRect(ctx, bg)

  let fontName = cfstr("Helvetica")
  let font = CTFontCreateWithName(fontName, 40, nil)

  # Attributes dictionary: kCTFontAttributeName -> CTFontRef
  let keyAddr = symAddr(ct, "kCTFontAttributeName")
  let key = cast[ptr CFRef](keyAddr)[]
  let keyCallbacks = cast[ptr pointer](symAddr(cf, "kCFTypeDictionaryKeyCallBacks"))
  let valueCallbacks = cast[ptr pointer](symAddr(cf, "kCFTypeDictionaryValueCallBacks"))
  let attrs = CFDictionaryCreateMutable(nil, 1, cast[pointer](keyCallbacks),
                                        cast[pointer](valueCallbacks))
  CFDictionaryAddValue(attrs, key, font)
  let fgKey = cast[ptr CFRef](symAddr(ct, "kCTForegroundColorAttributeName"))[]
  let fgColor = CGColorCreateGenericRGB(0.96, 0.96, 0.98, 1.0)
  CFDictionaryAddValue(attrs, fgKey, fgColor)

  let text = cfstr("Nimi — Hello, 世界 · こんにちは · مرحبا")
  let attrStr = CFAttributedStringCreate(nil, text, attrs)
  let line = CTLineCreateWithAttributedString(attrStr)

  var ascent, descent, leading: CGFloat
  let width = CTLineGetTypographicBounds(line, addr ascent, addr descent, addr leading)
  echo "line width=", width, " ascent=", ascent, " descent=", descent, " leading=", leading

  CGContextSetTextMatrix(ctx, CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0))
  CGContextSetTextPosition(ctx, 32, 80)
  CGContextSetRGBFillColor(ctx, 0.96, 0.96, 0.98, 1)
  CTLineDraw(line, ctx)

  # Count lit pixels to prove something was drawn.
  var lit = 0
  let bytes = cast[ptr UncheckedArray[uint8]](pixels)
  for i in 0 ..< w * h:
    if bytes[i * 4] > 40 or bytes[i * 4 + 1] > 40 or bytes[i * 4 + 2] > 40:
      inc lit
  echo "lit pixels: ", lit

  let image = CGBitmapContextCreateImage(ctx)
  let path = "coretext.png"
  let url = CFURLCreateFromFileSystemRepresentation(nil, path.cstring, path.len, false)
  let pngType = cfstr("public.png")
  let dest = CGImageDestinationCreateWithURL(url, pngType, 1, nil)
  doAssert dest != nil, "image destination"
  CGImageDestinationAddImage(dest, image, nil)
  let ok = CGImageDestinationFinalize(dest)
  echo "wrote ", path, ": ", ok
  doAssert ok
