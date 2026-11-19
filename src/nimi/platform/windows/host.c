#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windowsx.h>
#include <imm.h>
#include <shellapi.h>
#include <stdlib.h>
#include <string.h>
#include "host.h"
#include "menu.h"

static NimiEvent nimi_event;
static HWND dispatch_window;
static DWORD main_thread;
typedef struct {
    WINDOWPLACEMENT placement;
    LONG_PTR style;
    int client_width, client_height;
} NimiFullscreen;
static const wchar_t fullscreen_key[] = L"NimiFullscreen";
static UINT window_dpi(HWND w) {
    typedef UINT (WINAPI *GetDpi)(HWND);
    GetDpi fn=(GetDpi)GetProcAddress(GetModuleHandleW(L"user32.dll"),"GetDpiForWindow");
    UINT dpi=fn?fn(w):0;
    if (!dpi) {
        HDC dc=GetDC(w); dpi=dc?(UINT)GetDeviceCaps(dc,LOGPIXELSX):96;
        if(dc) ReleaseDC(w,dc);
    }
    return dpi?dpi:96;
}
static void client_to_outer(HWND w, RECT *rect) {
    typedef BOOL (WINAPI *AdjustDpi)(LPRECT,DWORD,BOOL,DWORD,UINT);
    AdjustDpi fn=(AdjustDpi)GetProcAddress(GetModuleHandleW(L"user32.dll"),"AdjustWindowRectExForDpi");
    DWORD style=(DWORD)GetWindowLongPtrW(w,GWL_STYLE);
    DWORD ex=(DWORD)GetWindowLongPtrW(w,GWL_EXSTYLE);
    if(fn) fn(rect,style,GetMenu(w)!=NULL,ex,window_dpi(w));
    else AdjustWindowRectEx(rect,style,GetMenu(w)!=NULL,ex);
}
static const wchar_t class_name[] = L"NimiWindow";
#define NIMI_DISPATCH (WM_APP + 1)
#define NIMI_FRAME (WM_APP + 3)
#define NIMI_HOTKEY (WM_APP + 4)
#define NIMI_TIMER_ID 1

typedef struct { HMONITOR monitor; MONITORINFOEXW info; } NimiMonitor;
typedef struct { NimiMonitor items[16]; int count; } NimiMonitorList;

typedef HRESULT (WINAPI *NimiGetDpiForMonitor)(HMONITOR, int, UINT *, UINT *);

static UINT monitor_dpi(HMONITOR monitor) {
    static NimiGetDpiForMonitor get_dpi;
    static int loaded;
    if (!loaded) {
        HMODULE shcore = LoadLibraryW(L"shcore.dll");
        if (shcore) get_dpi = (NimiGetDpiForMonitor)GetProcAddress(shcore, "GetDpiForMonitor");
        loaded = 1;
    }
    if (get_dpi) {
        UINT x = 96, y = 96;
        if (SUCCEEDED(get_dpi(monitor, 0, &x, &y))) return x;
    }
    return 96;
}

static BOOL CALLBACK nimi_enum_monitor(HMONITOR monitor, HDC dc, LPRECT rect, LPARAM data) {
    NimiMonitorList *list = (NimiMonitorList *)data;
    if (list->count >= (int)(sizeof(list->items) / sizeof(list->items[0]))) return FALSE;
    NimiMonitor *item = &list->items[list->count];
    item->monitor = monitor;
    item->info.cbSize = sizeof(item->info);
    if (!GetMonitorInfoW(monitor, (MONITORINFO *)&item->info)) return TRUE;
    list->count++;
    return TRUE;
}

static int enumerate_monitors(NimiMonitorList *list) {
    list->count = 0;
    EnumDisplayMonitors(NULL, NULL, nimi_enum_monitor, (LPARAM)list);
    return list->count;
}

