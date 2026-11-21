## Dynamic bindings for the Linux backend.
##
## Nimi loads GTK3, GDK, Cairo, Pango, GdkPixbuf, WebKitGTK and libnotify at
## runtime with dlopen. Building a Linux app therefore needs only a C compiler
## and the Nim standard library; missing runtime libraries produce explicit
## errors instead of link failures. Only native-only apps require GTK, and
## WebKitGTK is loaded when a page window is first created.

import std/[dynlib, os, strutils]

import ../contract

type
  GList* {.bycopy.} = object
    data*: pointer
    next*, prev*: ptr GList

  GSList* {.bycopy.} = object
    data*: pointer
    next*: ptr GSList

  GdkRectangle* {.bycopy.} = object
    x*, y*, width*, height*: cint

  GdkRGBA* {.bycopy.} = object
    red*, green*, blue*, alpha*: cdouble

  GtkTargetEntry* {.bycopy.} = object
    target*: cstring
    flags*, info*: cuint

  PangoRectangle* {.bycopy.} = object
    x*, y*, width*, height*: cint

  CairoMatrix* {.bycopy.} = object
    xx*, yx*, xy*, yy*, x0*, y0*: cdouble

  GSourceFunc* = proc(data: pointer): cint {.cdecl.}
  GTimeoutFunc* = proc(data: pointer): cint {.cdecl.}
  GUnixFdFunc* = proc(fd: cint, condition: cint, data: pointer): cint {.cdecl.}
  GSignalHandler* = proc(instance: pointer, data: pointer) {.cdecl.}
  GAsyncReadyCallback* = proc(source: pointer, result: pointer,
                              data: pointer) {.cdecl.}

  LibGroup* = object
    name*: string
    handle*: LibHandle

# --- libraries -------------------------------------------------------------

var
  glibLib*, gobjectLib*, gioLib*, gdkLib*, gtkLib*: LibGroup
  cairoLib*, pangoLib*, pangocairoLib*, pixbufLib*: LibGroup
  webkitLib*, jscLib*, soupLib*, notifyLib*: LibGroup

  coreLoaded*, gtkLoaded*, webkitChecked*, notifyChecked*: bool
  webkitAvailable*, notifyAvailable*: bool

proc candidateNames(pattern: string): seq[string] =
  ## `pattern` may contain `|`-separated sonames.
  for part in pattern.split('|'):
    let name = part.strip
    if name.len > 0:
      result.add name

proc openFirst(names: openArray[string]): LibHandle =
  for name in names:
    result = loadLib(name)
    if result != nil:
      return

proc openGroup(pattern: string): LibGroup =
  for name in candidateNames(pattern):
    let handle = loadLib(name)
    if handle != nil:
      return LibGroup(name: name, handle: handle)

proc loadFailed(pattern: string): ref BackendError =
  newException(BackendError,
    "Linux backend: cannot load " & pattern &
    " (install the corresponding GTK3/WebKitGTK runtime packages)")

template mustBind(dst: untyped, lib: LibHandle, symbol: string) =
  dst = cast[typeof(dst)](symAddr(lib, symbol.cstring))
  if dst == nil:
    raise newException(BackendError,
      "Linux backend: a runtime library is too old; symbol " & symbol &
      " is missing")

template bindOptional(dst: untyped, lib: LibHandle, symbol: string) =
  dst = cast[typeof(dst)](symAddr(lib, symbol.cstring))

# --- GLib ------------------------------------------------------------------

var
  g_free*: proc(mem: pointer) {.cdecl.}
  g_malloc0*: proc(size: csize_t): pointer {.cdecl.}
  g_list_free*: proc(list: ptr GList) {.cdecl.}
  g_slist_free*: proc(list: ptr GSList) {.cdecl.}
  g_object_unref*: proc(obj: pointer) {.cdecl.}
  g_object_ref*: proc(obj: pointer): pointer {.cdecl.}
  g_object_set*: proc(obj: pointer, firstProperty: cstring) {.cdecl, varargs.}
  g_signal_connect_data*: proc(instance: pointer, signalName: cstring,
                               handler: pointer, data: pointer,
                               destroy: pointer, flags: cuint): culong {.cdecl.}
  g_idle_add*: proc(fn: GSourceFunc, data: pointer): cuint {.cdecl.}
  g_source_remove*: proc(id: cuint): cint {.cdecl.}
  g_timeout_add*: proc(interval: cuint, fn: GTimeoutFunc,
                       data: pointer): cuint {.cdecl.}
  g_main_context_default*: proc(): pointer {.cdecl.}
  g_main_context_iteration*: proc(ctx: pointer, mayBlock: cint): cint {.cdecl.}
  g_main_context_wakeup*: proc(ctx: pointer) {.cdecl.}
  g_unix_fd_add*: proc(fd: cint, condition: cint, fn: GUnixFdFunc,
                       data: pointer): cuint {.cdecl.}
  g_utf8_validate*: proc(text: cstring, length: int, endPos: ptr cstring): cint {.cdecl.}

# --- GTK -------------------------------------------------------------------

