#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windowsx.h>
#include <shellapi.h>
#include "tray.h"

#define TRAY_CALLBACK (WM_APP + 1)
#define TRAY_ICON 1
#define NOTIFICATION_ICON 2
#define NOTIFICATION_TIMER 1

static HWND tray_window;
static UINT taskbar_created;
static HICON application_icon;
static int owns_icon;
static int has_tray, has_notification;
static wchar_t tooltip[128];
static NimiTrayActivate activate_tray;

static NOTIFYICONDATAW icon_data(UINT id) {
    NOTIFYICONDATAW data = { .cbSize = sizeof(data), .hWnd = tray_window, .uID = id };
    return data;
}

static void copy_label(wchar_t *target, int capacity, const wchar_t *value) {
    lstrcpynW(target, value, capacity);
    int size = lstrlenW(target);
    if (size && target[size-1] >= 0xd800 && target[size-1] <= 0xdbff) target[size-1] = 0;
}

static int add_icon(UINT id) {
    NOTIFYICONDATAW data = icon_data(id);
    data.uFlags = NIF_ICON | NIF_MESSAGE;
    data.uCallbackMessage = TRAY_CALLBACK;
    data.hIcon = application_icon;
    if (id == TRAY_ICON) {
        data.uFlags |= NIF_TIP | NIF_SHOWTIP;
        copy_label(data.szTip, ARRAYSIZE(data.szTip), tooltip);
    } else {
        data.uFlags |= NIF_STATE;
        data.dwState = NIS_HIDDEN;
        data.dwStateMask = NIS_HIDDEN;
    }
    if (!Shell_NotifyIconW(NIM_ADD, &data)) return 0;
    data.uVersion = NOTIFYICON_VERSION_4;
    if (Shell_NotifyIconW(NIM_SETVERSION, &data)) return 1;
    Shell_NotifyIconW(NIM_DELETE, &data);
    return 0;
}

static void clear_notification(void) {
    if (!has_notification) return;
    has_notification = 0;
    KillTimer(tray_window, NOTIFICATION_TIMER);
    NOTIFYICONDATAW data = icon_data(NOTIFICATION_ICON);
    Shell_NotifyIconW(NIM_DELETE, &data);
}

static LRESULT CALLBACK tray_proc(HWND window, UINT message, WPARAM wp, LPARAM lp) {
    if (taskbar_created && message == taskbar_created) {
        clear_notification();
        if (has_tray) add_icon(TRAY_ICON);
        return 0;
    }
    if (message == WM_TIMER && wp == NOTIFICATION_TIMER) {
        clear_notification();
        return 0;
    }
    if (message == TRAY_CALLBACK) {
        UINT action = LOWORD(lp);
        if (HIWORD(lp) == NOTIFICATION_ICON &&
            (action == NIN_BALLOONHIDE || action == NIN_BALLOONTIMEOUT ||
             action == NIN_BALLOONUSERCLICK)) {
            clear_notification();
        } else if (HIWORD(lp) == TRAY_ICON && has_tray && activate_tray &&
                   (action == WM_CONTEXTMENU || action == NIN_SELECT || action == NIN_KEYSELECT)) {
            POINT point = { GET_X_LPARAM(wp), GET_Y_LPARAM(wp) };
            if (action == WM_CONTEXTMENU) {
                NOTIFYICONIDENTIFIER icon = {
                    .cbSize = sizeof(icon), .hWnd = window, .uID = TRAY_ICON
                };
                RECT rect;
                if (SUCCEEDED(Shell_NotifyIconGetRect(&icon, &rect))) {
                    point = (POINT){(rect.left+rect.right)/2, rect.bottom};
                } else if (!GetCursorPos(&point)) return 0;
            }
            activate_tray(point.x, point.y);
        }
        return 0;
    }
    return DefWindowProcW(window, message, wp, lp);
}

