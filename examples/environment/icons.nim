## Small 24x24 stroke icons drawn with scene polygons. Keeping them as
## vector geometry avoids image assets, SVG parsing and resource paths while
## staying crisp at any DPI.

import std/math

import nimi/ui

type
  IconName* = enum
    icUser
    icShield
    icShieldDone
    icLayers
    icRoute
    icList
    icBraces
    icClock
    icSearch
    icPlus
    icMinus
    icX
    icPencil
    icMore
    icTrash
    icCopy
    icCheck
    icAlert
    icInfo
    icLock
    icChevron
    icChevronDown
    icChevronUp
    icArrowLeft
    icArrowRight
    icUnfold
    icFold
    icSun
    icMoon
    icSliders
    icRefresh
    icSort
    icGrip
    icFolder

proc px(r: Rect, x, y: float32): Point =
  let scale = min(r.w, r.h) / 24.0
  Point(x: r.x + (r.w - 24 * scale) / 2 + x * scale,
        y: r.y + (r.h - 24 * scale) / 2 + y * scale)

proc stroke(c: Context, a, b: Point, width: float32, color: Color) =
  let dx = b.x - a.x
  let dy = b.y - a.y
  let len = sqrt(dx * dx + dy * dy)
  if len < 0.01:
    return
  let nx = -dy / len * width / 2
  let ny = dx / len * width / 2
  c.scene.polygon(@[
    Point(x: a.x + nx, y: a.y + ny),
    Point(x: b.x + nx, y: b.y + ny),
    Point(x: b.x - nx, y: b.y - ny),
    Point(x: a.x - nx, y: a.y - ny)], color)

proc dot(c: Context, center: Point, radius: float32, color: Color) =
  var points: seq[Point]
  for i in 0 ..< 16:
    let a = float32(i) * 2 * PI / 16
    points.add Point(x: center.x + cos(a) * radius,
                     y: center.y + sin(a) * radius)
  c.scene.polygon(points, color)

