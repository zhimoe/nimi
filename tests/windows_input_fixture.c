#define WIN32_LEAN_AND_MEAN
#include <windows.h>

static HANDLE clipboard_ready, clipboard_release, clipboard_thread;
static int clipboard_locked;
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