static int primary_monitor(RECT *rect, UINT *dpi) {
    NimiMonitorList list;
    if (enumerate_monitors(&list) == 0) return 0;
    int primary = 0;
    for (int i = 0; i < list.count; i++) {
        if (list.items[i].info.dwFlags & MONITORINFOF_PRIMARY) { primary = i; break; }
    }
    *rect = list.items[primary].info.rcMonitor;
    *dpi = monitor_dpi(list.items[primary].monitor);
    if (!*dpi) *dpi = 96;
    return 1;
}

static LRESULT CALLBACK nimi_proc(HWND window, UINT message, WPARAM wp, LPARAM lp) {
    if (window == dispatch_window) {
        if (message == NIMI_DISPATCH) { nimi_event(NULL, NIMI_DISPATCH, 0, 0); return 0; }
        if (message == WM_HOTKEY) { nimi_event(NULL, NIMI_HOTKEY, wp, lp); return 0; }
        if (message == NIMI_WATCH_READY) { nimi_event(NULL, message, wp, 0); return 0; }
    } else if (nimi_event) {
        switch (message) {
        case WM_NCDESTROY: {
            NimiFullscreen *saved=(NimiFullscreen *)RemovePropW(window,fullscreen_key);
            free(saved); KillTimer(window,NIMI_TIMER_ID); break;
        }
        case WM_ERASEBKGND: return 1;
        case WM_SIZE:
            InvalidateRect(window,NULL,FALSE);
            nimi_event(window,message,wp,lp);
            break;
        case WM_TIMER:
            if (wp == NIMI_TIMER_ID) {
                InvalidateRect(window,NULL,FALSE);
                if (nimi_event) nimi_event(window,NIMI_FRAME,0,0);
                return 0;
            }
            break;
        case WM_PAINT: {
            PAINTSTRUCT ps; HDC screen=BeginPaint(window,&ps); RECT r; GetClientRect(window,&r);
            if (r.right>0 && r.bottom>0) {
                HDC dc=CreateCompatibleDC(screen); HBITMAP bitmap=CreateCompatibleBitmap(screen,r.right,r.bottom);
                HGDIOBJ old=SelectObject(dc,bitmap);
                FillRect(dc,&r,(HBRUSH)(COLOR_WINDOW+1));
                float scale=nimi_host_scale(window);
                SetGraphicsMode(dc,GM_ADVANCED);
                XFORM transform={scale,0,0,scale,0,0}; SetWorldTransform(dc,&transform);
                NimiPaint paint={dc,r.right/scale,r.bottom/scale};
                nimi_event(window,WM_APP+2,0,(intptr_t)&paint);
                ModifyWorldTransform(dc,NULL,MWT_IDENTITY);
                BitBlt(screen,0,0,r.right,r.bottom,dc,0,0,SRCCOPY);
                SelectObject(dc,old); DeleteObject(bitmap); DeleteDC(dc);
            }
            EndPaint(window,&ps); return 0;
        }
        case WM_LBUTTONDOWN: case WM_LBUTTONDBLCLK:
            SetFocus(window); SetCapture(window);
            nimi_event(window,message,wp,lp); return 0;
        case WM_LBUTTONUP:
            nimi_event(window,message,wp,lp);
            if(GetCapture()==window) ReleaseCapture(); return 0;
        case WM_MOUSEWHEEL: case WM_MOUSEHWHEEL: {
            POINT p={GET_X_LPARAM(lp),GET_Y_LPARAM(lp)}; ScreenToClient(window,&p);
            nimi_event(window,message,wp,MAKELPARAM(p.x,p.y)); return 0;
        }
        case WM_MOUSEMOVE: case WM_KEYDOWN: case WM_CHAR:
            nimi_event(window,message,wp,lp); return 0;
        case WM_UNICHAR:
            if(wp == UNICODE_NOCHAR) return TRUE;
            nimi_event(window,message,wp,lp); return 0;
        case WM_IME_SETCONTEXT:
            if(nimi_event(window,message,wp,lp)) lp &= ~ISC_SHOWUICOMPOSITIONWINDOW;
            break;
        case WM_IME_STARTCOMPOSITION: case WM_IME_COMPOSITION:
        case WM_IME_ENDCOMPOSITION: case WM_IME_CHAR:
            if(nimi_event(window,message,wp,lp)) return 0;
            break;
        case WM_IME_NOTIFY: case WM_INPUTLANGCHANGE:
            nimi_event(window,message,wp,lp); break;
        case WM_CLOSE:
            if (nimi_event(window, message, wp, lp)) DestroyWindow(window);
            return 0;
        case WM_CAPTURECHANGED: case WM_CANCELMODE:
            nimi_event(window,message,wp,lp); break;
        case WM_COMMAND:
            if(!lp) { nimi_event(window,message,wp,lp); return 0; }
            break;
        case WM_DESTROY:
            nimi_menu_detach(window);
            nimi_event(window,message,wp,lp); break;
        case WM_SETFOCUS: case WM_KILLFOCUS:
            nimi_event(window, message, wp, lp); break;
        case WM_SHOWWINDOW:
            nimi_event(window, message, wp, lp); break;
        case WM_SETTINGCHANGE: case WM_DISPLAYCHANGE: case WM_THEMECHANGED:
            nimi_event(window, message, wp, lp); break;
        case WM_DPICHANGED: {
            RECT *r = (RECT *)lp;
            SetWindowPos(window, NULL, r->left, r->top, r->right-r->left,
                         r->bottom-r->top, SWP_NOZORDER | SWP_NOACTIVATE);
            nimi_event(window, message, wp, lp);
            return 0;
        }
        }
    }
    return DefWindowProcW(window, message, wp, lp);
}
int nimi_host_init(NimiEvent callback) {
    if (dispatch_window) return 0;
    nimi_event = callback;
    main_thread = GetCurrentThreadId();
    /* Optional API keeps the host usable on older Windows versions. */
    HMODULE user = GetModuleHandleW(L"user32.dll");
    typedef BOOL (WINAPI *SetDpi)(HANDLE);
    SetDpi set_dpi = (SetDpi)GetProcAddress(user, "SetProcessDpiAwarenessContext");
    if (set_dpi) set_dpi((HANDLE)(intptr_t)-4);
    WNDCLASSW wc = {0};
    wc.style = CS_DBLCLKS;
    wc.lpfnWndProc = nimi_proc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.hCursor = LoadCursorW(NULL, MAKEINTRESOURCEW(32512));
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = class_name;
    if (!RegisterClassW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return 0;
    dispatch_window = CreateWindowExW(0, class_name, L"", 0, 0, 0, 0, 0,
                                     HWND_MESSAGE, NULL, wc.hInstance, NULL);
    return dispatch_window != NULL;
}
int nimi_host_run(void) {
    MSG msg;
    int status;
    while ((status = GetMessageW(&msg, NULL, 0, 0)) > 0) {
        if(!nimi_menu_translate(&msg)) { TranslateMessage(&msg); DispatchMessageW(&msg); }
    }
    return status;
}
void nimi_host_step(void) {
    MSG msg;
    while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
        if (msg.message == WM_QUIT) { PostQuitMessage((int)msg.wParam); break; }
        if(!nimi_menu_translate(&msg)) { TranslateMessage(&msg); DispatchMessageW(&msg); }
    }
}
void nimi_host_quit(void) { PostQuitMessage(0); }
void nimi_host_signal(void) { PostMessageW(dispatch_window, NIMI_DISPATCH, 0, 0); }
int nimi_host_main_thread(void) { return GetCurrentThreadId() == main_thread; }
void *nimi_host_dispatch_window(void) { return dispatch_window; }
void *nimi_host_window(const wchar_t *title, int width, int height, int resizable) {
    DWORD style = WS_OVERLAPPEDWINDOW;
    if (!resizable) style &= ~(WS_THICKFRAME | WS_MAXIMIZEBOX);
    RECT r = {0, 0, width, height}; AdjustWindowRectEx(&r, style, FALSE, 0);
    HWND w=CreateWindowExW(0, class_name, title, style, CW_USEDEFAULT, CW_USEDEFAULT,
        r.right-r.left, r.bottom-r.top, NULL, NULL, GetModuleHandleW(NULL), NULL);
    if(w) nimi_host_size(w,width,height);
    return w;
}
void nimi_host_close(void *w) { SendMessageW(w, WM_CLOSE, 0, 0); }
void nimi_host_destroy(void *w) { DestroyWindow(w); }
void nimi_host_title(void *w, const wchar_t *title) { SetWindowTextW(w, title); }
void nimi_host_show(void *w, int mode) { ShowWindow(w, mode); }
void nimi_host_size(void *w, int width, int height) {
    UINT dpi=window_dpi(w);
    RECT r = {0,0,MulDiv(width,dpi,96),MulDiv(height,dpi,96)};
    client_to_outer(w,&r);
    SetWindowPos(w, NULL, 0,0,r.right-r.left,r.bottom-r.top,SWP_NOMOVE|SWP_NOZORDER);
}
void nimi_host_position(void *w, int x, int y) { SetWindowPos(w,NULL,x,y,0,0,SWP_NOSIZE|SWP_NOZORDER); }
int nimi_host_fit_work_area(void *window) {
    RECT rect;
    MONITORINFO monitor = {sizeof(monitor)};
    if (!GetWindowRect(window, &rect) ||
        !GetMonitorInfoW(MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST), &monitor)) return 0;
    RECT work = monitor.rcWork;
    int width = min(rect.right - rect.left, work.right - work.left);
    int height = min(rect.bottom - rect.top, work.bottom - work.top);
    int x = max(work.left, min(rect.left, work.right - width));
    int y = max(work.top, min(rect.top, work.bottom - height));
    if (x == rect.left && y == rect.top &&
        width == rect.right - rect.left && height == rect.bottom - rect.top) return 1;
    return SetWindowPos(window, NULL, x, y, width, height, SWP_NOZORDER | SWP_NOACTIVATE);
}
void nimi_host_center(void *w) {
    MONITORINFO m = {sizeof(m)}; RECT r;
    GetMonitorInfoW(MonitorFromWindow(w, MONITOR_DEFAULTTONEAREST), &m);
    GetWindowRect(w, &r);
    nimi_host_position(w, m.rcWork.left+(m.rcWork.right-m.rcWork.left-(r.right-r.left))/2,
                         m.rcWork.top+(m.rcWork.bottom-m.rcWork.top-(r.bottom-r.top))/2);
}
void nimi_host_topmost(void *w, int on) { SetWindowPos(w,on?HWND_TOPMOST:HWND_NOTOPMOST,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE); }
int nimi_host_focused(void *w) { return GetForegroundWindow() == w; }
int nimi_host_visible(void *w) { return IsWindowVisible(w) && !IsIconic(w); }
int nimi_host_minimized(void *w) { return IsIconic(w); }
int nimi_host_maximized(void *w) { return IsZoomed(w) && !nimi_host_fullscreen(w,0); }
void nimi_host_focus(void *w) { ShowWindow(w, SW_SHOW); SetForegroundWindow(w); SetFocus(w); }

