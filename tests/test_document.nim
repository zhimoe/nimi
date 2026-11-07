import std/[os, unittest, tempfiles]

import nimi/core/document

suite "document":
  test "open, edit, save, reload":
    let path = getTempDir() / "nimi_doc_test.txt"
    if fileExists(path): removeFile(path)
    writeFile(path, "hello")
    defer:
      if fileExists(path): removeFile(path)
    let doc = openDocument(path)
    check doc.text == "hello"
    check not doc.dirty
    doc.setText("hello world")
    check doc.dirty
    check doc.save()
    check not doc.dirty
    check readFile(path) == "hello world"
    doc.setText("draft")
    doc.reload()
    check doc.text == "hello world"
    check not doc.dirty

  test "external conflict detection":
    let path = getTempDir() / "nimi_doc_conflict.txt"
    if fileExists(path): removeFile(path)
    writeFile(path, "v1")
    defer:
      if fileExists(path): removeFile(path)
    let doc = openDocument(path)
    doc.setText("local draft")
    writeFile(path, "external v2")
    doc.checkExternal()
    check doc.conflict
    check doc.text == "local draft"
    check doc.save()
    check not doc.conflict
    check readFile(path) == "local draft"

  test "new document save":
    let path = getTempDir() / "nimi_doc_new.txt"
    if fileExists(path): removeFile(path)
    defer:
      if fileExists(path): removeFile(path)
    let doc = newDocument()
    doc.setText("born in memory")
    check doc.save(path)
    check fileExists(path)
    check readFile(path) == "born in memory"

  test "failed save keeps draft and destination intact":
    let directory = createTempDir("nimi-save-test-", "")
    defer: removeDir(directory)
    let doc = newDocument()
    doc.setText("unsaved draft")
    check not doc.save(directory)
    check doc.dirty
    check doc.path == ""
    check dirExists(directory)
    var leftovers = 0
    for entry in walkDir(directory): inc leftovers
    check leftovers == 0

  test "replacement preserves permissions":
    let directory = createTempDir("nimi-save-mode-", "")
    let path = directory / "private.txt"
    defer: removeDir(directory)
    writeFile(path, "old")
    setFilePermissions(path, {fpUserRead, fpUserWrite})
    let doc = openDocument(path)
    defer: doc.close()
    doc.setText("new")
    check doc.save()
    check readFile(path) == "new"
    check getFilePermissions(path) == {fpUserRead, fpUserWrite}