proc ring(c: Context, center: Point, radius, width: float32, color: Color) =
  let outer = radius + width / 2
  let inner = max(0.1'f32, radius - width / 2)
  var points: seq[Point]
  for i in 0 ..< 24:
    let a = float32(i) * 2 * PI / 24
    points.add Point(x: center.x + cos(a) * outer,
                     y: center.y + sin(a) * outer)
  for i in countdown(23, 0):
    let a = float32(i) * 2 * PI / 24
    points.add Point(x: center.x + cos(a) * inner,
                     y: center.y + sin(a) * inner)
  c.scene.polygon(points, color)

proc arcStroke(c: Context, center: Point, radius, width: float32,
               startDeg, endDeg: float32, color: Color) =
  var points: seq[Point]
  let steps = 20
  for i in 0 .. steps:
    let t = float32(i) / float32(steps)
    let a = (startDeg + (endDeg - startDeg) * t) * PI / 180
    points.add Point(x: center.x + cos(a) * radius,
                     y: center.y + sin(a) * radius)
  for i in 0 ..< points.len - 1:
    c.stroke(points[i], points[i + 1], width, color)
    if i > 0:
      c.dot(points[i], width / 2, color)

proc polyline(c: Context, points: openArray[Point], width: float32,
              color: Color, closed = false) =
  for i in 0 ..< points.len - 1:
    c.stroke(points[i], points[i + 1], width, color)
    if i > 0:
      c.dot(points[i], width / 2, color)
  if closed and points.len > 2:
    c.stroke(points[^1], points[0], width, color)
    c.dot(points[0], width / 2, color)

proc roundedOutline(c: Context, a, b: Point, width: float32, color: Color) =
  ## A rectangle outline with cut corners at this icon scale.
  let pts = @[
    Point(x: a.x + 1, y: a.y), Point(x: b.x - 1, y: a.y),
    Point(x: b.x, y: a.y + 1), Point(x: b.x, y: b.y - 1),
    Point(x: b.x - 1, y: b.y), Point(x: a.x + 1, y: b.y),
    Point(x: a.x, y: b.y - 1), Point(x: a.x, y: a.y + 1)]
  c.polyline(pts, width, color, true)

proc drawIcon*(c: Context, r: Rect, name: IconName, color: Color) =
  let w = min(r.w, r.h) * 1.8 / 24
  let p = proc(x, y: float32): Point = px(r, x, y)
  case name
  of icUser:
    c.ring(p(12, 8.5), min(r.w, r.h) * 3.2 / 24, w, color)
    c.arcStroke(p(12, 18.5), min(r.w, r.h) * 6.8 / 24, w, 200, 340, color)
  of icShield, icShieldDone:
    c.polyline(@[p(12, 3), p(19, 6), p(18, 13), p(12, 21),
                 p(6, 13), p(5, 6)], w, color, true)
    if name == icShieldDone:
      c.polyline(@[p(8.5, 12), p(11, 14.5), p(15.5, 9.5)], w, color)
  of icLayers:
    c.polyline(@[p(12, 3), p(19, 7.5), p(12, 12), p(5, 7.5)], w, color, true)
    c.polyline(@[p(5, 12), p(12, 16.5), p(19, 12)], w, color)
    c.polyline(@[p(5, 16.5), p(12, 21), p(19, 16.5)], w, color)
  of icRoute:
    c.ring(p(6, 18), min(r.w, r.h) * 2.3 / 24, w, color)
    c.ring(p(18, 6), min(r.w, r.h) * 2.3 / 24, w, color)
    c.polyline(@[p(6, 18), p(6, 11), p(10, 7), p(18, 7)], w, color)
  of icList:
    for y in [6.0'f32, 12, 18]:
      c.dot(p(5, y), w * 0.75, color)
      c.stroke(p(9, y), p(19, y), w, color)
  of icBraces:
    c.polyline(@[p(9, 4), p(7, 6), p(7, 10), p(5, 12),
                 p(7, 14), p(7, 18), p(9, 20)], w, color)
    c.polyline(@[p(15, 4), p(17, 6), p(17, 10), p(19, 12),
                 p(17, 14), p(17, 18), p(15, 20)], w, color)
  of icClock:
    c.ring(p(12, 12), min(r.w, r.h) * 8.3 / 24, w, color)
    c.polyline(@[p(12, 7), p(12, 12), p(16, 14)], w, color)
  of icSearch:
    c.ring(p(10.5, 10.5), min(r.w, r.h) * 6.0 / 24, w, color)
    c.stroke(p(15, 15), p(20, 20), w, color)
  of icPlus:
    c.stroke(p(12, 5), p(12, 19), w, color)
    c.stroke(p(5, 12), p(19, 12), w, color)
  of icMinus:
    c.stroke(p(5, 12), p(19, 12), w, color)
  of icX:
    c.stroke(p(6, 6), p(18, 18), w, color)
    c.stroke(p(18, 6), p(6, 18), w, color)
  of icCheck:
    c.polyline(@[p(5, 12), p(10, 17), p(19, 7)], w, color)
  of icPencil:
    c.polyline(@[p(4, 20), p(5.5, 14.5), p(15, 5), p(19, 9),
                 p(9.5, 18.5)], w, color, true)
    c.stroke(p(14, 6), p(18, 10), w, color)
  of icMore:
    for x in [6.0'f32, 12, 18]:
      c.dot(p(x, 12), w * 1.1, color)
  of icTrash:
    c.stroke(p(4, 7), p(20, 7), w, color)
    c.polyline(@[p(9, 7), p(9, 4), p(15, 4), p(15, 7)], w, color)
    c.polyline(@[p(6, 7), p(7, 20), p(17, 20), p(18, 7)], w, color)
    c.stroke(p(10, 10), p(10, 17), w, color)
    c.stroke(p(14, 10), p(14, 17), w, color)
  of icCopy:
    c.roundedOutline(p(8, 8), p(20, 20), w, color)
    c.polyline(@[p(4, 16), p(4, 4), p(16, 4)], w, color)
  of icAlert:
    c.polyline(@[p(12, 3), p(21, 20), p(3, 20)], w, color, true)
    c.stroke(p(12, 9), p(12, 14), w, color)
    c.dot(p(12, 17), w * 0.75, color)
  of icInfo:
    c.ring(p(12, 12), min(r.w, r.h) * 8.3 / 24, w, color)
    c.stroke(p(12, 11), p(12, 17), w, color)
    c.dot(p(12, 7.5), w * 0.7, color)
  of icLock:
    c.roundedOutline(p(6, 11), p(18, 20), w, color)
    c.arcStroke(p(12, 11), min(r.w, r.h) * 4.2 / 24, w, 180, 360, color)
    c.dot(p(12, 15), w * 0.65, color)
  of icChevron:
    c.polyline(@[p(9, 5), p(16, 12), p(9, 19)], w, color)
  of icChevronDown:
    c.polyline(@[p(5, 9), p(12, 16), p(19, 9)], w, color)
  of icChevronUp:
    c.polyline(@[p(5, 15), p(12, 8), p(19, 15)], w, color)
  of icArrowLeft:
    c.stroke(p(19, 12), p(6, 12), w, color)
    c.polyline(@[p(6, 12), p(11, 7)], w, color)
    c.polyline(@[p(6, 12), p(11, 17)], w, color)
  of icArrowRight:
    c.stroke(p(5, 12), p(18, 12), w, color)
    c.polyline(@[p(18, 12), p(13, 7)], w, color)
    c.polyline(@[p(18, 12), p(13, 17)], w, color)
  of icUnfold:
    c.stroke(p(8, 18), p(8, 6), w, color)
    c.polyline(@[p(8, 6), p(5, 9)], w, color)
    c.polyline(@[p(8, 6), p(11, 9)], w, color)
    c.stroke(p(16, 6), p(16, 18), w, color)
    c.polyline(@[p(16, 18), p(13, 15)], w, color)
    c.polyline(@[p(16, 18), p(19, 15)], w, color)
  of icFold:
    c.stroke(p(8, 6), p(8, 18), w, color)
    c.polyline(@[p(8, 18), p(5, 15)], w, color)
    c.polyline(@[p(8, 18), p(11, 15)], w, color)
    c.stroke(p(16, 18), p(16, 6), w, color)
    c.polyline(@[p(16, 6), p(13, 9)], w, color)
    c.polyline(@[p(16, 6), p(19, 9)], w, color)
  of icSun:
    c.ring(p(12, 12), min(r.w, r.h) * 4.2 / 24, w, color)
    for i in 0 ..< 8:
      let a = float32(i) * PI / 4
      let r1 = min(r.w, r.h) * 6.5 / 24
      let r2 = min(r.w, r.h) * 9.0 / 24
      let cx = p(12, 12)
      c.stroke(Point(x: cx.x + cos(a) * r1, y: cx.y + sin(a) * r1),
               Point(x: cx.x + cos(a) * r2, y: cx.y + sin(a) * r2), w, color)
  of icMoon:
    var points: seq[Point]
    let center = p(11, 12)
    let radius = min(r.w, r.h) * 8.0 / 24
    for i in 0 .. 20:
      let a = (40 + (320 - 40) * float32(i) / 20) * PI / 180
      points.add Point(x: center.x + cos(a) * radius,
                       y: center.y + sin(a) * radius)
    let inner = p(16, 9)
    for i in countdown(20, 0):
      let a = (40 + (320 - 40) * float32(i) / 20) * PI / 180
      points.add Point(x: inner.x + cos(a) * radius * 0.9,
                       y: inner.y + sin(a) * radius * 0.9)
    c.scene.polygon(points, color)
  of icSliders:
    for y in [7.0'f32, 12, 17]:
      c.stroke(p(4, y), p(20, y), w, color)
    c.dot(p(9, 7), w * 1.1, color)
    c.dot(p(15, 12), w * 1.1, color)
    c.dot(p(10, 17), w * 1.1, color)
  of icRefresh:
    c.arcStroke(p(12, 12), min(r.w, r.h) * 7.5 / 24, w, 30, 300, color)
    c.polyline(@[p(16, 4), p(18, 8), p(14, 9)], w, color)
  of icSort:
    c.stroke(p(9, 18), p(9, 6), w, color)
    c.polyline(@[p(9, 6), p(6, 9)], w, color)
    c.polyline(@[p(9, 6), p(12, 9)], w, color)
    c.stroke(p(15, 6), p(15, 18), w, color)
    c.polyline(@[p(15, 18), p(12, 15)], w, color)
    c.polyline(@[p(15, 18), p(18, 15)], w, color)
  of icGrip:
    for y in [7.0'f32, 12, 17]:
      for x in [9.0'f32, 15]:
        c.dot(p(x, y), w * 0.8, color)
  of icFolder:
    c.polyline(@[p(3, 7), p(10, 7), p(12, 9), p(21, 9), p(21, 19),
                 p(3, 19)], w, color, true)

proc icon*(c: Context, name: IconName, size: float32, color: Color,
           key: string = "", onClick: proc() {.closure.} = nil): Node
  {.discardable.} =
  let drawColor = color
  custom(c, key, size, size, proc(ctx: Context, r: Rect) =
    drawIcon(ctx, r, name, drawColor)
  , onClick = onClick)

proc statusDot*(c: Context, size: float32, color: Color,
                key: string = ""): Node {.discardable.} =
  let drawColor = color
  custom(c, key, size, size, proc(ctx: Context, r: Rect) =
    let center = Point(x: r.x + r.w / 2, y: r.y + r.h / 2)
    dot(ctx, center, min(r.w, r.h) / 2, drawColor))
