## macOS status-bar tray. The platform description is a Menu, so tray menus
## use the same items/roles/accelerators as the application menu.

import std/tables

import ./menu
import ../platform/contract

type
  TrayOptions* = object
    title*: string
    tooltip*: string
    menu*: Menu

  Tray* = ref object
    id*: uint64
    native*: NativeTray
    menu*: Menu
    callbacks: Table[uint32, proc()]

var tray*: Tray

proc toPlatform(k: MenuItemKind): PlatformMenuItemKind =
  case k
  of miNormal: pmiNormal
  of miSeparator: pmiSeparator
  of miSubmenu: pmiSubmenu
  of miCheckbox: pmiCheckbox

proc buildItems(items: seq[MenuItem], nextId: var uint32,
                callbacks: var Table[uint32, proc()]): seq[PlatformMenuItem] =
  for item in items:
    var p = PlatformMenuItem(
      label: item.label,
      kind: toPlatform(item.kind),
      role: item.role,
      accelerator: item.accelerator,
      checked: item.checked,
      enabled: item.enabled)
    if item.kind == miSubmenu:
      p.submenu = buildItems(item.submenu, nextId, callbacks)
    elif item.onSelect != nil:
      inc nextId
      p.id = nextId
      callbacks[p.id] = item.onSelect
    result.add p

proc platformMenu(t: Tray, m: Menu): PlatformMenu =
  var nextId = 0'u32
  t.callbacks.clear()
  if m != nil:
    result = PlatformMenu(items: buildItems(m.items, nextId, t.callbacks))

proc applyMenu(t: Tray) =
  if t == nil or t.native == nil:
    return
  let handler = MenuHandler(select: proc(id: uint32) =
    let cb = t.callbacks.getOrDefault(id)
    if cb != nil:
      cb())
  t.native.setMenu(platformMenu(t, t.menu), handler)

proc remove*(t: Tray)

proc newTray*(opts: TrayOptions): Tray =
  if currentBackend == nil or currentBackend.newTray == nil:
    raise newException(BackendError, "tray is not supported by this backend")
  if tray != nil:
    tray.remove()
  let t = Tray(menu: opts.menu)
  t.native = currentBackend.newTray(PlatformTrayOptions(
    title: opts.title, tooltip: opts.tooltip))
  if t.native == nil:
    raise newException(BackendError, "cannot create status bar item")
  t.id = t.native.id
  t.applyMenu()
  tray = t
  result = t

proc setTitle*(t: Tray, title: string) =
  if t != nil and t.native != nil:
    t.native.setTitle(title)

proc setTooltip*(t: Tray, tooltip: string) =
  if t != nil and t.native != nil:
    t.native.setTooltip(tooltip)

proc setMenu*(t: Tray, m: Menu) =
  if t == nil:
    return
  t.menu = m
  t.applyMenu()

proc remove*(t: Tray) =
  if t == nil:
    return
  if t.native != nil:
    t.native.remove()
    t.native = nil
  if tray == t:
    tray = nil
