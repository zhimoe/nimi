## GtkMenuBar translation, accelerators and menu role dispatch.

import std/[strutils, tables]

import ../contract
import ./[dialogs, ffi, state]

const
  GdkShiftMask = 1'u32 shl 0
  GdkControlMask = 1'u32 shl 2
  GdkMod1Mask = 1'u32 shl 3
  GtkAccelVisible = 1'u32

type
  ParsedAccelerator* = object
    keyval*, modifiers*: cuint
    ok*: bool

proc parseAccelerator*(text: string): ParsedAccelerator =
  var found = false
  for token in text.toLowerAscii.split('+'):
    let part = token.strip
    case part
    of "ctrl", "control", "cmd", "command", "meta", "super":
      result.modifiers = result.modifiers or GdkControlMask
    of "shift":
      result.modifiers = result.modifiers or GdkShiftMask
    of "alt", "option":
      result.modifiers = result.modifiers or GdkMod1Mask
    else:
      if found or part.len == 0:
        return
      found = true
      if part.len == 1 and part[0] in {'a'..'z', '0'..'9'}:
        result.keyval = gdk_unicode_to_keyval(uint32(ord(part[0])))
      elif part.len >= 2 and part[0] == 'f':
        var n = 0
        try:
          n = parseInt(part[1 .. ^1])
        except ValueError:
          discard
        if n notin 1 .. 24:
          return
        result.keyval = cuint(0xffbe + n - 1)
      else:
        result.keyval = case part
          of "enter", "return": 0xff0d'u32
          of "tab": 0xff09'u32
          of "escape", "esc": 0xff1b'u32
          of "space": 0x0020'u32
          of "backspace": 0xff08'u32
          of "delete", "del": 0xffff'u32
          of "insert": 0xff63'u32
          of "home": 0xff50'u32
          of "end": 0xff57'u32
          of "pageup": 0xff55'u32
          of "pagedown": 0xff56'u32
          of "left": 0xff51'u32
          of "up": 0xff52'u32
          of "right": 0xff53'u32
          of "down": 0xff54'u32
          else: 0'u32
      if result.keyval == 0:
        return
  result.ok = found

proc quitApplication() =
  if linuxState != nil and linuxState.initialized:
    gtk_main_quit()

proc showWindow(w: LinuxWindow) =
  if w != nil and w.window != nil:
    gtk_widget_show_all(w.window)
    gtk_window_present(w.window)

proc invokeRole(w: LinuxWindow, role: string) =
  let target =
    if w != nil: w
    elif lastFocusedWindow != nil: lastFocusedWindow
    else: nil
  case role
  of "quit":
    if linuxState != nil and linuxState.handler.quitRequested != nil:
      if not linuxState.handler.quitRequested():
        return
    quitApplication()
  of "close":
    if target != nil: gtk_window_close(target.window)
  of "minimize":
    if target != nil: gtk_window_iconify(target.window)
  of "zoom":
    if target != nil:
      if gtk_window_is_maximized(target.window) != 0:
        gtk_window_unmaximize(target.window)
      else:
        gtk_window_maximize(target.window)
  of "fullscreen":
    if target != nil:
      let gdkWindow = gtk_widget_get_window(target.window)
      if gdkWindow != nil and (gdk_window_get_state(gdkWindow) and (1 shl 4)) != 0:
        gtk_window_unfullscreen(target.window)
      else:
        gtk_window_fullscreen(target.window)
  of "hide":
    if target != nil: gtk_widget_hide(target.window)
  of "hideOthers":
    for window in linuxWindows.values:
      if target == nil or window != target:
        gtk_widget_hide(window.window)
  of "showAll", "bringAllToFront":
    for window in linuxWindows.values:
      showWindow(window)
    if target != nil: showWindow(target)
  of "about":
    let name = if linuxState != nil and linuxState.appName.len > 0:
                 linuxState.appName
               else: "Nimi"
    discard messageDialog("About", name & "\n\nBuilt with Nimi", @["OK"])
  of "undo":
    if target != nil and target.handler.surface.undo != nil:
      target.handler.surface.undo()
  of "redo":
    if target != nil and target.handler.surface.redo != nil:
      target.handler.surface.redo()
  of "cut":
    if target != nil and target.handler.surface.cut != nil:
      target.handler.surface.cut()
  of "copy":
    if target != nil and target.handler.surface.copy != nil:
      target.handler.surface.copy()
  of "paste":
    if target != nil and target.handler.surface.paste != nil:
      target.handler.surface.paste()
  of "selectAll":
    if target != nil and target.handler.surface.selectAll != nil:
      target.handler.surface.selectAll()
  of "delete":
    if target != nil and target.handler.surface.keyDown != nil:
      target.handler.surface.keyDown("delete", 0)
  else:
    discard

proc dispatchAction*(action: MenuAction) =
  if action == nil:
    return
  let owner = linuxWindows.getOrDefault(action.owner)
  if action.role.len == 0:
    var handler = action.handler
    if handler.select == nil:
      handler = currentMenuHandler
    if action.callbackId != 0 and handler.select != nil:
      handler.select(action.callbackId)
  else:
    invokeRole(owner, action.role)

