## Windows notification area icon and popup menus.
import std/[os, strutils, widestrs]
import ./menu

const header = (currentSourcePath.parentDir / "tray.h").replace('\\', '/')
{.compile: "tray.c".}
{.passL: "-lshell32".}

type
  Activate = proc(x, y: cint) {.cdecl.}
  TrayState = ref object
    title, tooltip: string
    menu: MenuPlan
    handler: MenuHandler
    select: proc(item: MenuCommand, handler: MenuHandler)
    failed: proc(error: string)
    showing: bool

proc addIcon(tooltip: WideCString, activate: Activate): cint
  {.cdecl, importc: "nimi_tray_add", header: header.}
proc setTooltip(tooltip: WideCString): cint
  {.cdecl, importc: "nimi_tray_tooltip", header: header.}
proc removeIcon() {.cdecl, importc: "nimi_tray_remove", header: header.}
proc popup(menu: pointer, x, y: cint): cuint
  {.cdecl, importc: "nimi_tray_popup", header: header.}
proc balloon(title, text: WideCString): cint
  {.cdecl, importc: "nimi_tray_notify", header: header.}
proc shutdownShell() {.cdecl, importc: "nimi_tray_shutdown", header: header.}

var active: TrayState
var nextId: uint64

proc tooltip(title, text: string): WideCStringObj =
  if '\0' in title or '\0' in text:
    raise newException(BackendError, "Tray title and tooltip cannot contain NUL")
  newWideCString(if text.len == 0: title else: text)

proc activate(x, y: cint) {.cdecl.} =
  let state = active
  if state == nil or state.showing or state.menu.nodes.len == 0: return
  state.showing = true
  defer: state.showing = false
  let plan = state.menu
  let handler = state.handler
  try:
    let menu = buildPopup(plan)
    defer: freeMenu(menu)
    let choice = popup(menu, x, y)
    if active == state and choice != 0 and choice <= cuint(plan.commands.len):
      let item = plan.commands[int(choice) - 1]
      if item.enabled: state.select(item, handler)
  except Exception as error:
    state.failed(error.msg)

proc createTray*(options: PlatformTrayOptions, select: proc(item: MenuCommand,
                  handler: MenuHandler), failed: proc(error: string)): NativeTray =
  if active != nil:
    raise newException(BackendError, "Windows notification area icon already exists")
  let state = TrayState(title: options.title, tooltip: options.tooltip,
                        select: select, failed: failed)
  if addIcon(tooltip(state.title, state.tooltip), activate) == 0:
    raise newException(BackendError, "Cannot add the Windows notification area icon")
  active = state
  inc nextId
  result = NativeTray(id: nextId)
  result.setTitle = proc(title: string) =
    if active != state: return
    if setTooltip(tooltip(title, state.tooltip)) == 0:
      raise newException(BackendError, "Cannot update the Windows notification area title")
    state.title = title
  result.setTooltip = proc(text: string) =
    if active != state: return
    if setTooltip(tooltip(state.title, text)) == 0:
      raise newException(BackendError, "Cannot update the Windows notification area tooltip")
    state.tooltip = text
  result.setMenu = proc(menu: PlatformMenu, handler: MenuHandler) =
    if active != state: return
    state.menu = planMenu(menu, accelerators = false)
    state.handler = handler
  result.remove = proc() =
    if active == state:
      active = nil
      state.handler = MenuHandler()
      removeIcon()

proc notify*(notification: PlatformNotification) =
  var body = notification.subtitle
  if body.len != 0 and notification.body.len != 0: body.add "\r\n"
  body.add notification.body
  if '\0' in notification.title or '\0' in body:
    raise newException(BackendError, "Notification text cannot contain NUL")
  if body.len == 0: body = notification.title
  if body.len > 0 and balloon(newWideCString(notification.title), newWideCString(body)) == 0:
    raise newException(BackendError, "Cannot show the Windows notification")

proc closeTray*() =
  if active != nil:
    active.handler = MenuHandler()
    active = nil
  shutdownShell()
