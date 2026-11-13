## Platform-independent pieces of `nimi build` for Windows: ICO wrapping and
## the embedded manifest. The actual windres link is exercised by Windows CI.
import std/[base64, strutils, unittest]
import nimi/cli

const onePixelPng =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

proc le32(value: int): string =
  result.add char(value and 0xff)
  result.add char((value shr 8) and 0xff)
  result.add char((value shr 16) and 0xff)
  result.add char((value shr 24) and 0xff)

suite "Windows packaging":
  test "PNG icon is wrapped in a single-entry ICO":
    let png = decode(onePixelPng)
    let ico = pngToIco(png)
    check ico.len == png.len + 22
    check ico[0 ..< 6] == "\x00\x00\x01\x00\x01\x00"
    check ico[6 ..< 10] == "\x01\x01\x00\x00"
    check ico[10 ..< 14] == "\x01\x00\x20\x00"
    check ico[14 ..< 18] == le32(png.len)
    check ico[18 ..< 22] == le32(22)
    check ico[22 .. ^1] == png

  test "invalid and oversized PNG icons are rejected":
    expect CatchableError:
      discard pngToIco("not a png")
    let oversized = "\x89PNG\r\n\x1a\n" & "\x00\x00\x00\rIHDR" &
      "\x00\x00\x02\x00" & "\x00\x00\x02\x00"
    expect CatchableError:
      discard pngToIco(oversized)

  test "manifest requests asInvoker and per-monitor DPI":
    let manifest = windowsManifest("My & App", "com.example.app", "1.2")
    check "asInvoker" in manifest
    check "PerMonitorV2" in manifest
    check "com.example.app" in manifest
    check "1.2.0.0" in manifest
    check "My &amp; App" in manifest
