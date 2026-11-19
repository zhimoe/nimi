import std/[strutils, unittest]
import nimi/platform/contract
import nimi/platform/windows/[input, clipboardhtml]
import nimi/ui

suite "Windows input decoding":
  test "UTF-16 pairs, malformed sequences and focus reset":
    var decoder: Utf16Input
    check decoder.feed(0xd83d) == ""
    check decoder.feed(0xde00) == "😀"
    check decoder.feed(0xdc00) == "�"
    check decoder.feed(0xd800) == ""
    check decoder.feed(uint32(ord('a'))) == "�a"
    check decoder.feed(0xd83d) == ""
    decoder.reset()
    check decoder.feed(uint32(ord('b'))) == "b"
    check decodeUtf16([0x4e2d'u16, 0xd83d, 0xde00, 0xd800]) == "中😀�"

  test "IME selection uses UTF-16 attributes with a bounded cursor fallback":
    check compositionSelection(4, 2, [0'u8, 1, 1, 0]) == TextRange(location: 1, length: 2)
    check compositionSelection(2, 99, []) == TextRange(location: 2)
    check compositionSelection(2, -1, []) == TextRange(location: 0)
    check compositionSelection(2, 0, [0'u8, 3, 3, 3]) == TextRange(location: 1, length: 1)

  test "keyboard mapping preserves AltGr and names navigation and function keys":
    check keyName(65, KeyControl) == "a"
    check keyName(65, KeyControl or KeyAlt) == ""
    check keyName(65, 0) == ""
    check keyName(33, 0) == "pageup"
    check keyName(34, 0) == "pagedown"
    check keyName(112, 0) == "f1"
    check keyName(135, 0) == "f24"
    check keyName(229, 0) == "" # VK_PROCESSKEY belongs to the IME.

suite "Desktop text input boundaries":
  test "unbound shortcuts and function keys do not alter selected text":
    var value = "keep😀"
    let t = newTester(proc(c: Context) =
      textInput(c, value, proc(v: string) = value = v, key = "text"), 400, 100)
    check not t.engine.textInputActive()
    check t.click("text")
    check t.engine.textInputActive()
    t.engine.selectAll()
    for key in ["k", "space", "enter"]: t.key(key, KeyShortcut)
    for key in ["f1", "f24", "insert"]: t.key(key)
    check value == "keep😀"
    check t.imeSelectedRange() == TextRange(location: 0, length: 6)

  test "failed clipboard operations preserve selected text and undo history":
    var value = "keep"
    let t = newTester(proc(c: Context) =
      textInput(c, value, proc(v: string) = value = v, key = "text"), 400, 100)
    check t.click("text")
    t.engine.selectAll()
    t.engine.clipboardWrite = proc(text: string) = raise newException(ClipboardError, "busy")
    t.engine.clipboardRead = proc(): string = raise newException(ClipboardError, "busy")
    expect ClipboardError: t.engine.cutSelection()
    expect ClipboardError: t.engine.paste()
    check value == "keep"
    t.engine.undo()
    check value == "keep"
    t.engine.clipboardRead = proc(): string = ""
    t.engine.paste()
    check value == "keep"
    t.engine.clipboardWrite = nil
    t.engine.cutSelection()
    check value == "keep"

  test "Windows clipboard newlines normalize once":
    var value = ""
    let t = newTester(proc(c: Context) =
      textInput(c, value, proc(v: string) = value = v, key = "text"), 400, 100)
    check t.click("text")
    t.engine.clipboardRead = proc(): string = "a\r\nb\rc\nd"
    t.engine.paste()
    check value == "a b c d"

  test "IME can commit one clause and begin the next before a frame":
    var value = "old"
    let t = newTester(proc(c: Context) =
      textInput(c, value, proc(v: string) = value = v, key = "text"), 400, 100)
    check t.click("text")
    t.engine.selectAll()
    t.engine.setMarkedText("にほん")
    t.engine.insertText("日本")
    t.engine.setMarkedText("ご", TextRange(location: 1))
    check value == "日本"
    check t.engine.markedRange() == TextRange(location: 2, length: 1)
    t.engine.insertText("語")
    check value == "日本語"
    t.engine.unmarkText()
    check value == "日本語"

suite "Windows HTML clipboard format":
  test "fragment offsets count UTF-8 bytes and preserve surrounding markup":
    let html = "<b>中文😀</b>\r\n<p>next</p>"
    let payload = encodeClipboardHTML(html)
    let lines = payload.splitLines
    let startHTML = parseInt(lines[1].split(':')[1])
    let startFragment = parseInt(lines[3].split(':')[1])
    let endFragment = parseInt(lines[4].split(':')[1])
    check payload[startHTML..^1].startsWith("<html><body>")
    check payload[startFragment..<endFragment] == html
    check decodeClipboardHTML(payload) == html
    check decodeClipboardHTML(encodeClipboardHTML("")) == ""

  test "malformed, out-of-bounds and non-UTF-8 fragments fail":
    let payload = encodeClipboardHTML("<b>中</b>")
    let offset = payload.splitLines[4]
    for ending in ["0000000001", "99999999999999999999999", "+abc", "-1"]:
      expect ClipboardError:
        discard decodeClipboardHTML(payload.replace(offset, "EndFragment:" & ending))
    expect ClipboardError: discard decodeClipboardHTML(payload.replace("中", "\xff\xff\xff"))
    expect ClipboardError: discard encodeClipboardHTML("embedded\0null")
