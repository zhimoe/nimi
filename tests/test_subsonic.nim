import std/[unittest, uri, strutils, md5, os, json, tempfiles]
import nimi/audio
import ../examples/music/services/subsonic

suite "Subsonic adapter":
  test "token auth encodes values and preserves reverse proxy path":
    let config = ServerConfig(address: "https://example.test/music/", username: "a+b", password: "secret")
    let url = parseUri(config.endpoint("search3", [("query", "中文 & test")]))
    check url.path == "/music/rest/search3.view"
    var salt, token, username, query: string
    for key, value in decodeQuery(url.query):
      case key
      of "s": salt = value
      of "t": token = value
      of "u": username = value
      of "query": query = value
      else: discard
    check token == getMD5("secret" & salt)
    check username == "a+b"
    check query == "中文 & test"
    check "secret" notin $url
    expect ValueError: discard config.endpoint("ping", [("p", "override")])

  test "local HTTP fixture authenticates and returns catalog":
    let address = getEnv("NIMI_TEST_SUBSONIC")
    check address.len > 0
    let config = ServerConfig(address: address, username: "test", password: "secret")
    check config.request("ping")["status"].getStr == "ok"
    let tracks = config.searchTracks("中文")
    check tracks.len == 1
    check tracks[0].id == "song-1"
    check tracks[0].title == "中文歌曲"
    let denied = ServerConfig(address: address, username: "test", password: "wrong")
    expect IOError: discard denied.request("ping")

  test "search download and native decode share a playable cached file":
    let directory = createTempDir("nimi-stream-", "")
    defer: removeDir(directory)
    let config = ServerConfig(address: getEnv("NIMI_TEST_SUBSONIC"), username: "test", password: "secret")
    let tracks = config.searchTracks("中文")
    let path = config.downloadTrack(tracks[0].id, directory)
    check fileExists(path)
    let audio = openAudio(path)
    defer: audio.close()
    check abs(audio.duration - 1.0) < 0.01
    audio.setVolume(0)
    check audio.play()
    audio.pause()
    check config.downloadTrack(tracks[0].id, directory) == path
    check getFileSize(path) == 16044

  test "cover art downloads, caches, and respects its budget":
    let directory = createTempDir("nimi-cover-", "")
    defer: removeDir(directory)
    let config = ServerConfig(address: getEnv("NIMI_TEST_SUBSONIC"),
      username: "test", password: "secret")
    let tracks = config.searchTracks("中文")
    check tracks[0].coverId == "cover-1"
    let cover = config.downloadCover(tracks[0].coverId, directory)
    check fileExists(cover)
    let bytes = readFile(cover)
    check bytes.len > 8
    check bytes.startsWith("\x89PNG")
    check config.downloadCover(tracks[0].coverId, directory) == cover
    let budgetDir = createTempDir("nimi-cover-budget-", "")
    defer: removeDir(budgetDir)
    expect IOError:
      discard config.downloadCover(tracks[0].coverId, budgetDir, cacheBudget = 10)
    var entries = 0
    for entry in walkDir(budgetDir): inc entries
    check entries == 0

  test "HTTP 200 protocol errors leave neither cache nor partial downloads":
    let directory = createTempDir("nimi-stream-fail-", "")
    defer: removeDir(directory)
    let config = ServerConfig(address: getEnv("NIMI_TEST_SUBSONIC"), username: "test", password: "wrong")
    expect IOError: discard config.downloadTrack("bad", directory)
    var entries = 0
    for entry in walkDir(directory): inc entries
    check entries == 0

  test "cache budget rejects new content without publishing partial files":
    let directory = createTempDir("nimi-stream-budget-", "")
    defer: removeDir(directory)
    let config = ServerConfig(address: getEnv("NIMI_TEST_SUBSONIC"), username: "test", password: "secret")
    expect IOError: discard config.downloadTrack("song-1", directory, cacheBudget = 100)
    var entries = 0
    for entry in walkDir(directory): inc entries
    check entries == 0
