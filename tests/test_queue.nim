import std/unittest
import nimi/media/queue

suite "playback queue":
  test "automatic completion stops, wraps or repeats according to mode":
    var q = initPlaybackQueue()
    check q.nextIndex() == -1
    q.add("a"); q.add("b"); q.add("a")
    check q.tracks.len == 2
    check q.select(0)
    check q.nextIndex(true) == 1
    check q.select(1)
    check q.nextIndex(true) == -1
    q.repeatMode = repeatAll
    check q.nextIndex(true) == 0
    q.repeatMode = repeatOne
    check q.nextIndex(true) == 1
    check q.nextIndex(false) == -1

  test "shuffle avoids current track and previous walks actual history":
    var q = initPlaybackQueue(42)
    for path in ["a", "b", "c"]: q.add(path)
    q.shuffle = true
    check q.select(0)
    let second = q.nextIndex()
    check second != 0
    check q.select(second)
    let third = q.nextIndex()
    check third != second
    check q.select(third)
    check q.previousIndex() == second
    q.selectPrevious(second)
    check q.previousIndex() == 0
    q.selectPrevious(0)
    check q.previousIndex() == -1

  test "candidate resolution does not commit failed loads":
    var q = initPlaybackQueue()
    q.add("a"); q.add("b")
    check q.select(0)
    check q.nextIndex() == 1
    check not q.select(99)
    check q.selected == 0

suite "track metadata":
  test "identity deduplicates local paths and remote IDs":
    var q = initPlaybackQueue()
    q.add(localTrack("/music/song.mp3"))
    q.add(localTrack("/music/song.mp3"))
    q.add(Track(path: "/cache/a.audio", title: "远方", artist: "歌手",
                album: "专辑", source: "subsonic", remoteId: "id-1"))
    q.add(Track(path: "/cache/other.audio", title: "重复",
                source: "subsonic", remoteId: "id-1"))
    check q.tracks.len == 2
    check q.tracks[0].displayTitle() == "song"
    check q.tracks[1].displayTitle() == "远方"
    check q.tracks[1].displaySubtitle() == "歌手 — 专辑"