var
  gtk_init_check*: proc(argc: ptr cint, argv: ptr pointer): cint {.cdecl.}
  gtk_main*: proc() {.cdecl.}
  gtk_main_quit*: proc() {.cdecl.}
  gtk_main_level*: proc(): cuint {.cdecl.}
  gtk_window_new*: proc(kind: cint): pointer {.cdecl.}
  gtk_window_set_title*: proc(window: pointer, title: cstring) {.cdecl.}
  gtk_window_set_default_size*: proc(window: pointer, width, height: cint) {.cdecl.}
  gtk_window_resize*: proc(window: pointer, width, height: cint) {.cdecl.}
  gtk_window_move*: proc(window: pointer, x, y: cint) {.cdecl.}
  gtk_window_get_size*: proc(window: pointer, width, height: ptr cint) {.cdecl.}
  gtk_window_get_position*: proc(window: pointer, x, y: ptr cint) {.cdecl.}
  gtk_window_present*: proc(window: pointer) {.cdecl.}
  gtk_window_iconify*: proc(window: pointer) {.cdecl.}
  gtk_window_deiconify*: proc(window: pointer) {.cdecl.}
  gtk_window_maximize*: proc(window: pointer) {.cdecl.}
  gtk_window_unmaximize*: proc(window: pointer) {.cdecl.}
  gtk_window_fullscreen*: proc(window: pointer) {.cdecl.}
  gtk_window_unfullscreen*: proc(window: pointer) {.cdecl.}
  gtk_window_is_maximized*: proc(window: pointer): cint {.cdecl.}
  gtk_window_is_active*: proc(window: pointer): cint {.cdecl.}
  gtk_window_set_keep_above*: proc(window: pointer, setting: cint) {.cdecl.}
  gtk_window_set_resizable*: proc(window: pointer, resizable: cint) {.cdecl.}
  gtk_window_set_decorated*: proc(window: pointer, decorated: cint) {.cdecl.}
  gtk_window_set_position*: proc(window: pointer, position: cint) {.cdecl.}
  gtk_window_close*: proc(window: pointer) {.cdecl.}
  gtk_window_set_transient_for*: proc(window, parent: pointer) {.cdecl.}
  gtk_window_set_modal*: proc(window: pointer, modal: cint) {.cdecl.}
  gtk_window_add_accel_group*: proc(window, group: pointer) {.cdecl.}
  gtk_window_remove_accel_group*: proc(window, group: pointer) {.cdecl.}
  gtk_widget_show_all*: proc(widget: pointer) {.cdecl.}
  gtk_widget_show*: proc(widget: pointer) {.cdecl.}
  gtk_widget_hide*: proc(widget: pointer) {.cdecl.}
  gtk_widget_destroy*: proc(widget: pointer) {.cdecl.}
  gtk_widget_queue_draw*: proc(widget: pointer) {.cdecl.}
  gtk_widget_grab_focus*: proc(widget: pointer) {.cdecl.}
  gtk_widget_has_focus*: proc(widget: pointer): cint {.cdecl.}
  gtk_widget_get_window*: proc(widget: pointer): pointer {.cdecl.}
  gtk_widget_get_allocated_width*: proc(widget: pointer): cint {.cdecl.}
  gtk_widget_get_allocated_height*: proc(widget: pointer): cint {.cdecl.}
  gtk_widget_add_events*: proc(widget: pointer, events: cint) {.cdecl.}
  gtk_widget_set_can_focus*: proc(widget: pointer, canFocus: cint) {.cdecl.}
  gtk_widget_set_sensitive*: proc(widget: pointer, sensitive: cint) {.cdecl.}
  gtk_widget_get_sensitive*: proc(widget: pointer): cint {.cdecl.}
  gtk_widget_get_visible*: proc(widget: pointer): cint {.cdecl.}
  gtk_widget_get_style_context*: proc(widget: pointer): pointer {.cdecl.}
  gtk_widget_add_accelerator*: proc(widget: pointer, signalName: cstring,
                                    group: pointer, key: cuint,
                                    modifiers: cuint, flags: cuint) {.cdecl.}
  gtk_drawing_area_new*: proc(): pointer {.cdecl.}
  gtk_container_add*: proc(container, child: pointer) {.cdecl.}
  gtk_box_new*: proc(orientation, spacing: cint): pointer {.cdecl.}
  gtk_box_pack_start*: proc(box, child: pointer, expand, fill: cint,
                            padding: cuint) {.cdecl.}
  gtk_box_reorder_child*: proc(box, child: pointer, position: cint) {.cdecl.}
  gtk_menu_bar_new*: proc(): pointer {.cdecl.}
  gtk_menu_new*: proc(): pointer {.cdecl.}
  gtk_menu_item_new_with_label*: proc(label: cstring): pointer {.cdecl.}
  gtk_check_menu_item_new_with_label*: proc(label: cstring): pointer {.cdecl.}
  gtk_separator_menu_item_new*: proc(): pointer {.cdecl.}
  gtk_menu_item_set_submenu*: proc(item, submenu: pointer) {.cdecl.}
  gtk_menu_shell_append*: proc(shell, child: pointer) {.cdecl.}
  gtk_check_menu_item_set_active*: proc(item: pointer, active: cint) {.cdecl.}
  gtk_check_menu_item_get_active*: proc(item: pointer): cint {.cdecl.}
  gtk_menu_item_activate*: proc(item: pointer) {.cdecl.}
  gtk_accel_group_new*: proc(): pointer {.cdecl.}
  gtk_settings_get_default*: proc(): pointer {.cdecl.}
  gtk_style_context_get_color*: proc(context: pointer, state: cuint,
                                     color: ptr GdkRGBA) {.cdecl.}
  gtk_style_context_get_background_color*: proc(context: pointer, state: cuint,
                                                color: ptr GdkRGBA) {.cdecl.}
  gtk_file_chooser_native_new*: proc(title: cstring, parent: pointer,
                                     action: cint, acceptLabel,
                                     cancelLabel: cstring): pointer {.cdecl.}
  gtk_native_dialog_run*: proc(dialog: pointer): cint {.cdecl.}
  gtk_native_dialog_destroy*: proc(dialog: pointer) {.cdecl.}
  gtk_file_chooser_set_current_folder*: proc(chooser: pointer,
                                             folder: cstring): cint {.cdecl.}
  gtk_file_chooser_set_current_name*: proc(chooser: pointer, name: cstring) {.cdecl.}
  gtk_file_chooser_set_select_multiple*: proc(chooser: pointer,
                                              multiple: cint) {.cdecl.}
  gtk_file_chooser_get_filename*: proc(chooser: pointer): cstring {.cdecl.}
  gtk_file_chooser_get_filenames*: proc(chooser: pointer): ptr GSList {.cdecl.}
  gtk_file_chooser_add_filter*: proc(chooser, filter: pointer) {.cdecl.}
  gtk_file_filter_new*: proc(): pointer {.cdecl.}
  gtk_file_filter_set_name*: proc(filter: pointer, name: cstring) {.cdecl.}
  gtk_file_filter_add_pattern*: proc(filter: pointer, pattern: cstring) {.cdecl.}
  gtk_dialog_new*: proc(): pointer {.cdecl.}
  gtk_dialog_add_button*: proc(dialog: pointer, label: cstring,
                                response: cint): pointer {.cdecl.}
  gtk_dialog_run*: proc(dialog: pointer): cint {.cdecl.}
  gtk_dialog_get_content_area*: proc(dialog: pointer): pointer {.cdecl.}
  gtk_label_new*: proc(text: cstring): pointer {.cdecl.}
  gtk_label_set_line_wrap*: proc(label: pointer, wrap: cint) {.cdecl.}
  gtk_label_set_max_width_chars*: proc(label: pointer, count: cint) {.cdecl.}
  gtk_clipboard_get*: proc(selection: pointer): pointer {.cdecl.}
  gtk_clipboard_set_text*: proc(clipboard: pointer, text: cstring,
                                length: cint) {.cdecl.}
  gtk_clipboard_wait_for_text*: proc(clipboard: pointer): cstring {.cdecl.}
  gtk_clipboard_clear*: proc(clipboard: pointer) {.cdecl.}
  gtk_clipboard_wait_for_contents*: proc(clipboard, target: pointer): pointer {.cdecl.}
  gtk_clipboard_set_with_data*: proc(clipboard: pointer,
                                     targets: ptr GtkTargetEntry,
                                     count: cuint, getFunc: pointer,
                                     clearFunc: pointer, data: pointer): cint {.cdecl.}
  gtk_selection_data_set*: proc(data: pointer, typ: pointer, format: cint,
                                bytes: ptr uint8, length: cint): cint {.cdecl.}
  gtk_selection_data_get_data*: proc(data: pointer): ptr uint8 {.cdecl.}
  gtk_selection_data_get_length*: proc(data: pointer): cint {.cdecl.}
  gtk_selection_data_free*: proc(data: pointer) {.cdecl.}

# --- GDK -------------------------------------------------------------------

