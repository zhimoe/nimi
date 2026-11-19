#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stddef.h>
#include <stdlib.h>
#include "host.h"
#include "watch.h"

struct NimiWatch {
    HANDLE directory, event;
    PTP_WAIT wait;
    HWND dispatch;
    uintptr_t id;
    OVERLAPPED io;
    wchar_t *file;
    int pending;
    DWORD buffer[16384]; /* DWORD aligned, 64 KiB also works on network shares. */
};

static void CALLBACK watch_ready(PTP_CALLBACK_INSTANCE instance, void *context,
                                 PTP_WAIT wait, TP_WAIT_RESULT result) {
    (void)instance; (void)wait; (void)result;
    NimiWatch *watch = context;
    PostMessageW(watch->dispatch, NIMI_WATCH_READY, (WPARAM)watch->id, 0);
}

static int watch_arm(NimiWatch *watch) {
    if (!ResetEvent(watch->event)) return 0;
    watch->io = (OVERLAPPED){ .hEvent = watch->event };
    if (!ReadDirectoryChangesW(watch->directory, watch->buffer, sizeof(watch->buffer),
            watch->file == NULL, FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME |
            FILE_NOTIFY_CHANGE_LAST_WRITE | FILE_NOTIFY_CHANGE_SIZE | FILE_NOTIFY_CHANGE_ATTRIBUTES,
            NULL, &watch->io, NULL)) return 0;
    watch->pending = 1;
    SetThreadpoolWait(watch->wait, watch->event, NULL);
    return 1;
}

void nimi_watch_close(NimiWatch *watch) {
    if (!watch) return;
    if (watch->wait) {
        SetThreadpoolWait(watch->wait, NULL, NULL);
        WaitForThreadpoolWaitCallbacks(watch->wait, TRUE);
        CloseThreadpoolWait(watch->wait);
    }
    if (watch->pending) {
        CancelIoEx(watch->directory, &watch->io);
        DWORD bytes;
        GetOverlappedResult(watch->directory, &watch->io, &bytes, TRUE);
    }
    if (watch->directory != INVALID_HANDLE_VALUE) CloseHandle(watch->directory);
    if (watch->event) CloseHandle(watch->event);
    free(watch->file);
    free(watch);
}

NimiWatch *nimi_watch_open(const wchar_t *directory, const wchar_t *file, uintptr_t id) {
    if (!nimi_host_main_thread()) return NULL;
    NimiWatch *watch = calloc(1, sizeof(*watch));
    if (!watch) return NULL;
    watch->dispatch = nimi_host_dispatch_window();
    watch->id = id;
    watch->directory = CreateFileW(directory, FILE_LIST_DIRECTORY,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED, NULL);
    if (!watch->dispatch || watch->directory == INVALID_HANDLE_VALUE) goto fail;
    if (file && *file) {
        watch->file = _wcsdup(file);
        if (!watch->file) goto fail;
    }
    watch->event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!watch->event) goto fail;
    watch->wait = CreateThreadpoolWait(watch_ready, watch, NULL);
    if (!watch->wait || !watch_arm(watch)) goto fail;
    return watch;
fail:
    nimi_watch_close(watch);
    return NULL;
}

int nimi_watch_read(NimiWatch *watch, NimiWatchChange change, void *context) {
    DWORD bytes = 0;
    BOOL completed = GetOverlappedResult(watch->directory, &watch->io, &bytes, FALSE);
    DWORD error = completed ? ERROR_SUCCESS : GetLastError();
    if (error == ERROR_IO_INCOMPLETE) return 1;
    watch->pending = 0;
    if (error && error != ERROR_NOTIFY_ENUM_DIR) return 0;
    /* A full kernel buffer loses individual names. Ask consumers to refresh. */
    if (!bytes) change(context, NULL, 0, FILE_ACTION_MODIFIED);
    size_t remaining = bytes;
    BYTE *cursor = (BYTE *)watch->buffer;
    const size_t header = offsetof(FILE_NOTIFY_INFORMATION, FileName);
    while (remaining >= header) {
        FILE_NOTIFY_INFORMATION *entry = (FILE_NOTIFY_INFORMATION *)cursor;
        if (entry->FileNameLength > remaining - header ||
            entry->FileNameLength % sizeof(wchar_t)) break;
        int length = (int)(entry->FileNameLength / sizeof(wchar_t));
        if (!watch->file || CompareStringOrdinal(watch->file, -1, entry->FileName, length, TRUE)
                           == CSTR_EQUAL) {
            change(context, entry->FileName, length, (int)entry->Action);
        }
        DWORD next = entry->NextEntryOffset;
        if (!next || next < header + entry->FileNameLength ||
            next > remaining || next % sizeof(DWORD)) break;
        cursor += next;
        remaining -= next;
    }
    return watch_arm(watch);
}
