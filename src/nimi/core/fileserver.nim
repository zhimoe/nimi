## Static & virtual-filesystem (VFS) asset server used by custom WebView schemes
## (`nimi://app/...`) across macOS, Windows, and Linux.
##
## Supports:
## - Disk directory roots with path-traversal protection (`newFileServer`)
## - Zero-extraction compile-time embedded VFS (`embedAssets` + `newMemoryFileServer`)
## - Thread-safe runtime multi-mount prefixes (`mount` / `mountMemory`, e.g. `/blobs`)
## - Optional SPA fallback (`spaFallback = true`) and custom route handlers

import std/[locks, macros, options, os, strutils, tables]

export options

type
  VirtualFile* = tuple[path: string, data: string]

  FileResult* = object
    data*: string
    mime*: string
    status*: int

  MountEntry = object
    prefix: string
    diskRoot: string
    memoryFiles: Table[string, string]
    isMemory: bool

  CustomRouteHandler* = proc(requestPath: string): Option[FileResult] {.closure, gcsafe.}

  FileServer* = ref object
    root*: string
    scheme*: string
    spaFallback*: bool
    lock: Lock
    memoryRoot: Table[string, string]
    hasMemoryRoot: bool
    mounts: seq[MountEntry]
    customHandler: CustomRouteHandler

const reservedSchemes = ["http", "https", "file", "about", "data", "blob",
                         "javascript", "ws", "wss", "ftp", "mailto", "tel"]

proc sanitizeScheme*(scheme: string): string =
  result = scheme.toLowerAscii()
  if result.len == 0 or
      not result.allCharsInSet({'a'..'z', '0'..'9', '+', '-', '.'}) or
      result in reservedSchemes:
    result = "nimi"

proc normalizeRelPath(raw: string): tuple[ok: bool, rel: string] =
  var stripped = raw
  let qIdx = stripped.find('?')
  if qIdx >= 0:
    stripped = stripped[0 ..< qIdx]
  let hIdx = stripped.find('#')
  if hIdx >= 0:
    stripped = stripped[0 ..< hIdx]
  stripped = stripped.replace('\\', '/').strip(chars = {'/'})
  if stripped.len == 0:
    return (true, "index.html")
  var parts: seq[string]
  for part in stripped.split('/'):
    if part.len == 0 or part == ".":
      continue
    if part == "..":
      return (false, "")
    parts.add part
  if parts.len == 0:
    return (true, "index.html")
  (true, parts.join("/"))

proc normalizePrefix(prefix: string): string =
  prefix.replace('\\', '/').strip(chars = {'/'})

proc mimeFor*(ext: string): string =
  case ext.toLowerAscii
  of ".html", ".htm": "text/html"
  of ".css": "text/css"
  of ".js", ".mjs": "text/javascript"
  of ".json", ".map": "application/json"
  of ".txt", ".md": "text/plain"
  of ".xml": "application/xml"
  of ".svg": "image/svg+xml"
  of ".png": "image/png"
  of ".jpg", ".jpeg": "image/jpeg"
  of ".gif": "image/gif"
  of ".webp": "image/webp"
  of ".avif": "image/avif"
  of ".ico": "image/x-icon"
  of ".woff": "font/woff"
  of ".woff2": "font/woff2"
  of ".ttf": "font/ttf"
  of ".otf": "font/otf"
  of ".wasm": "application/wasm"
  of ".pdf": "application/pdf"
  else: "application/octet-stream"

proc notFound*(): FileResult =
  FileResult(data: "not found", mime: "text/plain", status: 404)

proc newFileServer*(root: string, scheme: string = "nimi",
                    spaFallback: bool = false): FileServer =
  result = FileServer(
    root: if root.len > 0: absolutePath(root) else: "",
    scheme: sanitizeScheme(scheme),
    spaFallback: spaFallback)
  initLock(result.lock)

proc newMemoryFileServer*(files: openArray[VirtualFile],
                          scheme: string = "nimi",
                          spaFallback: bool = false): FileServer =
  ## Serve compile-time embedded or in-memory assets directly without extracting
  ## temporary files to disk.
  result = FileServer(
    root: "",
    scheme: sanitizeScheme(scheme),
    spaFallback: spaFallback,
    hasMemoryRoot: true)
  initLock(result.lock)
  for (rawPath, content) in files:
    let (ok, norm) = normalizeRelPath(rawPath)
    if ok and norm.len > 0:
      result.memoryRoot[norm] = content

proc mount*(fs: FileServer, prefix: string, diskRoot: string) =
  ## Dynamically mount an additional disk directory at `prefix` (e.g. `"/blobs"`).
  ## Safe to call at runtime before or after window creation.
  if fs == nil or diskRoot.len == 0:
    return
  let cleanPrefix = normalizePrefix(prefix)
  let absRoot = absolutePath(diskRoot)
  acquire(fs.lock)
  try:
    for i in 0 ..< fs.mounts.len:
      if fs.mounts[i].prefix == cleanPrefix:
        fs.mounts[i] = MountEntry(prefix: cleanPrefix, diskRoot: absRoot)
        return
    fs.mounts.add MountEntry(prefix: cleanPrefix, diskRoot: absRoot)
  finally:
    release(fs.lock)

