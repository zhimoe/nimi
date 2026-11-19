#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include "menu.h"
#include "host.h"
static const wchar_t menu_key[]=L"NimiMenu", accel_key[]=L"NimiAccel";
void *nimi_menu_create(int popup) { return popup?CreatePopupMenu():CreateMenu(); }
int nimi_menu_append(void *menu,const wchar_t *label,unsigned command,void *child,int separator,int enabled,int checked) {
    UINT flags=separator?MF_SEPARATOR:MF_STRING;
    if(child) flags|=MF_POPUP;
    if(!enabled) flags|=MF_GRAYED;
    if(checked) flags|=MF_CHECKED;
    return AppendMenuW(menu,flags,child?(UINT_PTR)child:command,label);
}
void nimi_menu_free(void *menu) { if(menu) DestroyMenu(menu); }
void *nimi_accel_create(const uint16_t *keys,const uint16_t *commands,const uint8_t *flags,int count) {
    if(!count) return NULL;
    ACCEL *entries=calloc(count,sizeof(*entries)); if(!entries) return NULL;
    for(int i=0;i<count;i++) { entries[i].key=keys[i]; entries[i].cmd=commands[i]; entries[i].fVirt=flags[i]; }
    HACCEL result=CreateAcceleratorTableW(entries,count); free(entries); return result;
}
void nimi_accel_free(void *accel) { if(accel) DestroyAcceleratorTable(accel); }
int nimi_menu_install(void *window,void *menu,void *accel) {
    HMENU old=GetPropW(window,menu_key); HACCEL oldAccel=GetPropW(window,accel_key);
    float width,height; nimi_host_client_size(window,&width,&height);
    if(menu && !SetPropW(window,menu_key,menu)) return 0;
    if(accel && !SetPropW(window,accel_key,accel)) {
        if(old) SetPropW(window,menu_key,old); else RemovePropW(window,menu_key);
        return 0;
    }
    if(!SetMenu(window,menu)) {
        if(old) SetPropW(window,menu_key,old); else RemovePropW(window,menu_key);
        if(oldAccel) SetPropW(window,accel_key,oldAccel); else RemovePropW(window,accel_key);
        return 0;
    }
    if(!menu) RemovePropW(window,menu_key);
    if(!accel) RemovePropW(window,accel_key);
    nimi_menu_free(old); nimi_accel_free(oldAccel);
    DrawMenuBar(window);
    if(!IsZoomed(window) && !IsIconic(window) && !nimi_host_fullscreen(window,0))
        nimi_host_size(window,(int)(width+0.5f),(int)(height+0.5f));
    return 1;
}
void nimi_menu_detach(void *window) {
    HMENU menu=RemovePropW(window,menu_key); HACCEL accel=RemovePropW(window,accel_key);
    SetMenu(window,NULL); nimi_menu_free(menu); nimi_accel_free(accel);
}
int nimi_menu_translate(void *message) {
    MSG *msg=message;
    if(msg->message!=WM_KEYDOWN && msg->message!=WM_SYSKEYDOWN) return 0;
    HWND root=GetAncestor(msg->hwnd,GA_ROOT);
    HACCEL accel=GetPropW(root,accel_key);
    return accel && TranslateAcceleratorW(root,accel,msg);
}

void nimi_menu_test_key(void *window,unsigned key,unsigned modifiers) {
    HACCEL table=GetPropW(window,accel_key);
    if(!table) return;
    int count=CopyAcceleratorTableW(table,NULL,0);
    ACCEL *entries=calloc(count,sizeof(*entries)); if(!entries) return;
    count=CopyAcceleratorTableW(table,entries,count);
    BYTE flags=FVIRTKEY | ((modifiers&1)?FSHIFT:0) |
        ((modifiers&2)?FCONTROL:0) | ((modifiers&4)?FALT:0);
    WORD command=0;
    for(int i=0;i<count;i++) if(entries[i].key==key && (entries[i].fVirt&29)==flags) {
        command=entries[i].cmd; break;
    }
    free(entries);
    if(command) SendMessageW(window,WM_COMMAND,MAKEWPARAM(command,1),0);
}
