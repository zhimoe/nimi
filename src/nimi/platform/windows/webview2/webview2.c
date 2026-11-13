#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <ole2.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include "sdk/WebView2.h"
#include "webview2.h"

typedef enum {
    NIMI_PENDING_HTML,
    NIMI_PENDING_URL,
    NIMI_PENDING_EVAL
} NimiPendingKind;

typedef struct NimiPending {
    NimiPendingKind kind;
    wchar_t *text;
    wchar_t *base;
    struct NimiPending *next;
} NimiPending;

struct NimiWebView2 {
    HWND hwnd;
    HMODULE loader;
    ICoreWebView2Environment *environment;
    ICoreWebView2Controller *controller;
    ICoreWebView2 *webview;
    ICoreWebView2_3 *webview3;
    NimiWebView2Callbacks callbacks;
    wchar_t *scheme;
    wchar_t *file_root;
    wchar_t *bridge;
    NimiPending *pending_head;
    NimiPending *pending_tail;
    EventRegistrationToken message_token;
    int has_message_token;
    int com_initialized;
    float scale;
    int ready;
    int closed;
    int failed;
    LONG refs;
    char error[512];
};

typedef struct NimiEnvHandler {
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler iface;
    LONG ref;
    NimiWebView2 *owner;
} NimiEnvHandler;

typedef struct NimiControllerHandler {
    ICoreWebView2CreateCoreWebView2ControllerCompletedHandler iface;
    LONG ref;
    NimiWebView2 *owner;
} NimiControllerHandler;

typedef struct NimiMessageHandler {
    ICoreWebView2WebMessageReceivedEventHandler iface;
    LONG ref;
    NimiWebView2 *owner;
} NimiMessageHandler;

typedef HRESULT (STDAPICALLTYPE *NimiCreateEnvironment)(
    PCWSTR, PCWSTR, ICoreWebView2EnvironmentOptions *,
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *);
typedef HRESULT (STDAPICALLTYPE *NimiGetVersion)(PCWSTR, LPWSTR *);

static void owner_addref(NimiWebView2 *owner) {
    InterlockedIncrement(&owner->refs);
}

static void owner_release(NimiWebView2 *owner);

static void set_error(char *buffer, int size, const char *message) {
    if (!buffer || size <= 0) return;
    strncpy(buffer, message ? message : "", (size_t)size - 1);
    buffer[size - 1] = 0;
}

static wchar_t *wide_dup(const wchar_t *text) {
    if (!text) return NULL;
    size_t length = wcslen(text) + 1;
    wchar_t *copy = (wchar_t *)malloc(length * sizeof(wchar_t));
    if (copy) memcpy(copy, text, length * sizeof(wchar_t));
    return copy;
}

static char *wide_to_utf8(const wchar_t *text) {
    if (!text) return NULL;
    int length = WideCharToMultiByte(CP_UTF8, 0, text, -1, NULL, 0, NULL, NULL);
    if (length <= 0) return NULL;
    char *utf8 = (char *)calloc((size_t)length, 1);
    if (!utf8) return NULL;
    WideCharToMultiByte(CP_UTF8, 0, text, -1, utf8, length, NULL, NULL);
    return utf8;
}

static void fail(NimiWebView2 *owner, const char *message) {
    if (!owner || owner->failed) return;
    owner->failed = 1;
    set_error(owner->error, (int)sizeof(owner->error), message);
    if (!owner->closed && owner->callbacks.error) {
        owner->callbacks.error(owner->callbacks.context, owner->error);
    }
}

static int pending_add(NimiWebView2 *owner, NimiPendingKind kind,
                       const wchar_t *text, const wchar_t *base) {
    NimiPending *item = (NimiPending *)calloc(1, sizeof(*item));
    if (!item) return 0;
    item->kind = kind;
    item->text = wide_dup(text);
    item->base = base && *base ? wide_dup(base) : NULL;
    if (!item->text) {
        free(item);
        return 0;
    }
    if (owner->pending_tail) owner->pending_tail->next = item;
    else owner->pending_head = item;
    owner->pending_tail = item;
    return 1;
}

