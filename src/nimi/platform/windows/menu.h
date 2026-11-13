#ifndef NIMI_WINDOWS_MENU_H
#define NIMI_WINDOWS_MENU_H
#include <wchar.h>
#include <stdint.h>
void *nimi_menu_create(int popup);
int nimi_menu_append(void *menu,const wchar_t *label,unsigned command,void *child,int separator,int enabled,int checked);
void nimi_menu_free(void *menu);
void *nimi_accel_create(const uint16_t *keys,const uint16_t *commands,const uint8_t *flags,int count);
void nimi_accel_free(void *accel);
int nimi_menu_install(void *window,void *menu,void *accel);
void nimi_menu_detach(void *window);
int nimi_menu_translate(void *message);
void nimi_menu_test_key(void *window,unsigned key,unsigned modifiers);
#endif