float nimi_host_scale(void *w) { return (float)window_dpi(w)/96.0f; }

unsigned nimi_host_modifiers(void) {
    return ((GetKeyState(VK_SHIFT)&0x8000)?1:0) |
           ((GetKeyState(VK_CONTROL)&0x8000)?2:0) |
           ((GetKeyState(VK_MENU)&0x8000)?4:0);
}
void nimi_host_invalidate(void *w) { InvalidateRect(w,NULL,FALSE); }

int nimi_host_start_animation(void *w,int fps) {
    if(!w || fps<=0) return 0;
    UINT interval=(UINT)(1000.0/(double)fps+0.5);
    if(interval<1) interval=1;
    return SetTimer((HWND)w,NIMI_TIMER_ID,interval,NULL)!=0;
}
void nimi_host_stop_animation(void *w) {
    if(w) KillTimer((HWND)w,NIMI_TIMER_ID);
}

int nimi_host_clipboard_read(wchar_t **copy) {
    *copy=NULL;
    if (!dispatch_window || !nimi_host_main_thread() || !OpenClipboard(dispatch_window)) return -1;
    if (!IsClipboardFormatAvailable(CF_UNICODETEXT)) { CloseClipboard(); return 0; }
    int status=-1;
    HANDLE memory=GetClipboardData(CF_UNICODETEXT);
    if (memory) {
        const wchar_t *text=GlobalLock(memory);
        if (text) {
            SIZE_T bytes=GlobalSize(memory), count=bytes/sizeof(wchar_t), n=0;
            while(n<count && text[n]) ++n;
            if(n<count) {
                *copy=malloc((n+1)*sizeof(wchar_t));
                if(*copy) { memcpy(*copy,text,(n+1)*sizeof(wchar_t)); status=1; }
            }
            GlobalUnlock(memory);
        }
    }
    CloseClipboard(); return status;
}
void nimi_host_free(void *memory) { free(memory); }
static int clipboard_write(UINT format, const void *text, SIZE_T bytes) {
    if (!format || !dispatch_window || !nimi_host_main_thread()) return 0;
    HGLOBAL memory=GlobalAlloc(GMEM_MOVEABLE,bytes);
    if(!memory) return 0;
    void *data=GlobalLock(memory);
    if(!data) { GlobalFree(memory); return 0; }
    memcpy(data,text,bytes); GlobalUnlock(memory);
    if(!OpenClipboard(dispatch_window)) { GlobalFree(memory); return 0; }
    int success=EmptyClipboard() && SetClipboardData(format,memory)!=NULL;
    CloseClipboard();
    if(!success) GlobalFree(memory);
    return success;
}
int nimi_host_clipboard_write(const wchar_t *text) {
    return clipboard_write(CF_UNICODETEXT, text, (wcslen(text)+1)*sizeof(wchar_t));
}
int nimi_host_clipboard_read_html(char **copy, size_t *length) {
    *copy = NULL;
    *length = 0;
    UINT format = RegisterClipboardFormatW(L"HTML Format");
    if (!format || !dispatch_window || !nimi_host_main_thread() ||
        !OpenClipboard(dispatch_window)) return -1;
    int status = 0;
    if (IsClipboardFormatAvailable(format)) {
        status = -1;
        HANDLE memory = GetClipboardData(format);
        if (memory) {
            const char *data = GlobalLock(memory);
            if (data) {
                SIZE_T size = GlobalSize(memory);
                if (size && size <= PTRDIFF_MAX) {
                    const char *end = memchr(data, 0, size);
                    *length = end ? (size_t)(end - data) : size;
                    if (*length && (*copy = malloc(*length))) {
                        memcpy(*copy, data, *length);
                        status = 1;
                    }
                }
                GlobalUnlock(memory);
            }
        }
    }
    CloseClipboard();
    return status;
}
int nimi_host_clipboard_write_html(const char *text, size_t length) {
    return clipboard_write(RegisterClipboardFormatW(L"HTML Format"), text, length + 1);
}
int nimi_host_clipboard_clear(void) {
    if (!dispatch_window || !nimi_host_main_thread() || !OpenClipboard(dispatch_window)) return 0;
    int success=EmptyClipboard();
    CloseClipboard(); return success;
}
void nimi_host_input_error(void) { MessageBeep(MB_ICONWARNING); }
int nimi_host_message(const wchar_t *title,const wchar_t *text,int confirm) {
    return MessageBoxW(GetActiveWindow(),text,title,confirm?(MB_OKCANCEL|MB_ICONQUESTION):MB_OK);
}

