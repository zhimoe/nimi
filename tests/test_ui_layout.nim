## Flex/box-model behavior added for the environment UI.
import std/unittest

import nimi/ui

suite "flex layout":
  test "row grow shares the remaining width":
    proc view(c: Context) =
      row(c).fill().padding(10, 10).gap(10).children(c, proc() =
        button(c, "x", (proc() = discard), key = "a").grow(1).height(20)
        button(c, "x", (proc() = discard), key = "b").grow(1).height(20)
      )

    let t = newTester(view, 300, 100)
    discard t.render()
    check t.engine.hits.len == 2
    check t.engine.hits[0].rect.x == 10'f32
    check t.engine.hits[0].rect.w == 135'f32
    check t.engine.hits[0].rect.h == 20'f32
    check t.engine.hits[1].rect.x == 155'f32
    check t.engine.hits[1].rect.w == 135'f32

  test "column grow keeps fixed header and footer":
    proc view(c: Context) =
      column(c).fill().gap(5).children(c, proc() =
        button(c, "header", (proc() = discard), key = "head").height(40)
        button(c, "body", (proc() = discard), key = "body").grow(1)
        button(c, "footer", (proc() = discard), key = "foot").height(30)
      )

    let t = newTester(view, 200, 300)
    discard t.render()
    check t.engine.hits.len == 3
    check t.engine.hits[0].rect.y == 0'f32
    check t.engine.hits[0].rect.h == 40'f32
    check t.engine.hits[1].rect.y == 45'f32
    check t.engine.hits[1].rect.h == 220'f32
    check t.engine.hits[2].rect.y == 270'f32
    check t.engine.hits[2].rect.h == 30'f32

  test "align and justify center match legacy center":
    proc view(c: Context) =
      column(c).fill().justifyContent(jcCenter).alignItems(aiCenter).gap(10).
        children(c, proc() =
          text(c, "a").width(40).height(20)
          button(c, "b", (proc() = discard), key = "b").width(60).height(20)
        )

    let t = newTester(view, 320, 240)
    discard t.render()
    check t.engine.hits.len == 1
    check t.engine.hits[0].rect.x == 130'f32
    check t.engine.hits[0].rect.y == 125'f32

  test "row end alignment places the child at the cross end":
    proc view(c: Context) =
      row(c).fill().alignItems(aiEnd).children(c, proc() =
        button(c, "x", (proc() = discard), key = "x").width(60).height(20)
      )

    let t = newTester(view, 300, 100)
    discard t.render()
    check t.engine.hits.len == 1
    check t.engine.hits[0].rect.y == 80'f32

  test "margins offset a fixed child inside padding":
    proc view(c: Context) =
      column(c).fill().padding(10, 10).children(c, proc() =
        button(c, "x", (proc() = discard), key = "x").width(50).height(20).
          margin(5, 7)
      )

    let t = newTester(view, 300, 200)
    discard t.render()
    check t.engine.hits.len == 1
    check t.engine.hits[0].rect.x == 15'f32
    check t.engine.hits[0].rect.y == 17'f32

  test "stretch fills the cross axis and reflows text":
    proc view(c: Context) =
      column(c).fill().alignItems(aiStretch).children(c, proc() =
        button(c, "x", (proc() = discard), key = "x").height(20)
      )

    let t = newTester(view, 300, 100)
    discard t.render()
    check t.engine.hits.len == 1
    check t.engine.hits[0].rect.w == 300'f32

  test "grow respects maxWidth":
    proc view(c: Context) =
      row(c).fill().children(c, proc() =
        button(c, "x", (proc() = discard), key = "a").grow(1).
          maxWidth(100).height(20)
        button(c, "x", (proc() = discard), key = "b").grow(1).height(20)
      )

    let t = newTester(view, 300, 100)
    discard t.render()
    check t.engine.hits[0].rect.w == 100'f32
    check t.engine.hits[1].rect.w == 150'f32

  test "scroll grows and its viewport is used for scrolling":
    proc view(c: Context) =
      column(c).fill().children(c, proc() =
        button(c, "header", (proc() = discard), key = "head").height(40)
        scrollView(c, "list", height = 0).grow(1).basis(0).gap(5).children(c, proc() =
          for i in 0 ..< 20:
            button(c, "item", (proc() = discard), key = "item" & $i).height(30)
        )
        button(c, "footer", (proc() = discard), key = "foot").height(30)
      )

    let t = newTester(view, 200, 300)
    discard t.render()
    check t.engine.scrollRegions.len == 1
    check t.engine.scrollRegions[0].rect.y == 40'f32
    check t.engine.scrollRegions[0].rect.h == 230'f32
    check t.engine.scrollRegions[0].contentH == 20'f32 * 30 + 19'f32 * 5
    var foot: Hit
    for hit in t.engine.hits:
      if hit.key == "foot":
        foot = hit
    check foot.rect.y == 270'f32
