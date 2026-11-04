## M2 minimal display list. The first slice supports filled rectangles and
## single-run text; gradients/clips/glyph atlases land with the full UI.

type
  Color* = object
    r*, g*, b*, a*: float32

  Rect* = object
    x*, y*, w*, h*: float32

  OpKind* = enum
    opRect
    opText

  Op* = object
    color*: Color
    case kind*: OpKind
    of opRect:
      rect*: Rect
      radius*: float32
    of opText:
      text*: string
      x*, y*: float32
      size*: float32
      bold*: bool

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
