import std/[json, os, tempfiles, unittest]
import ../examples/music/session
import nimi/media/queue

suite "music session":
  test "track metadata, order, selection, mode and position survive restart":
    let dir = createTempDir("nimi-session-", "")
    defer: removeDir(dir)
    let path = dir / "session.json"
    var q = initPlaybackQueue()
    q.add(localTrack("/music/中文.mp3"))
    q.add(Track(path: "/cache/remote.audio", title: "远方", artist: "歌手",
                album: "专辑", source: "subsonic", remoteId: "id-1",
                coverId: "cover-1", coverPath: "/cache/cover.png", duration: 123.5))
    discard q.select(1)
    q.repeatMode = repeatAll
    q.shuffle = true
    check saveSession(path, MusicSession(queue: q, position: 42.5, volume: 0.25))
    check parseFile(path)["version"].getInt == 2
    let restored = loadSession(path)
    check restored.queue.tracks == q.tracks
    check restored.queue.tracks[0].displayTitle() == "中文"
    check restored.queue.tracks[1].coverId == "cover-1"
    check restored.queue.tracks[1].coverPath == "/cache/cover.png"
    check restored.queue.selected == 1
    check restored.queue.repeatMode == repeatAll
    check restored.queue.shuffle
    check restored.position == 42.5
    check restored.volume == 0.25

  test "version 1 path-only sessions migrate to local tracks":
    let dir = createTempDir("nimi-session-v1-", "")
    defer: removeDir(dir)
    let path = dir / "session.json"
    writeFile(path, """{"version":1,"tracks":["/music/a.mp3","/music/b.flac"],
      "selected":1,"repeat":2,"shuffle":false,"position":1.5,"volume":0.4}""")
    let restored = loadSession(path)
    check restored.queue.tracks.len == 2
    check restored.queue.tracks[0].path == "/music/a.mp3"
    check restored.queue.tracks[0].source == "local"
    check restored.queue.tracks[1].displayTitle() == "b"
    check restored.queue.selected == 1
    check restored.queue.repeatMode == repeatOne
    check restored.position == 1.5

  test "corrupt session is retained and falls back without partial state":
    let dir = createTempDir("nimi-session-bad-", "")
    defer: removeDir(dir)
    let path = dir / "session.json"
    writeFile(path, "{broken")
    let restored = loadSession(path)
    check restored.queue.tracks.len == 0
    check restored.queue.selected == -1
    check readFile(path) == "{broken"
