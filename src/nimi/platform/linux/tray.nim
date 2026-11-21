## GtkStatusIcon tray item with a GtkMenu. GtkStatusIcon is deprecated but is
## part of GTK3 and works on X11 panels; AppIndicator/StatusNotifier can be a
## later enhancement for GNOME/Wayland.

import std/tables

import ../contract
import ./[ffi, menu, state]

type
  TrayState = ref object
    id: uint64
    icon: pointer
    menu: pointer
    title: string
    tooltip: string
    actions: seq[MenuAction]

var
  trays: Table[pointer, TrayState]
  nextTrayId = 1'u64

proc disconnectTray(tray: TrayState) =
  # G_SIGNAL_MATCH_DATA; the by-data helper is a GLib macro, not a symbol.
  discard g_signal_handlers_disconnect_matched(tray.icon, 16'u32,
                                               0, 0, nil, nil,
                                               cast[pointer](tray))

proc updateTooltip(tray: TrayState) =
  if tray.icon == nil:
    return
  let text = if tray.tooltip.len > 0: tray.tooltip else: tray.title
  if text.len > 0:
    gtk_status_icon_set_tooltip_text(tray.icon, text.cstring)

proc popup(tray: TrayState, button, eventTime: cuint) =
  if tray == nil or tray.menu == nil:
    return
  gtk_menu_popup(tray.menu, nil, nil, nil, nil, button, eventTime)

proc onActivate(icon, data: pointer) {.cdecl.} =
  try:
    popup(cast[TrayState](data), 1, gtk_get_current_event_time())
  except CatchableError:
    discard

proc onPopupMenu(icon: pointer, button, eventTime: cuint,
                 data: pointer) {.cdecl.} =
  try:
    popup(cast[TrayState](data), button, eventTime)
  except CatchableError:
    discard

proc createTray*(opts: PlatformTrayOptions): NativeTray =
  if linuxState == nil or not linuxState.initialized:
    raise newException(BackendError,
      "Tray requires an initialized GTK backend")
  let icon = gtk_status_icon_new()
  if icon == nil:
    raise newException(BackendError, "Cannot create a GTK status icon")
  let tray = TrayState(id: nextTrayId, icon: icon,
                       title: opts.title, tooltip: opts.tooltip)
  inc nextTrayId
  trays[icon] = tray
  gtk_status_icon_set_from_icon_name(icon, "application-x-executable")
  if opts.title.len > 0 and gtk_status_icon_set_title != nil:
    gtk_status_icon_set_title(icon, opts.title.cstring)
  tray.updateTooltip()
  discard g_signal_connect_data(icon, "activate".cstring,
                                cast[pointer](onActivate),
                                cast[pointer](tray), nil, 0)
  discard g_signal_connect_data(icon, "popup-menu".cstring,
                                cast[pointer](onPopupMenu),
                                cast[pointer](tray), nil, 0)
  gtk_status_icon_set_visible(icon, 1)

  result = NativeTray(id: tray.id)
  result.setTitle = proc(title: string) =
    tray.title = title
    if gtk_status_icon_set_title != nil:
      gtk_status_icon_set_title(icon, title.cstring)
    updateTooltip(tray)
  result.setTooltip = proc(tooltip: string) =
    tray.tooltip = tooltip
    updateTooltip(tray)
  result.setMenu = proc(platformMenu: PlatformMenu, handler: MenuHandler) =
    if tray.menu != nil:
      gtk_widget_destroy(tray.menu)
      tray.menu = nil
    tray.actions.setLen(0)
    if platformMenu.items.len == 0:
      return
    let menuWidget = gtk_menu_new()
    if menuWidget == nil:
      return
    ## Tray items dispatch through the same MenuAction callbacks as menu bars;
    ## owner is nil so role actions apply to the focused window.
    appendMenuItems(menuWidget, platformMenu.items, nil, nil, handler,
                    tray.actions)
    gtk_widget_show_all(menuWidget)
    tray.menu = menuWidget
  result.remove = proc() =
    if tray.icon == nil:
      return
    disconnectTray(tray)
    gtk_status_icon_set_visible(tray.icon, 0)
    if tray.menu != nil:
      gtk_widget_destroy(tray.menu)
      tray.menu = nil
    tray.actions.setLen(0)
    trays.del(tray.icon)
    g_object_unref(tray.icon)
    tray.icon = nil

proc testTrayItem*(id: uint64, label: string): bool =
  ## Test hook: invoke a tray menu item without a real pointer event.
  for tray in trays.values:
    if tray.id != id:
      continue
    for action in tray.actions:
      if action.label == label and action.enabled:
        dispatchAction(action)
        return true
  false

proc closeTray*() =
  var remaining: seq[TrayState]
  for tray in trays.values:
    remaining.add tray
  for tray in remaining:
    if tray.icon != nil:
      disconnectTray(tray)
      gtk_status_icon_set_visible(tray.icon, 0)
      if tray.menu != nil:
        gtk_widget_destroy(tray.menu)
        tray.menu = nil
      tray.actions.setLen(0)
      trays.del(tray.icon)
      g_object_unref(tray.icon)
      tray.icon = nil
