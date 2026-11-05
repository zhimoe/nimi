import std/[tables, unittest]

import nimi/ui

suite "ui":
  test "layout and click by key":
    var n = 0
    proc view(c: Context) =
      column(c).fill().center().gap(10).children(c, proc() =
        text(c, $n).fontSize(40).bold()
        button(c, "+", (proc() = inc n), key = "inc")
      )

    let engine = Engine()
    discard engine.render(view, 320, 240)
    check engine.hits.len == 1
    check engine.hits[0].key == "inc"
    check engine.hits[0].rect.w > 0
    check engine.hits[0].rect.h > 0

    check engine.clickKey("inc")
    check n == 1
    check not engine.clickKey("missing")

  test "mouse down/up inside the button":
    var n = 0
    proc view(c: Context) =
      column(c).fill().center().children(c, proc() =
        button(c, "+", (proc() = inc n), key = "inc")
      )

    let engine = Engine()
    discard engine.render(view, 320, 240)
    let r = engine.hits[0].rect
    let cx = r.x + r.w / 2
    let cy = r.y + r.h / 2
    engine.handleMouseMove(cx, cy)
    check engine.hoveredKey == "inc"
    engine.handleMouseDown(cx, cy)
    check engine.pressedKey == "inc"
    engine.handleMouseUp(cx, cy)
    check n == 1
    check engine.pressedKey == ""

  test "mouse up outside does not click":
    var n = 0
    proc view(c: Context) =
      column(c).fill().children(c, proc() =
        button(c, "+", (proc() = inc n), key = "inc")
      )

    let engine = Engine()
    discard engine.render(view, 320, 240)
    let r = engine.hits[0].rect
    engine.handleMouseDown(r.x + 2, r.y + 2)
    engine.handleMouseUp(r.x + r.w + 50, r.y + r.h + 50)
    check n == 0

  test "key events are consumed per frame":
    var n = 0
    proc view(c: Context) =
      while c.keyPressed("up"): inc n
      while c.keyPressed("down"): dec n
      column(c).fill().children(c, proc() =
        text(c, $n)
      )

    let engine = Engine()
    engine.handleKeyDown("up")
    engine.handleKeyDown("up")
    engine.handleKeyDown("down")
    discard engine.render(view, 200, 120)
    check n == 1
    # A key not consumed in one frame does not leak into the next.
    discard engine.render(view, 200, 120)
    check n == 1

  test "tester click and text":
    var n = 0
    proc view(c: Context) =
      column(c).fill().center().gap(8).children(c, proc() =
        text(c, $n).fontSize(30)
        button(c, "+", (proc() = inc n), key = "inc")
      )

    let t = newTester(view, 200, 150)
    discard t.render()
    check t.hasText("0")
    check t.click("inc")
    check t.hasText("1")
    t.resize(240, 180)
    discard t.render()
    check t.hasText("1")

  test "tab focus and enter activate":
    var n = 0
    proc view(c: Context) =
      column(c).fill().center().gap(8).children(c, proc() =
        button(c, "-", (proc() = dec n), key = "dec")
        button(c, "+", (proc() = inc n), key = "inc")
        text(c, $n)
      )

    let t = newTester(view, 200, 150)
    discard t.render()
    t.key("tab")
    check t.engine.focusedKey == "dec"
    t.key("tab")
    check t.engine.focusedKey == "inc"
    t.key("enter")
    check n == 1
    check t.hasText("1")

  test "text wraps":
    proc view(c: Context) =
      column(c).fill().padding(10, 10).children(c, proc() =
        text(c, "one two three four five six seven eight").fontSize(16).wrap()
      )

    let t = newTester(view, 120, 200)
    discard t.render()
    check t.texts().len > 1
    check t.texts()[0].len < 40

  test "checkbox and switch":
    var checked = false
    var on = false
    proc view(c: Context) =
      column(c).fill().padding(10, 10).gap(8).children(c, proc() =
        checkbox(c, "Remember", checked, proc() = checked = not checked, key = "check")
        switch(c, on, proc() = on = not on, key = "switch")
        text(c, $checked & "/" & $on)
      )

    let t = newTester(view, 240, 160)
    discard t.render()
    check t.hasText("false/false")
    check t.click("check")
    check t.hasText("true/false")
    check t.click("switch")
    check t.hasText("true/true")

  test "slider drag":
    var v = 0.0'f32
    proc view(c: Context) =
      column(c).fill().padding(10, 10).children(c, proc() =
        slider(c, v, proc(x: float32) = v = x, key = "s").width(200)
        text(c, $int(v * 100))
      )

    let t = newTester(view, 240, 120)
    discard t.render()
    let r = t.engine.hits[0].rect
    t.clickAt(r.x + r.w * 0.75, r.y + r.h / 2)
    check abs(v - 0.75) < 0.02

  test "scroll view offsets and clips hits":
    var clicks = 0
    proc view(c: Context) =
      column(c).fill().padding(10, 10).children(c, proc() =
        scrollView(c, "list", height = 100).width(200).children(c, proc() =
          for i in 0 ..< 20:
            button(c, "item " & $i, (proc() = inc clicks), key = "item" & $i)
        )
      )

    let t = newTester(view, 260, 200)
    discard t.render()
    check t.engine.scrollRegions.len == 1
    let region = t.engine.scrollRegions[0]
    check region.contentH > region.rect.h
    t.scrollAt(region.rect.x + 10, region.rect.y + 10, 80)
    check t.engine.scrollOffsets["list"] == 80
    t.scrollAt(region.rect.x + 10, region.rect.y + 10, 10000)
    check t.engine.scrollOffsets["list"] == region.contentH - region.rect.h
    t.scrollAt(region.rect.x + 10, region.rect.y + 10, -10000)
    check t.engine.scrollOffsets["list"] == 0

  test "undo and redo":
    var value = ""
    proc view(c: Context) =
      column(c).fill().padding(10, 10).children(c, proc() =
        textInput(c, value, proc(s: string) = value = s, key = "name")
      )

    let t = newTester(view, 260, 100)
    discard t.render()
    t.clickAt(20, 20)
    t.typeText("hello")
    check value == "hello"
    t.key("z", KeyCommand)
    check value == "hell"
    t.key("z", KeyCommand or KeyShift)
    check value == "hello"

  test "selection and clipboard":
    var value = "hello world"
    var clip = ""
    proc view(c: Context) =
      column(c).fill().padding(10, 10).children(c, proc() =
        textInput(c, value, proc(s: string) = value = s, key = "name")
      )

    let t = newTester(view, 320, 100)
    t.engine.clipboardRead = proc(): string = clip
    t.engine.clipboardWrite = proc(s: string) = clip = s
    discard t.render()
    t.clickAt(20, 20)
    t.key("end")
    t.key("left", KeyShift)
    t.key("left", KeyShift)
    t.key("c", KeyCommand)
    check clip == "ld"
    t.key("end")
    t.key("v", KeyCommand)
    check value == "hello worldld"
    t.key("home")
    t.key("right", KeyShift)
    t.key("right", KeyShift)
    t.key("right", KeyShift)
    t.key("right", KeyShift)
    t.key("right", KeyShift)
    t.key("x", KeyCommand)
    check clip == "hello"
    check value == " worldld"
    t.key("v", KeyCommand)
    check value == "hello worldld"

  test "text area multiline typing":
    var value = ""
    proc view(c: Context) =
      column(c).fill().padding(10, 10).children(c, proc() =
        textArea(c, value, proc(s: string) = value = s, key = "body",
                 height = 100)
        text(c, value)
      )

    let t = newTester(view, 280, 180)
    discard t.render()
    t.clickAt(20, 20)
    t.typeText("hi")
    t.key("enter")
    t.typeText("there")
    check value == "hi\nthere"
    check t.hasText("hi")
    check t.hasText("there")

  test "text input typing and caret":
    var value = ""
    proc view(c: Context) =
      column(c).fill().padding(10, 10).children(c, proc() =
        textInput(c, value, proc(s: string) = value = s, key = "name")
        text(c, value)
      )

    let t = newTester(view, 240, 120)
    discard t.render()
    t.clickAt(20, 20)
    t.typeText("hello")
    check value == "hello"
    t.key("backspace")
    check value == "hell"
    t.key("left")
    t.key("left")
    t.typeText("X")
    check value == "heXll"