var
  gdk_screen_get_default*: proc(): pointer {.cdecl.}
  gdk_screen_get_n_monitors*: proc(screen: pointer): cint {.cdecl.}
  gdk_screen_get_monitor_geometry*: proc(screen: pointer, monitor: cint,
                                         rect: ptr GdkRectangle) {.cdecl.}
  gdk_screen_get_monitor_workarea*: proc(screen: pointer, monitor: cint,
                                         rect: ptr GdkRectangle) {.cdecl.}
  gdk_screen_get_monitor_scale_factor*: proc(screen: pointer,
                                             monitor: cint): cint {.cdecl.}
  gdk_screen_get_primary_monitor*: proc(screen: pointer): cint {.cdecl.}
  gdk_screen_get_monitor_model*: proc(screen: pointer, monitor: cint): cstring {.cdecl.}
  gdk_screen_get_monitor_plug_name*: proc(screen: pointer, monitor: cint): cstring {.cdecl.}
  gdk_screen_get_display*: proc(screen: pointer): pointer {.cdecl.}
  gdk_display_get_default*: proc(): pointer {.cdecl.}
  gdk_display_get_default_seat*: proc(display: pointer): pointer {.cdecl.}
  gdk_seat_get_pointer*: proc(seat: pointer): pointer {.cdecl.}
  gdk_device_get_position*: proc(device: pointer, screen: ptr pointer,
                                 x, y: ptr cint): cint {.cdecl.}
  gdk_event_get_event_type*: proc(event: pointer): cint {.cdecl.}
  gdk_event_get_coords*: proc(event: pointer, x, y: ptr cdouble): cint {.cdecl.}
  gdk_event_get_keyval*: proc(event: pointer, keyval: ptr cuint): cint {.cdecl.}
  gdk_event_get_state*: proc(event: pointer, state: ptr cuint): cint {.cdecl.}
  gdk_event_get_scroll_deltas*: proc(event: pointer, dx, dy: ptr cdouble): cint {.cdecl.}
  gdk_event_get_scroll_direction*: proc(event: pointer,
                                        direction: ptr cint): cint {.cdecl.}
  gdk_event_get_button*: proc(event: pointer, button: ptr cuint): cint {.cdecl.}
  gdk_keyval_name*: proc(keyval: cuint): cstring {.cdecl.}
  gdk_keyval_to_unicode*: proc(keyval: cuint): uint32 {.cdecl.}
  gdk_unicode_to_keyval*: proc(wc: uint32): cuint {.cdecl.}
  gdk_atom_intern*: proc(name: cstring, onlyIfExists: cint): pointer {.cdecl.}
  gdk_window_get_state*: proc(window: pointer): cint {.cdecl.}
  gdk_window_get_scale_factor*: proc(window: pointer): cint {.cdecl.}
  gdk_window_is_visible*: proc(window: pointer): cint {.cdecl.}

# --- Pango / Cairo / GdkPixbuf --------------------------------------------

var
  pango_font_description_new*: proc(): pointer {.cdecl.}
  pango_font_description_free*: proc(desc: pointer) {.cdecl.}
  pango_font_description_set_family*: proc(desc: pointer, family: cstring) {.cdecl.}
  pango_font_description_set_absolute_size*: proc(desc: pointer, size: cdouble) {.cdecl.}
  pango_font_description_set_weight*: proc(desc: pointer, weight: cint) {.cdecl.}
  pango_cairo_create_layout*: proc(cr: pointer): pointer {.cdecl.}
  pango_cairo_update_layout*: proc(cr, layout: pointer) {.cdecl.}
  pango_cairo_show_layout*: proc(cr, layout: pointer) {.cdecl.}
  pango_layout_set_text*: proc(layout: pointer, text: cstring, length: cint) {.cdecl.}
  pango_layout_set_font_description*: proc(layout, desc: pointer) {.cdecl.}
  pango_layout_set_single_paragraph_mode*: proc(layout: pointer, setting: cint) {.cdecl.}
  pango_layout_set_width*: proc(layout: pointer, width: cint) {.cdecl.}
  pango_layout_get_extents*: proc(layout: pointer, ink: ptr PangoRectangle,
                                  logical: ptr PangoRectangle) {.cdecl.}
  pango_layout_get_baseline*: proc(layout: pointer): cint {.cdecl.}
  pango_layout_get_context*: proc(layout: pointer): pointer {.cdecl.}
  pango_context_get_metrics*: proc(context, desc, language: pointer): pointer {.cdecl.}
  pango_font_metrics_get_ascent*: proc(metrics: pointer): cint {.cdecl.}
  pango_font_metrics_get_descent*: proc(metrics: pointer): cint {.cdecl.}
  pango_font_metrics_get_height*: proc(metrics: pointer): cint {.cdecl.}
  pango_font_metrics_unref*: proc(metrics: pointer) {.cdecl.}

  cairo_image_surface_create*: proc(format: cint, width, height: cint): pointer {.cdecl.}
  cairo_create*: proc(target: pointer): pointer {.cdecl.}
  cairo_destroy*: proc(cr: pointer) {.cdecl.}
  cairo_surface_destroy*: proc(surface: pointer) {.cdecl.}
  cairo_surface_write_to_png*: proc(surface: pointer, filename: cstring): cint {.cdecl.}
  cairo_surface_flush*: proc(surface: pointer) {.cdecl.}
  cairo_surface_mark_dirty*: proc(surface: pointer) {.cdecl.}
  cairo_surface_status*: proc(surface: pointer): cint {.cdecl.}
  cairo_image_surface_get_data*: proc(surface: pointer): ptr uint8 {.cdecl.}
  cairo_image_surface_get_stride*: proc(surface: pointer): cint {.cdecl.}
  cairo_image_surface_get_width*: proc(surface: pointer): cint {.cdecl.}
  cairo_image_surface_get_height*: proc(surface: pointer): cint {.cdecl.}
  cairo_set_source_rgba*: proc(cr: pointer, r, g, b, a: cdouble) {.cdecl.}
  cairo_rectangle*: proc(cr: pointer, x, y, width, height: cdouble) {.cdecl.}
  cairo_fill*: proc(cr: pointer) {.cdecl.}
  cairo_paint*: proc(cr: pointer) {.cdecl.}
  cairo_save*: proc(cr: pointer) {.cdecl.}
  cairo_restore*: proc(cr: pointer) {.cdecl.}
  cairo_clip*: proc(cr: pointer) {.cdecl.}
  cairo_new_path*: proc(cr: pointer) {.cdecl.}
  cairo_new_sub_path*: proc(cr: pointer) {.cdecl.}
  cairo_move_to*: proc(cr: pointer, x, y: cdouble) {.cdecl.}
  cairo_line_to*: proc(cr: pointer, x, y: cdouble) {.cdecl.}
  cairo_close_path*: proc(cr: pointer) {.cdecl.}
  cairo_arc*: proc(cr: pointer, xc, yc, radius, angle1, angle2: cdouble) {.cdecl.}
  cairo_translate*: proc(cr: pointer, x, y: cdouble) {.cdecl.}
  cairo_scale*: proc(cr: pointer, sx, sy: cdouble) {.cdecl.}
  cairo_transform*: proc(cr: pointer, matrix: ptr CairoMatrix) {.cdecl.}
  cairo_set_matrix*: proc(cr: pointer, matrix: ptr CairoMatrix) {.cdecl.}
  cairo_identity_matrix*: proc(cr: pointer) {.cdecl.}
  cairo_set_source_surface*: proc(cr, surface: pointer, x, y: cdouble) {.cdecl.}
  cairo_pattern_create_for_surface*: proc(surface: pointer): pointer {.cdecl.}
  cairo_pattern_set_matrix*: proc(pattern: pointer, matrix: ptr CairoMatrix) {.cdecl.}
  cairo_pattern_set_filter*: proc(pattern: pointer, filter: cint) {.cdecl.}
  cairo_set_source*: proc(cr, pattern: pointer) {.cdecl.}
  cairo_pattern_destroy*: proc(pattern: pointer) {.cdecl.}
  cairo_paint_with_alpha*: proc(cr: pointer, alpha: cdouble) {.cdecl.}

  gdk_pixbuf_new_from_file*: proc(filename: cstring, error: ptr pointer): pointer {.cdecl.}
  gdk_pixbuf_new_subpixbuf*: proc(src: pointer, x, y, width, height: cint): pointer {.cdecl.}
  gdk_pixbuf_get_width*: proc(pixbuf: pointer): cint {.cdecl.}
  gdk_pixbuf_get_height*: proc(pixbuf: pointer): cint {.cdecl.}
  gdk_pixbuf_get_n_channels*: proc(pixbuf: pointer): cint {.cdecl.}
  gdk_pixbuf_get_rowstride*: proc(pixbuf: pointer): cint {.cdecl.}
  gdk_pixbuf_get_pixels*: proc(pixbuf: pointer): ptr uint8 {.cdecl.}
  gdk_pixbuf_get_has_alpha*: proc(pixbuf: pointer): cint {.cdecl.}
  gdk_pixbuf_unref*: proc(pixbuf: pointer) {.cdecl.}

