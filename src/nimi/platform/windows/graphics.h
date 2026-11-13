#ifndef NIMI_GRAPHICS_H
#define NIMI_GRAPHICS_H
#include <wchar.h>
void nimi_gdi_measure(const wchar_t *text, int count, float size, int bold, float *metrics);
void nimi_gdi_text(void *dc, const wchar_t *text, int count, float x, float y, float size, int bold, unsigned color);
void nimi_gdi_rect(void *dc, int x, int y, int w, int h, int radius, unsigned color, unsigned alpha);
void nimi_gdi_clip(void *dc, int x, int y, int w, int h);
void nimi_gdi_restore(void *dc);
#endif
