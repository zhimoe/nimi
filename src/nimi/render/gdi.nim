## Windows CPU scene slice: rectangles, text and nested clipping.
import ../scene/scene
import ../platform/windows/graphics
import ../platform/contract

proc component(v: float32): cuint = cuint(max(0'f32, min(1'f32, v)) * 255)
proc color(c: Color): cuint = component(c.r) or (component(c.g) shl 8) or (component(c.b) shl 16)
proc fill(dc: pointer, r: Rect, c: Color, radius: float32 = 0) =
  gdiRect(dc, cint(r.x), cint(r.y), cint(r.w), cint(r.h), cint(radius), color(c), component(c.a))
proc drawScene*(dc: pointer, scene: Scene) =
  fill(dc, Rect(w: scene.width, h: scene.height), scene.clear)
  var clips = 0
  defer:
    while clips > 0:
      gdiRestore(dc)
      dec clips
  for op in scene.ops:
    case op.kind
    of opRect: fill(dc, op.rect, op.color, op.radius)
    of opText:
      let wide = newWideCString(op.text)
      gdiText(dc, wide, cint(wide.len), op.x, op.y, op.size, cint(op.bold), color(op.color))
    of opClip:
      let r = op.clipRect
      gdiClip(dc, cint(r.x), cint(r.y), cint(r.w), cint(r.h))
      inc clips
    of opRestore:
      if clips > 0:
        gdiRestore(dc)
        dec clips
    else:
      raise newException(BackendError, "Windows renderer does not yet support " & $op.kind)
