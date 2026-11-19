## Container painting, overlays, focus, shortcuts, custom and rich-text nodes.
import std/[strutils, unittest]

import nimi/ui

suite "ui widgets":
  test "container background, border and clip":
    proc view(c: Context) =
      column(c).width(100).height(60).
        background(rgb(0.9, 0.1, 0.1)).border(2, rgb(0.1, 0.1, 0.9))

    let t = newTester(view, 160, 100)
    discard t.render()
    var sawBg, sawBorder = false
    for op in t.scene.ops:
      if op.kind == opRect:
        if abs(op.color.r - 0.9) < 0.01 and op.rect.w == 100:
          sawBg = true
        if abs(op.color.b - 0.9) < 0.01:
          sawBorder = true
    check sawBg
    check sawBorder

  test "clipChildren clips painting and hits":
    var clicks = 0
    proc view(c: Context) =
      column(c).key("clip").width(50).height(50).clipChildren().children(c, proc() =
        button(c, "wide", (proc() = inc clicks), key = "wide").width(100).height(20)
      )

    let t = newTester(view, 120, 100)
    discard t.render()
    var clipped = false
    for op in t.scene.ops:
      if op.kind == opClip and op.clipRect.w == 50 and op.clipRect.h == 50:
        clipped = true
    check clipped
    t.engine.handleMouseDown(80, 10)
    t.engine.handleMouseUp(80, 10)
    check clicks == 0
    t.engine.handleMouseDown(10, 10)
    t.engine.handleMouseUp(10, 10)
    check clicks == 1

  test "buttonBase contains children and activates":
    var clicks = 0
    proc view(c: Context) =
      buttonBase(c, "base", proc() = inc clicks).width(100).height(30).
        children(c, proc() =
          text(c, "OK")
        )

    let t = newTester(view, 160, 100)
    discard t.render()
    check t.engine.hits.len == 1
    check t.click("base")
    check clicks == 1
    check t.hasText("OK")

  test "overlay sits above content and owns tab focus":
    var mainClicks, closeClicks, dismissed = 0
    proc view(c: Context) =
      column(c).fill().children(c, proc() =
        button(c, "main", (proc() = inc mainClicks), key = "main").width(60).height(30)
      )
      let sheet = overlay(c, "sheet")
      sheet.background(rgb(0, 0, 0, 0.32)).whenClicked(proc() = inc dismissed)
      sheet.justifyContent(jcEnd).alignItems(aiStretch).children(c, proc() =
        column(c).key("panel").width(200).blockClicks().
          whenClicked(proc() = discard).children(c, proc() =
            button(c, "close", (proc() = inc closeClicks), key = "close").height(30)
          )
      )

    let t = newTester(view, 300, 200)
    discard t.render()
    var layers = 0
    for hit in t.engine.hits:
      layers = max(layers, hit.layer)
    check layers == 1
    t.engine.handleMouseDown(10, 10)
    t.engine.handleMouseUp(10, 10)
    check dismissed == 1
    check mainClicks == 0
    t.engine.handleMouseDown(110, 10)
    t.engine.handleMouseUp(110, 10)
    check closeClicks == 1
    check dismissed == 1
    t.key("tab")
    check t.engine.focusedKey == "close"

  test "focus request focuses and optional select-all":
    var value = ""
    var first = true
    proc view(c: Context) =
      column(c).fill().padding(10, 10).children(c, proc() =
        textInput(c, value, (proc(v: string) = value = v), key = "search")
      )
      if first:
        c.requestFocus("search", selectAll = true)
        first = false

    let t = newTester(view, 240, 100)
    discard t.render()
    check t.engine.focusedKey == "search"
    t.typeText("x")
    check value == "x"

    value = "abc"
    first = true
    discard t.render()
    check t.engine.focusedKey == "search"
    t.typeText("y")
    check value == "y"

  test "registered shortcuts beat text editing but preserve Ctrl+A":
    var value = ""
    var shortcuts = 0
    proc view(c: Context) =
      c.registerShortcut("k", KeyShortcut, proc() = inc shortcuts)
      column(c).fill().padding(10, 10).children(c, proc() =
        textInput(c, value, (proc(v: string) = value = v), key = "search")
      )

    let t = newTester(view, 240, 100)
    discard t.render()
    check t.click("search")
    t.typeText("ab")
    check value == "ab"
    t.key("k", KeyShortcut)
    check shortcuts == 1
    check value == "ab"
    t.key("a", KeyShortcut)
    t.typeText("x")
    check value == "x"

  test "rich text paints runs, highlight, and ellipsis":
    proc view(c: Context) =
      column(c).fill().padding(4, 4).children(c, proc() =
        richText(c, [
          TextRun(text: "abc", color: rgb(0.8, 0.1, 0.1),
                  bg: rgb(1, 0.9, 0.2, 0.5)),
          TextRun(text: "def", color: rgb(0.1, 0.2, 0.8))
        ]).width(30).height(20)
      )

    let t = newTester(view, 80, 60)
    discard t.render()
    check t.hasText("abc")
    var ellipsis = false
    var highlight = false
    for op in t.scene.ops:
      if op.kind == opText and op.text.endsWith("…"):
        ellipsis = true
      if op.kind == opRect and op.color.a > 0.4 and
          abs(op.color.g - 0.9) < 0.01:
        highlight = true
    check ellipsis
    check highlight

  test "custom node paints and clicks":
    var clicks = 0
    proc view(c: Context) =
      custom(c, "icon", 24, 24, proc(c: Context, r: Rect) =
        c.scene.rect(r, rgb(0.2, 0.4, 0.8))
      , onClick = proc() = inc clicks)

    let t = newTester(view, 80, 60)
    discard t.render()
    var painted = false
    for op in t.scene.ops:
      if op.kind == opRect and abs(op.color.b - 0.8) < 0.01:
        painted = true
    check painted
    check t.click("icon")
    check clicks == 1
