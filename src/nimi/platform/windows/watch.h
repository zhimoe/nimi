#ifndef NIMI_WINDOWS_WATCH_H
#define NIMI_WINDOWS_WATCH_H
#include <stdint.h>
#include <wchar.h>
typedef struct NimiWatch NimiWatch;
typedef void (*NimiWatchChange)(void *context, wchar_t *name, int length, int action);
NimiWatch *nimi_watch_open(const wchar_t *directory, const wchar_t *file, uintptr_t id);
int nimi_watch_read(NimiWatch *watch, NimiWatchChange change, void *context);
void nimi_watch_close(NimiWatch *watch);
#endif
