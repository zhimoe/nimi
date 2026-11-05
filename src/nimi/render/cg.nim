## CoreGraphics + CoreText renderer for the M2 scene. Draws into the current
## NSView CGContext (top-left scene coordinates converted to AppKit's
## bottom-left context). No GPU yet: this is the reference path and the M2
## vertical slice.

import std/[dynlib, tables]

import ../scene/scene

type
  CFRef = pointer
  CGFloat = float64
  CGRect {.bycopy.} = object
    x, y, w, h: CGFloat
  CGAffineTransform {.bycopy.} = object
    a, b, c, d, tx, ty: CGFloat

let
  io = loadLib("/System/Library/Frameworks/ImageIO.framework/ImageIO")
  cf = loadLib("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
  ct = loadLib("/System/Library/Frameworks/CoreText.framework/CoreText")
  cg = loadLib("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")

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
    proc(n: CFRef, size: CGFloat, m: pointer): CFRef {.cdecl.})
  CTLineCreateWithAttributedString = fn(ct, "CTLineCreateWithAttributedString",
    proc(s: CFRef): CFRef {.cdecl.})
  CTLineGetTypographicBounds = fn(ct, "CTLineGetTypographicBounds",
    proc(l: CFRef, ascent, descent, leading: ptr CGFloat): float64 {.cdecl.})
  CTLineDraw = fn(ct, "CTLineDraw", proc(l: CFRef, c: CFRef) {.cdecl.})

  CGColorCreateGenericRGB = fn(cg, "CGColorCreateGenericRGB",
    proc(r, g, b, a: CGFloat): CFRef {.cdecl.})
  CGContextSetRGBFillColor = fn(cg, "CGContextSetRGBFillColor",
    proc(c: CFRef, r, g, b, a: CGFloat) {.cdecl.})
  CGContextSaveGState = fn(cg, "CGContextSaveGState",
    proc(c: CFRef) {.cdecl.})
  CGContextRestoreGState = fn(cg, "CGContextRestoreGState",
    proc(c: CFRef) {.cdecl.})
  CGContextClipToRect = fn(cg, "CGContextClipToRect",
    proc(c: CFRef, r: CGRect) {.cdecl.})
  CGContextDrawImage = fn(cg, "CGContextDrawImage",
    proc(c: CFRef, r: CGRect, img: CFRef) {.cdecl.})
  CGImageCreateWithImageInRect = fn(cg, "CGImageCreateWithImageInRect",
    proc(img: CFRef, r: CGRect): CFRef {.cdecl.})
  CGImageGetWidth = fn(cg, "CGImageGetWidth",
    proc(img: CFRef): uint {.cdecl.})
  CGImageGetHeight = fn(cg, "CGImageGetHeight",
    proc(img: CFRef): uint {.cdecl.})
  CGContextBeginPath = fn(cg, "CGContextBeginPath",
    proc(c: CFRef) {.cdecl.})
  CGContextMoveToPoint = fn(cg, "CGContextMoveToPoint",
    proc(c: CFRef, x, y: CGFloat) {.cdecl.})
  CGContextAddLineToPoint = fn(cg, "CGContextAddLineToPoint",
    proc(c: CFRef, x, y: CGFloat) {.cdecl.})
  CGContextClosePath = fn(cg, "CGContextClosePath",
    proc(c: CFRef) {.cdecl.})
  CGContextClip = fn(cg, "CGContextClip", proc(c: CFRef) {.cdecl.})
  CGContextConcatCTM = fn(cg, "CGContextConcatCTM",
    proc(c: CFRef, t: CGAffineTransform) {.cdecl.})
  CGImageRelease = fn(cg, "CGImageRelease", proc(img: CFRef) {.cdecl.})
  CGContextFillRect = fn(cg, "CGContextFillRect",
    proc(c: CFRef, r: CGRect) {.cdecl.})
  CGContextSetTextMatrix = fn(cg, "CGContextSetTextMatrix",
    proc(c: CFRef, t: CGAffineTransform) {.cdecl.})
  CGContextSetTextPosition = fn(cg, "CGContextSetTextPosition",
    proc(c: CFRef, x, y: CGFloat) {.cdecl.})
  CGPathCreateWithRoundedRect = fn(cg, "CGPathCreateWithRoundedRect",
    proc(r: CGRect, cw, ch: CGFloat, t: pointer): CFRef {.cdecl.})
  CGContextAddPath = fn(cg, "CGContextAddPath",
    proc(c: CFRef, path: CFRef) {.cdecl.})
  CGContextFillPath = fn(cg, "CGContextFillPath",
    proc(c: CFRef) {.cdecl.})
  CGPathRelease = fn(cg, "CGPathRelease", proc(p: CFRef) {.cdecl.})
  CGColorSpaceCreateDeviceRGB = fn(cg, "CGColorSpaceCreateDeviceRGB",
    proc(): CFRef {.cdecl.})
  CGBitmapContextCreate = fn(cg, "CGBitmapContextCreate",
    proc(data: pointer, w, h: int, bpc, bpr: int, space: CFRef,
         info: uint32): CFRef {.cdecl.})
  CGBitmapContextCreateImage = fn(cg, "CGBitmapContextCreateImage",
    proc(c: CFRef): CFRef {.cdecl.})
  CGContextRelease = fn(cg, "CGContextRelease", proc(c: CFRef) {.cdecl.})
  CGImageSourceCreateWithURL = fn(io, "CGImageSourceCreateWithURL",
    proc(url: CFRef, opts: pointer): CFRef {.cdecl.})
  CGImageSourceCreateImageAtIndex = fn(io, "CGImageSourceCreateImageAtIndex",
    proc(src: CFRef, index: int, opts: pointer): CFRef {.cdecl.})
  CGImageDestinationCreateWithURL = fn(io, "CGImageDestinationCreateWithURL",
    proc(url: CFRef, typ: CFRef, count: int, opts: pointer): CFRef {.cdecl.})
  CGImageDestinationAddImage = fn(io, "CGImageDestinationAddImage",
    proc(d: CFRef, img: CFRef, props: pointer) {.cdecl.})
  CGImageDestinationFinalize = fn(io, "CGImageDestinationFinalize",
    proc(d: CFRef): bool {.cdecl.})
  CGDataProviderCreateWithData = fn(cg, "CGDataProviderCreateWithData",
    proc(info: pointer, data: pointer, size: int,
         releaseData: pointer): CFRef {.cdecl.})
  CGImageCreate = fn(cg, "CGImageCreate",
    proc(width, height: int, bitsPerComponent, bitsPerPixel, bytesPerRow: int,
         space: CFRef, bitmapInfo: uint32, provider: CFRef,
         decode: pointer, shouldInterpolate: bool,
         intent: uint32): CFRef {.cdecl.})
  CFURLCreateFromFileSystemRepresentation = fn(cf,
    "CFURLCreateFromFileSystemRepresentation",
    proc(a: CFRef, b: pointer, n: int, dir: bool): CFRef {.cdecl.})

