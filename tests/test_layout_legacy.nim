## Exact legacy layout guards. These must stay green while flex/box-model
## support is added: defaults keep the old fill/center/gap/padding geometry,
## hit count and hit order.
import std/[strutils, unittest]

import nimi/ui

suite "legacy layout":
  test "column padding, row children, and hit order":
    proc view(c: Context) =
      column(c).fill().padding(10, 10).gap(8).children(c, proc() =
        row(c).width(200).height(40).gap(4).children(c, proc() =
          text(c, "a").width(50).height(20)
          text(c, "b").width(60).height(30)
        )
        button(c, "x", (proc() = discard), key = "btn").width(80).height(24)
      )

    let t = newTester(view, 320, 240)
    discard t.render()
    check t.engine.hits.len == 1
    check t.engine.hits[0].key == "btn"
    check t.engine.hits[0].rect.x == 10
    check t.engine.hits[0].rect.y == 58
    check t.engine.hits[0].rect.w == 80
    check t.engine.hits[0].rect.h == 24

  test "center centers the group and each child on the cross axis":
    proc view(c: Context) =
      column(c).fill().center().gap(10).children(c, proc() =
        text(c, "a").width(40).height(20)
        button(c, "b", (proc() = discard), key = "b").width(60).height(20)
      )

    let t = newTester(view, 320, 240)
    discard t.render()
    check t.engine.hits.len == 1
    check t.engine.hits[0].rect.x == 130
    check t.engine.hits[0].rect.y == 125
    check t.engine.hits[0].rect.w == 60
    check t.engine.hits[0].rect.h == 20

  test "scroll content height and child arrangement":
    proc view(c: Context) =
      scrollView(c, "list", height = 100).width(200).gap(5).children(c, proc() =
        for i in 0 ..< 5:
          button(c, "item", (proc() = discard), key = "item" & $i).height(30)
      )

    let t = newTester(view, 260, 200)
    discard t.render()
    check t.engine.scrollRegions.len == 1
    check t.engine.scrollRegions[0].key == "list"
    check t.engine.scrollRegions[0].contentH == 170
    var rows: seq[Hit]
    for hit in t.engine.hits:
      if hit.key.startsWith("item"):
        rows.add hit
    check rows.len == 5
    check rows[0].rect.y == 0
    check rows[1].rect.y == 35
    check rows[4].rect.y == 140

  test "root fill and text wrapping still use the viewport width":
    proc view(c: Context) =
      column(c).fill().padding(10, 10).children(c, proc() =
        text(c, "one two three four five six seven eight").wrap()
      )

    let t = newTester(view, 120, 200)
    discard t.render()
    check t.texts().len > 1
    check t.texts()[0].len < 40
    check t.engine.hits.len == 0