# --- WebKitGTK -------------------------------------------------------------

var
  webkit_user_content_manager_new*: proc(): pointer {.cdecl.}
  webkit_user_content_manager_register_script_message_handler*:
    proc(manager: pointer, name: cstring): cint {.cdecl.}
  webkit_user_script_new*: proc(source: cstring, injectedFrames, injectionTime: cint,
                                allowList, blockList: ptr cstring): pointer {.cdecl.}
  webkit_user_script_unref*: proc(script: pointer) {.cdecl.}
  webkit_user_content_manager_add_script*: proc(manager, script: pointer) {.cdecl.}
  webkit_web_view_new_with_user_content_manager*: proc(manager: pointer): pointer {.cdecl.}
  webkit_web_view_load_html*: proc(view: pointer, content, baseUri: cstring) {.cdecl.}
  webkit_web_view_load_uri*: proc(view: pointer, uri: cstring) {.cdecl.}
  webkit_web_view_evaluate_javascript*: proc(view: pointer, script: cstring,
                                             length: int64, worldName,
                                             sourceUri: cstring,
                                             cancellable: pointer,
                                             callback: GAsyncReadyCallback,
                                             data: pointer) {.cdecl.}
  webkit_web_view_evaluate_javascript_finish*: proc(view, result: pointer,
                                                    error: ptr pointer): pointer {.cdecl.}
  webkit_web_view_get_title*: proc(view: pointer): cstring {.cdecl.}
  webkit_web_context_get_default*: proc(): pointer {.cdecl.}
  webkit_web_context_register_uri_scheme*: proc(context: pointer, scheme: cstring,
                                                callback: pointer, data: pointer,
                                                destroy: pointer) {.cdecl.}
  webkit_web_context_get_security_manager*: proc(context: pointer): pointer {.cdecl.}
  webkit_security_manager_register_uri_scheme_as_secure*: proc(manager: pointer,
                                                               scheme: cstring) {.cdecl.}
  webkit_security_manager_register_uri_scheme_as_cors_enabled*:
    proc(manager: pointer, scheme: cstring) {.cdecl.}
  webkit_uri_scheme_request_get_uri*: proc(request: pointer): cstring {.cdecl.}
  webkit_uri_scheme_request_finish*: proc(request, stream: pointer, length: int64,
                                          contentType: cstring) {.cdecl.}
  webkit_javascript_result_get_js_value*: proc(result: pointer): pointer {.cdecl.}
  jsc_value_to_string*: proc(value: pointer): cstring {.cdecl.}
  webkit_web_context_get_cookie_manager*: proc(context: pointer): pointer {.cdecl.}
  webkit_cookie_manager_add_cookie*: proc(manager, cookie: pointer,
                                          cancellable: pointer,
                                          callback: GAsyncReadyCallback,
                                          data: pointer) {.cdecl.}
  webkit_cookie_manager_get_all_cookies*: proc(manager: pointer,
                                                cancellable: pointer,
                                                callback: GAsyncReadyCallback,
                                                data: pointer) {.cdecl.}
  soup_cookie_new*: proc(name, value, domain, path: cstring,
                         maxAge: cint): pointer {.cdecl.}
  webkit_cookie_manager_get_all_cookies_finish*: proc(manager, result: pointer,
                                                      error: ptr pointer): ptr GList {.cdecl.}
  webkit_cookie_manager_delete_all_cookies*: proc(manager: pointer) {.cdecl.}
  soup_cookie_get_name*: proc(cookie: pointer): cstring {.cdecl.}
  soup_cookie_get_value*: proc(cookie: pointer): cstring {.cdecl.}
  soup_cookie_get_domain*: proc(cookie: pointer): cstring {.cdecl.}
  soup_cookie_get_path*: proc(cookie: pointer): cstring {.cdecl.}
  soup_cookie_get_secure*: proc(cookie: pointer): cint {.cdecl.}
  soup_cookie_get_http_only*: proc(cookie: pointer): cint {.cdecl.}
  soup_cookie_free*: proc(cookie: pointer) {.cdecl.}
  g_memory_input_stream_new_from_bytes*: proc(bytes: pointer): pointer {.cdecl.}
  g_bytes_new*: proc(data: pointer, size: csize_t): pointer {.cdecl.}
  g_bytes_unref*: proc(bytes: pointer) {.cdecl.}

# --- libnotify -------------------------------------------------------------

var
  notify_init*: proc(appName: cstring): cint {.cdecl.}
  notify_uninit*: proc() {.cdecl.}
  notify_notification_new*: proc(summary, body, icon: cstring): pointer {.cdecl.}
  notify_notification_show*: proc(notification: pointer, error: ptr pointer): cint {.cdecl.}

# --- loading ---------------------------------------------------------------

