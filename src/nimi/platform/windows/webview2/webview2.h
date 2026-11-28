#ifndef NIMI_WEBVIEW2_H
#define NIMI_WEBVIEW2_H
#include <stddef.h>
#include <stdint.h>
#include <wchar.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct NimiWebView2 NimiWebView2;
typedef struct NimiCookie {
    wchar_t *name, *value, *domain, *path;
    int secure, http_only;
} NimiCookie;
typedef void (*NimiCookiesDone)(void *context, uintptr_t request, NimiCookie *cookies,
                                unsigned count, int32_t status);

typedef struct NimiWebResource {
    const char *data;
    size_t length;
    const char *mime;
    int status;
} NimiWebResource;

typedef struct NimiWebView2Callbacks {
    void (*ready)(void *context);
    void (*message)(void *context, char *text);
    void (*error)(void *context, char *text);
    void (*finalized)(void *context);
    int (*serve_resource)(void *context, char *path, NimiWebResource *out_res);
    void (*free_resource)(NimiWebResource *res);
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
int32_t nimi_webview2_read_cookies(NimiWebView2 *view, uintptr_t request, NimiCookiesDone done);
int32_t nimi_webview2_clear_cookies(NimiWebView2 *view);
void nimi_webview2_close(NimiWebView2 *view);

#ifdef __cplusplus
}
#endif

#endif
