## NSScreen/NSEvent appearance and display snapshots, plus AppKit observers
## for screen-parameter and effective-appearance changes.

import std/strutils

import ../contract
import ./[objc, types]

const NimiDesktopObserverClass = "NimiDesktopObserver"

proc displaySnapshots(): seq[PlatformDisplay] =
  if gState == nil:
    return @[]
  let list = send0(loadClass("NSScreen"), sel("screens"))
  if list == nil:
    return @[]
  let count = int(sendInt(list, sel("count")))
  if count == 0:
    return @[]
  let first = sendIdUInt(list, sel("objectAtIndex:"), NSUInteger(0))
  let firstFrame = sendRect(first, sel("frame"))
  let top = firstFrame.y + firstFrame.h
  let left = firstFrame.x

  for i in 0 ..< count:
    let screen = sendIdUInt(list, sel("objectAtIndex:"), NSUInteger(i))
    let frame = sendRect(screen, sel("frame"))
    let visible = sendRect(screen, sel("visibleFrame"))
    var name = ""
    let nameObj = send0(screen, sel("localizedName"))
    if nameObj != nil:
      name = goString(nameObj)
    if name.len == 0:
      name = "Display " & $(i + 1)
    result.add PlatformDisplay(
      id: $i,
      name: name,
      x: float32(frame.x - left),
      y: float32(top - (frame.y + frame.h)),
      width: float32(frame.w),
      height: float32(frame.h),
      workX: float32(visible.x - left),
      workY: float32(top - (visible.y + visible.h)),
      workWidth: float32(visible.w),
      workHeight: float32(visible.h),
      scale: float32(sendDouble(screen, sel("backingScaleFactor"))),
      primary: i == 0)

proc cursorSnapshot(): PlatformPoint =
  if gState == nil:
    return
  let p = sendPoint(loadClass("NSEvent"), sel("mouseLocation"))
  let list = send0(loadClass("NSScreen"), sel("screens"))
  if list == nil or int(sendInt(list, sel("count"))) == 0:
    return PlatformPoint(x: float32(p.x), y: float32(p.y))
  let first = sendIdUInt(list, sel("objectAtIndex:"), NSUInteger(0))
  let f = sendRect(first, sel("frame"))
  result = PlatformPoint(
    x: float32(p.x - f.x),
    y: float32(f.y + f.h - p.y))

proc themeSnapshot(): PlatformTheme =
  result = PlatformTheme(dark: false, accentR: 0.0, accentG: 0.48,
                         accentB: 1.0)
  if gState == nil:
    return
  let appearance = send0(gState.nsApp, sel("effectiveAppearance"))
  if appearance != nil:
    result.dark = goString(send0(appearance, sel("name"))).contains("Dark")
  let accent = send0(loadClass("NSColor"), sel("controlAccentColor"))
  if accent != nil:
    var color = accent
    let space = send0(loadClass("NSColorSpace"), sel("sRGBColorSpace"))
    if space != nil:
      let converted = sendId1(accent, sel("colorUsingColorSpace:"), space)
      if converted != nil:
        color = converted
    var r, g, b, a: CGFloat
    if sendColorComponents(color, sel("getRed:green:blue:alpha:"),
                           addr r, addr g, addr b, addr a):
      result.accentR = float32(r)
      result.accentG = float32(g)
      result.accentB = float32(b)

proc screenParamsChanged(self: Id, cmd: SEL, notification: Id) {.cdecl.} =
  if gState != nil and gState.displayHandler != nil:
    gState.displayHandler()

proc appearanceChanged(self: Id, cmd: SEL, notification: Id) {.cdecl.} =
  if gState != nil and gState.themeHandler != nil:
    gState.themeHandler()

proc observerClass(): Id =
  registerClass(NimiDesktopObserverClass, loadClass("NSObject"), [
    ("screenParamsChanged:", cast[pointer](screenParamsChanged), "v@:@"),
    ("appearanceChanged:", cast[pointer](appearanceChanged), "v@:@"),
  ])

proc installDesktopObservers*() =
  if gState == nil:
    return
  let observer = send0(observerClass(), sel("new"))
  gState.notificationObserver = observer
  let center = send0(loadClass("NSNotificationCenter"), sel("defaultCenter"))
  let screenName = nsConstant(appkit,
    "NSApplicationDidChangeScreenParametersNotification")
  if screenName != nil:
    sendAddObserver(center, observer, sel("screenParamsChanged:"), screenName, nil)

  let appearanceName = nsConstant(appkit,
    "NSApplicationDidChangeEffectiveAppearanceNotification")
  if appearanceName != nil:
    sendAddObserver(center, observer, sel("appearanceChanged:"), appearanceName, nil)
  else:
    let distributed = send0(loadClass("NSDistributedNotificationCenter"),
                            sel("defaultCenter"))
    if distributed != nil:
      sendAddObserver(distributed, observer, sel("appearanceChanged:"),
                      nsString("AppleInterfaceThemeChangedNotification"), nil)

proc installDesktopBackend*(b: Backend) =
  if b == nil:
    return
  b.screens = proc(): seq[PlatformDisplay] = displaySnapshots()
  b.cursorPosition = proc(): PlatformPoint = cursorSnapshot()
  b.themeInfo = proc(): PlatformTheme = themeSnapshot()
  b.onDisplayChanged = proc(cb: proc()) =
    if gState != nil:
      gState.displayHandler = cb
  b.onThemeChanged = proc(cb: proc()) =
    if gState != nil:
      gState.themeHandler = cb
