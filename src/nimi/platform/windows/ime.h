#ifndef NIMI_WINDOWS_IME_H
#define NIMI_WINDOWS_IME_H
#include <stdint.h>
typedef struct {
    uint16_t *result, *composition;
    unsigned char *attributes;
    int result_length, composition_length, attributes_length, cursor;
} NimiComposition;
int nimi_ime_read(void *window, unsigned flags, NimiComposition *data);
void nimi_ime_free(NimiComposition *data);
void nimi_ime_place(void *window, float x, float y, float width, float height);
void nimi_ime_cancel(void *window);
void nimi_ime_enable(void *window, int enabled);
#endif
