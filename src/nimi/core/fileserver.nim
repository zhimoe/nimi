## A small static file server used by custom WKWebView schemes. Paths are
## resolved under the configured root; traversal outside the root is rejected.

import std/[os, strutils]

type
  FileServer* = ref object
    root*: string
    scheme*: string

  FileResult* = object
    data*: string
    mime*: string
    status*: int

const reservedSchemes = ["http", "https", "file", "about", "data", "blob",
                         "javascript", "ws", "wss", "ftp", "mailto", "tel"]

proc newFileServer*(root: string, scheme: string = "nimi"): FileServer =
  var safeScheme = scheme.toLowerAscii
  if safeScheme.len == 0 or
      not safeScheme.allCharsInSet({'a'..'z', '0'..'9', '+', '-', '.'}) or
      safeScheme in reservedSchemes:
    safeScheme = "nimi"
  FileServer(root: absolutePath(root), scheme: safeScheme)

proc mimeFor(ext: string): string =
  case ext.toLowerAscii
  of ".html", ".htm": "text/html"
  of ".css": "text/css"
  of ".js", ".mjs": "text/javascript"
  of ".json": "application/json"
  of ".txt", ".md": "text/plain"
  of ".xml": "application/xml"
  of ".svg": "image/svg+xml"
  of ".png": "image/png"
  of ".jpg", ".jpeg": "image/jpeg"
  of ".gif": "image/gif"
  of ".webp": "image/webp"
  of ".ico": "image/x-icon"
  of ".woff": "font/woff"
  of ".woff2": "font/woff2"
  of ".ttf": "font/ttf"
  of ".otf": "font/otf"
  of ".wasm": "application/wasm"
  else: "application/octet-stream"

proc notFound(): FileResult =
  FileResult(data: "not found", mime: "text/plain", status: 404)

proc serve*(fs: FileServer, requestPath: string): FileResult =
  if fs == nil or fs.root.len == 0:
    return notFound()
  var rel = requestPath.strip(chars = {'/'})
  if rel.len == 0:
    rel = "index.html"
  var parts: seq[string]
  for part in rel.split('/'):
    if part.len == 0 or part == ".":
      continue
    if part == "..":
      return notFound()
    parts.add part
  let root = expandFilename(absolutePath(fs.root))
  var full = root / parts.join("/")
  if dirExists(full):
    full = full / "index.html"
  if not fileExists(full):
    return notFound()
  try:
    let resolved = expandFilename(full)
    if resolved != root and not resolved.startsWith(root & $DirSep):
      return notFound()
    result.data = readFile(full)
  except CatchableError:
    return notFound()
  result.mime = mimeFor(splitFile(full).ext)
  result.status = 200
