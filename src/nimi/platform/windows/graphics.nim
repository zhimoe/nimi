import std/[os, strutils, widestrs]
export widestrs
const header = (currentSourcePath.parentDir / "graphics.h").replace('\\', '/')
{.compile: "graphics.c".}
{.passL: "-lgdi32 -lmsimg32".}
proc gdiMeasure*(text: WideCString, count: cint, size: cfloat, bold: cint,
                 metrics: ptr cfloat) {.cdecl, importc: "nimi_gdi_measure", header: header.}
proc gdiText*(dc: pointer, text: WideCString, count: cint, x, y, size: cfloat,
              bold: cint, color: cuint) {.cdecl, importc: "nimi_gdi_text", header: header.}
proc gdiRect*(dc: pointer, x, y, w, h, radius: cint, color, alpha: cuint) {.cdecl, importc: "nimi_gdi_rect", header: header.}
proc gdiClip*(dc: pointer, x, y, w, h: cint) {.cdecl, importc: "nimi_gdi_clip", header: header.}
proc gdiRestore*(dc: pointer) {.cdecl, importc: "nimi_gdi_restore", header: header.}
