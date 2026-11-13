#ifndef NIMI_WINDOWS_HOST_H
#define NIMI_WINDOWS_HOST_H
#include <stdint.h>
#include <wchar.h>
typedef intptr_t (*NimiEvent)(void *, unsigned, uintptr_t, intptr_t);
typedef struct { void *dc; float width, height; } NimiPaint;
float nimi_host_scale(void *window);
unsigned nimi_host_modifiers(void);
void nimi_host_invalidate(void *window);
int nimi_host_init(NimiEvent callback);
int nimi_host_run(void);
void nimi_host_step(void);
void nimi_host_quit(void);
void nimi_host_shutdown(void);
void nimi_host_signal(void);
int nimi_host_main_thread(void);
void *nimi_host_window(const wchar_t *title, int width, int height, int resizable);
void nimi_host_close(void *window);
void nimi_host_destroy(void *window);
void nimi_host_title(void *window, const wchar_t *title);
void nimi_host_show(void *window, int mode);
void nimi_host_size(void *window, int width, int height);
void nimi_host_position(void *window, int x, int y);
void nimi_host_center(void *window);
void nimi_host_resizable(void *window, int enabled);
int nimi_host_fullscreen(void *window, int toggle);
void nimi_host_zoom(void *window);
void nimi_host_client_size(void *window, float *width, float *height);
void nimi_host_topmost(void *window, int enabled);
int nimi_host_focused(void *window);
void nimi_host_focus(void *window);
int nimi_host_clipboard_read(wchar_t **text);
void nimi_host_free(void *memory);
int nimi_host_clipboard_write(const wchar_t *text);
int nimi_host_clipboard_clear(void);
void nimi_host_input_error(void);
int nimi_host_message(const wchar_t *title,const wchar_t *text,int confirm);
#endif
