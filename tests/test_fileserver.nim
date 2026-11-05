import std/[os, strutils, unittest]

import nimi/core/fileserver

suite "fileserver":
  test "serves index, mime types, and blocks traversal":
    let root = getTempDir() / "nimi_test_fileserver"
    removeDir(root)
    createDir(root)
    defer: removeDir(root)
    writeFile(root / "index.html", "<h1>hello</h1>")
    writeFile(root / "app.js", "console.log('nim')")
    createDir(root / "assets")
    writeFile(root / "assets" / "data.json", "{\"ok\":true}")
    writeFile(getTempDir() / "nimi_outside_secret.txt", "secret")
    defer: removeFile(getTempDir() / "nimi_outside_secret.txt")

    let fs = newFileServer(root, "nimi")
    check fs.scheme == "nimi"
    let index = fs.serve("/")
    check index.status == 200
    check index.mime.startsWith("text/html")
    check index.data == "<h1>hello</h1>"

    let js = fs.serve("/app.js")
    check js.status == 200
    check js.mime.startsWith("text/javascript")
    check js.data == "console.log('nim')"

    let data = fs.serve("/assets/data.json")
    check data.status == 200
    check data.mime.startsWith("application/json")

    let traversal = fs.serve("/../nimi_outside_secret.txt")
    check traversal.status == 404
    check fs.serve("/missing.html").status == 404

    let custom = newFileServer(root, "Bad Scheme")
    check custom.scheme == "nimi"
    check newFileServer(root, "https").scheme == "nimi"