proc onActivate(item, data: pointer) {.cdecl.} =
  try:
    dispatchAction(cast[MenuAction](data))
  except CatchableError:
    discard

proc onToggled(item, data: pointer) {.cdecl.} =
  try:
    # Programmatic set_active happens before the signal is connected, so a
    # user toggle (check or uncheck) is the only event that reaches here.
    dispatchAction(cast[MenuAction](data))
  except CatchableError:
    discard

proc makeMenuItem(owner: pointer, accelGroup: pointer,
                  handler: MenuHandler,
                  actions: var seq[MenuAction],
                  item: PlatformMenuItem): pointer =
  if item.kind == pmiSeparator:
    return gtk_separator_menu_item_new()
  if item.kind == pmiSubmenu:
    let submenu = gtk_menu_new()
    if submenu == nil:
      return nil
    for child in item.submenu:
      let childItem = makeMenuItem(owner, accelGroup, handler, actions, child)
      if childItem != nil:
        gtk_menu_shell_append(submenu, childItem)
    let holder = gtk_menu_item_new_with_label(item.label.cstring)
    if holder != nil:
      gtk_menu_item_set_submenu(holder, submenu)
      gtk_widget_set_sensitive(holder, cint(item.enabled))
    return holder

  let widget =
    if item.kind == pmiCheckbox:
      gtk_check_menu_item_new_with_label(item.label.cstring)
    else:
      gtk_menu_item_new_with_label(item.label.cstring)
  if widget == nil:
    return nil

  let action = MenuAction(label: item.label, role: item.role,
                          callbackId: item.id, enabled: item.enabled,
                          checkable: item.kind == pmiCheckbox,
                          owner: owner, handler: handler)
  if item.kind == pmiCheckbox:
    gtk_check_menu_item_set_active(widget, cint(item.checked))
    discard g_signal_connect_data(widget, "toggled".cstring,
                                  cast[pointer](onToggled),
                                  cast[pointer](action), nil, 0)
  else:
    discard g_signal_connect_data(widget, "activate".cstring,
                                  cast[pointer](onActivate),
                                  cast[pointer](action), nil, 0)
  gtk_widget_set_sensitive(widget, cint(item.enabled))

  if item.accelerator.len > 0 and item.enabled:
    let accel = parseAccelerator(item.accelerator)
    if accel.ok:
      action.accelKey = accel.keyval
      action.accelMods = accel.modifiers
      if accelGroup != nil:
        gtk_widget_add_accelerator(widget, "activate".cstring, accelGroup,
                                   accel.keyval, accel.modifiers,
                                   GtkAccelVisible)
  actions.add action
  widget

proc appendMenuItems*(shell: pointer, items: seq[PlatformMenuItem],
                      owner: pointer, accelGroup: pointer,
                      handler: MenuHandler, actions: var seq[MenuAction]) =
  for item in items:
    let widget = makeMenuItem(owner, accelGroup, handler, actions, item)
    if widget != nil:
      gtk_menu_shell_append(shell, widget)

proc installMenu*(w: LinuxWindow) =
  ## Rebuild one window's menu bar from the application menu.
  if w == nil or w.box == nil:
    return
  if w.menuBar != nil:
    gtk_widget_destroy(w.menuBar)
    w.menuBar = nil
  if w.accelGroup != nil:
    gtk_window_remove_accel_group(w.window, w.accelGroup)
    w.accelGroup = nil
  w.menuActions.setLen(0)
  if currentMenu.items.len == 0:
    return
  let group = gtk_accel_group_new()
  if group != nil:
    gtk_window_add_accel_group(w.window, group)
    g_object_unref(group) # The window keeps its own reference.
    w.accelGroup = group
  let bar = gtk_menu_bar_new()
  if bar == nil:
    return
  appendMenuItems(bar, currentMenu.items, w.window, w.accelGroup,
                  currentMenuHandler, w.menuActions)
  gtk_box_pack_start(w.box, bar, 0, 0, 0)
  gtk_box_reorder_child(w.box, bar, 0)
  gtk_widget_show_all(bar)
  w.menuBar = bar

proc installMenuForAll*(menu: PlatformMenu, handler: MenuHandler) =
  currentMenu = menu
  currentMenuHandler = handler
  for window in linuxWindows.values:
    installMenu(window)

proc testMenuKey*(w: LinuxWindow, keyCode: int, modifiers: uint32) =
  ## Test hook mirroring the Windows accelerator-table lookup.
  var keyval: cuint
  if keyCode in 32 .. 126:
    var ch = char(keyCode)
    if ch in {'A' .. 'Z'}:
      ch = char(ord(ch) + 32)
    keyval = gdk_unicode_to_keyval(uint32(ord(ch)))
  else:
    keyval = cuint(keyCode)
  var mods = 0'u32
  if (modifiers and KeyShift) != 0: mods = mods or GdkShiftMask
  if (modifiers and KeyControl) != 0: mods = mods or GdkControlMask
  if (modifiers and KeyAlt) != 0: mods = mods or GdkMod1Mask
  if (modifiers and KeyCommand) != 0:
    mods = mods or GdkControlMask
  for action in w.menuActions:
    if action.enabled and action.accelKey == keyval and
        action.accelMods == mods:
      dispatchAction(action)
      return