static wchar_t *translate_url(NimiWebView2 *owner, const wchar_t *url) {
    if (!owner->scheme || !*owner->scheme || !url) return NULL;
    size_t schemeLength = wcslen(owner->scheme);
    if (wcsncmp(url, owner->scheme, schemeLength) != 0) return NULL;
    if (url[schemeLength] != L':' || url[schemeLength + 1] != L'/' ||
        url[schemeLength + 2] != L'/') {
        return NULL;
    }
    const wchar_t *host = url + schemeLength + 3;
    if (wcsncmp(host, L"app", 3) != 0) return NULL;
    const wchar_t *tail = host + 3;
    if (*tail == L'/') tail++;
    else if (*tail != 0) return NULL;
    static const wchar_t prefix[] = L"https://app.local/";
    size_t prefixLength = sizeof(prefix) / sizeof(prefix[0]) - 1;
    size_t tailLength = wcslen(tail);
    wchar_t *result = (wchar_t *)malloc((prefixLength + tailLength + 1) *
                                        sizeof(wchar_t));
    if (!result) return NULL;
    memcpy(result, prefix, prefixLength * sizeof(wchar_t));
    memcpy(result + prefixLength, tail, (tailLength + 1) * sizeof(wchar_t));
    return result;
}

static wchar_t *html_with_base(const wchar_t *html, const wchar_t *base) {
    if (!html) return NULL;
    if (!base || !*base) return wide_dup(html);
    size_t baseLength = wcslen(base);
    size_t htmlLength = wcslen(html);
    size_t capacity = baseLength * 6 + htmlLength + 64;
    wchar_t *result = (wchar_t *)malloc(capacity * sizeof(wchar_t));
    if (!result) return NULL;
    wchar_t *out = result;
    static const wchar_t prefix[] = L"<base href=\"";
    for (size_t i = 0; i < sizeof(prefix) / sizeof(prefix[0]) - 1; i++) {
        *out++ = prefix[i];
    }
    for (size_t i = 0; i < baseLength; i++) {
        wchar_t ch = base[i];
        if (ch == L'&') { memcpy(out, L"&amp;", 5 * sizeof(wchar_t)); out += 5; }
        else if (ch == L'"') { memcpy(out, L"&quot;", 6 * sizeof(wchar_t)); out += 6; }
        else if (ch == L'<') { memcpy(out, L"&lt;", 4 * sizeof(wchar_t)); out += 4; }
        else if (ch == L'>') { memcpy(out, L"&gt;", 4 * sizeof(wchar_t)); out += 4; }
        else *out++ = ch;
    }
    memcpy(out, L"\">", 2 * sizeof(wchar_t));
    out += 2;
    memcpy(out, html, (htmlLength + 1) * sizeof(wchar_t));
    return result;
}

static void navigate_html(NimiWebView2 *owner, const wchar_t *html,
                          const wchar_t *base) {
    if (!owner->webview || !html) return;
    wchar_t *document = html_with_base(html, base);
    if (!document) {
        fail(owner, "out of memory while building the HTML document");
        return;
    }
    ICoreWebView2_NavigateToString(owner->webview, document);
    free(document);
}

static void navigate_url(NimiWebView2 *owner, const wchar_t *url) {
    if (!owner->webview || !url) return;
    wchar_t *translated = translate_url(owner, url);
    ICoreWebView2_Navigate(owner->webview, translated ? translated : url);
    free(translated);
}

static void eval_js(NimiWebView2 *owner, const wchar_t *js) {
    if (!owner->webview || !js) return;
    ICoreWebView2_ExecuteScript(owner->webview, js, NULL);
}

static void set_scale(NimiWebView2 *owner) {
    if (!owner->controller) return;
    ICoreWebView2Controller3 *controller3 = NULL;
    if (SUCCEEDED(owner->controller->lpVtbl->QueryInterface(
            owner->controller, &IID_ICoreWebView2Controller3,
            (void **)&controller3)) && controller3) {
        ICoreWebView2Controller3_put_RasterizationScale(controller3,
            owner->scale > 0 ? (double)owner->scale : 1.0);
        controller3->lpVtbl->Release(controller3);
    }
}

static void set_bounds(NimiWebView2 *owner) {
    if (!owner->controller || !owner->hwnd) return;
    RECT rect;
    if (!GetClientRect(owner->hwnd, &rect)) return;
    ICoreWebView2Controller_put_Bounds(owner->controller, rect);
}

static void apply_pending(NimiWebView2 *owner) {
    NimiPending *item = owner->pending_head;
    owner->pending_head = NULL;
    owner->pending_tail = NULL;
    while (item) {
        NimiPending *next = item->next;
        switch (item->kind) {
        case NIMI_PENDING_HTML: navigate_html(owner, item->text, item->base); break;
        case NIMI_PENDING_URL: navigate_url(owner, item->text); break;
        case NIMI_PENDING_EVAL: eval_js(owner, item->text); break;
        }
        free(item->text);
        free(item->base);
        free(item);
        item = next;
    }
}

