## Cairo scene renderer for Linux. Mirrors the CoreGraphics/GDI scene
## contracts: top-left scene coordinates, rounded rectangles, clipped groups,
## Pango text, images and triangle-mapped image quads.

import std/[math, tables]

import ../platform/linux/[ffi, pangohelper]
import ../scene/scene

const
  CairoFormatArgb32 = 0
  CairoFilterBilinear = 4

proc setColor(cr: pointer, c: Color) =
  cairo_set_source_rgba(cr, cdouble(c.r), cdouble(c.g), cdouble(c.b),
                        cdouble(c.a))

proc roundedRect(cr: pointer, r: Rect, radius: float32) =
  let x = cdouble(r.x)
  let y = cdouble(r.y)
  let w = cdouble(max(0.0'f32, r.w))
  let h = cdouble(max(0.0'f32, r.h))
  let rad = cdouble(min(max(0.0'f32, radius),
                        min(r.w, r.h) / 2.0'f32))
  if rad <= 0:
    cairo_rectangle(cr, x, y, w, h)
    return
  cairo_new_sub_path(cr)
  cairo_arc(cr, x + w - rad, y + rad, rad, -PI / 2, 0)
  cairo_arc(cr, x + w - rad, y + h - rad, rad, 0, PI / 2)
  cairo_arc(cr, x + rad, y + h - rad, rad, PI / 2, PI)
  cairo_arc(cr, x + rad, y + rad, rad, PI, 3 * PI / 2)
  cairo_close_path(cr)

# --- images ----------------------------------------------------------------

var
  imageCache: Table[string, pointer]
  cropCache: Table[tuple[path: string, x, y, w, h: int], pointer]
  imageCacheLimit = 128

proc releaseImageCache() =
  for surface in cropCache.values:
    cairo_surface_destroy(surface)
  cropCache.clear()
  for surface in imageCache.values:
    cairo_surface_destroy(surface)
  imageCache.clear()

proc clearImageCache*() =
  ## Render-thread only. Mirrors the CoreGraphics cache controls.
  releaseImageCache()

proc setImageCacheLimit*(entries: int) =
  ## Limit each cache's entry count, not decoded bytes. Minimum one entry.
  imageCacheLimit = max(1, entries)
  releaseImageCache()

proc imageCacheStats*(): tuple[images, crops: int] =
  (imageCache.len, cropCache.len)

proc pixbufToSurface(pixbuf: pointer): pointer =
  let width = int(gdk_pixbuf_get_width(pixbuf))
  let height = int(gdk_pixbuf_get_height(pixbuf))
  if width <= 0 or height <= 0:
    return nil
  let channels = int(gdk_pixbuf_get_n_channels(pixbuf))
  let srcStride = int(gdk_pixbuf_get_rowstride(pixbuf))
  let hasAlpha = gdk_pixbuf_get_has_alpha(pixbuf) != 0
  let pixels = gdk_pixbuf_get_pixels(pixbuf)
  if pixels == nil:
    return nil
  let surface = cairo_image_surface_create(CairoFormatArgb32,
                                           cint(width), cint(height))
  if surface == nil or cairo_surface_status(surface) != 0:
    if surface != nil:
      cairo_surface_destroy(surface)
    return nil
  cairo_surface_flush(surface)
  let stride = int(cairo_image_surface_get_stride(surface))
  let data = cairo_image_surface_get_data(surface)
  if data == nil:
    cairo_surface_destroy(surface)
    return nil
  let pixelsBase = cast[ptr UncheckedArray[uint8]](pixels)
  let dataBase = cast[ptr UncheckedArray[uint8]](data)
  for y in 0 ..< height:
    let src = y * srcStride
    let dst = y * stride
    for x in 0 ..< width:
      let s = src + x * channels
      let d = dst + x * 4
      let r = pixelsBase[s]
      let g = if channels > 1: pixelsBase[s + 1] else: r
      let b = if channels > 2: pixelsBase[s + 2] else: r
      let a = if hasAlpha and channels > 3: pixelsBase[s + 3] else: 255'u8
      when cpuEndian == littleEndian:
        dataBase[d] = b
        dataBase[d + 1] = g
        dataBase[d + 2] = r
        dataBase[d + 3] = a
      else:
        dataBase[d] = a
        dataBase[d + 1] = r
        dataBase[d + 2] = g
        dataBase[d + 3] = b
  cairo_surface_mark_dirty(surface)
  result = surface

proc loadImage(path: string): pointer =
  if path.len == 0:
    return nil
  if imageCache.hasKey(path):
    return imageCache[path]
  var error: pointer
  let pixbuf = gdk_pixbuf_new_from_file(path.cstring, addr error)
  if pixbuf == nil:
    if error != nil:
      g_free(error)
    return nil
  let surface = pixbufToSurface(pixbuf)
  if gdk_pixbuf_unref != nil:
    gdk_pixbuf_unref(pixbuf)
  else:
    g_object_unref(pixbuf)
  if surface != nil:
    if imageCache.len >= imageCacheLimit:
      releaseImageCache()
    imageCache[path] = surface
  result = surface

proc cropImage(path: string, source: Rect): pointer =
  ## Cache a source rectangle crop in image-pixel coordinates (top-left).
  if path.len == 0:
    return nil
  let full = loadImage(path)
  if full == nil:
    return nil
  var error: pointer
  let pixbuf = gdk_pixbuf_new_from_file(path.cstring, addr error)
  if pixbuf == nil:
    if error != nil:
      g_free(error)
    return nil
  let iw = int(gdk_pixbuf_get_width(pixbuf))
  let ih = int(gdk_pixbuf_get_height(pixbuf))
  if iw <= 0 or ih <= 0:
    g_object_unref(pixbuf)
    return nil
  let x = max(0, min(iw - 1, int(source.x)))
  let y = max(0, min(ih - 1, int(source.y)))
  let w = max(1, min(iw - x, int(source.w)))
  let h = max(1, min(ih - y, int(source.h)))
  let key = (path: path, x: x, y: y, w: w, h: h)
  if cropCache.hasKey(key):
    g_object_unref(pixbuf)
    return cropCache[key]
  let crop = gdk_pixbuf_new_subpixbuf(pixbuf, cint(x), cint(y),
                                      cint(w), cint(h))
  var surface: pointer
  if crop != nil:
    surface = pixbufToSurface(crop)
    g_object_unref(crop)
  g_object_unref(pixbuf)
  if surface != nil:
    if cropCache.len >= imageCacheLimit:
      for cached in cropCache.values:
        cairo_surface_destroy(cached)
      cropCache.clear()
    cropCache[key] = surface
  result = surface

proc affineForTriangles(s0, s1, s2, d0, d1, d2: Point): CairoMatrix =
  let m00 = s1.x - s0.x
  let m01 = s1.y - s0.y
  let m10 = s2.x - s0.x
  let m11 = s2.y - s0.y
  let det = m00 * m11 - m01 * m10
  if abs(det) < 1e-6:
    return CairoMatrix(xx: 1, yx: 0, xy: 0, yy: 1, x0: 0, y0: 0)
  let rx1 = d1.x - d0.x
  let rx2 = d2.x - d0.x
  let ry1 = d1.y - d0.y
  let ry2 = d2.y - d0.y
  let a = (rx1 * m11 - rx2 * m01) / det
  let c = (m00 * rx2 - m10 * rx1) / det
  let b = (ry1 * m11 - ry2 * m01) / det
  let d = (m00 * ry2 - m10 * ry1) / det
  result = CairoMatrix(
    xx: cdouble(a), yx: cdouble(b), xy: cdouble(c), yy: cdouble(d),
    x0: cdouble(d0.x - a * s0.x - c * s0.y),
    y0: cdouble(d0.y - b * s0.x - d * s0.y))

proc drawTriangle(cr, surface: pointer, width, height: float32,
                  src, dst: array[3, Point]) =
  ## Map the source triangle (image pixels) onto the destination triangle.
  ## Both coordinate systems have a top-left origin.
  let transform = affineForTriangles(src[0], src[1], src[2],
                                     dst[0], dst[1], dst[2])
  cairo_save(cr)
  cairo_new_path(cr)
  cairo_move_to(cr, cdouble(dst[0].x), cdouble(dst[0].y))
  cairo_line_to(cr, cdouble(dst[1].x), cdouble(dst[1].y))
  cairo_line_to(cr, cdouble(dst[2].x), cdouble(dst[2].y))
  cairo_close_path(cr)
  cairo_clip(cr)
  cairo_transform(cr, addr transform)
  cairo_rectangle(cr, 0, 0, cdouble(width), cdouble(height))
  cairo_set_source_surface(cr, surface, 0, 0)
  cairo_fill(cr)
  cairo_restore(cr)

proc drawImageQuad(cr: pointer, op: Op) =
  let crop = cropImage(op.imagePath, op.sourceRect)
  if crop == nil:
    return
  let width = float32(cairo_image_surface_get_width(crop))
  let height = float32(cairo_image_surface_get_height(crop))
  if width <= 0 or height <= 0:
    return
  let tl = Point(x: 0, y: 0)
  let tr = Point(x: width, y: 0)
  let br = Point(x: width, y: height)
  let bl = Point(x: 0, y: height)
  drawTriangle(cr, crop, width, height, [tl, tr, br],
               [op.quad[0], op.quad[1], op.quad[2]])
  drawTriangle(cr, crop, width, height, [tl, br, bl],
               [op.quad[0], op.quad[2], op.quad[3]])

# --- scene -----------------------------------------------------------------

proc drawScene*(ctx: pointer, scene: Scene) =
  ## ctx is a cairo_t supplied by GTK or an offscreen image surface.
  ensureCore()
  let cr = cast[pointer](ctx)
  cairo_save(cr)
  setColor(cr, scene.clear)
  cairo_rectangle(cr, 0, 0, cdouble(scene.width), cdouble(scene.height))
  cairo_fill(cr)

  for op in scene.ops:
    case op.kind
    of opRect:
      setColor(cr, op.color)
      roundedRect(cr, op.rect, op.radius)
      cairo_fill(cr)
    of opText:
      drawPango(cr, op.text, op.x, op.y, op.size, op.bold, op.family,
                op.color.r, op.color.g, op.color.b, op.color.a)
    of opClip:
      cairo_save(cr)
      roundedRect(cr, op.clipRect, op.clipRadius)
      cairo_clip(cr)
    of opRestore:
      cairo_restore(cr)
    of opImage:
      let surface = loadImage(op.imagePath)
      if surface != nil:
        let iw = float32(cairo_image_surface_get_width(surface))
        let ih = float32(cairo_image_surface_get_height(surface))
        if iw > 0 and ih > 0:
          cairo_save(cr)
          cairo_translate(cr, cdouble(op.imageRect.x), cdouble(op.imageRect.y))
          cairo_scale(cr, cdouble(op.imageRect.w / iw),
                      cdouble(op.imageRect.h / ih))
          cairo_set_source_surface(cr, surface, 0, 0)
          cairo_rectangle(cr, 0, 0, cdouble(iw), cdouble(ih))
          cairo_fill(cr)
          cairo_restore(cr)
    of opImageQuad:
      drawImageQuad(cr, op)
    of opPolygon:
      if op.points.len > 0:
        setColor(cr, op.color)
        cairo_new_path(cr)
        cairo_move_to(cr, cdouble(op.points[0].x), cdouble(op.points[0].y))
        for i in 1 ..< op.points.len:
          cairo_line_to(cr, cdouble(op.points[i].x),
                        cdouble(op.points[i].y))
        cairo_close_path(cr)
        cairo_fill(cr)
  cairo_restore(cr)

# --- offscreen -------------------------------------------------------------

proc readPixel(data: ptr uint8, offset: int): tuple[r, g, b, a: uint8] =
  let bytes = cast[ptr UncheckedArray[uint8]](data)
  when cpuEndian == littleEndian:
    (bytes[offset + 2], bytes[offset + 1], bytes[offset], bytes[offset + 3])
  else:
    (bytes[offset + 1], bytes[offset + 2], bytes[offset + 3], bytes[offset])

proc writePixel(data: ptr uint8, offset: int, r, g, b, a: uint8) =
  let bytes = cast[ptr UncheckedArray[uint8]](data)
  when cpuEndian == littleEndian:
    bytes[offset] = b
    bytes[offset + 1] = g
    bytes[offset + 2] = r
    bytes[offset + 3] = a
  else:
    bytes[offset] = a
    bytes[offset + 1] = r
    bytes[offset + 2] = g
    bytes[offset + 3] = b

proc renderSceneToPixels*(scene: Scene): tuple[width, height: int,
                                                    pixels: seq[uint8]] =
  ## Render into a tightly packed straight-alpha RGBA8 buffer.
  ensureCore()
  let w = max(1, int(scene.width))
  let h = max(1, int(scene.height))
  result = (width: w, height: h,
            pixels: newSeq[uint8](w * h * 4))
  let surface = cairo_image_surface_create(CairoFormatArgb32,
                                           cint(w), cint(h))
  if surface == nil or cairo_surface_status(surface) != 0:
    if surface != nil:
      cairo_surface_destroy(surface)
    return
  let cr = cairo_create(surface)
  if cr == nil:
    cairo_surface_destroy(surface)
    return
  drawScene(cr, scene)
  cairo_destroy(cr)
  cairo_surface_flush(surface)
  let stride = int(cairo_image_surface_get_stride(surface))
  let data = cairo_image_surface_get_data(surface)
  if data != nil:
    for y in 0 ..< h:
      for x in 0 ..< w:
        let (r, g, b, a) = readPixel(data, y * stride + x * 4)
        let offset = (y * w + x) * 4
        if a == 0:
          result.pixels[offset] = 0
          result.pixels[offset + 1] = 0
          result.pixels[offset + 2] = 0
          result.pixels[offset + 3] = 0
        else:
          # Cairo stores premultiplied alpha; the public buffer is straight.
          result.pixels[offset] = uint8(min(255, (int(r) * 255 + int(a) div 2) div int(a)))
          result.pixels[offset + 1] = uint8(min(255, (int(g) * 255 + int(a) div 2) div int(a)))
          result.pixels[offset + 2] = uint8(min(255, (int(b) * 255 + int(a) div 2) div int(a)))
          result.pixels[offset + 3] = a
  cairo_surface_destroy(surface)

proc writeRgbaPng*(pixels: seq[uint8], width, height: int,
                   path: string): bool =
  ## Write a tightly packed straight-alpha RGBA8 buffer as a PNG.
  if width <= 0 or height <= 0 or pixels.len < width * height * 4:
    return false
  ensureCore()
  let surface = cairo_image_surface_create(CairoFormatArgb32,
                                           cint(width), cint(height))
  if surface == nil or cairo_surface_status(surface) != 0:
    if surface != nil:
      cairo_surface_destroy(surface)
    return false
  cairo_surface_flush(surface)
  let stride = int(cairo_image_surface_get_stride(surface))
  let data = cairo_image_surface_get_data(surface)
  if data == nil:
    cairo_surface_destroy(surface)
    return false
  for y in 0 ..< height:
    for x in 0 ..< width:
      let offset = (y * width + x) * 4
      let a = pixels[offset + 3]
      let r = uint8((int(pixels[offset]) * int(a) + 127) div 255)
      let g = uint8((int(pixels[offset + 1]) * int(a) + 127) div 255)
      let b = uint8((int(pixels[offset + 2]) * int(a) + 127) div 255)
      writePixel(data, y * stride + x * 4, r, g, b, a)
  cairo_surface_mark_dirty(surface)
  result = cairo_surface_write_to_png(surface, path.cstring) == 0
  cairo_surface_destroy(surface)

proc renderSceneToPng*(scene: Scene, path: string): bool =
  ## Offscreen render with Cairo. Used by Tester screenshots and tests.
  ensureCore()
  let w = max(1, int(scene.width))
  let h = max(1, int(scene.height))
  let surface = cairo_image_surface_create(CairoFormatArgb32,
                                           cint(w), cint(h))
  if surface == nil or cairo_surface_status(surface) != 0:
    if surface != nil:
      cairo_surface_destroy(surface)
    return false
  let cr = cairo_create(surface)
  if cr == nil:
    cairo_surface_destroy(surface)
    return false
  drawScene(cr, scene)
  cairo_destroy(cr)
  result = cairo_surface_write_to_png(surface, path.cstring) == 0
  cairo_surface_destroy(surface)
