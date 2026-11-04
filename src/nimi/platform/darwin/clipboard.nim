## NSPasteboard implementation.

import ../contract
import ./objc

const
  PlainText = "public.utf8-plain-text"
  HtmlType = "public.html"

proc pasteboard(): Id =
  send0(loadClass("NSPasteboard"), sel("generalPasteboard"))

proc readType(typ: string): string =
  let pb = pasteboard()
  goString(sendId1(pb, sel("stringForType:"), nsString(typ)))

proc writeType(text, typ: string) =
  let pb = pasteboard()
  discard sendInt(pb, sel("clearContents"))
  discard cast[proc(a: Id, s: SEL, b: Id, c: Id): bool {.cdecl.}](msgSend)(
    pb, sel("setString:forType:"), nsString(text), nsString(typ))

proc newDarwinClipboard*(): Clipboard =
  result = Clipboard()
  result.readText = proc(): string = readType(PlainText)
  result.writeText = proc(text: string) = writeType(text, PlainText)
  result.readHTML = proc(): string = readType(HtmlType)
  result.writeHTML = proc(html: string) = writeType(html, HtmlType)
  result.clear = proc() =
    discard sendInt(pasteboard(), sel("clearContents"))
