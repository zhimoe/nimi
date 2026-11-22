## Pango text layout shared by measurement and Cairo rendering.

import ../contract
import ./ffi

const
  PangoScale = 1024.0
  PangoWeightBold = 700

type
  PangoMetrics* = object
    width*, height*, ascent*, descent*: float32

proc fontFamily*(family: string): cstring =
  ## `""` is the platform UI font, `"mono"` its monospace face.
  if family == "mono": "Monospace"
  else: "Sans"

proc newFontDescription*(size: float32, bold: bool,
                         family: string): pointer =
  result = pango_font_description_new()
  pango_font_description_set_family(result, fontFamily(family))
  pango_font_description_set_absolute_size(result,
    cdouble(max(size, 1.0'f32)) * PangoScale)
  if bold:
    pango_font_description_set_weight(result, PangoWeightBold)

proc newLayout*(cr: pointer, text: string, size: float32, bold: bool,
                family: string, desc: pointer = nil): pointer =
  result = pango_cairo_create_layout(cr)
  let description = if desc != nil: desc
                    else: newFontDescription(size, bold, family)
  pango_layout_set_font_description(result, description)
  pango_layout_set_text(result, text.cstring, cint(text.len))
  pango_layout_set_single_paragraph_mode(result, 1)
  pango_layout_set_width(result, -1)
  if desc == nil:
    pango_font_description_free(description)

var
  measureSurface, measureContext: pointer

proc measureContextHandle(): pointer =
  ensureCore()
  if measureContext == nil:
    measureSurface = cairo_image_surface_create(0, 1, 1)
    if measureSurface == nil:
      raise newException(BackendError, "Linux backend: cannot create a Cairo surface")
    measureContext = cairo_create(measureSurface)
    if measureContext == nil:
      raise newException(BackendError, "Linux backend: cannot create a Cairo context")
  measureContext

proc measurePango*(text: string, size: float32, bold: bool,
                   family: string): PangoMetrics =
  let cr = measureContextHandle()
  let desc = newFontDescription(size, bold, family)
  defer: pango_font_description_free(desc)
  let layout = newLayout(cr, text, size, bold, family, desc)
  defer: g_object_unref(layout)
  var ink, logical: PangoRectangle
  pango_layout_get_extents(layout, addr ink, addr logical)
  let context = pango_layout_get_context(layout)
  var ascent, descent, fontHeight: float64
  let metrics = pango_context_get_metrics(context, desc, nil)
  if metrics != nil:
    ascent = float64(pango_font_metrics_get_ascent(metrics)) / PangoScale
    descent = float64(pango_font_metrics_get_descent(metrics)) / PangoScale
    fontHeight =
      if pango_font_metrics_get_height != nil:
        float64(pango_font_metrics_get_height(metrics)) / PangoScale
      else:
        ascent + descent
    pango_font_metrics_unref(metrics)
  if fontHeight <= 0:
    fontHeight = float64(pango_layout_get_baseline(layout)) / PangoScale
  if ascent <= 0:
    ascent = fontHeight
  result = PangoMetrics(
    width: max(0.0'f32, float32(logical.width) / float32(PangoScale)),
    height: max(float32(fontHeight), float32(logical.height) / float32(PangoScale)),
    ascent: float32(ascent),
    descent: float32(max(0.0, descent)))

proc drawPango*(cr: pointer, text: string, x, y, size: float32,
                bold: bool, family: string, r, g, b, a: float32) =
  if text.len == 0:
    return
  let layout = newLayout(cr, text, size, bold, family)
  defer: g_object_unref(layout)
  pango_cairo_update_layout(cr, layout)
  cairo_move_to(cr, cdouble(x), cdouble(y))
  cairo_set_source_rgba(cr, cdouble(r), cdouble(g), cdouble(b), cdouble(a))
  pango_cairo_show_layout(cr, layout)