proc mountMemory*(fs: FileServer, prefix: string,
                  files: openArray[VirtualFile]) =
  ## Mount an in-memory file map under `prefix`.
  if fs == nil:
    return
  let cleanPrefix = normalizePrefix(prefix)
  var table = initTable[string, string]()
  for (rawPath, content) in files:
    let (ok, norm) = normalizeRelPath(rawPath)
    if ok and norm.len > 0:
      table[norm] = content
  acquire(fs.lock)
  try:
    for i in 0 ..< fs.mounts.len:
      if fs.mounts[i].prefix == cleanPrefix:
        fs.mounts[i] = MountEntry(prefix: cleanPrefix, memoryFiles: table, isMemory: true)
        return
    fs.mounts.add MountEntry(prefix: cleanPrefix, memoryFiles: table, isMemory: true)
  finally:
    release(fs.lock)

proc setCustomHandler*(fs: FileServer, handler: CustomRouteHandler) =
  if fs == nil:
    return
  acquire(fs.lock)
  fs.customHandler = handler
  release(fs.lock)

proc serveFromDisk(diskRoot, rel: string): Option[FileResult] =
  if diskRoot.len == 0 or not dirExists(diskRoot):
    return none(FileResult)
  try:
    let root = expandFilename(absolutePath(diskRoot))
    var full = root / rel.replace('/', DirSep)
    if dirExists(full):
      full = full / "index.html"
    if not fileExists(full):
      return none(FileResult)
    let resolved = expandFilename(full)
    if resolved != root and not resolved.startsWith(root & $DirSep):
      return none(FileResult)
    let content = readFile(full)
    return some(FileResult(
      data: content,
      mime: mimeFor(splitFile(full).ext),
      status: 200))
  except CatchableError:
    return none(FileResult)

proc serveFromMemory(mem: Table[string, string], rel: string): Option[FileResult] =
  if mem.hasKey(rel):
    return some(FileResult(
      data: mem[rel],
      mime: mimeFor(splitFile(rel).ext),
      status: 200))
  let asIndex = rel & "/index.html"
  if mem.hasKey(asIndex):
    return some(FileResult(
      data: mem[asIndex],
      mime: "text/html",
      status: 200))
  none(FileResult)

proc serve*(fs: FileServer, requestPath: string): FileResult =
  if fs == nil:
    return notFound()
  let (ok, rel) = normalizeRelPath(requestPath)
  if not ok:
    return notFound()

  var handler: CustomRouteHandler
  var mountsSnapshot: seq[MountEntry]
  var hasMem = false
  acquire(fs.lock)
  handler = fs.customHandler
  mountsSnapshot = fs.mounts
  hasMem = fs.hasMemoryRoot
  release(fs.lock)

  if handler != nil:
    let custom = handler("/" & rel)
    if custom.isSome:
      return custom.get

  # 1. Check mounted sub-prefixes (longest prefix match wins).
  var bestIdx = -1
  var bestLen = -1
  for i, m in mountsSnapshot:
    if m.prefix.len == 0:
      if bestLen < 0:
        bestIdx = i
        bestLen = 0
    elif rel == m.prefix or rel.startsWith(m.prefix & "/"):
      if m.prefix.len > bestLen:
        bestIdx = i
        bestLen = m.prefix.len
  if bestIdx >= 0:
    let m = mountsSnapshot[bestIdx]
    let subRel =
      if m.prefix.len == 0: rel
      elif rel.len == m.prefix.len: "index.html"
      else: rel[m.prefix.len + 1 .. ^1]
    if m.isMemory:
      let hit = serveFromMemory(m.memoryFiles, subRel)
      if hit.isSome:
        return hit.get
    else:
      let hit = serveFromDisk(m.diskRoot, subRel)
      if hit.isSome:
        return hit.get

  # 2. Check primary in-memory VFS root.
  if hasMem:
    acquire(fs.lock)
    let hit = serveFromMemory(fs.memoryRoot, rel)
    release(fs.lock)
    if hit.isSome:
      return hit.get

  # 3. Check primary disk root.
  if fs.root.len > 0:
    let hit = serveFromDisk(fs.root, rel)
    if hit.isSome:
      return hit.get

  # 4. Optional SPA history fallback for extensionless client routes.
  if fs.spaFallback and splitFile(rel).ext.len == 0:
    if hasMem:
      acquire(fs.lock)
      let hit = serveFromMemory(fs.memoryRoot, "index.html")
      release(fs.lock)
      if hit.isSome:
        return hit.get
    if fs.root.len > 0:
      let hit = serveFromDisk(fs.root, "index.html")
      if hit.isSome:
        return hit.get

  notFound()

macro embedAssets*(dirPath: untyped): seq[VirtualFile] =
  ## Compile-time directory walker that embeds an entire frontend build folder
  ## (e.g. `embedAssets("../web/dist")`) into a `seq[VirtualFile]` via `staticRead`.
  if dirPath.kind notin {nnkStrLit, nnkRStrLit, nnkTripleStrLit}:
    error("embedAssets expects a string literal directory path", dirPath)
  let rawDir = dirPath.strVal
  let callerDir = dirPath.lineInfoObj.filename.parentDir
  let resolvedRoot =
    if isAbsolute(rawDir): rawDir
    else: normalizedPath(callerDir / rawDir)
  var entries = newNimNode(nnkBracket)
  if dirExists(resolvedRoot):
    for fullPath in walkDirRec(resolvedRoot):
      let rel = relativePath(fullPath, resolvedRoot).replace('\\', '/')
      if rel.startsWith(".") or "/." in rel:
        continue
      entries.add newTree(nnkTupleConstr,
        newLit(rel),
        newCall(bindSym"staticRead", newLit(fullPath)))
  result = newTree(nnkPrefix, ident("@"), entries)