proc ensureCore*() =
  ## Loads Cairo, Pango and GdkPixbuf. Required by layout and offscreen
  ## rendering, including headless `Tester` tests.
  if coreLoaded:
    return
  glibLib = openGroup("libglib-2.0.so.0|libglib-2.0.so")
  if glibLib.handle == nil:
    raise loadFailed("libglib-2.0.so.0")
  mustBind(g_free, glibLib.handle, "g_free")
  mustBind(g_malloc0, glibLib.handle, "g_malloc0")
  gobjectLib = openGroup("libgobject-2.0.so.0|libgobject-2.0.so")
  if gobjectLib.handle == nil:
    raise loadFailed("libgobject-2.0.so.0")
  mustBind(g_object_unref, gobjectLib.handle, "g_object_unref")
  mustBind(g_object_ref, gobjectLib.handle, "g_object_ref")
  cairoLib = openGroup("libcairo.so.2|libcairo.so")
  if cairoLib.handle == nil:
    raise loadFailed("libcairo.so.2")
  pangoLib = openGroup("libpango-1.0.so.0|libpango-1.0.so")
  if pangoLib.handle == nil:
    raise loadFailed("libpango-1.0.so.0")
  pangocairoLib = openGroup("libpangocairo-1.0.so.0|libpangocairo-1.0.so")
  if pangocairoLib.handle == nil:
    raise loadFailed("libpangocairo-1.0.so.0")
  pixbufLib = openGroup("libgdk_pixbuf-2.0.so.0|libgdk_pixbuf-2.0.so")
  if pixbufLib.handle == nil:
    raise loadFailed("libgdk_pixbuf-2.0.so.0")

  mustBind(cairo_image_surface_create, cairoLib.handle, "cairo_image_surface_create")
  mustBind(cairo_create, cairoLib.handle, "cairo_create")
  mustBind(cairo_destroy, cairoLib.handle, "cairo_destroy")
  mustBind(cairo_surface_destroy, cairoLib.handle, "cairo_surface_destroy")
  mustBind(cairo_surface_write_to_png, cairoLib.handle, "cairo_surface_write_to_png")
  mustBind(cairo_surface_flush, cairoLib.handle, "cairo_surface_flush")
  mustBind(cairo_surface_mark_dirty, cairoLib.handle, "cairo_surface_mark_dirty")
  mustBind(cairo_surface_status, cairoLib.handle, "cairo_surface_status")
  mustBind(cairo_image_surface_get_data, cairoLib.handle, "cairo_image_surface_get_data")
  mustBind(cairo_image_surface_get_stride, cairoLib.handle, "cairo_image_surface_get_stride")
  mustBind(cairo_image_surface_get_width, cairoLib.handle, "cairo_image_surface_get_width")
  mustBind(cairo_image_surface_get_height, cairoLib.handle, "cairo_image_surface_get_height")
  mustBind(cairo_set_source_rgba, cairoLib.handle, "cairo_set_source_rgba")
  mustBind(cairo_rectangle, cairoLib.handle, "cairo_rectangle")
  mustBind(cairo_fill, cairoLib.handle, "cairo_fill")
  mustBind(cairo_paint, cairoLib.handle, "cairo_paint")
  mustBind(cairo_save, cairoLib.handle, "cairo_save")
  mustBind(cairo_restore, cairoLib.handle, "cairo_restore")
  mustBind(cairo_clip, cairoLib.handle, "cairo_clip")
  mustBind(cairo_new_path, cairoLib.handle, "cairo_new_path")
  mustBind(cairo_new_sub_path, cairoLib.handle, "cairo_new_sub_path")
  mustBind(cairo_move_to, cairoLib.handle, "cairo_move_to")
  mustBind(cairo_line_to, cairoLib.handle, "cairo_line_to")
  mustBind(cairo_close_path, cairoLib.handle, "cairo_close_path")
  mustBind(cairo_arc, cairoLib.handle, "cairo_arc")
  mustBind(cairo_translate, cairoLib.handle, "cairo_translate")
  mustBind(cairo_scale, cairoLib.handle, "cairo_scale")
  mustBind(cairo_transform, cairoLib.handle, "cairo_transform")
  mustBind(cairo_set_matrix, cairoLib.handle, "cairo_set_matrix")
  mustBind(cairo_identity_matrix, cairoLib.handle, "cairo_identity_matrix")
  mustBind(cairo_set_source_surface, cairoLib.handle, "cairo_set_source_surface")
  mustBind(cairo_pattern_create_for_surface, cairoLib.handle, "cairo_pattern_create_for_surface")
  mustBind(cairo_pattern_set_matrix, cairoLib.handle, "cairo_pattern_set_matrix")
  mustBind(cairo_pattern_set_filter, cairoLib.handle, "cairo_pattern_set_filter")
  mustBind(cairo_set_source, cairoLib.handle, "cairo_set_source")
  mustBind(cairo_pattern_destroy, cairoLib.handle, "cairo_pattern_destroy")
  mustBind(cairo_paint_with_alpha, cairoLib.handle, "cairo_paint_with_alpha")

  mustBind(pango_font_description_new, pangoLib.handle, "pango_font_description_new")
  mustBind(pango_font_description_free, pangoLib.handle, "pango_font_description_free")
  mustBind(pango_font_description_set_family, pangoLib.handle, "pango_font_description_set_family")
  mustBind(pango_font_description_set_absolute_size, pangoLib.handle, "pango_font_description_set_absolute_size")
  mustBind(pango_font_description_set_weight, pangoLib.handle, "pango_font_description_set_weight")
  mustBind(pango_layout_set_text, pangoLib.handle, "pango_layout_set_text")
  mustBind(pango_layout_set_font_description, pangoLib.handle, "pango_layout_set_font_description")
  mustBind(pango_layout_set_single_paragraph_mode, pangoLib.handle, "pango_layout_set_single_paragraph_mode")
  mustBind(pango_layout_set_width, pangoLib.handle, "pango_layout_set_width")
  mustBind(pango_layout_get_extents, pangoLib.handle, "pango_layout_get_extents")
  mustBind(pango_layout_get_baseline, pangoLib.handle, "pango_layout_get_baseline")
  mustBind(pango_layout_get_context, pangoLib.handle, "pango_layout_get_context")
  mustBind(pango_context_get_metrics, pangoLib.handle, "pango_context_get_metrics")
  mustBind(pango_font_metrics_get_ascent, pangoLib.handle, "pango_font_metrics_get_ascent")
  mustBind(pango_font_metrics_get_descent, pangoLib.handle, "pango_font_metrics_get_descent")
  bindOptional(pango_font_metrics_get_height, pangoLib.handle, "pango_font_metrics_get_height")
  mustBind(pango_font_metrics_unref, pangoLib.handle, "pango_font_metrics_unref")

  mustBind(pango_cairo_create_layout, pangocairoLib.handle, "pango_cairo_create_layout")
  mustBind(pango_cairo_update_layout, pangocairoLib.handle, "pango_cairo_update_layout")
  mustBind(pango_cairo_show_layout, pangocairoLib.handle, "pango_cairo_show_layout")

  mustBind(gdk_pixbuf_new_from_file, pixbufLib.handle, "gdk_pixbuf_new_from_file")
  mustBind(gdk_pixbuf_new_subpixbuf, pixbufLib.handle, "gdk_pixbuf_new_subpixbuf")
  mustBind(gdk_pixbuf_get_width, pixbufLib.handle, "gdk_pixbuf_get_width")
  mustBind(gdk_pixbuf_get_height, pixbufLib.handle, "gdk_pixbuf_get_height")
  mustBind(gdk_pixbuf_get_n_channels, pixbufLib.handle, "gdk_pixbuf_get_n_channels")
  mustBind(gdk_pixbuf_get_rowstride, pixbufLib.handle, "gdk_pixbuf_get_rowstride")
  mustBind(gdk_pixbuf_get_pixels, pixbufLib.handle, "gdk_pixbuf_get_pixels")
  mustBind(gdk_pixbuf_get_has_alpha, pixbufLib.handle, "gdk_pixbuf_get_has_alpha")
  bindOptional(gdk_pixbuf_unref, pixbufLib.handle, "gdk_pixbuf_unref")

  coreLoaded = true