static NimiMessageHandler *message_handler_create(NimiWebView2 *owner);

/* --- controller completed handler -------------------------------------- */

static HRESULT STDMETHODCALLTYPE controller_QueryInterface(
    ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *This,
    REFIID riid, void **object) {
    if (!object) return E_POINTER;
    if (IsEqualIID(riid, &IID_IUnknown) ||
        IsEqualIID(riid,
            &IID_ICoreWebView2CreateCoreWebView2ControllerCompletedHandler)) {
        *object = This;
        This->lpVtbl->AddRef(This);
        return S_OK;
    }
    *object = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE controller_AddRef(
    ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *This) {
    NimiControllerHandler *handler = (NimiControllerHandler *)This;
    return (ULONG)InterlockedIncrement(&handler->ref);
}

static ULONG STDMETHODCALLTYPE controller_Release(
    ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *This) {
    NimiControllerHandler *handler = (NimiControllerHandler *)This;
    ULONG refs = (ULONG)InterlockedDecrement(&handler->ref);
    if (refs == 0) {
        NimiWebView2 *owner = handler->owner;
        handler->owner = NULL;
        free(handler);
        owner_release(owner);
    }
    return refs;
}

static HRESULT STDMETHODCALLTYPE controller_Invoke(
    ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *This,
    HRESULT errorCode, ICoreWebView2Controller *controller) {
    NimiControllerHandler *handler = (NimiControllerHandler *)This;
    NimiWebView2 *owner = handler->owner;
    if (!owner) return S_OK;
    if (owner->closed) {
        if (controller) controller->lpVtbl->Release(controller);
        return S_OK;
    }
    if (FAILED(errorCode) || !controller) {
        fail(owner, "WebView2 controller creation failed");
        return S_OK;
    }
    owner->controller = controller;
    controller->lpVtbl->AddRef(controller);
    if (FAILED(ICoreWebView2Controller_get_CoreWebView2(controller,
                                                         &owner->webview)) ||
        !owner->webview) {
        fail(owner, "cannot access CoreWebView2");
        return S_OK;
    }
    ICoreWebView2Controller_put_IsVisible(controller, TRUE);
    if (owner->scale <= 0) {
        HDC dc = GetDC(owner->hwnd);
        int dpi = dc ? GetDeviceCaps(dc, LOGPIXELSX) : 96;
        if (dc) ReleaseDC(owner->hwnd, dc);
        owner->scale = dpi > 0 ? (float)dpi / 96.0f : 1.0f;
    }
    set_scale(owner);
    set_bounds(owner);

    if (owner->bridge && *owner->bridge) {
        if (FAILED(ICoreWebView2_AddScriptToExecuteOnDocumentCreated(
                owner->webview, owner->bridge, NULL))) {
            fail(owner, "cannot inject the Nimi bridge script");
            return S_OK;
        }
    }

    if (owner->scheme && *owner->scheme && owner->file_root && *owner->file_root) {
        ICoreWebView2_3 *webview3 = NULL;
        if (FAILED(owner->webview->lpVtbl->QueryInterface(owner->webview,
                &IID_ICoreWebView2_3, (void **)&webview3)) || !webview3) {
            fail(owner, "WebView2 runtime does not support virtual host mapping");
            return S_OK;
        }
        if (FAILED(ICoreWebView2_3_SetVirtualHostNameToFolderMapping(webview3,
                L"app.local", owner->file_root,
                COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW))) {
            webview3->lpVtbl->Release(webview3);
            fail(owner, "cannot map the custom scheme folder");
            return S_OK;
        }
        owner->webview3 = webview3;
    }

    NimiMessageHandler *messageHandler = message_handler_create(owner);
    if (!messageHandler) {
        fail(owner, "out of memory");
        return E_OUTOFMEMORY;
    }
    HRESULT hr = ICoreWebView2_add_WebMessageReceived(owner->webview,
        &messageHandler->iface, &owner->message_token);
    messageHandler->iface.lpVtbl->Release(&messageHandler->iface);
    if (FAILED(hr)) {
        fail(owner, "cannot subscribe to WebView2 messages");
        return S_OK;
    }
    owner->has_message_token = 1;
    owner->ready = 1;
    set_bounds(owner);
    apply_pending(owner);
    if (owner->callbacks.ready) {
        owner->callbacks.ready(owner->callbacks.context);
    }
    return S_OK;
}

static const ICoreWebView2CreateCoreWebView2ControllerCompletedHandlerVtbl
    controller_vtbl = {
        controller_QueryInterface,
        controller_AddRef,
        controller_Release,
        controller_Invoke
    };

static NimiControllerHandler *controller_handler_create(NimiWebView2 *owner) {
    NimiControllerHandler *handler =
        (NimiControllerHandler *)calloc(1, sizeof(*handler));
    if (!handler) return NULL;
    handler->iface.lpVtbl =
        (ICoreWebView2CreateCoreWebView2ControllerCompletedHandlerVtbl *)
        &controller_vtbl;
    handler->ref = 1;
    handler->owner = owner;
    owner_addref(owner);
    return handler;
}

/* --- environment completed handler ------------------------------------- */

static HRESULT STDMETHODCALLTYPE env_QueryInterface(
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *This,
    REFIID riid, void **object) {
    if (!object) return E_POINTER;
    if (IsEqualIID(riid, &IID_IUnknown) ||
        IsEqualIID(riid,
            &IID_ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler)) {
        *object = This;
        This->lpVtbl->AddRef(This);
        return S_OK;
    }
    *object = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE env_AddRef(
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *This) {
    NimiEnvHandler *handler = (NimiEnvHandler *)This;
    return (ULONG)InterlockedIncrement(&handler->ref);
}

static ULONG STDMETHODCALLTYPE env_Release(
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *This) {
    NimiEnvHandler *handler = (NimiEnvHandler *)This;
    ULONG refs = (ULONG)InterlockedDecrement(&handler->ref);
    if (refs == 0) {
        NimiWebView2 *owner = handler->owner;
        handler->owner = NULL;
        free(handler);
        owner_release(owner);
    }
    return refs;
}

static HRESULT STDMETHODCALLTYPE env_Invoke(
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *This,
    HRESULT errorCode, ICoreWebView2Environment *environment) {
    NimiEnvHandler *handler = (NimiEnvHandler *)This;
    NimiWebView2 *owner = handler->owner;
    if (!owner) return S_OK;
    if (owner->closed) {
        if (environment) environment->lpVtbl->Release(environment);
        return S_OK;
    }
    if (FAILED(errorCode) || !environment) {
        fail(owner, "WebView2 environment creation failed");
        return S_OK;
    }
    owner->environment = environment;
    environment->lpVtbl->AddRef(environment);
    NimiControllerHandler *controllerHandler = controller_handler_create(owner);
    if (!controllerHandler) {
        fail(owner, "out of memory");
        return E_OUTOFMEMORY;
    }
    HRESULT hr = ICoreWebView2Environment_CreateCoreWebView2Controller(
        environment, owner->hwnd, &controllerHandler->iface);
    controllerHandler->iface.lpVtbl->Release(&controllerHandler->iface);
    if (FAILED(hr)) {
        fail(owner, "CreateCoreWebView2Controller failed");
    }
    return S_OK;
}

static const ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandlerVtbl
    env_vtbl = {
        env_QueryInterface,
        env_AddRef,
        env_Release,
        env_Invoke
    };

/* --- web message handler ----------------------------------------------- */

static HRESULT STDMETHODCALLTYPE message_QueryInterface(
    ICoreWebView2WebMessageReceivedEventHandler *This,
    REFIID riid, void **object) {
    if (!object) return E_POINTER;
    if (IsEqualIID(riid, &IID_IUnknown) ||
        IsEqualIID(riid, &IID_ICoreWebView2WebMessageReceivedEventHandler)) {
        *object = This;
        This->lpVtbl->AddRef(This);
        return S_OK;
    }
    *object = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE message_AddRef(
    ICoreWebView2WebMessageReceivedEventHandler *This) {
    NimiMessageHandler *handler = (NimiMessageHandler *)This;
    return (ULONG)InterlockedIncrement(&handler->ref);
}

static ULONG STDMETHODCALLTYPE message_Release(
    ICoreWebView2WebMessageReceivedEventHandler *This) {
    NimiMessageHandler *handler = (NimiMessageHandler *)This;
    ULONG refs = (ULONG)InterlockedDecrement(&handler->ref);
    if (refs == 0) {
        NimiWebView2 *owner = handler->owner;
        handler->owner = NULL;
        free(handler);
        owner_release(owner);
    }
    return refs;
}

static HRESULT STDMETHODCALLTYPE message_Invoke(
    ICoreWebView2WebMessageReceivedEventHandler *This,
    ICoreWebView2 *sender, ICoreWebView2WebMessageReceivedEventArgs *args) {
    NimiMessageHandler *handler = (NimiMessageHandler *)This;
    NimiWebView2 *owner = handler->owner;
    (void)sender;
    if (!owner || owner->closed || !args) return S_OK;
    LPWSTR text = NULL;
    HRESULT hr = ICoreWebView2WebMessageReceivedEventArgs_TryGetWebMessageAsString(
        args, &text);
    if (FAILED(hr)) {
        hr = ICoreWebView2WebMessageReceivedEventArgs_get_WebMessageAsJson(
            args, &text);
    }
    if (SUCCEEDED(hr) && text) {
        char *utf8 = wide_to_utf8(text);
        CoTaskMemFree(text);
        if (utf8) {
            if (owner->callbacks.message) {
                owner->callbacks.message(owner->callbacks.context, utf8);
            }
            free(utf8);
        }
    }
    return S_OK;
}

static const ICoreWebView2WebMessageReceivedEventHandlerVtbl message_vtbl = {
    message_QueryInterface,
    message_AddRef,
    message_Release,
    message_Invoke
};

static NimiMessageHandler *message_handler_create(NimiWebView2 *owner) {
    NimiMessageHandler *handler =
        (NimiMessageHandler *)calloc(1, sizeof(*handler));
    if (!handler) return NULL;
    handler->iface.lpVtbl =
        (ICoreWebView2WebMessageReceivedEventHandlerVtbl *)&message_vtbl;
    handler->ref = 1;
    handler->owner = owner;
    owner_addref(owner);
    return handler;
}

/* --- owner lifetime ----------------------------------------------------- */

static void free_pending(NimiWebView2 *owner) {
    NimiPending *item = owner->pending_head;
    while (item) {
        NimiPending *next = item->next;
        free(item->text);
        free(item->base);
        free(item);
        item = next;
    }
    owner->pending_head = NULL;
    owner->pending_tail = NULL;
}

static void owner_release(NimiWebView2 *owner) {
    if (!owner) return;
    if (InterlockedDecrement(&owner->refs) != 0) return;
    if (owner->webview3) {
        owner->webview3->lpVtbl->Release(owner->webview3);
        owner->webview3 = NULL;
    }
    if (owner->webview) {
        owner->webview->lpVtbl->Release(owner->webview);
        owner->webview = NULL;
    }
    if (owner->controller) {
        owner->controller->lpVtbl->Release(owner->controller);
        owner->controller = NULL;
    }
    if (owner->environment) {
        owner->environment->lpVtbl->Release(owner->environment);
        owner->environment = NULL;
    }
    if (owner->com_initialized) {
        CoUninitialize();
        owner->com_initialized = 0;
    }
    if (owner->loader) {
        FreeLibrary(owner->loader);
        owner->loader = NULL;
    }
    free_pending(owner);
    free(owner->scheme);
    free(owner->file_root);
    free(owner->bridge);
    if (owner->callbacks.finalized) {
        owner->callbacks.finalized(owner->callbacks.context);
    }
    free(owner);
}

/* --- public API --------------------------------------------------------- */

NimiWebView2 *nimi_webview2_create(void *parent, const wchar_t *user_data_folder,
    const wchar_t *loader_hint, const wchar_t *scheme, const wchar_t *file_root,
    const wchar_t *bridge_script, NimiWebView2Callbacks callbacks,
    char *error, int error_size) {
    if (error && error_size > 0) error[0] = 0;
    NimiWebView2 *owner = (NimiWebView2 *)calloc(1, sizeof(*owner));
    if (!owner) {
        set_error(error, error_size, "out of memory");
        return NULL;
    }
    owner->refs = 1;
    owner->hwnd = (HWND)parent;
    owner->callbacks = callbacks;
    owner->scale = 1.0f;
    owner->scheme = wide_dup(scheme);
    owner->file_root = wide_dup(file_root);
    owner->bridge = wide_dup(bridge_script);

    HRESULT hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED |
                                      COINIT_DISABLE_OLE1DDE);
    if (FAILED(hr)) {
        set_error(error, error_size,
                  "WebView2 requires a single-threaded COM apartment");
        owner_release(owner);
        return NULL;
    }
    if (SUCCEEDED(hr)) owner->com_initialized = 1;

    HMODULE loader = LoadLibraryW(L"WebView2Loader.dll");
    if (!loader && loader_hint && *loader_hint) {
        loader = LoadLibraryW(loader_hint);
    }
    if (!loader) {
        set_error(error, error_size,
                  "WebView2Loader.dll was not found next to the application");
        owner_release(owner);
        return NULL;
    }
    owner->loader = loader;

    NimiGetVersion getVersion = (NimiGetVersion)GetProcAddress(loader,
        "GetAvailableCoreWebView2BrowserVersionString");
    if (getVersion) {
        LPWSTR version = NULL;
        HRESULT versionResult = getVersion(NULL, &version);
        if (FAILED(versionResult) || !version) {
            set_error(error, error_size,
                      "the WebView2 Runtime is not installed");
            owner_release(owner);
            return NULL;
        }
        CoTaskMemFree(version);
    }

    NimiCreateEnvironment createEnvironment = (NimiCreateEnvironment)
        GetProcAddress(loader, "CreateCoreWebView2EnvironmentWithOptions");
    if (!createEnvironment) {
        set_error(error, error_size,
                  "WebView2Loader.dll does not export the environment factory");
        owner_release(owner);
        return NULL;
    }

    NimiEnvHandler *handler = (NimiEnvHandler *)calloc(1, sizeof(*handler));
    if (!handler) {
        set_error(error, error_size, "out of memory");
        owner_release(owner);
        return NULL;
    }
    handler->iface.lpVtbl =
        (ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandlerVtbl *)
        &env_vtbl;
    handler->ref = 1;
    handler->owner = owner;
    owner_addref(owner);
    hr = createEnvironment(NULL, user_data_folder, NULL, &handler->iface);
    handler->iface.lpVtbl->Release(&handler->iface);
    if (FAILED(hr)) {
        set_error(error, error_size,
                  "CreateCoreWebView2EnvironmentWithOptions failed");
        owner_release(owner);
        return NULL;
    }
    return owner;
}

int nimi_webview2_ready(NimiWebView2 *view) {
    return view && view->ready && !view->closed && !view->failed;
}

void nimi_webview2_resize(NimiWebView2 *view, int width, int height,
                          float scale) {
    if (!view || view->closed) return;
    view->scale = scale > 0 ? scale : 1.0f;
    if (!view->ready || !view->controller) return;
    RECT rect = {0, 0, width > 0 ? width : 1, height > 0 ? height : 1};
    ICoreWebView2Controller_put_Bounds(view->controller, rect);
    set_scale(view);
}

void nimi_webview2_show(NimiWebView2 *view, int visible) {
    if (!view || view->closed || !view->controller) return;
    ICoreWebView2Controller_put_IsVisible(view->controller, visible ? TRUE : FALSE);
}

void nimi_webview2_focus(NimiWebView2 *view) {
    if (!view || view->closed || !view->controller) return;
    ICoreWebView2Controller_MoveFocus(view->controller,
        COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
}

void nimi_webview2_load_html(NimiWebView2 *view, const wchar_t *html,
                             const wchar_t *base_url) {
    if (!view || view->closed || view->failed || !html) return;
    if (view->ready && view->webview) {
        navigate_html(view, html, base_url);
        return;
    }
    if (!pending_add(view, NIMI_PENDING_HTML, html, base_url)) {
        fail(view, "out of memory");
    }
}

void nimi_webview2_load_url(NimiWebView2 *view, const wchar_t *url) {
    if (!view || view->closed || view->failed || !url) return;
    if (view->ready && view->webview) {
        navigate_url(view, url);
        return;
    }
    if (!pending_add(view, NIMI_PENDING_URL, url, NULL)) {
        fail(view, "out of memory");
    }
}

void nimi_webview2_eval(NimiWebView2 *view, const wchar_t *js) {
    if (!view || view->closed || view->failed || !js) return;
    if (view->ready && view->webview) {
        eval_js(view, js);
        return;
    }
    if (!pending_add(view, NIMI_PENDING_EVAL, js, NULL)) {
        fail(view, "out of memory");
    }
}

void nimi_webview2_close(NimiWebView2 *view) {
    if (!view || view->closed) return;
    view->closed = 1;
    if (view->webview && view->has_message_token) {
        ICoreWebView2_remove_WebMessageReceived(view->webview,
                                                view->message_token);
        view->has_message_token = 0;
    }
    if (view->controller) {
        ICoreWebView2Controller_Close(view->controller);
    }
    owner_release(view);
}
