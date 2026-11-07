import std/[unicode, unittest]

import nimi/text/grapheme
import nimi/text/range

suite "grapheme boundaries":
  test "combining marks stay with their base":
    let text = "e" & Rune(0x0301).toUTF8
    check graphemeBoundaries(text) == @[0, text.len]
    check graphemeStartBefore(text, text.len) == 0
    check graphemeEndAfter(text, 0) == text.len
    check graphemeStartAt(text, 1) == 0

  test "ZWJ emoji sequences and skin tones are single clusters":
    let family = "👨‍👩‍👧‍👦"
    check graphemeBoundaries(family) == @[0, family.len]
    let thumb = "👍🏽"
    check graphemeBoundaries(thumb) == @[0, thumb.len]

  test "regional indicators pair into flags":
    let flags = "🇨🇳🇺🇸"
    check graphemeBoundaries(flags) == @[0, 8, 16]
    check graphemeStartBefore(flags, 16) == 8
    check graphemeEndAfter(flags, 0) == 8

  test "variation selectors extend the previous cluster":
    let heart = "❤️"
    check graphemeBoundaries(heart) == @[0, heart.len]

  test "CRLF is one cluster and controls break separately":
    check graphemeBoundaries("a\r\nb") == @[0, 1, 3, 4]
    check graphemeBoundaries("\n") == @[0, 1]

  test "invalid UTF-8 bytes do not get swallowed":
    let text = "a" & "\xFF" & "b"
    check graphemeBoundaries(text) == @[0, 1, 2, 3]

  test "empty text has one boundary":
    check graphemeBoundaries("") == @[0]

suite "UTF-16 offsets":
  test "ASCII, CJK, and emoji lengths":
    check utf16Length("abc") == 3
    check utf16Length("中文") == 2
    check utf16Length("a😀b") == 4
    check utf16Length("👨‍👩‍👧‍👦") == 11

  test "byte and UTF-16 offsets round-trip":
    let text = "a😀中b"
    check utf16OffsetForUtf8(text, 0) == 0
    check utf16OffsetForUtf8(text, 1) == 1
    check utf16OffsetForUtf8(text, 5) == 3
    check utf16OffsetForUtf8(text, 8) == 4
    check utf16OffsetForUtf8(text, text.len) == 5
    check utf8OffsetForUtf16(text, 0) == 0
    check utf8OffsetForUtf16(text, 1) == 1
    check utf8OffsetForUtf16(text, 3) == 5
    check utf8OffsetForUtf16(text, 4) == 8
    check utf8OffsetForUtf16(text, 5) == text.len

  test "offsets inside a surrogate pair round down":
    let text = "a😀b"
    check utf8OffsetForUtf16(text, 2) == 1
    check utf8OffsetForUtf16(text, 4) == text.len
    check utf16OffsetForUtf8(text, 2) == 1

  test "negative and oversized offsets clamp":
    check utf16OffsetForUtf8("abc", -4) == 0
    check utf16OffsetForUtf8("abc", 99) == 3
    check utf8OffsetForUtf16("abc", -2) == 0
    check utf8OffsetForUtf16("abc", 99) == 3

suite "text ranges":
  test "validity and finish":
    check NoTextRange.valid == false
    check TextRange(location: 2, length: 3).valid
    check TextRange(location: 2, length: 3).finish == 5
    check TextRange(location: -1, length: 3).valid == false
