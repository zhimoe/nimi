import std/[os, strutils, tables, widestrs]
export widestrs
const header = (currentSourcePath.parentDir / "graphics.h").replace('\\', '/')
{.compile: "graphics.c".}
{.passL: "-lgdi32 -lmsimg32 -lole32 -luuid -lwindowscodecs".}
type
  NimiPoint* {.importc: "NimiPoint", header: header, bycopy.} = object
    x*, y*: cint
proc gdiMeasure*(text: WideCString, count: cint, size: cfloat, bold: cint,
                 metrics: ptr cfloat) {.cdecl, importc: "nimi_gdi_measure", header: header.}
proc gdiText*(dc: pointer, text: WideCString, count: cint, x, y, size: cfloat,
              bold: cint, color: cuint) {.cdecl, importc: "nimi_gdi_text", header: header.}
proc gdiRect*(dc: pointer, x, y, w, h, radius: cint, color, alpha: cuint) {.cdecl, importc: "nimi_gdi_rect", header: header.}
proc gdiPolygon*(dc: pointer, points: ptr NimiPoint, count: cint,
                 color, alpha: cuint) {.cdecl, importc: "nimi_gdi_polygon", header: header.}
proc gdiClip*(dc: pointer, x, y, w, h: cint) {.cdecl, importc: "nimi_gdi_clip", header: header.}
proc gdiRestore*(dc: pointer) {.cdecl, importc: "nimi_gdi_restore", header: header.}
proc gdiImageLoad*(path: WideCString): pointer {.cdecl, importc: "nimi_gdi_image_load", header: header.}
proc gdiImageFree*(image: pointer) {.cdecl, importc: "nimi_gdi_image_free", header: header.}
proc gdiImageWidth*(image: pointer): cint {.cdecl, importc: "nimi_gdi_image_width", header: header.}
proc gdiImageHeight*(image: pointer): cint {.cdecl, importc: "nimi_gdi_image_height", header: header.}
proc gdiImageDraw*(dc, image: pointer, x, y, w, h, sourceX, sourceY,
                   sourceWidth, sourceHeight: cint): cint
  {.cdecl, importc: "nimi_gdi_image_draw", header: header.}

var
  imageCache: Table[string, pointer]
  imageCacheLimit = 128

proc clearImageCache*() =
  ## Render-thread only. Releases every decoded image in the cache.
  for image in imageCache.values:
    gdiImageFree(image)
  imageCache.clear()

proc setImageCacheLimit*(entries: int) =
  ## Limit the entry count, not decoded bytes. Minimum one entry.
  imageCacheLimit = max(1, entries)
  clearImageCache()

proc imageCacheStats*(): tuple[images, crops: int] =
  (imageCache.len, 0)

proc loadImage*(path: string): pointer =
  ## Decode through WIC and keep the premultiplied BGRA bitmap for painting.
  if path.len == 0:
    return nil
  if imageCache.hasKey(path):
    return imageCache[path]
  let image = gdiImageLoad(newWideCString(path))
  if image != nil:
    if imageCache.len >= imageCacheLimit:
      clearImageCache()
    imageCache[path] = image
  result = image