let
  kCTFontAttributeName = cast[ptr CFRef](
    symAddr(ct, "kCTFontAttributeName"))[]
  kCTForegroundColorAttributeName = cast[ptr CFRef](
    symAddr(ct, "kCTForegroundColorAttributeName"))[]
  kCFTypeDictionaryKeyCallBacks = cast[pointer](
    symAddr(cf, "kCFTypeDictionaryKeyCallBacks"))
  kCFTypeDictionaryValueCallBacks = cast[pointer](
    symAddr(cf, "kCFTypeDictionaryValueCallBacks"))

proc cfstr(s: string): CFRef =
  CFStringCreateWithCString(nil, s.cstring, 0x08000100'u32)


proc drawText(ctx: CFRef, op: Op, sceneHeight: float32) =
  let fontName = cfstr(if op.bold: "Helvetica-Bold" else: "Helvetica")
  defer: CFRelease(fontName)
  let font = CTFontCreateWithName(fontName, CGFloat(op.size), nil)
  defer: CFRelease(font)

  let color = CGColorCreateGenericRGB(CGFloat(op.color.r), CGFloat(op.color.g),
                                      CGFloat(op.color.b), CGFloat(op.color.a))
  defer: CFRelease(color)

  let attrs = CFDictionaryCreateMutable(nil, 2,
    kCFTypeDictionaryKeyCallBacks, kCFTypeDictionaryValueCallBacks)
  defer: CFRelease(attrs)
  CFDictionaryAddValue(attrs, kCTFontAttributeName, font)
  CFDictionaryAddValue(attrs, kCTForegroundColorAttributeName, color)

  let text = cfstr(op.text)
  defer: CFRelease(text)
  let attrStr = CFAttributedStringCreate(nil, text, attrs)
  defer: CFRelease(attrStr)
  let line = CTLineCreateWithAttributedString(attrStr)
  defer: CFRelease(line)

  var ascent, descent, leading: CGFloat
  discard CTLineGetTypographicBounds(line, addr ascent, addr descent, addr leading)
  let baseline = CGFloat(sceneHeight) - CGFloat(op.y) - ascent

  CGContextSetTextMatrix(ctx, CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0))
  CGContextSetTextPosition(ctx, CGFloat(op.x), baseline)
  CTLineDraw(line, ctx)

