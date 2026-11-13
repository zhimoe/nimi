#ifndef NIMI_WINDOWS_DIALOGS_H
#define NIMI_WINDOWS_DIALOGS_H
#include <stdint.h>
#include <stddef.h>
#include <wchar.h>
typedef struct { wchar_t **paths; size_t count; } NimiPaths;
int32_t nimi_file_dialog(int save, int multiple, int directory,
    const wchar_t *title, const wchar_t *folder, const wchar_t *name,
    const wchar_t *extension, const wchar_t *pattern, NimiPaths *result);
void nimi_paths_free(NimiPaths *paths);
#endif
