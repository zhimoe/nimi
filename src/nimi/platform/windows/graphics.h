#ifndef NIMI_GRAPHICS_H
#define NIMI_GRAPHICS_H
#include <wchar.h>
typedef struct { int x, y; } NimiPoint;
typedef struct NimiImage NimiImage;
void nimi_gdi_measure(const wchar_t *text, int count, float size, int bold, float *metrics);
void nimi_gdi_text(void *dc, const wchar_t *text, int count, float x, float y, float size, int bold, unsigned color);
void nimi_gdi_rect(void *dc, int x, int y, int w, int h, int radius, unsigned color, unsigned alpha);
void nimi_gdi_polygon(void *dc, const NimiPoint *points, int count, unsigned color, unsigned alpha);
void nimi_gdi_clip(void *dc, int x, int y, int w, int h);
void nimi_gdi_restore(void *dc);
NimiImage *nimi_gdi_image_load(const wchar_t *path);
void nimi_gdi_image_free(NimiImage *image);
int nimi_gdi_image_width(const NimiImage *image);
int nimi_gdi_image_height(const NimiImage *image);
int nimi_gdi_image_draw(void *dc, const NimiImage *image, int x, int y, int w, int h,
                        int sourceX, int sourceY, int sourceWidth, int sourceHeight);
#endif