var imageCache: Table[string, CFRef]
var cropCache: Table[tuple[path: string, x, y, w, h: int], CFRef]

proc loadImage(path: string): CFRef =
  if path.len == 0:
    return nil
  if imageCache.hasKey(path):
    return imageCache[path]
  let url = CFURLCreateFromFileSystemRepresentation(
    nil, path.cstring, path.len, false)
  if url == nil:
    return nil
  let src = CGImageSourceCreateWithURL(url, nil)
  CFRelease(url)
  if src == nil:
    return nil
  let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
  CFRelease(src)
  if img != nil:
    imageCache[path] = img
  result = img

proc cropImage(path: string, source: Rect): CFRef =
  ## Cache a source rectangle crop in image-pixel coordinates (top-left).
  let full = loadImage(path)
  if full == nil:
    return nil
  let iw = int(CGImageGetWidth(full))
  let ih = int(CGImageGetHeight(full))
  if iw <= 0 or ih <= 0:
    return nil
  let x = max(0, min(iw - 1, int(source.x)))
  let y = max(0, min(ih - 1, int(source.y)))
  let w = max(1, min(iw - x, int(source.w)))
  let h = max(1, min(ih - y, int(source.h)))
  let key = (path: path, x: x, y: y, w: w, h: h)
  if cropCache.hasKey(key):
    return cropCache[key]
  let rect = CGRect(x: CGFloat(x), y: CGFloat(ih - y - h),
                    w: CGFloat(w), h: CGFloat(h))
  let crop = CGImageCreateWithImageInRect(full, rect)
  if crop != nil:
    cropCache[key] = crop
  result = crop

proc affineForTriangles(s0, s1, s2, d0, d1, d2: Point): CGAffineTransform =
  let m00 = s1.x - s0.x
  let m01 = s1.y - s0.y
  let m10 = s2.x - s0.x
  let m11 = s2.y - s0.y
  let det = m00 * m11 - m01 * m10
  if abs(det) < 1e-6:
    return CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
  let rx1 = d1.x - d0.x
  let rx2 = d2.x - d0.x
  let ry1 = d1.y - d0.y
  let ry2 = d2.y - d0.y
  let a = (rx1 * m11 - rx2 * m01) / det
  let c = (m00 * rx2 - m10 * rx1) / det
  let b = (ry1 * m11 - ry2 * m01) / det
  let d = (m00 * ry2 - m10 * ry1) / det
  result = CGAffineTransform(
    a: CGFloat(a), b: CGFloat(b), c: CGFloat(c), d: CGFloat(d),
    tx: CGFloat(d0.x - a * s0.x - c * s0.y),
    ty: CGFloat(d0.y - b * s0.x - d * s0.y))

proc drawImageTriangle(c: CFRef, img: CFRef, sceneHeight: float32,
                       src, dst: array[3, Point]) =
  ## `src` is in cropped-image coordinates with a top-left origin; `dst` is in
  ## scene coordinates with a top-left origin. CoreGraphics's user space is
  ## bottom-left, so both triangles are flipped before the affine solve.
  let iw = float32(CGImageGetWidth(img))
  let ih = float32(CGImageGetHeight(img))
  if iw <= 0 or ih <= 0:
    return
  var s, d: array[3, Point]
  for i in 0 ..< 3:
    s[i] = Point(x: src[i].x, y: ih - src[i].y)
    d[i] = Point(x: dst[i].x, y: float32(sceneHeight) - dst[i].y)
  let t = affineForTriangles(s[0], s[1], s[2], d[0], d[1], d[2])
  CGContextSaveGState(c)
  CGContextBeginPath(c)
  CGContextMoveToPoint(c, CGFloat(d[0].x), CGFloat(d[0].y))
  CGContextAddLineToPoint(c, CGFloat(d[1].x), CGFloat(d[1].y))
  CGContextAddLineToPoint(c, CGFloat(d[2].x), CGFloat(d[2].y))
  CGContextClosePath(c)
  CGContextClip(c)
  CGContextConcatCTM(c, t)
  CGContextDrawImage(c, CGRect(x: 0, y: 0, w: CGFloat(iw), h: CGFloat(ih)), img)
  CGContextRestoreGState(c)

