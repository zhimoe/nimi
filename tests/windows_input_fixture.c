#define WIN32_LEAN_AND_MEAN
#include <windows.h>

static HANDLE clipboard_ready, clipboard_release, clipboard_thread;
static int clipboard_locked;
int test_scroll_at_client_origin(void *window, unsigned message, int delta, unsigned modifiers) {
    POINT origin = {0, 0};
    if (!ClientToScreen(window, &origin)) return 0;
    SendMessageW(window, message, MAKEWPARAM(modifiers, delta),
                 MAKELPARAM(origin.x, origin.y));
    return 1;
}
static DWORD WINAPI lock_clipboard(void *unused) {
    clipboard_locked = OpenClipboard(NULL);
    SetEvent(clipboard_ready);
    WaitForSingleObject(clipboard_release, INFINITE);
    if(clipboard_locked) CloseClipboard();
    return 0;
}
void test_unlock_clipboard(void) {
    if(clipboard_thread) {
        SetEvent(clipboard_release);
        WaitForSingleObject(clipboard_thread, INFINITE);
        CloseHandle(clipboard_thread); clipboard_thread=NULL;
    }
    if(clipboard_ready) { CloseHandle(clipboard_ready); clipboard_ready=NULL; }
    if(clipboard_release) { CloseHandle(clipboard_release); clipboard_release=NULL; }
}
int test_lock_clipboard(void) {
    clipboard_locked=0;
    clipboard_ready=CreateEventW(NULL,TRUE,FALSE,NULL);
    clipboard_release=CreateEventW(NULL,TRUE,FALSE,NULL);
    if(clipboard_ready && clipboard_release)
        clipboard_thread=CreateThread(NULL,0,lock_clipboard,NULL,0,NULL);
    if(!clipboard_thread) { test_unlock_clipboard(); return 0; }
    WaitForSingleObject(clipboard_ready, INFINITE);
    return clipboard_locked;
}
int test_bad_clipboard(void *window) {
    HGLOBAL memory=GlobalAlloc(GMEM_MOVEABLE,16);
    if(!memory) return 0;
    SIZE_T count=GlobalSize(memory)/sizeof(WCHAR);
    WCHAR *text=GlobalLock(memory);
    if(!text) {GlobalFree(memory); return 0;}
    for(SIZE_T i=0;i<count;++i) text[i]=L'x';
    GlobalUnlock(memory);
    if(!OpenClipboard(window)) {GlobalFree(memory); return 0;}
    int ok=EmptyClipboard() && SetClipboardData(CF_UNICODETEXT,memory)!=NULL;
    CloseClipboard();
    if(!ok) GlobalFree(memory);
    return ok;
}

static const wchar_t *dialog_button;
static UINT_PTR dialog_timer;
static int dialog_attempts, dialog_handled;

static BOOL CALLBACK click_dialog_button(HWND window, LPARAM context) {
    (void)context;
    wchar_t label[128];
    if (GetWindowTextW(window, label, ARRAYSIZE(label)) &&
        lstrcmpW(label, dialog_button) == 0) {
        dialog_handled = 1;
        PostMessageW(window, BM_CLICK, 0, 0);
        return FALSE;
    }
    return TRUE;
}
static BOOL CALLBACK find_message_dialog(HWND window, LPARAM context) {
    (void)context;
    wchar_t title[128];
    if (!GetWindowTextW(window, title, ARRAYSIZE(title)) ||
        lstrcmpW(title, L"Nimi custom dialog test") != 0) return TRUE;
    if (dialog_button) EnumChildWindows(window, click_dialog_button, 0);
    else {
        dialog_handled = 1;
        PostMessageW(window, WM_CLOSE, 0, 0);
    }
    if (!dialog_handled && dialog_attempts >= 100) PostMessageW(window, WM_CLOSE, 0, 0);
    return FALSE;
}
static void CALLBACK drive_dialog(HWND window, UINT message, UINT_PTR timer, DWORD time) {
    (void)window; (void)message; (void)time;
    ++dialog_attempts;
    EnumThreadWindows(GetCurrentThreadId(), find_message_dialog, 0);
    if (dialog_handled || dialog_attempts >= 100) {
        KillTimer(NULL, timer);
        dialog_timer = 0;
    }
}
int test_start_dialog(const wchar_t *button) {
    dialog_button = button;
    dialog_attempts = dialog_handled = 0;
    dialog_timer = SetTimer(NULL, 0, 30, drive_dialog);
    return dialog_timer != 0;
}
int test_stop_dialog(void) {
    if (dialog_timer) KillTimer(NULL, dialog_timer);
    dialog_timer = 0;
    dialog_button = NULL;
    return dialog_handled;
}
