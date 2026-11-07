import std/[tables, unittest]

import nimi/keys
import nimi/ui
import nimi/text/range

suite "IME composition":
  test "marked text is drawn and commit replaces the composition":
    var value = ""
    proc view(c: Context) =
      textInput(c, value, proc(v: string) = value = v, key = "ime")
    let t = newTester(view, 400, 160)
    check t.click("ime")
    t.imeSetMarkedText("に", TextRange(location: 1, length: 0))
    check t.imeMarkedRange() == TextRange(location: 0, length: 1)
    check t.imeSelectedRange() == TextRange(location: 1, length: 0)
    check t.hasText("に")
    t.imeInsertText("日本", t.imeMarkedRange())
    check value == "日本"
    check t.imeMarkedRange() == NoTextRange

  test "composition replaces an existing selection":
    var value = "abcd"
    proc view(c: Context) =
      textInput(c, value, proc(v: string) = value = v, key = "ime")
    let t = newTester(view, 400, 160)
    check t.click("ime")
    t.key("end")
    t.key("left", KeyShift)
    check t.imeSelectedRange() == TextRange(location: 3, length: 1)
    t.imeSetMarkedText("に", TextRange(location: 1, length: 0))
    check t.imeMarkedRange() == TextRange(location: 3, length: 1)
    check t.hasText("abc")
    check t.hasText("に")
    t.imeInsertText("X")
    check value == "abcX"

  test "replacement ranges use UTF-16 offsets":
    var value = "a😀b"
    proc view(c: Context) =
      textInput(c, value, proc(v: string) = value = v, key = "ime")
    let t = newTester(view, 400, 160)
    check t.click("ime")
    t.key("end")
    check t.imeTextLength() == 4
    check t.imeSelectedRange() == TextRange(location: 4, length: 0)
    check t.imeAttributedSubstring(TextRange(location: 1, length: 2)) == "😀"
    t.imeInsertText("X", TextRange(location: 1, length: 2))
    check value == "aXb"
    check t.imeTextLength() == 3

  test "characterIndexAt maps glyph positions to UTF-16":
    var value = "a😀b"
    proc view(c: Context) =
      textInput(c, value, proc(v: string) = value = v, key = "ime")
    let t = newTester(view, 400, 160)
    check t.click("ime")
    discard t.render()
    check t.engine.hits.len == 1
    let hit = t.engine.hits[0]
    let y = hit.rect.y + hit.rect.h / 2
    check t.imeCharacterIndexAt(hit.rect.x + hit.padX - 1, y) == 0
    check t.imeCharacterIndexAt(hit.rect.x + hit.rect.w - 1, y) == 4

  test "composition participates in wrapping and scrolling":
    var value = ""
    proc view(c: Context) =
      textArea(c, value, proc(v: string) = value = v,
               key = "area", height = 32).width(70)
    let t = newTester(view, 140, 160)
    check t.click("area")
    t.imeSetMarkedText("ああああああああああああああああ")
    check t.imeMarkedRange().length == 16
    check t.texts().len >= 2
    check t.engine.scrollOffsets.getOrDefault("area", 0) > 0

  test "unmarkText cancels without touching the document":
    var value = "ab"
    proc view(c: Context) =
      textInput(c, value, proc(v: string) = value = v, key = "ime")
    let t = newTester(view, 400, 160)
    check t.click("ime")
    t.imeSetMarkedText("に")
    check t.hasText("ab")
    check t.hasText("に")
    t.imeUnmarkText()
    check value == "ab"
    check t.imeMarkedRange() == NoTextRange
    check not t.hasText("に")
