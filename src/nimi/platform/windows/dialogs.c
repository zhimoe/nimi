#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shobjidl.h>
#include <stdlib.h>
#include "dialogs.h"
#include "host.h"

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
    hr=CoCreateInstance(save?&CLSID_FileSaveDialog:&CLSID_FileOpenDialog,NULL,
                        CLSCTX_INPROC_SERVER,&IID_IFileDialog,(void **)&dialog);
    if(FAILED(hr)) goto done;
    FILEOPENDIALOGOPTIONS options;
    hr=IFileDialog_GetOptions(dialog,&options); if(FAILED(hr)) goto done;
    options|=FOS_FORCEFILESYSTEM|FOS_PATHMUSTEXIST|FOS_NOCHANGEDIR;
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
    result->count=count;
    for(DWORD i=0;i<count;i++) {
        hr=save?IFileDialog_GetResult(dialog,&item):IShellItemArray_GetItemAt(items,i,&item);
        if(FAILED(hr)) goto done;
        hr=IShellItem_GetDisplayName(item,SIGDN_FILESYSPATH,&result->paths[i]);
        IShellItem_Release(item); item=NULL;
        if(FAILED(hr)) goto done;
    }
done:
    if(item) IShellItem_Release(item);
    if(items) IShellItemArray_Release(items);
    if(open) IFileOpenDialog_Release(open);
    if(dialog) IFileDialog_Release(dialog);
    if(FAILED(hr)) nimi_paths_free(result);
    CoUninitialize();
    return hr;
}
