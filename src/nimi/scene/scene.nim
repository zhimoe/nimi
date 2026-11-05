## M2 minimal display list. The first slice supports filled rectangles and
## single-run text; gradients/clips/glyph atlases land with the full UI.

type
  Color* = object
    r*, g*, b*, a*: float32

  Rect* = object
    x*, y*, w*, h*: float32

  Point* = object
    x*, y*: float32

  OpKind* = enum
    opRect
    opText
    opClip
    opRestore
    opImage
    opImageQuad
    opPolygon

  Op* = object
    color*: Color
    imagePath*: string
    case kind*: OpKind
    of opRect:
      rect*: Rect
      radius*: float32
    of opText:
      text*: string
      x*, y*: float32
      size*: float32
      bold*: bool
    of opClip:
      clipRect*: Rect
    of opRestore:
      discard
    of opImage:
      imageRect*: Rect
    of opImageQuad:
      sourceRect*: Rect
      quad*: array[4, Point]
    of opPolygon:
      points*: seq[Point]

  Scene* = object
    width*, height*: float32
    clear*: Color
    ops*: seq[Op]

proc rgb*(r, g, b: float32, a: float32 = 1.0): Color =
  Color(r: r, g: g, b: b, a: a)

proc rect*(s: var Scene, r: Rect, color: Color, radius: float32 = 0) =
  s.ops.add Op(kind: opRect, rect: r, color: color, radius: radius)

proc text*(s: var Scene, text: string, x, y: float32, size: float32,
           color: Color, bold: bool = false) =
  ## x is the left edge; y is the top of the line (not the baseline).
  s.ops.add Op(kind: opText, text: text, x: x, y: y, size: size,
               bold: bold, color: color)

proc clip*(s: var Scene, r: Rect) =
  s.ops.add Op(kind: opClip, clipRect: r)

proc restoreClip*(s: var Scene) =
  s.ops.add Op(kind: opRestore)

proc image*(s: var Scene, path: string, r: Rect) =
  s.ops.add Op(kind: opImage, imagePath: path, imageRect: r)

proc polygon*(s: var Scene, points: seq[Point], color: Color) =
  s.ops.add Op(kind: opPolygon, points: points, color: color)

proc imageQuad*(s: var Scene, path: string, source: Rect,
                quad: array[4, Point]) =
  ## Draw a source rectangle from an image into an arbitrary quad. The quad is
  ## ordered top-left, top-right, bottom-right, bottom-left. `source` is in
  ## image pixels, top-left origin. The CPU renderer splits the quad into two
  ## textured triangles; a future Metal renderer can consume the same op.
  s.ops.add Op(kind: opImageQuad, imagePath: path, sourceRect: source,
               quad: quad)
