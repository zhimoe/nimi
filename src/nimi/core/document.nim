## A small document model: path, text, dirty state, save/reload, and external
## change detection via the file watcher. UI policy stays in the application;
## this layer owns the file lifecycle.

import std/[os, times, tempfiles]

import ./watch

type
  Document* = ref object
    path*: string
    text*: string
    dirty*: bool
    conflict*: bool
    modifiedAt*: int64
    fileSize*: int64
    watcher*: FileWatcher
    changeListeners*: seq[proc(doc: Document) {.closure.}]
    conflictListeners*: seq[proc(doc: Document) {.closure.}]
    saveListeners*: seq[proc(doc: Document) {.closure.}]

proc stamp(path: string): tuple[modifiedAt, fileSize: int64] =
  if not fileExists(path):
    return (0'i64, 0'i64)
  let info = getFileInfo(path)
  (info.lastWriteTime.toUnix, info.size.int64)

proc notifyChanged(doc: Document) =
  for fn in doc.changeListeners:
    fn(doc)

proc notifyConflict(doc: Document) =
  for fn in doc.conflictListeners:
    fn(doc)

proc notifySaved(doc: Document) =
  for fn in doc.saveListeners:
    fn(doc)

proc onChanged*(doc: Document, fn: proc(doc: Document)) =
  doc.changeListeners.add fn

proc onConflict*(doc: Document, fn: proc(doc: Document)) =
  doc.conflictListeners.add fn

proc onSaved*(doc: Document, fn: proc(doc: Document)) =
  doc.saveListeners.add fn

proc checkExternal*(doc: Document) =
  if doc == nil or doc.path.len == 0 or not fileExists(doc.path):
    return
  let s = stamp(doc.path)
  if s.modifiedAt == doc.modifiedAt and s.fileSize == doc.fileSize:
    return
  if doc.dirty:
    if not doc.conflict:
      doc.conflict = true
      doc.notifyConflict()
  else:
    try:
      doc.text = readFile(doc.path)
      doc.modifiedAt = s.modifiedAt
      doc.fileSize = s.fileSize
      doc.conflict = false
      doc.notifyChanged()
    except CatchableError:
      doc.conflict = true
      doc.notifyConflict()

proc watchDocument(doc: Document) =
  if doc.path.len == 0:
    return
  let parent = parentDir(doc.path)
  let target = doc.path
  doc.watcher = watch(parent, proc(e: FileEvent) =
    if e.path == target or e.kind in {feCreated, feRemoved, feRenamed}:
      doc.checkExternal())

proc openDocument*(path: string): Document =
  let doc = Document(path: absolutePath(path))
  let s = stamp(doc.path)
  doc.text = readFile(doc.path)
  doc.modifiedAt = s.modifiedAt
  doc.fileSize = s.fileSize
  doc.watchDocument()
  result = doc

proc newDocument*(path: string = ""): Document =
  result = Document(path: if path.len > 0: absolutePath(path) else: "")
  if result.path.len > 0:
    result.watchDocument()

proc setText*(doc: Document, text: string) =
  if doc == nil or doc.text == text:
    return
  doc.text = text
  doc.dirty = true
  doc.notifyChanged()

proc save*(doc: Document, path: string = ""): bool =
  if doc == nil:
    return false
  let target = if path.len > 0: absolutePath(path) else: doc.path
  if target.len == 0:
    return false
  try:
    # Stage beside the destination so replacement stays on the same volume.
    let (file, temporary) = createTempFile(".nimi-save-", ".tmp", parentDir(target))
    var closed = false
    defer:
      if not closed: file.close()
      if fileExists(temporary): removeFile(temporary)
    file.write(doc.text)
    file.flushFile()
    file.close()
    closed = true
    if fileExists(target):
      setFilePermissions(temporary, getFilePermissions(target))
    moveFile(temporary, target)
  except CatchableError:
    return false
  if doc.path != target:
    doc.path = target
    if doc.watcher != nil:
      doc.watcher.close()
      doc.watcher = nil
    doc.watchDocument()
  let s = stamp(target)
  doc.modifiedAt = s.modifiedAt
  doc.fileSize = s.fileSize
  doc.dirty = false
  doc.conflict = false
  doc.notifySaved()
  result = true

proc reload*(doc: Document) =
  if doc == nil or doc.path.len == 0 or not fileExists(doc.path):
    return
  doc.text = readFile(doc.path)
  let s = stamp(doc.path)
  doc.modifiedAt = s.modifiedAt
  doc.fileSize = s.fileSize
  doc.dirty = false
  doc.conflict = false
  doc.notifyChanged()

proc close*(doc: Document) =
  if doc == nil:
    return
  if doc.watcher != nil:
    doc.watcher.close()
    doc.watcher = nil
