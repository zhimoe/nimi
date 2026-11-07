import std/[unittest, tables]
import nimi/ui

suite "virtual list":
  test "ten thousand rows build only viewport and scrolling targets correct item":
    var built: seq[int]
    var selected = -1
    proc view(c: Context) =
      built.setLen(0)
      virtualList(c, "library", 10_000, 40, 200, proc(c: Context, i: int) =
        built.add(i)
        let index = i
        button(c, "Song " & $i, proc() = selected = index, key = "song-" & $i).height(40)
      )
    let t = newTester(view, 400, 200)
    discard t.render()
    check built.len <= 9
    check built[0] == 0
    t.scrollAt(50, 50, 20_000)
    check built.len <= 9
    check 500 in built
    t.clickAt(20, 20)
    check selected == 500
    check t.engine.scrollRegions[0].contentH == 400_000
    t.scrollAt(50, 50, 1_000_000)
    check 9999 in built
    t.clickAt(20, 180)
    check selected == 9999

  test "shrinking or clearing a scrolled list clamps before building":
    var count = 10_000
    var built: seq[int]
    proc view(c: Context) =
      built.setLen(0)
      virtualList(c, "library", count, 40, 200, proc(c: Context, i: int) =
        built.add(i)
        text(c, $i)
      )
    let t = newTester(view, 400, 200)
    discard t.render()
    t.scrollAt(50, 50, 100_000)
    count = 3
    discard t.render()
    check built == @[0, 1, 2]
    check t.engine.scrollOffsets["library"] == 0
    count = 0
    discard t.render()
    check built.len == 0

  test "revealing current song preserves visibility and ignores invalid rows":
    let engine = Engine()
    engine.revealListRow("songs", 500, 1000, 40, 200)
    check engine.scrollOffsets["songs"] == 19_840
    engine.revealListRow("songs", 499, 1000, 40, 200)
    check engine.scrollOffsets["songs"] == 19_840
    engine.revealListRow("songs", 0, 1000, 40, 200)
    check engine.scrollOffsets["songs"] == 0
    engine.revealListRow("songs", 1000, 1000, 40, 200)
    check engine.scrollOffsets["songs"] == 0