proc ensureGtk*() =
  ## Loads GTK3 and its GObject/GDK dependencies. Call before any window or
  ## desktop API operation.
  if gtkLoaded:
    return
  ensureCore()
  if gobjectLib.handle == nil:
    gobjectLib = openGroup("libgobject-2.0.so.0|libgobject-2.0.so")
  if gobjectLib.handle == nil:
    raise loadFailed("libgobject-2.0.so.0")
  glibLib = openGroup("libglib-2.0.so.0|libglib-2.0.so")
  if glibLib.handle == nil:
    raise loadFailed("libglib-2.0.so.0")
  gobjectLib = openGroup("libgobject-2.0.so.0|libgobject-2.0.so")
  if gobjectLib.handle == nil:
    raise loadFailed("libgobject-2.0.so.0")
  gioLib = openGroup("libgio-2.0.so.0|libgio-2.0.so")
  if gioLib.handle == nil:
    raise loadFailed("libgio-2.0.so.0")
  gdkLib = openGroup("libgdk-3.so.0|libgdk-3.so")
  if gdkLib.handle == nil:
    raise loadFailed("libgdk-3.so.0")
  gtkLib = openGroup("libgtk-3.so.0|libgtk-3.so")
  if gtkLib.handle == nil:
    raise loadFailed("libgtk-3.so.0")

  mustBind(g_free, glibLib.handle, "g_free")
  mustBind(g_malloc0, glibLib.handle, "g_malloc0")
  mustBind(g_list_free, glibLib.handle, "g_list_free")
  mustBind(g_slist_free, glibLib.handle, "g_slist_free")
  mustBind(g_idle_add, glibLib.handle, "g_idle_add")
  mustBind(g_source_remove, glibLib.handle, "g_source_remove")
  mustBind(g_timeout_add, glibLib.handle, "g_timeout_add")
  mustBind(g_main_context_default, glibLib.handle, "g_main_context_default")
  mustBind(g_main_context_iteration, glibLib.handle, "g_main_context_iteration")
  mustBind(g_main_context_wakeup, glibLib.handle, "g_main_context_wakeup")
  mustBind(g_unix_fd_add, glibLib.handle, "g_unix_fd_add")
  bindOptional(g_utf8_validate, glibLib.handle, "g_utf8_validate")
  mustBind(g_bytes_new, glibLib.handle, "g_bytes_new")
  mustBind(g_bytes_unref, glibLib.handle, "g_bytes_unref")

  mustBind(g_object_unref, gobjectLib.handle, "g_object_unref")
  mustBind(g_object_ref, gobjectLib.handle, "g_object_ref")
  mustBind(g_object_set, gobjectLib.handle, "g_object_set")
  mustBind(g_signal_connect_data, gobjectLib.handle, "g_signal_connect_data")
  mustBind(g_memory_input_stream_new_from_bytes, gioLib.handle,
           "g_memory_input_stream_new_from_bytes")

  mustBind(gdk_screen_get_default, gdkLib.handle, "gdk_screen_get_default")
  mustBind(gdk_screen_get_n_monitors, gdkLib.handle, "gdk_screen_get_n_monitors")
  mustBind(gdk_screen_get_monitor_geometry, gdkLib.handle, "gdk_screen_get_monitor_geometry")
  mustBind(gdk_screen_get_monitor_workarea, gdkLib.handle, "gdk_screen_get_monitor_workarea")
  mustBind(gdk_screen_get_monitor_scale_factor, gdkLib.handle, "gdk_screen_get_monitor_scale_factor")
  mustBind(gdk_screen_get_primary_monitor, gdkLib.handle, "gdk_screen_get_primary_monitor")
  bindOptional(gdk_screen_get_monitor_model, gdkLib.handle, "gdk_screen_get_monitor_model")
  bindOptional(gdk_screen_get_monitor_plug_name, gdkLib.handle, "gdk_screen_get_monitor_plug_name")
  mustBind(gdk_screen_get_display, gdkLib.handle, "gdk_screen_get_display")
  mustBind(gdk_display_get_default, gdkLib.handle, "gdk_display_get_default")
  mustBind(gdk_display_get_default_seat, gdkLib.handle, "gdk_display_get_default_seat")
  mustBind(gdk_seat_get_pointer, gdkLib.handle, "gdk_seat_get_pointer")
  mustBind(gdk_device_get_position, gdkLib.handle, "gdk_device_get_position")
  mustBind(gdk_event_get_event_type, gdkLib.handle, "gdk_event_get_event_type")
  mustBind(gdk_event_get_coords, gdkLib.handle, "gdk_event_get_coords")
  mustBind(gdk_event_get_keyval, gdkLib.handle, "gdk_event_get_keyval")
  mustBind(gdk_event_get_state, gdkLib.handle, "gdk_event_get_state")
  mustBind(gdk_event_get_scroll_deltas, gdkLib.handle, "gdk_event_get_scroll_deltas")
  mustBind(gdk_event_get_scroll_direction, gdkLib.handle, "gdk_event_get_scroll_direction")
  mustBind(gdk_event_get_button, gdkLib.handle, "gdk_event_get_button")
  mustBind(gdk_keyval_name, gdkLib.handle, "gdk_keyval_name")
  mustBind(gdk_keyval_to_unicode, gdkLib.handle, "gdk_keyval_to_unicode")
  mustBind(gdk_unicode_to_keyval, gdkLib.handle, "gdk_unicode_to_keyval")
  mustBind(gdk_atom_intern, gdkLib.handle, "gdk_atom_intern")
  mustBind(gdk_window_get_state, gdkLib.handle, "gdk_window_get_state")
  mustBind(gdk_window_get_scale_factor, gdkLib.handle, "gdk_window_get_scale_factor")
  mustBind(gdk_window_is_visible, gdkLib.handle, "gdk_window_is_visible")

  mustBind(gtk_init_check, gtkLib.handle, "gtk_init_check")
  mustBind(gtk_main, gtkLib.handle, "gtk_main")
  mustBind(gtk_main_quit, gtkLib.handle, "gtk_main_quit")
  mustBind(gtk_main_level, gtkLib.handle, "gtk_main_level")
  mustBind(gtk_window_new, gtkLib.handle, "gtk_window_new")
  mustBind(gtk_window_set_title, gtkLib.handle, "gtk_window_set_title")
  mustBind(gtk_window_set_default_size, gtkLib.handle, "gtk_window_set_default_size")
  mustBind(gtk_window_resize, gtkLib.handle, "gtk_window_resize")
  mustBind(gtk_window_move, gtkLib.handle, "gtk_window_move")
  mustBind(gtk_window_get_size, gtkLib.handle, "gtk_window_get_size")
  mustBind(gtk_window_get_position, gtkLib.handle, "gtk_window_get_position")
  mustBind(gtk_window_present, gtkLib.handle, "gtk_window_present")
  mustBind(gtk_window_iconify, gtkLib.handle, "gtk_window_iconify")
  mustBind(gtk_window_deiconify, gtkLib.handle, "gtk_window_deiconify")
  mustBind(gtk_window_maximize, gtkLib.handle, "gtk_window_maximize")
  mustBind(gtk_window_unmaximize, gtkLib.handle, "gtk_window_unmaximize")
  mustBind(gtk_window_fullscreen, gtkLib.handle, "gtk_window_fullscreen")
  mustBind(gtk_window_unfullscreen, gtkLib.handle, "gtk_window_unfullscreen")
  mustBind(gtk_window_is_maximized, gtkLib.handle, "gtk_window_is_maximized")
  mustBind(gtk_window_is_active, gtkLib.handle, "gtk_window_is_active")
  mustBind(gtk_window_set_keep_above, gtkLib.handle, "gtk_window_set_keep_above")
  mustBind(gtk_window_set_resizable, gtkLib.handle, "gtk_window_set_resizable")
  mustBind(gtk_window_set_decorated, gtkLib.handle, "gtk_window_set_decorated")
  mustBind(gtk_window_set_position, gtkLib.handle, "gtk_window_set_position")
  mustBind(gtk_window_close, gtkLib.handle, "gtk_window_close")
  mustBind(gtk_window_set_transient_for, gtkLib.handle, "gtk_window_set_transient_for")
  mustBind(gtk_window_set_modal, gtkLib.handle, "gtk_window_set_modal")
  mustBind(gtk_window_add_accel_group, gtkLib.handle, "gtk_window_add_accel_group")
  mustBind(gtk_window_remove_accel_group, gtkLib.handle,
           "gtk_window_remove_accel_group")
  mustBind(gtk_widget_show_all, gtkLib.handle, "gtk_widget_show_all")
  mustBind(gtk_widget_show, gtkLib.handle, "gtk_widget_show")
  mustBind(gtk_widget_hide, gtkLib.handle, "gtk_widget_hide")
  mustBind(gtk_widget_destroy, gtkLib.handle, "gtk_widget_destroy")
  mustBind(gtk_widget_queue_draw, gtkLib.handle, "gtk_widget_queue_draw")
  mustBind(gtk_widget_grab_focus, gtkLib.handle, "gtk_widget_grab_focus")
  mustBind(gtk_widget_has_focus, gtkLib.handle, "gtk_widget_has_focus")
  mustBind(gtk_widget_get_window, gtkLib.handle, "gtk_widget_get_window")
  mustBind(gtk_widget_get_allocated_width, gtkLib.handle, "gtk_widget_get_allocated_width")
  mustBind(gtk_widget_get_allocated_height, gtkLib.handle, "gtk_widget_get_allocated_height")
  mustBind(gtk_widget_add_events, gtkLib.handle, "gtk_widget_add_events")
  mustBind(gtk_widget_set_can_focus, gtkLib.handle, "gtk_widget_set_can_focus")
  mustBind(gtk_widget_set_sensitive, gtkLib.handle, "gtk_widget_set_sensitive")
  mustBind(gtk_widget_get_sensitive, gtkLib.handle, "gtk_widget_get_sensitive")
  mustBind(gtk_widget_get_visible, gtkLib.handle, "gtk_widget_get_visible")
  mustBind(gtk_widget_get_style_context, gtkLib.handle, "gtk_widget_get_style_context")
  mustBind(gtk_widget_add_accelerator, gtkLib.handle, "gtk_widget_add_accelerator")
  mustBind(gtk_drawing_area_new, gtkLib.handle, "gtk_drawing_area_new")
  mustBind(gtk_container_add, gtkLib.handle, "gtk_container_add")
  mustBind(gtk_box_new, gtkLib.handle, "gtk_box_new")
  mustBind(gtk_box_pack_start, gtkLib.handle, "gtk_box_pack_start")
  mustBind(gtk_box_reorder_child, gtkLib.handle, "gtk_box_reorder_child")
  mustBind(gtk_menu_bar_new, gtkLib.handle, "gtk_menu_bar_new")
  mustBind(gtk_menu_new, gtkLib.handle, "gtk_menu_new")
  mustBind(gtk_menu_item_new_with_label, gtkLib.handle, "gtk_menu_item_new_with_label")
  mustBind(gtk_check_menu_item_new_with_label, gtkLib.handle, "gtk_check_menu_item_new_with_label")
  mustBind(gtk_separator_menu_item_new, gtkLib.handle, "gtk_separator_menu_item_new")
  mustBind(gtk_menu_item_set_submenu, gtkLib.handle, "gtk_menu_item_set_submenu")
  mustBind(gtk_menu_shell_append, gtkLib.handle, "gtk_menu_shell_append")
  mustBind(gtk_check_menu_item_set_active, gtkLib.handle, "gtk_check_menu_item_set_active")
  mustBind(gtk_check_menu_item_get_active, gtkLib.handle, "gtk_check_menu_item_get_active")
  mustBind(gtk_menu_item_activate, gtkLib.handle, "gtk_menu_item_activate")
  mustBind(gtk_accel_group_new, gtkLib.handle, "gtk_accel_group_new")
  mustBind(gtk_settings_get_default, gtkLib.handle, "gtk_settings_get_default")
  bindOptional(gtk_style_context_get_color, gtkLib.handle, "gtk_style_context_get_color")
  bindOptional(gtk_style_context_get_background_color, gtkLib.handle,
               "gtk_style_context_get_background_color")
  mustBind(gtk_file_chooser_native_new, gtkLib.handle, "gtk_file_chooser_native_new")
  mustBind(gtk_native_dialog_run, gtkLib.handle, "gtk_native_dialog_run")
  mustBind(gtk_native_dialog_destroy, gtkLib.handle, "gtk_native_dialog_destroy")
  mustBind(gtk_file_chooser_set_current_folder, gtkLib.handle, "gtk_file_chooser_set_current_folder")
  mustBind(gtk_file_chooser_set_current_name, gtkLib.handle, "gtk_file_chooser_set_current_name")
  mustBind(gtk_file_chooser_set_select_multiple, gtkLib.handle, "gtk_file_chooser_set_select_multiple")
  mustBind(gtk_file_chooser_get_filename, gtkLib.handle, "gtk_file_chooser_get_filename")
  mustBind(gtk_file_chooser_get_filenames, gtkLib.handle, "gtk_file_chooser_get_filenames")
  mustBind(gtk_file_chooser_add_filter, gtkLib.handle, "gtk_file_chooser_add_filter")
  mustBind(gtk_file_filter_new, gtkLib.handle, "gtk_file_filter_new")
  mustBind(gtk_file_filter_set_name, gtkLib.handle, "gtk_file_filter_set_name")
  mustBind(gtk_file_filter_add_pattern, gtkLib.handle, "gtk_file_filter_add_pattern")
  mustBind(gtk_dialog_new, gtkLib.handle, "gtk_dialog_new")
  mustBind(gtk_dialog_add_button, gtkLib.handle, "gtk_dialog_add_button")
  mustBind(gtk_dialog_run, gtkLib.handle, "gtk_dialog_run")
  mustBind(gtk_dialog_get_content_area, gtkLib.handle, "gtk_dialog_get_content_area")
  mustBind(gtk_label_new, gtkLib.handle, "gtk_label_new")
  mustBind(gtk_label_set_line_wrap, gtkLib.handle, "gtk_label_set_line_wrap")
  mustBind(gtk_label_set_max_width_chars, gtkLib.handle, "gtk_label_set_max_width_chars")
  mustBind(gtk_clipboard_get, gtkLib.handle, "gtk_clipboard_get")
  mustBind(gtk_clipboard_set_text, gtkLib.handle, "gtk_clipboard_set_text")
  mustBind(gtk_clipboard_wait_for_text, gtkLib.handle, "gtk_clipboard_wait_for_text")
  mustBind(gtk_clipboard_clear, gtkLib.handle, "gtk_clipboard_clear")
  mustBind(gtk_clipboard_wait_for_contents, gtkLib.handle, "gtk_clipboard_wait_for_contents")
  mustBind(gtk_clipboard_set_with_data, gtkLib.handle, "gtk_clipboard_set_with_data")
  mustBind(gtk_selection_data_set, gtkLib.handle, "gtk_selection_data_set")
  mustBind(gtk_selection_data_get_data, gtkLib.handle, "gtk_selection_data_get_data")
  mustBind(gtk_selection_data_get_length, gtkLib.handle, "gtk_selection_data_get_length")
  mustBind(gtk_selection_data_free, gtkLib.handle, "gtk_selection_data_free")

  gtkLoaded = true