void nimi_host_shutdown(void) {
    if (dispatch_window) { DestroyWindow(dispatch_window); dispatch_window=NULL; }
    /* Window destruction can enqueue quit; do not poison a subsequent run. */
    MSG msg;
    while (PeekMessageW(&msg,NULL,WM_QUIT,WM_QUIT,PM_REMOVE)) {}
    nimi_event=NULL;
    main_thread=0;
}

void nimi_host_client_size(void *w,float *width,float *height) {
    RECT r; GetClientRect(w,&r); float scale=nimi_host_scale(w);
    *width=(r.right-r.left)/scale; *height=(r.bottom-r.top)/scale;
}
void nimi_host_resizable(void *w,int enabled) {
    NimiFullscreen *saved=(NimiFullscreen *)GetPropW(w,fullscreen_key);
    LONG_PTR style=saved?saved->style:GetWindowLongPtrW(w,GWL_STYLE);
    if(enabled) style|=WS_THICKFRAME|WS_MAXIMIZEBOX;
    else style&=~(WS_THICKFRAME|WS_MAXIMIZEBOX);
    if(saved) { saved->style=style; return; }
    float width,height; nimi_host_client_size(w,&width,&height);
    SetWindowLongPtrW(w,GWL_STYLE,style);
    SetWindowPos(w,NULL,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOZORDER|SWP_FRAMECHANGED);
    if(!IsZoomed(w) && !IsIconic(w)) nimi_host_size(w,(int)(width+0.5f),(int)(height+0.5f));
}
int nimi_host_fullscreen(void *w,int toggle) {
    NimiFullscreen *saved=(NimiFullscreen *)GetPropW(w,fullscreen_key);
    if(!toggle) return saved!=NULL;
    if(saved) {
        int width=saved->client_width, height=saved->client_height;
        RemovePropW(w,fullscreen_key);
        SetWindowLongPtrW(w,GWL_STYLE,saved->style);
        SetWindowPlacement(w,&saved->placement);
        SetWindowPos(w,NULL,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOZORDER|SWP_FRAMECHANGED);
        if(width>0 && height>0) nimi_host_size(w,width,height);
        free(saved); return 0;
    }
    saved=calloc(1,sizeof(*saved));
    if(!saved) return -1;
    saved->placement.length=sizeof(saved->placement);
    if(!GetWindowPlacement(w,&saved->placement)) {free(saved); return -1;}
    saved->style=GetWindowLongPtrW(w,GWL_STYLE);
    {
        RECT client; GetClientRect(w,&client);
        float scale=nimi_host_scale(w);
        if(scale<=0) scale=1.0f;
        saved->client_width=(int)((client.right-client.left)/scale+0.5f);
        saved->client_height=(int)((client.bottom-client.top)/scale+0.5f);
    }
    MONITORINFO m={sizeof(m)};
    if(!GetMonitorInfoW(MonitorFromWindow(w,MONITOR_DEFAULTTONEAREST),&m) ||
       !SetPropW(w,fullscreen_key,saved)) {free(saved); return -1;}
    ShowWindow(w,SW_RESTORE);
    SetWindowLongPtrW(w,GWL_STYLE,saved->style & ~WS_OVERLAPPEDWINDOW);
    SetWindowPos(w,NULL,m.rcMonitor.left,m.rcMonitor.top,
        m.rcMonitor.right-m.rcMonitor.left,m.rcMonitor.bottom-m.rcMonitor.top,
        SWP_NOZORDER|SWP_FRAMECHANGED);
    return 1;
}
void nimi_host_zoom(void *w) { ShowWindow(w,IsZoomed(w)?SW_RESTORE:SW_MAXIMIZE); }