proc drawImageQuad(c: CFRef, op: Op, sceneHeight: float32) =
  let crop = cropImage(op.imagePath, op.sourceRect)
  if crop == nil:
    return
  let iw = float32(CGImageGetWidth(crop))
  let ih = float32(CGImageGetHeight(crop))
  if iw <= 0 or ih <= 0:
    return
  let tl = Point(x: 0, y: 0)
  let tr = Point(x: iw, y: 0)
  let br = Point(x: iw, y: ih)
  let bl = Point(x: 0, y: ih)
  drawImageTriangle(c, crop, sceneHeight, [tl, tr, br],
                    [op.quad[0], op.quad[1], op.quad[2]])
  drawImageTriangle(c, crop, sceneHeight, [tl, br, bl],
                    [op.quad[0], op.quad[2], op.quad[3]])

proc drawScene*(ctx: pointer, scene: Scene) =
  ## ctx is a CGContextRef supplied by AppKit (bottom-left origin).
  let c = cast[CFRef](ctx)
  CGContextSetRGBFillColor(c, CGFloat(scene.clear.r), CGFloat(scene.clear.g),
                           CGFloat(scene.clear.b), CGFloat(scene.clear.a))
  CGContextFillRect(c, CGRect(x: 0, y: 0, w: CGFloat(scene.width),
                              h: CGFloat(scene.height)))

  for op in scene.ops:
    case op.kind
    of opRect:
      let r = CGRect(x: CGFloat(op.rect.x),
                     y: CGFloat(scene.height) - CGFloat(op.rect.y) - CGFloat(op.rect.h),
                     w: CGFloat(op.rect.w), h: CGFloat(op.rect.h))
      CGContextSetRGBFillColor(c, CGFloat(op.color.r), CGFloat(op.color.g),
                               CGFloat(op.color.b), CGFloat(op.color.a))
      if op.radius > 0:
        let path = CGPathCreateWithRoundedRect(r, CGFloat(op.radius),
                                               CGFloat(op.radius), nil)
        CGContextAddPath(c, path)
        CGContextFillPath(c)
        CGPathRelease(path)
      else:
        CGContextFillRect(c, r)
    of opText:
      drawText(c, op, scene.height)
    of opClip:
      let r = op.clipRect
      CGContextSaveGState(c)
      CGContextClipToRect(c, CGRect(
        x: CGFloat(r.x),
        y: CGFloat(scene.height) - CGFloat(r.y) - CGFloat(r.h),
        w: CGFloat(r.w), h: CGFloat(r.h)))
    of opRestore:
      CGContextRestoreGState(c)
    of opImage:
      let img = loadImage(op.imagePath)
      if img != nil:
        let r = op.imageRect
        CGContextDrawImage(c, CGRect(
          x: CGFloat(r.x),
          y: CGFloat(scene.height) - CGFloat(r.y) - CGFloat(r.h),
          w: CGFloat(r.w), h: CGFloat(r.h)), img)
    of opImageQuad:
      drawImageQuad(c, op, scene.height)
    of opPolygon:
      if op.points.len > 0:
        CGContextSetRGBFillColor(c, CGFloat(op.color.r), CGFloat(op.color.g),
                                 CGFloat(op.color.b), CGFloat(op.color.a))
        CGContextBeginPath(c)
        CGContextMoveToPoint(c, CGFloat(op.points[0].x),
                             CGFloat(scene.height) - CGFloat(op.points[0].y))
        for i in 1 ..< op.points.len:
          CGContextAddLineToPoint(c, CGFloat(op.points[i].x),
                                  CGFloat(scene.height) - CGFloat(op.points[i].y))
        CGContextClosePath(c)
        CGContextFillPath(c)


