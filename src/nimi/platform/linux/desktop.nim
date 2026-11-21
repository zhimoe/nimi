## GDK display/theme queries and libnotify integration.

import std/[math]

import ../contract
import ./[ffi, state]

var
  probeWindow: pointer
  desktopHooked: bool
  notifyReady: bool

# --- displays --------------------------------------------------------------

proc screens*(): seq[PlatformDisplay] =
  if not ffi.gtkLoaded:
    return
  let screen = gdk_screen_get_default()
  if screen == nil:
    return
  let count = int(gdk_screen_get_n_monitors(screen))
  let primary = int(gdk_screen_get_primary_monitor(screen))
  for i in 0 ..< count:
    var geometry, work: GdkRectangle
    gdk_screen_get_monitor_geometry(screen, cint(i), addr geometry)
    gdk_screen_get_monitor_workarea(screen, cint(i), addr work)
    if work.width <= 0 or work.height <= 0:
      work = geometry
    var name = ""
    if gdk_screen_get_monitor_model != nil:
      let model = gdk_screen_get_monitor_model(screen, cint(i))
      if model != nil:
        name = $model
    if name.len == 0 and gdk_screen_get_monitor_plug_name != nil:
      let plug = gdk_screen_get_monitor_plug_name(screen, cint(i))
      if plug != nil:
        name = $plug
    if name.len == 0:
      name = "Display " & $(i + 1)
    result.add PlatformDisplay(
      id: $i,
      name: name,
      x: float32(geometry.x),
      y: float32(geometry.y),
      width: float32(geometry.width),
      height: float32(geometry.height),
      workX: float32(work.x),
      workY: float32(work.y),
      workWidth: float32(work.width),
      workHeight: float32(work.height),
      scale: float32(max(1, int(gdk_screen_get_monitor_scale_factor(screen,
                                                                   cint(i))))),
      primary: i == primary or (primary < 0 and i == 0))

proc cursorPosition*(): PlatformPoint =
  if not ffi.gtkLoaded:
    return
  let display = gdk_display_get_default()
  if display == nil:
    return
  let seat = gdk_display_get_default_seat(display)
  if seat == nil:
    return
  let pointer = gdk_seat_get_pointer(seat)
  if pointer == nil:
    return
  var screen: pointer
  var x, y: cint
  if gdk_device_get_position(pointer, addr screen, addr x, addr y) == 0:
    return
  result = PlatformPoint(x: float32(x), y: float32(y))

# --- theme -----------------------------------------------------------------

proc ensureProbe(): pointer =
  if probeWindow == nil:
    probeWindow = gtk_window_new(0)
    if probeWindow != nil:
      gtk_window_set_decorated(probeWindow, 0)
  probeWindow

proc themeInfo*(): PlatformTheme =
  if not ffi.gtkLoaded:
    result = PlatformTheme(dark: false, accentR: 0.0, accentG: 0.48,
                           accentB: 1.0)
    return
  result.accentR = 0.0
  result.accentG = 0.48
  result.accentB = 1.0
  let window = ensureProbe()
  if window == nil:
    return
  let context = gtk_widget_get_style_context(window)
  if context == nil:
    return
  var dark = false
  if gtk_style_context_get_background_color != nil:
    var background: GdkRGBA
    gtk_style_context_get_background_color(context, 0, addr background)
    let luminance = 0.2126 * background.red + 0.7152 * background.green +
                    0.0722 * background.blue
    if background.alpha > 0.01 and luminance < 0.45:
      dark = true
  if not dark and gtk_style_context_get_color != nil:
    var foreground: GdkRGBA
    gtk_style_context_get_color(context, 0, addr foreground)
    let luminance = 0.2126 * foreground.red + 0.7152 * foreground.green +
                    0.0722 * foreground.blue
    if luminance > 0.6:
      dark = true
  result.dark = dark

# --- change notifications --------------------------------------------------

proc onMonitorsChanged(screen, data: pointer) {.cdecl.} =
  if linuxState != nil and linuxState.displayHandler != nil:
    try:
      linuxState.displayHandler()
    except CatchableError:
      discard

proc onScreenSizeChanged(screen, data: pointer): cint {.cdecl.} =
  onMonitorsChanged(screen, data)
  0

proc onThemeChanged(settings, pspec, data: pointer) {.cdecl.} =
  if linuxState != nil and linuxState.themeHandler != nil:
    try:
      linuxState.themeHandler()
    except CatchableError:
      discard

proc hookDesktopChanges*() =
  if desktopHooked or not ffi.gtkLoaded:
    return
  desktopHooked = true
  let screen = gdk_screen_get_default()
  if screen != nil:
    discard g_signal_connect_data(screen, "monitors-changed".cstring,
                                  cast[pointer](onMonitorsChanged), nil, nil, 0)
    discard g_signal_connect_data(screen, "size-changed".cstring,
                                  cast[pointer](onScreenSizeChanged), nil, nil, 0)
  let settings = gtk_settings_get_default()
  if settings != nil:
    discard g_signal_connect_data(settings, "notify::gtk-theme-name".cstring,
                                  cast[pointer](onThemeChanged), nil, nil, 0)
    discard g_signal_connect_data(settings,
      "notify::gtk-application-prefer-dark-theme".cstring,
      cast[pointer](onThemeChanged), nil, nil, 0)

# --- notifications ---------------------------------------------------------

proc initNotifications*(appName: string) =
  if ensureNotify():
    notifyReady = notify_init(appName.cstring) != 0

proc shutdownNotifications*() =
  if notifyReady:
    notify_uninit()
    notifyReady = false

proc sendNotification*(n: PlatformNotification) =
  if not notifyReady:
    return
  var body = n.body
  if n.subtitle.len > 0:
    body = if body.len > 0: n.subtitle & "\n" & body else: n.subtitle
  let title = if n.title.len > 0: n.title
              elif linuxState != nil and linuxState.appName.len > 0:
                linuxState.appName
              else: "Nimi"
  let notification = notify_notification_new(title.cstring, body.cstring,
                                             "dialog-information".cstring)
  if notification == nil:
    return
  try:
    discard notify_notification_show(notification, nil)
  finally:
    g_object_unref(notification)

# --- shutdown --------------------------------------------------------------

proc shutdownDesktop*() =
  if probeWindow != nil:
    gtk_widget_destroy(probeWindow)
    probeWindow = nil