int nimi_host_displays(NimiDisplay *items,int capacity) {
    if(!items || capacity<=0) return 0;
    NimiMonitorList list;
    int count=enumerate_monitors(&list);
    if(!count) return 0;
    int primary=0;
    for(int i=0;i<count;i++) {
        if(list.items[i].info.dwFlags & MONITORINFOF_PRIMARY) { primary=i; break; }
    }
    RECT base=list.items[primary].info.rcMonitor;
    UINT baseDpi=monitor_dpi(list.items[primary].monitor);
    if(!baseDpi) baseDpi=96;
    int n=count<capacity?count:capacity;
    for(int i=0;i<n;i++) {
        MONITORINFOEXW *info=&list.items[i].info;
        UINT dpi=monitor_dpi(list.items[i].monitor);
        if(!dpi) dpi=96;
        NimiDisplay *d=&items[i];
        memset(d,0,sizeof(*d));
        d->x=MulDiv(info->rcMonitor.left-base.left,96,(int)baseDpi);
        d->y=MulDiv(info->rcMonitor.top-base.top,96,(int)baseDpi);
        d->width=MulDiv(info->rcMonitor.right-info->rcMonitor.left,96,(int)dpi);
        d->height=MulDiv(info->rcMonitor.bottom-info->rcMonitor.top,96,(int)dpi);
        d->workX=MulDiv(info->rcWork.left-base.left,96,(int)baseDpi);
        d->workY=MulDiv(info->rcWork.top-base.top,96,(int)baseDpi);
        d->workWidth=MulDiv(info->rcWork.right-info->rcWork.left,96,(int)dpi);
        d->workHeight=MulDiv(info->rcWork.bottom-info->rcWork.top,96,(int)dpi);
        d->dpi=(int)dpi;
        d->primary=(i==primary)?1:0;
        WideCharToMultiByte(CP_UTF8,0,info->szDevice,-1,d->id,sizeof(d->id),NULL,NULL);
        const wchar_t *name=info->szDevice;
        if(wcsncmp(name,L"\\\\.\\",4)==0) name+=4;
        WideCharToMultiByte(CP_UTF8,0,name,-1,d->name,sizeof(d->name),NULL,NULL);
    }
    return n;
}

