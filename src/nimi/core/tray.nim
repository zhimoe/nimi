## System tray. Tray and application menus share the same item model.

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

proc applyMenu(t: Tray, m: Menu) =
  if t == nil or t.native == nil:
    return
  var nextId = 0'u32
  var callbacks: Table[uint32, proc()]
  let menu = if m == nil: PlatformMenu()
             else: PlatformMenu(items: buildItems(m.items, nextId, callbacks))
  let handler = MenuHandler(select: proc(id: uint32) =
    let cb = callbacks.getOrDefault(id)
    if cb != nil:
      cb())
  t.native.setMenu(menu, handler)
  t.menu = m

proc remove*(t: Tray)

proc newTray*(opts: TrayOptions): Tray =
  if currentBackend == nil or currentBackend.newTray == nil:
    raise newException(BackendError, "tray is not supported by this backend")
  if tray != nil:
    tray.remove()
  let t = Tray()
  t.native = currentBackend.newTray(PlatformTrayOptions(
    title: opts.title, tooltip: opts.tooltip))
  if t.native == nil:
    raise newException(BackendError, "cannot create status bar item")
  t.id = t.native.id
  try:
    t.applyMenu(opts.menu)
  except:
    t.native.remove()
    raise
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
  if t.native == nil: t.menu = m
  else: t.applyMenu(m)

proc remove*(t: Tray) =
  if t == nil:
    return
  if t.native != nil:
    t.native.remove()
    t.native = nil
  if tray == t:
    tray = nil