static int ensure_tray_window(void) {
    if (tray_window) return 1;
    HINSTANCE instance = GetModuleHandleW(NULL);
    const wchar_t name[] = L"NimiNotificationWindow";
    WNDCLASSW wc = {.lpfnWndProc = tray_proc, .hInstance = instance, .lpszClassName = name};
    if (!RegisterClassW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return 0;
    taskbar_created = RegisterWindowMessageW(L"TaskbarCreated");
    tray_window = CreateWindowExW(WS_EX_TOOLWINDOW, name, L"", WS_POPUP,
                                 0, 0, 0, 0, NULL, NULL, instance, NULL);
    if (!tray_window) return 0;
    wchar_t exe[32768];
    DWORD size = GetModuleFileNameW(NULL, exe, ARRAYSIZE(exe));
    if (size && size < ARRAYSIZE(exe) &&
        ExtractIconExW(exe, 0, NULL, &application_icon, 1) == 1 && application_icon)
        owns_icon = 1;
    if (!application_icon) application_icon = LoadIconW(NULL, MAKEINTRESOURCEW(32512));
    return 1;
}

int nimi_tray_add(const wchar_t *text, NimiTrayActivate activate) {
    if (has_tray || !ensure_tray_window()) return 0;
    copy_label(tooltip, ARRAYSIZE(tooltip), text);
    if (!add_icon(TRAY_ICON)) return 0;
    activate_tray = activate;
    has_tray = 1;
    return 1;
}

int nimi_tray_tooltip(const wchar_t *text) {
    NOTIFYICONDATAW data = icon_data(TRAY_ICON);
    data.uFlags = NIF_TIP | NIF_SHOWTIP;
    copy_label(data.szTip, ARRAYSIZE(data.szTip), text);
    if (!has_tray || !Shell_NotifyIconW(NIM_MODIFY, &data)) return 0;
    copy_label(tooltip, ARRAYSIZE(tooltip), data.szTip);
    return 1;
}

void nimi_tray_remove(void) {
    if (!has_tray) return;
    has_tray = 0;
    activate_tray = NULL;
    NOTIFYICONDATAW data = icon_data(TRAY_ICON);
    Shell_NotifyIconW(NIM_DELETE, &data);
}

unsigned nimi_tray_popup(void *menu, int x, int y) {
    if (!has_tray) return 0;
    HWND window = tray_window;
    SetForegroundWindow(window);
    UINT choice = (UINT)TrackPopupMenuEx(menu, TPM_RIGHTBUTTON | TPM_NONOTIFY |
        TPM_RETURNCMD, x, y, window, NULL);
    if (window == tray_window) {
        PostMessageW(window, WM_NULL, 0, 0);
        if (!choice && has_tray) {
            NOTIFYICONDATAW data = icon_data(TRAY_ICON);
            Shell_NotifyIconW(NIM_SETFOCUS, &data);
        }
    }
    return choice;
}

int nimi_tray_notify(const wchar_t *title, const wchar_t *text) {
    if (!ensure_tray_window()) return 0;
    UINT id = has_tray ? TRAY_ICON : NOTIFICATION_ICON;
    if (id == NOTIFICATION_ICON && !has_notification) {
        if (!add_icon(id)) return 0;
        has_notification = 1;
    }
    NOTIFYICONDATAW data = icon_data(id);
    data.uFlags = NIF_INFO;
    data.dwInfoFlags = NIIF_INFO | NIIF_RESPECT_QUIET_TIME;
    copy_label(data.szInfoTitle, ARRAYSIZE(data.szInfoTitle), title);
    copy_label(data.szInfo, ARRAYSIZE(data.szInfo), text);
    int success = Shell_NotifyIconW(NIM_MODIFY, &data);
    if (id == NOTIFICATION_ICON &&
        (!success || (has_notification && !SetTimer(tray_window, NOTIFICATION_TIMER, 30000, NULL))))
        clear_notification();
    return success;
}

void nimi_tray_shutdown(void) {
    if (!tray_window) return;
    clear_notification();
    nimi_tray_remove();
    DestroyWindow(tray_window);
    tray_window = NULL;
    if (owns_icon) DestroyIcon(application_icon);
    application_icon = NULL;
    owns_icon = 0;
}
