## Global shortcuts through X11 XGrabKey. Wayland sessions have no portable
## global grab without the XDG desktop portal, so registration returns false
## there instead of failing at runtime.

import std/tables

import ../contract
import ./[ffi, menu, state]

const
  XKeyPress = 2
  XLockMask = 1'u32 shl 1
  XMod2Mask = 1'u32 shl 4
  GrabModeAsync = 1

type
  XKeyEvent {.bycopy.} = object
    kind: cint
    serial: culong
    sendEvent: cint
    display: pointer
    window, root, subwindow: culong
    time: culong
    x, y, xRoot, yRoot: cint
    state, keycode: cuint
    sameScreen: cint

  KeyIdentity = tuple[keycode: cuint, modifiers: cuint]
  GrabInfo = object
    keycode: cint
    modifiers: cuint

var
  callbacks: Table[KeyIdentity, proc() {.closure.}]
  grabs: Table[string, GrabInfo]
  rootFilterInstalled = false
  x11ErrorOccurred = false

proc displayHandle(): pointer =
  let display = gdk_display_get_default()
  if display == nil:
    return nil
  gdk_x11_display_get_xdisplay(display)

proc rootHandle(): culong =
  gdk_x11_get_default_root_xwindow()

proc x11ErrorHandler(display, event: pointer): cint {.cdecl.} =
  x11ErrorOccurred = true
  0

proc eventFilter(xevent, event, data: pointer): cint {.cdecl.} =
  if xevent == nil:
    return 0
  let key = cast[ptr XKeyEvent](xevent)
  if key.kind == XKeyPress:
    let modifiers = key.state and not cuint(XLockMask or XMod2Mask)
    let callback = callbacks.getOrDefault((cuint(key.keycode), modifiers))
    if callback != nil:
      try:
        callback()
      except CatchableError:
        discard
      return 2 # GDK_FILTER_REMOVE
  0

proc ensureFilter() =
  if rootFilterInstalled:
    return
  let root = gdk_get_default_root_window()
  if root == nil:
    return
  gdk_window_add_filter(root, cast[pointer](eventFilter), nil)
  rootFilterInstalled = true

proc removeFilter() =
  if not rootFilterInstalled:
    return
  let root = gdk_get_default_root_window()
  if root != nil:
    gdk_window_remove_filter(root, cast[pointer](eventFilter), nil)
  rootFilterInstalled = false

proc modifierCombos(modifiers: cuint): array[4, cuint] =
  [modifiers, modifiers or XLockMask, modifiers or XMod2Mask,
   modifiers or XLockMask or XMod2Mask]

proc registerShortcut*(accel: string, fn: proc()): bool =
  if fn == nil or not ensureX11():
    return false
  if linuxState == nil or not linuxState.initialized:
    return false
  if getThreadId() != linuxState.mainThreadId:
    return false
  if grabs.hasKey(accel):
    return false
  let parsed = parseAccelerator(accel)
  if not parsed.ok:
    return false
  let display = displayHandle()
  let root = rootHandle()
  if display == nil or root == 0:
    return false
  let keycode = int(XKeysymToKeycode(display, culong(parsed.keyval)))
  if keycode == 0:
    return false

  x11ErrorOccurred = false
  let previous = XSetErrorHandler(cast[pointer](x11ErrorHandler))
  for combo in modifierCombos(parsed.modifiers):
    discard XGrabKey(display, cint(keycode), combo, root, 0,
                     GrabModeAsync, GrabModeAsync)
  discard XSync(display, 0)
  discard XSetErrorHandler(previous)
  if x11ErrorOccurred:
    # Another client owns this combination; undo any partial grabs.
    let restore = XSetErrorHandler(cast[pointer](x11ErrorHandler))
    for combo in modifierCombos(parsed.modifiers):
      discard XUngrabKey(display, cint(keycode), combo, root)
    discard XSync(display, 0)
    discard XSetErrorHandler(restore)
    return false

  callbacks[(cuint(keycode), parsed.modifiers)] = fn
  grabs[accel] = GrabInfo(keycode: cint(keycode),
                          modifiers: parsed.modifiers)
  ensureFilter()
  true

proc unregisterShortcut*(accel: string): bool =
  let info = grabs.getOrDefault(accel)
  if info.keycode == 0:
    return false
  if ensureX11():
    let display = displayHandle()
    let root = rootHandle()
    if display != nil and root != 0:
      for combo in modifierCombos(info.modifiers):
        discard XUngrabKey(display, info.keycode, combo, root)
      discard XSync(display, 0)
  callbacks.del((cuint(info.keycode), info.modifiers))
  grabs.del(accel)
  if grabs.len == 0:
    removeFilter()
  true

proc unregisterAllShortcuts*() =
  if not ensureX11():
    grabs.clear()
    callbacks.clear()
    removeFilter()
    return
  let display = displayHandle()
  let root = rootHandle()
  for info in grabs.values:
    if display != nil and root != 0:
      for combo in modifierCombos(info.modifiers):
        discard XUngrabKey(display, info.keycode, combo, root)
  if display != nil:
    discard XSync(display, 0)
  grabs.clear()
  callbacks.clear()
  removeFilter()

proc testShortcut*(accel: string): bool =
  ## Test-only hook: synthesizes the key combination with XTest.
  if XTestFakeKeyEvent == nil or not ensureX11():
    return false
  let display = displayHandle()
  if display == nil:
    return false
  let parsed = parseAccelerator(accel)
  if not parsed.ok:
    return false
  let keycode = XKeysymToKeycode(display, culong(parsed.keyval))
  if keycode == 0:
    return false
  var modifierKeys: seq[cuint]
  if (parsed.modifiers and 1'u32) != 0: # Shift
    modifierKeys.add cuint(XKeysymToKeycode(display, 0xffe1)) # Shift_L
  if (parsed.modifiers and 4'u32) != 0: # Control
    modifierKeys.add cuint(XKeysymToKeycode(display, 0xffe3)) # Control_L
  if (parsed.modifiers and 8'u32) != 0: # Mod1
    modifierKeys.add cuint(XKeysymToKeycode(display, 0xffe9)) # Alt_L
  for key in modifierKeys:
    if key != 0:
      discard XTestFakeKeyEvent(display, key, 1, 0)
  discard XTestFakeKeyEvent(display, cuint(keycode), 1, 0)
  discard XTestFakeKeyEvent(display, cuint(keycode), 0, 0)
  for key in modifierKeys:
    if key != 0:
      discard XTestFakeKeyEvent(display, key, 0, 0)
  discard XSync(display, 0)
  true

proc installShortcutBackend*(b: Backend) =
  if b == nil:
    return
  b.registerShortcut = proc(accel: string, fn: proc()): bool =
    registerShortcut(accel, fn)
  b.unregisterShortcut = proc(accel: string): bool =
    unregisterShortcut(accel)
  b.unregisterAllShortcuts = proc() =
    unregisterAllShortcuts()
