#ifndef NIMI_WEBVIEW2_H
#define NIMI_WEBVIEW2_H
#include <wchar.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct NimiWebView2 NimiWebView2;

typedef struct NimiWebView2Callbacks {
    void (*ready)(void *context);
    void (*message)(void *context, char *text);
    void (*error)(void *context, char *text);
    /* Called after the C owner has released every COM object, before it is
       freed. The Nim side uses it to drop its callback context safely. */
    void (*finalized)(void *context);
    void *context;
} NimiWebView2Callbacks;

NimiWebView2 *nimi_webview2_create(void *parent, const wchar_t *user_data_folder,
    const wchar_t *loader_hint, const wchar_t *scheme, const wchar_t *file_root,
    const wchar_t *bridge_script, NimiWebView2Callbacks callbacks,
    char *error, int error_size);
int nimi_webview2_ready(NimiWebView2 *view);
void nimi_webview2_resize(NimiWebView2 *view, int width, int height, float scale);
void nimi_webview2_show(NimiWebView2 *view, int visible);
void nimi_webview2_focus(NimiWebView2 *view);
void nimi_webview2_load_html(NimiWebView2 *view, const wchar_t *html,
                             const wchar_t *base_url);
void nimi_webview2_load_url(NimiWebView2 *view, const wchar_t *url);
void nimi_webview2_eval(NimiWebView2 *view, const wchar_t *js);
void nimi_webview2_close(NimiWebView2 *view);

#ifdef __cplusplus
}
#endif

#endif
