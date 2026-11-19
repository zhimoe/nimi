#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commctrl.h>
#include <shobjidl.h>
#include <stdlib.h>
#include "dialogs.h"
#include "host.h"

static HRESULT item_path(IShellItem *item, int directory, wchar_t **path) {
    *path = NULL;
    HRESULT hr = IShellItem_GetDisplayName(item, SIGDN_FILESYSPATH, path);
    if (FAILED(hr) && directory) {
        IShellLibrary *library = NULL;
        if (SUCCEEDED(CoCreateInstance(&CLSID_ShellLibrary, NULL,
                CLSCTX_INPROC_SERVER, &IID_IShellLibrary, (void **)&library))) {
            IShellItem *folder = NULL;
            if (SUCCEEDED(IShellLibrary_LoadLibraryFromItem(library, item, STGM_READ))) {
                IShellLibrary_GetDefaultSaveFolder(library, DSFT_DETECT,
                                                    &IID_IShellItem, (void **)&folder);
            }
            IShellLibrary_Release(library);
            if (folder) {
                hr = IShellItem_GetDisplayName(folder, SIGDN_FILESYSPATH, path);
                IShellItem_Release(folder);
                return hr;
            }
        }
    }
    return hr;
}

typedef struct {
    IFileDialogEvents iface;
    ULONG refs;
} FolderCheck;

static HRESULT STDMETHODCALLTYPE folder_query(IFileDialogEvents *self, REFIID iid, void **value) {
    if (!value) return E_POINTER;
    *value = NULL;
    if (!IsEqualIID(iid, &IID_IUnknown) && !IsEqualIID(iid, &IID_IFileDialogEvents))
        return E_NOINTERFACE;
    *value = self;
    IFileDialogEvents_AddRef(self);
    return S_OK;
}
static ULONG STDMETHODCALLTYPE folder_addref(IFileDialogEvents *self) {
    return ++((FolderCheck *)self)->refs;
}
static ULONG STDMETHODCALLTYPE folder_release(IFileDialogEvents *self) {
    ULONG refs = --((FolderCheck *)self)->refs;
    if (!refs) free(self);
    return refs;
}
static HRESULT STDMETHODCALLTYPE folder_ok(IFileDialogEvents *self, IFileDialog *dialog) {
    (void)self;
    IFileOpenDialog *open = NULL;
    IShellItemArray *items = NULL;
    DWORD count = 0;
    HRESULT hr = IFileDialog_QueryInterface(dialog, &IID_IFileOpenDialog, (void **)&open);
    if (SUCCEEDED(hr)) {
        hr = IFileOpenDialog_GetResults(open, &items);
        IFileOpenDialog_Release(open);
    }
    if (SUCCEEDED(hr)) hr = IShellItemArray_GetCount(items, &count);
    for (DWORD i = 0; SUCCEEDED(hr) && i < count; ++i) {
        IShellItem *item = NULL;
        hr = IShellItemArray_GetItemAt(items, i, &item);
        if (SUCCEEDED(hr)) {
            wchar_t *path = NULL;
            hr = item_path(item, 1, &path);
            CoTaskMemFree(path);
            IShellItem_Release(item);
        }
    }
    if (items) IShellItemArray_Release(items);
    if (SUCCEEDED(hr) && count) return S_OK;

    IOleWindow *window = NULL;
    HWND owner = GetActiveWindow();
    if (SUCCEEDED(IFileDialog_QueryInterface(dialog, &IID_IOleWindow, (void **)&window))) {
        IOleWindow_GetWindow(window, &owner);
        IOleWindow_Release(window);
    }
    MessageBoxW(owner, L"Select a folder with a file system path.", NULL, MB_OK | MB_ICONWARNING);
    return S_FALSE;
}
static HRESULT STDMETHODCALLTYPE folder_changing(IFileDialogEvents *self, IFileDialog *dialog,
                                                  IShellItem *item) { return S_OK; }