proc ensureWebKit*(): bool =
  ## Loads WebKitGTK 4.1 (preferred) or 4.0. Returns false when no WebKit
  ## runtime is installed; native-only windows still work.
  if webkitChecked:
    return webkitAvailable
  webkitChecked = true
  ensureGtk()
  webkitLib = openGroup("libwebkit2gtk-4.1.so.0|libwebkit2gtk-4.0.so.37|" &
                        "libwebkit2gtk-4.0.so")
  if webkitLib.handle == nil:
    return false
  jscLib = openGroup("libjavascriptcoregtk-4.1.so.0|" &
                     "libjavascriptcoregtk-4.0.so.37|" &
                     "libjavascriptcoregtk-4.0.so")
  if jscLib.handle == nil:
    return false
  soupLib = openGroup("libsoup-3.0.so.0|libsoup-2.4.so.1|libsoup-2.4.so.0")
  if soupLib.handle == nil:
    return false
  try:
    mustBind(webkit_user_content_manager_new, webkitLib.handle,
             "webkit_user_content_manager_new")
    mustBind(webkit_user_content_manager_register_script_message_handler,
             webkitLib.handle, "webkit_user_content_manager_register_script_message_handler")
    mustBind(webkit_user_script_new, webkitLib.handle, "webkit_user_script_new")
    mustBind(webkit_user_script_unref, webkitLib.handle, "webkit_user_script_unref")
    mustBind(webkit_user_content_manager_add_script, webkitLib.handle,
             "webkit_user_content_manager_add_script")
    mustBind(webkit_web_view_new_with_user_content_manager, webkitLib.handle,
             "webkit_web_view_new_with_user_content_manager")
    mustBind(webkit_web_view_load_html, webkitLib.handle, "webkit_web_view_load_html")
    mustBind(webkit_web_view_load_uri, webkitLib.handle, "webkit_web_view_load_uri")
    mustBind(webkit_web_view_evaluate_javascript, webkitLib.handle,
             "webkit_web_view_evaluate_javascript")
    mustBind(webkit_web_view_evaluate_javascript_finish, webkitLib.handle,
             "webkit_web_view_evaluate_javascript_finish")
    mustBind(webkit_web_view_get_title, webkitLib.handle, "webkit_web_view_get_title")
    mustBind(webkit_web_context_get_default, webkitLib.handle,
             "webkit_web_context_get_default")
    mustBind(webkit_web_context_register_uri_scheme, webkitLib.handle,
             "webkit_web_context_register_uri_scheme")
    mustBind(webkit_web_context_get_security_manager, webkitLib.handle,
             "webkit_web_context_get_security_manager")
    mustBind(webkit_security_manager_register_uri_scheme_as_secure, webkitLib.handle,
             "webkit_security_manager_register_uri_scheme_as_secure")
    mustBind(webkit_security_manager_register_uri_scheme_as_cors_enabled,
             webkitLib.handle,
             "webkit_security_manager_register_uri_scheme_as_cors_enabled")
    mustBind(webkit_uri_scheme_request_get_uri, webkitLib.handle,
             "webkit_uri_scheme_request_get_uri")
    mustBind(webkit_uri_scheme_request_finish, webkitLib.handle,
             "webkit_uri_scheme_request_finish")
    mustBind(webkit_javascript_result_get_js_value, webkitLib.handle,
             "webkit_javascript_result_get_js_value")
    mustBind(jsc_value_to_string, jscLib.handle, "jsc_value_to_string")
    mustBind(webkit_web_context_get_cookie_manager, webkitLib.handle,
             "webkit_web_context_get_cookie_manager")
    mustBind(webkit_cookie_manager_delete_all_cookies, webkitLib.handle,
             "webkit_cookie_manager_delete_all_cookies")
    mustBind(webkit_cookie_manager_add_cookie, webkitLib.handle,
             "webkit_cookie_manager_add_cookie")
    bindOptional(webkit_cookie_manager_get_all_cookies, webkitLib.handle,
                 "webkit_cookie_manager_get_all_cookies")
    bindOptional(webkit_cookie_manager_get_all_cookies_finish, webkitLib.handle,
                 "webkit_cookie_manager_get_all_cookies_finish")
    mustBind(soup_cookie_new, soupLib.handle, "soup_cookie_new")
    mustBind(soup_cookie_get_name, soupLib.handle, "soup_cookie_get_name")
    mustBind(soup_cookie_get_value, soupLib.handle, "soup_cookie_get_value")
    mustBind(soup_cookie_get_domain, soupLib.handle, "soup_cookie_get_domain")
    mustBind(soup_cookie_get_path, soupLib.handle, "soup_cookie_get_path")
    mustBind(soup_cookie_get_secure, soupLib.handle, "soup_cookie_get_secure")
    mustBind(soup_cookie_get_http_only, soupLib.handle,
             "soup_cookie_get_http_only")
    mustBind(soup_cookie_free, soupLib.handle, "soup_cookie_free")
  except BackendError:
    return false
  webkitAvailable = true
  result = true

proc ensureNotify*(): bool =
  ## Loads libnotify when present. Notification failures never prevent the
  ## application from running.
  if notifyChecked:
    return notifyAvailable
  notifyChecked = true
  notifyLib = openGroup("libnotify.so.4|libnotify.so")
  if notifyLib.handle == nil:
    return false
  try:
    mustBind(notify_init, notifyLib.handle, "notify_init")
    mustBind(notify_uninit, notifyLib.handle, "notify_uninit")
    mustBind(notify_notification_new, notifyLib.handle, "notify_notification_new")
    mustBind(notify_notification_show, notifyLib.handle, "notify_notification_show")
  except BackendError:
    return false
  notifyAvailable = true
  result = true

