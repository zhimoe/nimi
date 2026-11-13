import std/[os, strutils, widestrs]
import ./menuplan
export menuplan
const header = (currentSourcePath.parentDir / "menu.h").replace('\\', '/')
{.compile: "menu.c".}
{.passL: "-luser32".}
proc testMenuKey*(window: pointer, key, modifiers: cuint) {.cdecl, importc: "nimi_menu_test_key", header: header.}
proc create(popup: cint): pointer {.cdecl, importc: "nimi_menu_create", header: header.}
proc append(menu: pointer, label: WideCString, command: cuint, child: pointer,
  separator, enabled, checked: cint): cint {.cdecl, importc: "nimi_menu_append", header: header.}
proc freeMenu(menu: pointer) {.cdecl, importc: "nimi_menu_free", header: header.}
proc createAccel(keys, commands: ptr uint16, flags: ptr uint8, count: cint): pointer {.cdecl, importc: "nimi_accel_create", header: header.}
proc freeAccel(accel: pointer) {.cdecl, importc: "nimi_accel_free", header: header.}
proc install(window, menu, accel: pointer): cint {.cdecl, importc: "nimi_menu_install", header: header.}

proc build(nodes: seq[MenuNode], popup: bool): pointer =
  result = create(cint(popup))
  if result == nil: raise newException(BackendError, "Cannot allocate Windows menu")
  try:
    for node in nodes:
      var child: pointer
      if node.kind == pmiSubmenu: child = build(node.children, true)
      if append(result, newWideCString(node.label), cuint(node.command), child,
          cint(node.kind == pmiSeparator), cint(node.enabled), cint(node.checked)) == 0:
        freeMenu(child)
        raise newException(BackendError, "Cannot append Windows menu item")
  except:
    freeMenu(result)
    raise

proc installMenu*(window: pointer, plan: MenuPlan) =
  var menu, accel: pointer
  try:
    if plan.nodes.len > 0: menu = build(plan.nodes, false)
    if plan.shortcuts.len > 0:
      var keys, commands: seq[uint16]
      var flags: seq[uint8]
      for entry in plan.shortcuts:
        keys.add entry.key
        commands.add entry.command
        flags.add entry.flags
      accel = createAccel(addr keys[0], addr commands[0], addr flags[0], cint(keys.len))
      if accel == nil: raise newException(BackendError, "Cannot create Windows accelerator table")
    if install(window, menu, accel) == 0:
      raise newException(BackendError, "Cannot install Windows menu")
    menu = nil
    accel = nil # Ownership transferred to the HWND until replacement/destruction.
  finally:
    freeMenu(menu)
    freeAccel(accel)