static HRESULT STDMETHODCALLTYPE folder_changed(IFileDialogEvents *self, IFileDialog *dialog) {
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE folder_share(IFileDialogEvents *self, IFileDialog *dialog,
                                               IShellItem *item, FDE_SHAREVIOLATION_RESPONSE *response) {
    *response = FDESVR_DEFAULT;
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE folder_overwrite(IFileDialogEvents *self, IFileDialog *dialog,
                                                   IShellItem *item, FDE_OVERWRITE_RESPONSE *response) {
    *response = FDEOR_DEFAULT;
    return S_OK;
}
static IFileDialogEventsVtbl folder_vtbl = {
    folder_query, folder_addref, folder_release, folder_ok, folder_changing,
    folder_changed, folder_changed, folder_share, folder_changed, folder_overwrite
};

typedef HRESULT (WINAPI *TaskDialogFn)(const TASKDIALOGCONFIG *, int *, int *, BOOL *);

int32_t nimi_task_dialog(const wchar_t *manifest, const wchar_t *title,
                         const wchar_t *text, wchar_t *const *labels,
                         int count, int *selected) {
    if (!nimi_host_main_thread()) return RPC_E_WRONG_THREAD;
    ACTCTXW context = { .cbSize = sizeof(context), .lpSource = manifest };
    HANDLE activation = CreateActCtxW(&context);
    if (activation == INVALID_HANDLE_VALUE) return HRESULT_FROM_WIN32(GetLastError());
    ULONG_PTR cookie;
    if (!ActivateActCtx(activation, &cookie)) {
        HRESULT hr = HRESULT_FROM_WIN32(GetLastError());
        ReleaseActCtx(activation);
        return hr;
    }
    HMODULE controls = LoadLibraryExW(L"comctl32.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!controls) {
        HRESULT hr = HRESULT_FROM_WIN32(GetLastError());
        DeactivateActCtx(0, cookie);
        ReleaseActCtx(activation);
        return hr;
    }
    TaskDialogFn show = (TaskDialogFn)GetProcAddress(controls, "TaskDialogIndirect");
    HRESULT hr = E_NOTIMPL;
    TASKDIALOG_BUTTON *buttons = calloc((size_t)count, sizeof(*buttons));
    if (!buttons) hr = E_OUTOFMEMORY;
    else if (show) {
        const int first = 100;
        for (int i = 0; i < count; ++i) {
            buttons[i].nButtonID = first + i;
            buttons[i].pszButtonText = labels[i];
        }
        TASKDIALOGCONFIG config = {
            .cbSize = sizeof(config), .hwndParent = GetActiveWindow(),
            .dwFlags = TDF_ALLOW_DIALOG_CANCELLATION | TDF_SIZE_TO_CONTENT,
            .pszWindowTitle = title, .pszContent = text, .cButtons = (UINT)count,
            .pButtons = buttons, .nDefaultButton = first
        };
        int button = 0;
        hr = show(&config, &button, NULL, NULL);
        *selected = button >= first && button - first < count ? button - first : -1;
    }
    free(buttons);
    FreeLibrary(controls);
    DeactivateActCtx(0, cookie);
    ReleaseActCtx(activation);
    return hr;
}

void nimi_paths_free(NimiPaths *paths) {
    for(size_t i=0;i<paths->count;i++) CoTaskMemFree(paths->paths[i]);
    free(paths->paths); paths->paths=NULL; paths->count=0;
}
int32_t nimi_file_dialog(int save,int multiple,int directory,
    const wchar_t *title,const wchar_t *folder,const wchar_t *name,
    const wchar_t *extension,const wchar_t *pattern,NimiPaths *result) {
    result->paths=NULL; result->count=0;
    if(!nimi_host_main_thread()) return RPC_E_WRONG_THREAD;
    HRESULT hr=CoInitializeEx(NULL,COINIT_APARTMENTTHREADED|COINIT_DISABLE_OLE1DDE);
    if(FAILED(hr)) return hr;
    IFileDialog *dialog=NULL; IShellItem *item=NULL; IShellItemArray *items=NULL;
    IFileOpenDialog *open=NULL;
    DWORD cookie=0;
    int advised=0;
    hr=CoCreateInstance(save?&CLSID_FileSaveDialog:&CLSID_FileOpenDialog,NULL,
                        CLSCTX_INPROC_SERVER,&IID_IFileDialog,(void **)&dialog);
    if(FAILED(hr)) goto done;
    FILEOPENDIALOGOPTIONS options;
    hr=IFileDialog_GetOptions(dialog,&options); if(FAILED(hr)) goto done;
    options|=FOS_PATHMUSTEXIST|FOS_NOCHANGEDIR;
    /* Forcing file system items can stall folder navigation on WSL shares. */
    if(directory) options&=~FOS_FORCEFILESYSTEM;
    else options|=FOS_FORCEFILESYSTEM;
    if(save) options|=FOS_OVERWRITEPROMPT;
    else { if(directory) options|=FOS_PICKFOLDERS; else options|=FOS_FILEMUSTEXIST;
           if(multiple) options|=FOS_ALLOWMULTISELECT; }
    hr=IFileDialog_SetOptions(dialog,options); if(FAILED(hr)) goto done;
    if(title && *title) { hr=IFileDialog_SetTitle(dialog,title); if(FAILED(hr)) goto done; }
    if(folder && *folder) {
        hr=SHCreateItemFromParsingName(folder,NULL,&IID_IShellItem,(void **)&item);
        if(FAILED(hr)) goto done;
        hr=IFileDialog_SetFolder(dialog,item); IShellItem_Release(item); item=NULL;
        if(FAILED(hr)) goto done;
    }
    if(name && *name) { hr=IFileDialog_SetFileName(dialog,name); if(FAILED(hr)) goto done; }
    if(save && extension && *extension) {
        hr=IFileDialog_SetDefaultExtension(dialog,extension); if(FAILED(hr)) goto done;
    }
    if(!directory && pattern && *pattern) {
        COMDLG_FILTERSPEC filter={L"Allowed files",pattern};
        hr=IFileDialog_SetFileTypes(dialog,1,&filter); if(FAILED(hr)) goto done;
    }
    if(directory) {
        FolderCheck *check=calloc(1,sizeof(*check));
        if(!check) { hr=E_OUTOFMEMORY; goto done; }
        check->iface.lpVtbl=&folder_vtbl;
        check->refs=1;
        hr=IFileDialog_Advise(dialog,&check->iface,&cookie);
        IFileDialogEvents_Release(&check->iface);
        if(FAILED(hr)) goto done;
        advised=1;
    }
    hr=IFileDialog_Show(dialog,GetActiveWindow()); if(FAILED(hr)) goto done;
    DWORD count=1;
    if(!save) {
        hr=IFileDialog_QueryInterface(dialog,&IID_IFileOpenDialog,(void **)&open);
        if(FAILED(hr)) goto done;
        hr=IFileOpenDialog_GetResults(open,&items); if(FAILED(hr)) goto done;
        hr=IShellItemArray_GetCount(items,&count); if(FAILED(hr)) goto done;
    }
    result->paths=calloc(count,sizeof(wchar_t *));
    if(count && !result->paths) { hr=E_OUTOFMEMORY; goto done; }
    for(DWORD i=0;i<count;i++) {
        hr=save?IFileDialog_GetResult(dialog,&item):IShellItemArray_GetItemAt(items,i,&item);
        if(FAILED(hr)) goto done;
        wchar_t *path=NULL;
        hr=item_path(item,directory,&path);
        IShellItem_Release(item); item=NULL;
        if(FAILED(hr)) {
            CoTaskMemFree(path);
            if(!directory) goto done;
            hr=S_OK;
        } else {
            result->paths[result->count++]=path;
        }
    }
done:
    if(item) IShellItem_Release(item);
    if(items) IShellItemArray_Release(items);
    if(open) IFileOpenDialog_Release(open);
    if(advised) IFileDialog_Unadvise(dialog,cookie);
    if(dialog) IFileDialog_Release(dialog);
    if(FAILED(hr)) nimi_paths_free(result);
    CoUninitialize();
    return hr;
}
