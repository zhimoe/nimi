#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <imm.h>
#include <stdlib.h>
#include <string.h>
#include "ime.h"
#include "host.h"

static int read_value(HIMC context, DWORD kind, void **out, int *length, int unit) {
    LONG bytes = ImmGetCompositionStringW(context, kind, NULL, 0);
    if (bytes < 0 || bytes > 16*1024*1024 || bytes % unit) return 0;
    *length = bytes / unit;
    if (!bytes) return 1;
    *out = malloc((size_t)bytes);
    if (!*out) return 0;
    return ImmGetCompositionStringW(context, kind, *out, bytes) == bytes;
}
int nimi_ime_read(void *window, unsigned flags, NimiComposition *data) {
    memset(data, 0, sizeof(*data));
    HIMC context = ImmGetContext(window);
    if (!context) return 0;
    int ok = 1;
    if (flags & GCS_RESULTSTR)
        ok = read_value(context, GCS_RESULTSTR, (void **)&data->result, &data->result_length, 2);
    if (ok && (flags & (GCS_COMPSTR | GCS_COMPATTR | GCS_CURSORPOS))) {
        ok = read_value(context, GCS_COMPSTR, (void **)&data->composition, &data->composition_length, 2);
        /* Some IMEs expose no attributes; the cursor is a sufficient fallback. */
        if (!read_value(context, GCS_COMPATTR, (void **)&data->attributes, &data->attributes_length, 1))
            data->attributes_length = 0;
        data->cursor = ImmGetCompositionStringW(context, GCS_CURSORPOS, NULL, 0);
    }
    ImmReleaseContext(window, context);
    return ok;
}
void nimi_ime_free(NimiComposition *data) {
    free(data->result); free(data->composition); free(data->attributes);
    memset(data, 0, sizeof(*data));
}
void nimi_ime_place(void *window, float x, float y, float width, float height) {
    HIMC context = ImmGetContext(window);
    if (!context) return;
    float scale = nimi_host_scale(window);
    LONG left = (LONG)(x*scale), top = (LONG)(y*scale);
    LONG right = (LONG)((x+width)*scale), bottom = (LONG)((y+height)*scale);
    if (right <= left) right = left+1;
    if (bottom <= top) bottom = top+1;
    COMPOSITIONFORM composition = {0};
    composition.dwStyle = CFS_POINT;
    composition.ptCurrentPos.x = left; composition.ptCurrentPos.y = top;
    ImmSetCompositionWindow(context, &composition);
    CANDIDATEFORM candidate = {0};
    candidate.dwStyle = CFS_EXCLUDE;
    candidate.ptCurrentPos.x = left; candidate.ptCurrentPos.y = bottom;
    candidate.rcArea = (RECT){left, top, right, bottom};
    ImmSetCandidateWindow(context, &candidate);
    ImmReleaseContext(window, context);
}
void nimi_ime_cancel(void *window) {
    HIMC context = ImmGetContext(window);
    if (!context) return;
    ImmNotifyIME(context, NI_COMPOSITIONSTR, CPS_CANCEL, 0);
    ImmReleaseContext(window, context);
}
void nimi_ime_enable(void *window, int enabled) {
    ImmAssociateContextEx(window, NULL, enabled ? IACE_DEFAULT : 0);
}
