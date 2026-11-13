#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windowsx.h>
#include <imm.h>
#include <stdlib.h>
#include <string.h>
#include "host.h"
#include "menu.h"

static NimiEvent nimi_event;
static HWND dispatch_window;
static DWORD main_thread;
typedef struct { WINDOWPLACEMENT placement; LONG_PTR style; } NimiFullscreen;
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
#define NIMI_TIMER_ID 1

static LRESULT CALLBACK nimi_proc(HWND window, UINT message, WPARAM wp, LPARAM lp) {
    if (window == dispatch_window) {
        if (message == NIMI_DISPATCH) { nimi_event(NULL, NIMI_DISPATCH, 0, 0); return 0; }
    } else if (nimi_event) {
        switch (message) {
        case WM_NCDESTROY: {
            NimiFullscreen *saved=(NimiFullscreen *)RemovePropW(window,fullscreen_key);
            free(saved); KillTimer(window,NIMI_TIMER_ID); break;
        }
        case WM_ERASEBKGND: return 1;
        case WM_SIZE: InvalidateRect(window,NULL,FALSE); break;
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
        case WM_MOUSEWHEEL: {
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
        case WM_DPICHANGED: {
            RECT *r = (RECT *)lp;
            SetWindowPos(window, NULL, r->left, r->top, r->right-r->left,
                         r->bottom-r->top, SWP_NOZORDER | SWP_NOACTIVATE);
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
void nimi_host_center(void *w) {
    MONITORINFO m = {sizeof(m)}; RECT r;
    GetMonitorInfoW(MonitorFromWindow(w, MONITOR_DEFAULTTONEAREST), &m);
    GetWindowRect(w, &r);
    nimi_host_position(w, m.rcWork.left+(m.rcWork.right-m.rcWork.left-(r.right-r.left))/2,
                         m.rcWork.top+(m.rcWork.bottom-m.rcWork.top-(r.bottom-r.top))/2);
}
void nimi_host_topmost(void *w, int on) { SetWindowPos(w,on?HWND_TOPMOST:HWND_NOTOPMOST,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE); }
int nimi_host_focused(void *w) { return GetForegroundWindow() == w; }
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
int nimi_host_clipboard_write(const wchar_t *text) {
    if (!dispatch_window || !nimi_host_main_thread()) return 0;
    SIZE_T bytes=(wcslen(text)+1)*sizeof(wchar_t);
    HGLOBAL memory=GlobalAlloc(GMEM_MOVEABLE,bytes);
    if(!memory) return 0;
    void *data=GlobalLock(memory);
    if(!data) { GlobalFree(memory); return 0; }
    memcpy(data,text,bytes); GlobalUnlock(memory);
    if(!OpenClipboard(dispatch_window)) { GlobalFree(memory); return 0; }
    int success=EmptyClipboard() && SetClipboardData(CF_UNICODETEXT,memory)!=NULL;
    CloseClipboard();
    if(!success) GlobalFree(memory);
    return success;
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
        RemovePropW(w,fullscreen_key);
        SetWindowLongPtrW(w,GWL_STYLE,saved->style);
        SetWindowPlacement(w,&saved->placement);
        SetWindowPos(w,NULL,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOZORDER|SWP_FRAMECHANGED);
        free(saved); return 0;
    }
    saved=calloc(1,sizeof(*saved));
    if(!saved) return -1;
    saved->placement.length=sizeof(saved->placement);
    if(!GetWindowPlacement(w,&saved->placement)) {free(saved); return -1;}
    saved->style=GetWindowLongPtrW(w,GWL_STYLE);
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
