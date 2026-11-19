import std/[os, strutils]
import ./input
const header = (currentSourcePath.parentDir / "ime.h").replace('\\', '/')
{.compile: "ime.c".}
{.passL: "-limm32".}
type NativeComposition {.importc: "NimiComposition", header: header, bycopy.} = object
  committed {.importc: "result".}, composition: ptr UncheckedArray[uint16]
  attributes: ptr UncheckedArray[uint8]
  resultLength {.importc: "result_length".}: cint
  compositionLength {.importc: "composition_length".}: cint
  attributesLength {.importc: "attributes_length".}: cint
  cursor: cint
proc read(window: pointer, flags: cuint, data: ptr NativeComposition): cint {.cdecl, importc: "nimi_ime_read", header: header.}
proc free(data: ptr NativeComposition) {.cdecl, importc: "nimi_ime_free", header: header.}
proc place(window: pointer, x, y, w, h: cfloat) {.cdecl, importc: "nimi_ime_place", header: header.}
proc cancelIme*(window: pointer) {.cdecl, importc: "nimi_ime_cancel", header: header.}
proc enableIme*(window: pointer, enabled: cint) {.cdecl, importc: "nimi_ime_enable", header: header.}

proc placeIme*(window: pointer, surface: SurfaceHandler) =
  if surface.caretRect != nil:
    let r = surface.caretRect()
    place(window, r.x, r.y, r.w, r.h)

proc updateComposition*(window: pointer, flags: uint, surface: SurfaceHandler) =
  if (flags and 0x1fff) == 0:
    if surface.unmarkText != nil: surface.unmarkText()
    return
  var data: NativeComposition
  defer: free(addr data)
  if read(window, cuint(flags), addr data) == 0:
    raise newException(BackendError, "Cannot read Windows IME composition")
  if (flags and 0x800) != 0 and surface.insertText != nil:
    let text = if data.resultLength > 0:
      decodeUtf16(data.committed.toOpenArray(0, int(data.resultLength) - 1)) else: ""
    surface.insertText(text, NoTextRange)
  if (flags and 0x98) != 0 and surface.setMarkedText != nil:
    let text = if data.compositionLength > 0:
      decodeUtf16(data.composition.toOpenArray(0, int(data.compositionLength) - 1)) else: ""
    let selection = if data.attributesLength > 0:
      compositionSelection(int(data.compositionLength), int(data.cursor),
        data.attributes.toOpenArray(0, int(data.attributesLength) - 1))
      else: compositionSelection(int(data.compositionLength), int(data.cursor), [])
    surface.setMarkedText(text, selection, NoTextRange)
