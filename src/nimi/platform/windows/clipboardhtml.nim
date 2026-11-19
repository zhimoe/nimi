## CF_HTML uses UTF-8 byte offsets from the beginning of the payload.
import std/[sequtils, strutils, unicode]
import ../contract

const
  prefix = "<html><body><!--StartFragment-->"
  suffix = "<!--EndFragment--></body></html>"
  headerPattern = "Version:1.0\r\nStartHTML:$1\r\nEndHTML:$2\r\n" &
    "StartFragment:$3\r\nEndFragment:$4\r\n"

proc encodeClipboardHTML*(html: string): string =
  if '\0' in html or validateUtf8(html) != -1:
    raise newException(ClipboardError, "Clipboard HTML must be valid UTF-8 without NUL")
  let startHTML = (headerPattern % ["0000000000", "0000000000",
    "0000000000", "0000000000"]).len
  let startFragment = startHTML + prefix.len
  let endFragment = startFragment + html.len
  let endHTML = endFragment + suffix.len
  headerPattern % [align($startHTML, 10, '0'), align($endHTML, 10, '0'),
    align($startFragment, 10, '0'), align($endFragment, 10, '0')] &
    prefix & html & suffix

proc decodeClipboardHTML*(payload: string): string =
  var startFragment = -1
  var endFragment = -1
  var headerEnd = 0
  # Read only header lines. Offset values must describe a range beyond those lines.
  for line in payload.splitLines:
    if line.len == 0 or line[0] == '<' or ':' notin line:
      break
    headerEnd += line.len
    if headerEnd < payload.len and payload[headerEnd] == '\r': inc headerEnd
    if headerEnd < payload.len and payload[headerEnd] == '\n': inc headerEnd
    let colon = line.find(':')
    let name = line[0..<colon]
    if name == "StartFragment" or name == "EndFragment":
      let value = strutils.strip(line[colon + 1..^1])
      if value.len == 0 or value.anyIt(it notin {'0'..'9'}):
        break
      try:
        let offset = parseInt(value)
        if name == "StartFragment": startFragment = offset
        else: endFragment = offset
      except ValueError:
        break
    if startFragment >= 0 and endFragment >= 0:
      if startFragment >= headerEnd and endFragment >= startFragment and
          endFragment <= payload.len:
        result = payload[startFragment..<endFragment]
        if '\0' notin result and validateUtf8(result) == -1:
          return
      break
  raise newException(ClipboardError, "Invalid Windows HTML clipboard fragment")
