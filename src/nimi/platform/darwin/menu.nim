## NSMenu construction from the platform menu description.

import std/[strutils, tables]

import ../contract
import ./[objc, types]

const
  NimiMenuTargetClass = "NimiMenuTarget"
  ModShift = NSUInteger(1 shl 17)
  ModControl = NSUInteger(1 shl 18)
  ModOption = NSUInteger(1 shl 19)
  ModCommand = NSUInteger(1 shl 20)

proc menuClicked(self: Id, cmd: SEL, sender: Id) {.cdecl.} =
  if gState == nil:
    return
  let handler = gState.menuTargets.getOrDefault(self)
  if handler.select == nil:
    return
  let tag = int(sendInt(sender, sel("tag")))
  handler.select(uint32(tag))

proc validateMenuItem(self: Id, cmd: SEL, item: Id): bool {.cdecl.} =
  result = sendBool(item, sel("isEnabled"))

proc newMenuTarget*(handler: MenuHandler): Id =
  let cls = registerClass(NimiMenuTargetClass, loadClass("NSObject"), [
    ("nimiMenuClicked:", cast[pointer](menuClicked), "v@:@"),
    ("validateMenuItem:", cast[pointer](validateMenuItem), "c@:@"),
  ])
  let target = send0(cls, sel("new"))
  gState.menuTargets[target] = handler
  retain(target)
  result = target

proc roleSelector(role: string): SEL =
  case role
  of "quit": sel("terminate:")
  of "about": sel("orderFrontStandardAboutPanel:")
  of "hide": sel("hide:")
  of "hideOthers": sel("hideOtherApplications:")
  of "showAll": sel("unhideAllApplications:")
  of "undo": sel("undo:")
  of "redo": sel("redo:")
  of "cut": sel("cut:")
  of "copy": sel("copy:")
  of "paste": sel("paste:")
  of "selectAll": sel("selectAll:")
  of "delete": sel("delete:")
  of "minimize": sel("performMiniaturize:")
  of "zoom": sel("performZoom:")
  of "close": sel("performClose:")
  of "fullscreen": sel("toggleFullScreen:")
  of "bringAllToFront": sel("arrangeInFront:")
  else: default(SEL)

proc parseAccel(acc: string): tuple[key: string, mods: NSUInteger] =
  var key = ""
  var mods = NSUInteger(0)
  for part in acc.split('+'):
    let p = part.strip.toLowerAscii
    case p
    of "cmd", "command", "super", "meta": mods = mods or ModCommand
    of "shift": mods = mods or ModShift
    of "alt", "option": mods = mods or ModOption
    of "ctrl", "control": mods = mods or ModControl
    else:
      if part.strip.len > 0:
        key = part.strip
  if key.len == 0 and acc.len == 1:
    key = acc
  result = (key, mods)

const appRoles = ["quit", "about", "hide", "hideOthers", "showAll",
                  "bringAllToFront"]

proc buildMenu*(items: seq[PlatformMenuItem], target: Id): Id =
  let menu = send0(loadClass("NSMenu"), sel("new"))
  sendVoidBool(menu, sel("setAutoenablesItems:"), false)
  for item in items:
    if item.kind == pmiSeparator:
      sendVoidId(menu, sel("addItem:"),
                 send0(loadClass("NSMenuItem"), sel("separatorItem")))
      continue

    if item.kind == pmiSubmenu:
      let mi = cast[MsgSendInitMenuItem](msgSend)(
        send0(loadClass("NSMenuItem"), sel("alloc")),
        sel("initWithTitle:action:keyEquivalent:"),
        nsString(item.label), cast[SEL](nil), nsString(""))
      let sub = buildMenu(item.submenu, target)
      sendVoidId(mi, sel("setSubmenu:"), sub)
      sendVoidId(menu, sel("addItem:"), mi)
      continue

    let custom = item.role.len == 0
    let action = if custom: sel("nimiMenuClicked:") else: roleSelector(item.role)
    let accel = parseAccel(item.accelerator)
    let mi = cast[MsgSendInitMenuItem](msgSend)(
      send0(loadClass("NSMenuItem"), sel("alloc")),
      sel("initWithTitle:action:keyEquivalent:"),
      nsString(item.label), action, nsString(accel.key))
    if accel.key.len > 0:
      sendVoidUInt(mi, sel("setKeyEquivalentModifierMask:"), accel.mods)
    if custom:
      sendVoidId(mi, sel("setTarget:"), target)
      sendVoidInt(mi, sel("setTag:"), int(item.id))
      if not item.enabled:
        sendVoidBool(mi, sel("setEnabled:"), false)
      if item.checked:
        sendVoidInt(mi, sel("setState:"), 1)
    elif item.role in appRoles:
      sendVoidId(mi, sel("setTarget:"), gState.nsApp)
    sendVoidId(menu, sel("addItem:"), mi)
  result = menu

proc installPlatformMenu*(menu: PlatformMenu, h: MenuHandler) =
  if gState == nil:
    return
  let target = newMenuTarget(h)
  let main = buildMenu(menu.items, target)
  sendVoidId(gState.nsApp, sel("setMainMenu:"), main)
  if gState.appMenuTarget != nil:
    gState.menuTargets.del(gState.appMenuTarget)
    release(gState.appMenuTarget)
  gState.appMenuTarget = target