proc renderSceneToPixels*(scene: Scene): tuple[width, height: int,
                                                    pixels: seq[uint8]] =
  ## Render a scene into a tightly packed RGBA8 buffer. This is the bridge used
  ## by the Metal renderer for source textures and by offscreen tests.
  let w = max(1, int(scene.width))
  let h = max(1, int(scene.height))
  let stride = w * 4
  var pixels = newSeq[uint8](stride * h)
  let space = CGColorSpaceCreateDeviceRGB()
  if space == nil:
    return (w, h, pixels)
  let ctx = CGBitmapContextCreate(addr pixels[0], w, h, 8, stride, space,
                                  (4'u32 shl 12) or 1'u32)
  if ctx == nil:
    CFRelease(space)
    return (w, h, pixels)
  drawScene(ctx, scene)
  CGContextRelease(ctx)
  CFRelease(space)
  result = (w, h, pixels)

proc writeRgbaPng*(pixels: seq[uint8], width, height: int,
                   path: string): bool =
  ## Write a tightly packed RGBA8 buffer as a PNG. Used to inspect Metal
  ## offscreen frames in tests and smoke runs.
  if width <= 0 or height <= 0 or pixels.len < width * height * 4:
    return false
  var data = pixels
  let provider = CGDataProviderCreateWithData(nil, addr data[0],
                                               data.len, nil)
  if provider == nil:
    return false
  let space = CGColorSpaceCreateDeviceRGB()
  if space == nil:
    CFRelease(provider)
    return false
  let img = CGImageCreate(width, height, 8, 32, width * 4, space,
                          (4'u32 shl 12) or 1'u32, provider, nil, true, 0)
  if img == nil:
    CFRelease(space)
    CFRelease(provider)
    return false
  let url = CFURLCreateFromFileSystemRepresentation(
    nil, path.cstring, path.len, false)
  let png = cfstr("public.png")
  if url == nil or png == nil:
    if url != nil: CFRelease(url)
    if png != nil: CFRelease(png)
    CGImageRelease(img)
    CFRelease(space)
    CFRelease(provider)
    return false
  let dest = CGImageDestinationCreateWithURL(url, png, 1, nil)
  var ok = false
  if dest != nil:
    CGImageDestinationAddImage(dest, img, nil)
    ok = CGImageDestinationFinalize(dest)
    CFRelease(dest)
  CFRelease(img)
  CFRelease(space)
  CFRelease(provider)
  CFRelease(png)
  CFRelease(url)
  result = ok

proc renderSceneToPng*(scene: Scene, path: string): bool =
  ## Offscreen render with CoreGraphics. Used by Tester/readme screenshots;
  ## returns false if CoreGraphics or ImageIO cannot produce the file.
  let w = max(1, int(scene.width))
  let h = max(1, int(scene.height))
  let stride = w * 4
  let pixels = alloc0(stride * h)
  if pixels == nil:
    return false
  let space = CGColorSpaceCreateDeviceRGB()
  if space == nil:
    dealloc(pixels)
    return false
  let ctx = CGBitmapContextCreate(pixels, w, h, 8, stride, space,
                                  (4'u32 shl 12) or 1'u32)
  if ctx == nil:
    CFRelease(space)
    dealloc(pixels)
    return false
  drawScene(ctx, scene)
  let image = CGBitmapContextCreateImage(ctx)
  let url = CFURLCreateFromFileSystemRepresentation(
    nil, path.cstring, path.len, false)
  let png = cfstr("public.png")
  if url == nil or png == nil or image == nil:
    if png != nil: CFRelease(png)
    if url != nil: CFRelease(url)
    if image != nil: CFRelease(image)
    CGContextRelease(ctx)
    CFRelease(space)
    dealloc(pixels)
    return false
  let dest = CGImageDestinationCreateWithURL(url, png, 1, nil)
  var ok = false
  if dest != nil:
    CGImageDestinationAddImage(dest, image, nil)
    ok = CGImageDestinationFinalize(dest)
  if dest != nil: CFRelease(dest)
  if png != nil: CFRelease(png)
  if url != nil: CFRelease(url)
  if image != nil: CFRelease(image)
  CGContextRelease(ctx)
  if space != nil: CFRelease(space)
  dealloc(pixels)
  result = ok
