## GTK clipboard: UTF-8 text and text/html via the standard selection.

import std/unicode

import ../contract
import ./[ffi, state]

const
  GdkSelectionClipboard = 69
  GtkTargetSameApp = 1'u32

var
  htmlContent = ""
  htmlTargets: ptr GtkTargetEntry
  htmlAtom: pointer

proc selection(): pointer =
  gtk_clipboard_get(cast[pointer](GdkSelectionClipboard))

proc requireClipboard(): pointer =
  if not ffi.gtkLoaded or linuxState == nil or not linuxState.initialized:
    raise newException(ClipboardError,
      "Clipboard requires an initialized GTK backend")
  result = selection()
  if result == nil:
    raise newException(ClipboardError, "GTK clipboard is unavailable")

proc validateText(text: string) =
  if '\0' in text or validateUtf8(text) != -1:
    raise newException(ClipboardError,
      "Clipboard text must be valid UTF-8 without NUL")

proc getHTML(clipboard, data: pointer, info: cuint,
             userData: pointer) {.cdecl.} =
  if data == nil:
    return
  if htmlAtom == nil:
    htmlAtom = gdk_atom_intern("text/html", 0)
  let text = htmlContent
  var bytes: ptr uint8
  if text.len > 0:
    bytes = cast[ptr uint8](text[0].addr)
  discard gtk_selection_data_set(data, htmlAtom, 8, bytes, cint(text.len))

proc clearHTML(clipboard, userData: pointer) {.cdecl.} =
  if htmlTargets != nil:
    g_free(cast[pointer](htmlTargets))
    htmlTargets = nil

proc readText*(): string =
  let clipboard = requireClipboard()
  let text = gtk_clipboard_wait_for_text(clipboard)
  if text == nil:
    return ""
  defer: g_free(cast[pointer](text))
  $text

proc writeText*(text: string) =
  validateText(text)
  let clipboard = requireClipboard()
  gtk_clipboard_set_text(clipboard, text.cstring, cint(text.len))

proc readHTML*(): string =
  let clipboard = requireClipboard()
  if htmlAtom == nil:
    htmlAtom = gdk_atom_intern("text/html", 0)
  if htmlAtom == nil:
    return ""
  let data = gtk_clipboard_wait_for_contents(clipboard, htmlAtom)
  if data == nil:
    return ""
  defer: gtk_selection_data_free(data)
  let length = int(gtk_selection_data_get_length(data))
  let bytes = gtk_selection_data_get_data(data)
  if length <= 0 or bytes == nil:
    return ""
  result = newString(length)
  copyMem(addr result[0], bytes, length)

proc writeHTML*(html: string) =
  validateText(html)
  let clipboard = requireClipboard()
  if htmlAtom == nil:
    htmlAtom = gdk_atom_intern("text/html", 0)
  htmlContent = html
  # Release any previous ownership first: GTK may invoke the old clear
  # callback synchronously, which frees the target array we are about to use.
  gtk_clipboard_clear(clipboard)
  if htmlTargets == nil:
    htmlTargets = cast[ptr GtkTargetEntry](g_malloc0(csize_t(sizeof(GtkTargetEntry))))
    htmlTargets[] = GtkTargetEntry(target: "text/html".cstring,
                                   flags: GtkTargetSameApp, info: 0)
  if gtk_clipboard_set_with_data(clipboard, htmlTargets, 1,
                                 cast[pointer](getHTML),
                                 cast[pointer](clearHTML), nil) == 0:
    raise newException(ClipboardError, "Cannot own the GTK clipboard")

proc clear*() =
  let clipboard = requireClipboard()
  gtk_clipboard_clear(clipboard)
  htmlContent = ""

proc newLinuxClipboard*(): Clipboard =
  result = Clipboard()
  result.readText = proc(): string = readText()
  result.writeText = proc(text: string) = writeText(text)
  result.readHTML = proc(): string = readHTML()
  result.writeHTML = proc(html: string) = writeHTML(html)
  result.clear = proc() = clear()
