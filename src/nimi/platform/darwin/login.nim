## Starting at login: SMAppService on macOS 13 and later, a LaunchAgent on
## macOS 12. Both need an app bundle.
##
## WasOpenedAtLogin reads the launch Apple Event in
## applicationDidFinishLaunching:, while AppKit still handles it, or the
## marker the LaunchAgent passes.

import std/[dynlib, os, strutils]

import ../[contract, loginargs]
import ./[objc, types]

const
  smNotRegistered* = 0
  smEnabled* = 1
  smRequiresApproval* = 2

  keyAEPropData = 0x70726474'u32       # 'prdt'
  keyAELaunchedAsLogInItem = 0x6c676974'u32 # 'lgit'

type
  MsgSendBoolPtr* = proc(a: Id, s: SEL, err: ptr Id): bool {.cdecl.}
  MsgSendIdUInt32* = proc(a: Id, s: SEL, v: uint32): Id {.cdecl.}
  MsgSendUInt32* = proc(a: Id, s: SEL): uint32 {.cdecl.}

proc sendBoolPtr(o: Id, s: SEL, err: ptr Id): bool =
  cast[MsgSendBoolPtr](msgSend)(o, s, err)

proc sendIdUInt32(o: Id, s: SEL, v: uint32): Id =
  cast[MsgSendIdUInt32](msgSend)(o, s, v)

proc sendUInt32(o: Id, s: SEL): uint32 =
  cast[MsgSendUInt32](msgSend)(o, s)

proc bundlePath*(): string =
  let bundle = send0(loadClass("NSBundle"), sel("mainBundle"))
  if bundle == nil:
    return ""
  goString(send0(bundle, sel("bundlePath")))

proc bundleIdentifier*(): string =
  let bundle = send0(loadClass("NSBundle"), sel("mainBundle"))
  if bundle == nil:
    return ""
  goString(send0(bundle, sel("bundleIdentifier")))

proc processName(): string =
  let processInfo = send0(loadClass("NSProcessInfo"), sel("processInfo"))
  if processInfo == nil:
    return "nimi"
  goString(send0(processInfo, sel("processName")))

proc appID*(): string =
  ## The bundle identifier, else the process name for unbundled builds.
  result = bundleIdentifier()
  if result.len == 0:
    result = processName()

proc requireAppBundle*(): string =
  result = bundlePath()
  if not result.endsWith(".app"):
    raise newException(BackendError,
      "starting at login needs an app bundle; build the app with `nimi build`")

var serviceManagementLoaded = false

proc loadServiceManagement() =
  ## SMAppService lives in ServiceManagement.framework, which AppKit does
  ## not load. It is absent before macOS 13.
  if serviceManagementLoaded:
    return
  serviceManagementLoaded = true
  try:
    discard loadLib("/System/Library/Frameworks/ServiceManagement.framework/ServiceManagement")
  except CatchableError:
    discard

proc mainAppService(): Id =
  loadServiceManagement()
  let serviceClass =
    try:
      loadClass("SMAppService")
    except ValueError:
      return nil
  if serviceClass == nil:
    return nil
  send0(serviceClass, sel("mainAppService"))

proc launchedAsLoginItem*(): bool =
  ## Whether the Apple Event being handled marks this launch as a login
  ## item. AppKit delivers the launch event only after
  ## applicationWillFinishLaunching:, so read it in
  ## applicationDidFinishLaunching:.
  let manager = send0(loadClass("NSAppleEventManager"),
                      sel("sharedAppleEventManager"))
  if manager == nil:
    return false
  let event = send0(manager, sel("currentAppleEvent"))
  if event == nil:
    return false
  let prop = sendIdUInt32(event, sel("paramDescriptorForKeyword:"),
                          keyAEPropData)
  result = prop != nil and
    sendUInt32(prop, sel("enumCodeValue")) == keyAELaunchedAsLogInItem

proc detectOpenedAtLogin*() =
  ## Main thread, from applicationDidFinishLaunching:.
  if gState != nil:
    gState.openedAtLogin =
      hasOpenedAtLoginArg(commandLineParams()) or launchedAsLoginItem()

proc wasOpenedAtLogin*(): bool =
  gState != nil and gState.openedAtLogin

proc loginAgentPath*(id: string): string =
  getHomeDir() / "Library" / "LaunchAgents" / (id & ".plist")

proc xmlEscape(s: string): string =
  result = s
  result = result.replace("&", "&amp;")
  result = result.replace("<", "&lt;")
  result = result.replace(">", "&gt;")
  result = result.replace("\"", "&quot;")
  result = result.replace("'", "&apos;")

proc loginAgentPlist*(id, app, arg: string): string =
  ## The LaunchAgent that opens the app at login on macOS 12.
  result = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>""" & xmlEscape(id) & """</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>""" & xmlEscape(app) & """</string>
    <string>--args</string>
    <string>""" & xmlEscape(arg) & """</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
"""

proc setLaunchAgent(enabled: bool, id, app, arg: string) =
  let path = loginAgentPath(id)
  if not enabled:
    if fileExists(path):
      removeFile(path)
    return
  createDir(path.parentDir)
  writeFile(path, loginAgentPlist(id, app, arg))

proc errorMessage(err: Id): string =
  if err == nil:
    return "unknown error"
  goString(send0(err, sel("localizedDescription")))

proc setOpenAtLogin*(enabled: bool) =
  withPool(proc() =
    let app = requireAppBundle()
    let service = mainAppService()
    if service == nil:
      setLaunchAgent(enabled, appID(), app, openedAtLoginArg)
      return
    if not enabled:
      if int(sendInt(service, sel("status"))) == smNotRegistered:
        return
      var err: Id = nil
      if not sendBoolPtr(service, sel("unregisterAndReturnError:"), addr err):
        raise newException(BackendError,
          "cannot stop opening at login: " & errorMessage(err))
      return
    var err: Id = nil
    if not sendBoolPtr(service, sel("registerAndReturnError:"), addr err):
      raise newException(BackendError,
        "cannot open at login: " & errorMessage(err))
    if int(sendInt(service, sel("status"))) == smRequiresApproval:
      raise newException(BackendError,
        "allow the app to open at login in System Settings > General > Login Items"))

proc openAtLogin*(): bool =
  var registered = false
  withPool(proc() =
    let app = bundlePath()
    if not app.endsWith(".app"):
      return
    let service = mainAppService()
    if service != nil:
      registered = int(sendInt(service, sel("status"))) == smEnabled
    else:
      registered = fileExists(loginAgentPath(appID())))
  result = registered
