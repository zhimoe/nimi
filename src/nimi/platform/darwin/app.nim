## NSApplication lifecycle and the macOS Backend implementation.

import ../contract
import ./[clipboard, dialogs, menu, objc, types, window]

const
  NimiAppDelegateClass = "NimiAppDelegate"

proc dispatchTrampoline(ctx: pointer) {.cdecl.} =
  if gState != nil and gState.handler.dispatch != nil:
    gState.handler.dispatch()

proc postWake(state: DarwinState) =
  let event = newEventId(NSEventTypeApplicationDefined,
                         NSPoint(x: 0, y: 0), 0, 0, 0x6d67)
  if event != nil:
    sendVoidIdBool(state.nsApp, sel("postEvent:atStart:"), event, false)

proc stopApp(state: DarwinState) =
  if state == nil or state.nsApp == nil:
    return
  state.quitting = true
  sendVoidId(state.nsApp, sel("stop:"), nil)
  postWake(state)

# --- app delegate ----------------------------------------------------------

proc appDidFinishLaunching(self: Id, cmd: SEL, notification: Id) {.cdecl.} =
  if gState != nil and gState.handler.ready != nil:
    gState.handler.ready()

proc appShouldTerminate(self: Id, cmd: SEL, sender: Id): NSUInteger {.cdecl.} =
  if gState == nil:
    return NSTerminateNow
  let allow =
    if gState.handler.quitRequested != nil:
      gState.handler.quitRequested()
    else:
      true
  if not allow:
    return NSTerminateCancel
  # Stop our run loop, then tell AppKit not to terminate: App.Run returns and
  # the core owns the final cleanup.
  stopApp(gState)
  result = NSTerminateCancel

proc appWillTerminate(self: Id, cmd: SEL, notification: Id) {.cdecl.} =
  if gState != nil and gState.handler.terminated != nil:
    gState.handler.terminated()

proc appShouldTerminateAfterLastWindowClosed(self: Id, cmd: SEL,
                                            sender: Id): bool {.cdecl.} =
  result = false

proc installMenu(state: DarwinState, appName: string) =
  let mainMenu = send0(loadClass("NSMenu"), sel("new"))
  let appItem = cast[MsgSendInitMenuItem](msgSend)(
    send0(loadClass("NSMenuItem"), sel("alloc")),
    sel("initWithTitle:action:keyEquivalent:"),
    nsString(appName), cast[SEL](nil), nsString(""))
  let appMenu = send0(loadClass("NSMenu"), sel("new"))
  sendVoidId(appItem, sel("setSubmenu:"), appMenu)
  sendVoidId(mainMenu, sel("addItem:"), appItem)

  let quitItem = cast[MsgSendInitMenuItem](msgSend)(
    send0(loadClass("NSMenuItem"), sel("alloc")),
    sel("initWithTitle:action:keyEquivalent:"),
    nsString("Quit " & appName), sel("terminate:"), nsString("q"))
  sendVoidId(quitItem, sel("setTarget:"), state.nsApp)
  sendVoidUInt(quitItem, sel("setKeyEquivalentModifierMask:"),
               NSEventModifierFlagCommand)
  sendVoidId(appMenu, sel("addItem:"), quitItem)
  sendVoidId(state.nsApp, sel("setMainMenu:"), mainMenu)

proc initApp(state: DarwinState, h: AppHandler, opts: AppOptions) =
  gState = state
  state.handler = h
  state.nsApp = send0(loadClass("NSApplication"), sel("sharedApplication"))
  if state.nsApp == nil:
    raise newException(BackendError, "cannot open NSApplication")
  sendVoidInt(state.nsApp, sel("setActivationPolicy:"),
              NSApplicationActivationPolicyRegular)

  let delegateClass = registerClass(NimiAppDelegateClass, loadClass("NSObject"), [
    ("applicationDidFinishLaunching:",
      cast[pointer](appDidFinishLaunching), "v@:@"),
    ("applicationShouldTerminate:",
      cast[pointer](appShouldTerminate), "Q@:@"),
    ("applicationWillTerminate:",
      cast[pointer](appWillTerminate), "v@:@"),
    ("applicationShouldTerminateAfterLastWindowClosed:",
      cast[pointer](appShouldTerminateAfterLastWindowClosed), "c@:@"),
  ])
  state.appDelegate = send0(delegateClass, sel("new"))
  sendVoidId(state.nsApp, sel("setDelegate:"), state.appDelegate)

  installMenu(state, if opts.name.len > 0: opts.name else: "Nimi")
  sendVoidBool(state.nsApp, sel("activateIgnoringOtherApps:"), true)

proc newDarwinBackend*(): Backend =
  if not dispatchAvailable():
    raise newException(BackendError, "libdispatch main queue is unavailable")
  let state = DarwinState(nextWindowId: 1)
  result = Backend(name: "darwin/wkwebview")
  result.clipboard = newDarwinClipboard()
  result.dialogs = newDarwinDialogs()
  result.setMenu = proc(menu: PlatformMenu, h: MenuHandler) =
    installPlatformMenu(menu, h)
  result.init = proc(h: AppHandler, opts: AppOptions) =
    initApp(state, h, opts)
  result.run = proc() =
    sendVoid(state.nsApp, sel("run"))
  result.quit = proc() =
    stopApp(state)
  result.signal = proc() =
    dispatchAsyncMain(dispatchTrampoline)
  result.step = proc() =
    discard
  result.wake = proc() =
    discard
  result.isMainThread = proc(): bool =
    isMainThread()
  result.newWindow = proc(opts: PlatformWindowOptions,
                          h: WindowHandler): NativeWindow =
    createWindow(state, opts, h)
