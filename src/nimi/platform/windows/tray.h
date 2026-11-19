#ifndef NIMI_WINDOWS_TRAY_H
#define NIMI_WINDOWS_TRAY_H
#include <wchar.h>
typedef void (*NimiTrayActivate)(int x, int y);
int nimi_tray_add(const wchar_t *tooltip, NimiTrayActivate activate);
int nimi_tray_tooltip(const wchar_t *tooltip);
void nimi_tray_remove(void);
unsigned nimi_tray_popup(void *menu, int x, int y);
int nimi_tray_notify(const wchar_t *title, const wchar_t *text);
void nimi_tray_shutdown(void);
#endif
