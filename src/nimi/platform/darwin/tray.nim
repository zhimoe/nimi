## NSStatusBar tray item with an NSMenu. The button title is used as the tray
## glyph for now; template images/icon loading can be added later.

import std/tables

import ../contract
import ./[menu, objc, types]

proc createTray*(opts: PlatformTrayOptions): NativeTray =
  if gState == nil:
    return nil
  let bar = send0(loadClass("NSStatusBar"), sel("systemStatusBar"))
  if bar == nil:
    return nil
  let item = sendIdDouble(bar, sel("statusItemWithLength:"),
                          NSVariableStatusItemLength)
  if item == nil:
    return nil

  let id = gState.nextTrayId
  inc gState.nextTrayId
  gState.trays[id] = item

  let button = send0(item, sel("button"))
  if button != nil:
    if opts.title.len > 0:
      sendVoidId(button, sel("setTitle:"), nsString(opts.title))
    if opts.tooltip.len > 0:
      sendVoidId(button, sel("setToolTip:"), nsString(opts.tooltip))

  result = NativeTray(id: id)
  result.setTitle = proc(title: string) =
    if button != nil:
      sendVoidId(button, sel("setTitle:"), nsString(title))
  result.setTooltip = proc(tooltip: string) =
    if button != nil:
      sendVoidId(button, sel("setToolTip:"), nsString(tooltip))
  result.setMenu = proc(menu: PlatformMenu, h: MenuHandler) =
    let target = newMenuTarget(h)
    let nsmenu = buildMenu(menu.items, target)
    sendVoidId(item, sel("setMenu:"), nsmenu)
    let old = gState.trayTargets.getOrDefault(id)
    if old != nil:
      gState.menuTargets.del(old)
      release(old)
    gState.trayTargets[id] = target
  result.remove = proc() =
    let bar2 = send0(loadClass("NSStatusBar"), sel("systemStatusBar"))
    if bar2 != nil:
      sendVoidId(bar2, sel("removeStatusItem:"), item)
    let old = gState.trayTargets.getOrDefault(id)
    if old != nil:
      gState.menuTargets.del(old)
      release(old)
    gState.trayTargets.del(id)
    gState.trays.del(id)