int nimi_host_cursor(float *x,float *y) {
    if(!x || !y) return 0;
    POINT p;
    if(!GetCursorPos(&p)) return 0;
    RECT base; UINT dpi;
    if(primary_monitor(&base,&dpi)) {
        *x=(float)MulDiv(p.x-base.left,96,(int)dpi);
        *y=(float)MulDiv(p.y-base.top,96,(int)dpi);
    } else {
        *x=(float)p.x; *y=(float)p.y;
    }
    return 1;
}


typedef HRESULT (WINAPI *NimiDwmSet)(HWND, DWORD, LPCVOID, DWORD);
typedef HRESULT (WINAPI *NimiDwmGet)(HWND, DWORD, LPVOID, DWORD);
static HMODULE dwm_module;
static NimiDwmSet dwm_set;
static NimiDwmGet dwm_get;
static void load_dwm(void) {
    if (dwm_module) return;
    dwm_module=LoadLibraryW(L"dwmapi.dll");
    if (dwm_module) {
        dwm_set=(NimiDwmSet)GetProcAddress(dwm_module,"DwmSetWindowAttribute");
        dwm_get=(NimiDwmGet)GetProcAddress(dwm_module,"DwmGetWindowAttribute");
    }
}
int nimi_host_set_titlebar_dark(void *window, int dark) {
    load_dwm();
    if (!dwm_set || !window) return 0;
    BOOL value=dark?TRUE:FALSE;
    HRESULT hr=dwm_set((HWND)window,20,&value,sizeof(value));
    if (FAILED(hr)) hr=dwm_set((HWND)window,19,&value,sizeof(value));
    return SUCCEEDED(hr)?1:0;
}
int nimi_host_titlebar_dark(void *window) {
    load_dwm();
    if (!dwm_get || !window) return 0;
    BOOL value=FALSE;
    HRESULT hr=dwm_get((HWND)window,20,&value,sizeof(value));
    if (FAILED(hr)) hr=dwm_get((HWND)window,19,&value,sizeof(value));
    return SUCCEEDED(hr) && value ? 1 : 0;
}
double nimi_host_text_scale(void) {
    HKEY key; DWORD value=100, size=sizeof(value), kind=0;
    if (RegOpenKeyExW(HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Accessibility",0,KEY_READ,&key)==ERROR_SUCCESS) {
        if (RegQueryValueExW(key,L"TextScaleFactor",NULL,&kind,
            (LPBYTE)&value,&size)!=ERROR_SUCCESS || kind!=REG_DWORD) value=100;
        RegCloseKey(key);
    }
    if (value<100) value=100;
    if (value>500) value=500;
    return (double)value/100.0;
}
int nimi_host_high_contrast(void) {
    HIGHCONTRASTW hc;
    memset(&hc,0,sizeof(hc));
    hc.cbSize=sizeof(hc);
    if (SystemParametersInfoW(SPI_GETHIGHCONTRAST,sizeof(hc),&hc,0))
        return (hc.dwFlags & HCF_HIGHCONTRASTON) ? 1 : 0;
    return 0;
}
int nimi_host_is_elevated(void) {
    BOOL member=FALSE;
    PSID admins=NULL;
    SID_IDENTIFIER_AUTHORITY nt=SECURITY_NT_AUTHORITY;
    if (AllocateAndInitializeSid(&nt,2,SECURITY_BUILTIN_DOMAIN_RID,
        DOMAIN_ALIAS_RID_ADMINS,0,0,0,0,0,0,&admins)) {
        CheckTokenMembership(NULL,admins,&member);
        FreeSid(admins);
    }
    return member?1:0;
}
int nimi_host_relaunch_elevated(const wchar_t *args) {
    wchar_t exe[MAX_PATH];
    DWORD len=GetModuleFileNameW(NULL,exe,MAX_PATH);
    if (!len || len>=MAX_PATH) return (int)ERROR_FILE_NOT_FOUND;
    SHELLEXECUTEINFOW sei;
    memset(&sei,0,sizeof(sei));
    sei.cbSize=sizeof(sei);
    sei.fMask=SEE_MASK_NOCLOSEPROCESS;
    sei.lpVerb=L"runas";
    sei.lpFile=exe;
    sei.lpParameters=args;
    sei.nShow=SW_SHOWNORMAL;
    if (ShellExecuteExW(&sei)) {
        if (sei.hProcess) CloseHandle(sei.hProcess);
        return 0;
    }
    return (int)GetLastError();
}
int nimi_host_rect(void *window, int *x, int *y, int *w, int *h) {
    RECT r;
    if (!window || !GetWindowRect((HWND)window,&r)) return 0;
    if (x) *x=r.left;
    if (y) *y=r.top;
    if (w) *w=r.right-r.left;
    if (h) *h=r.bottom-r.top;
    return 1;
}

int nimi_host_apps_dark(void) {
    DWORD value=1, size=sizeof(value);
    LONG status=RegGetValueW(HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        L"AppsUseLightTheme",RRF_RT_REG_DWORD,NULL,&value,&size);
    if(status!=ERROR_SUCCESS) return 0;
    return value==0?1:0;
}

unsigned nimi_host_accent(void) {
    DWORD value=0, size=sizeof(value);
    LONG status=RegGetValueW(HKEY_CURRENT_USER,L"Software\\Microsoft\\Windows\\DWM",
        L"AccentColor",RRF_RT_REG_DWORD,NULL,&value,&size);
    if(status!=ERROR_SUCCESS) return 0;
    return value & 0x00ffffffu;
}

int nimi_host_register_hotkey(int id,unsigned modifiers,unsigned key) {
    if(!dispatch_window || !nimi_host_main_thread()) return 0;
    return RegisterHotKey(dispatch_window,(int)id,(UINT)modifiers,(UINT)key)!=0;
}

int nimi_host_unregister_hotkey(int id) {
    if(!dispatch_window) return 0;
    return UnregisterHotKey(dispatch_window,(int)id)!=0;
}
