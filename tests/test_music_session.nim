import std/[os, tempfiles, unittest]
import ../examples/music/session
import nimi/media/queue

suite "music session":
  test "queue order, selection, mode and position survive restart":
    let dir = createTempDir("nimi-session-", "")
    defer: removeDir(dir)
    let path = dir / "session.json"
    var q = initPlaybackQueue()
    q.add("/music/中文.mp3"); q.add("/music/second.flac")
    discard q.select(1)
    q.repeatMode = repeatAll
    q.shuffle = true
    check saveSession(path, MusicSession(queue: q, position: 42.5, volume: 0.25))
    let restored = loadSession(path)
    check restored.queue.tracks == q.tracks
    check restored.queue.selected == 1
    check restored.queue.repeatMode == repeatAll
    check restored.queue.shuffle
    check restored.position == 42.5
    check restored.volume == 0.25

  test "corrupt session is retained and falls back without partial state":
    let dir = createTempDir("nimi-session-bad-", "")
    defer: removeDir(dir)
    let path = dir / "session.json"
    writeFile(path, "{broken")
    let restored = loadSession(path)
    check restored.queue.tracks.len == 0
    check restored.queue.selected == -1
    check readFile(path) == "{broken"
