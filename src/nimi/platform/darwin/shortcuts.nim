## Carbon RegisterEventHotKey bindings. Carbon's hotkey API is still the
## least-friction system-wide shortcut API on macOS and does not require
## Input Monitoring permission.

import std/[dynlib, strutils, tables]

import ../contract
import ./[objc, types]

type
  OSType = uint32
  OSStatus = int32
  EventRef = pointer
  EventTargetRef = pointer
  EventHandlerRef = pointer
  EventHotKeyRef = pointer
  EventHotKeyID {.bycopy.} = object
    signature: OSType
    id: uint32
  EventTypeSpec {.bycopy.} = object
    eventClass: uint32
    eventKind: uint32

const
  KEventClassKeyboard = 0x6B657962'u32       # 'keyb'
  KEventHotKeyPressed = 5'u32
  KEventParamDirectObject = 0x2D2D2D2D'u32   # '----'
  TypeEventHotKeyID = 0x686B6964'u32         # 'hkid'
  HotKeySignature = 0x4E494D49'u32           # 'NIMI'
  ModCmd = 1'u32 shl 8
  ModShift = 1'u32 shl 9
  ModOption = 1'u32 shl 11
  ModControl = 1'u32 shl 12

let
  getApplicationEventTarget = cast[proc(): EventTargetRef {.cdecl.}](
    symAddr(carbon, "GetApplicationEventTarget"))
  installEventHandler = cast[proc(target: EventTargetRef,
                                   handler: proc(callRef: pointer, event: EventRef,
                                                 userData: pointer): OSStatus {.cdecl.},
                                   numTypes: uint32, typeList: ptr EventTypeSpec,
                                   userData: pointer,
                                   outRef: ptr EventHandlerRef): OSStatus {.cdecl.}](
    symAddr(carbon, "InstallEventHandler"))
  registerEventHotKey = cast[proc(keyCode: uint32, modifiers: uint32,
                                  hotKeyID: EventHotKeyID,
                                  target: EventTargetRef, options: uint32,
                                  outRef: ptr EventHotKeyRef): OSStatus {.cdecl.}](
    symAddr(carbon, "RegisterEventHotKey"))
  unregisterEventHotKey = cast[proc(hotKeyRef: EventHotKeyRef): OSStatus {.cdecl.}](
    symAddr(carbon, "UnregisterEventHotKey"))
  getEventParameter = cast[proc(event: EventRef, name: OSType,
                                desiredType: OSType, actualType: ptr OSType,
                                bufferSize: uint32, actualSize: ptr uint32,
                                data: pointer): OSStatus {.cdecl.}](
    symAddr(carbon, "GetEventParameter"))

proc hotKeyHandler(callRef: pointer, event: EventRef,
                   userData: pointer): OSStatus {.cdecl.} =
  var hotKeyID: EventHotKeyID
  let status = getEventParameter(event, KEventParamDirectObject,
                                 TypeEventHotKeyID, nil,
                                 uint32(sizeof(EventHotKeyID)), nil,
                                 addr hotKeyID)
  if status == 0 and gState != nil:
    let cb = gState.shortcutCallbacks.getOrDefault(hotKeyID.id)
    if cb != nil:
      cb()
  result = 0

proc ensureHandler(): bool =
  if gState == nil:
    return false
  if gState.shortcutsInstalled:
    return true
  if getApplicationEventTarget == nil or installEventHandler == nil:
    return false
  var spec = EventTypeSpec(eventClass: KEventClassKeyboard,
                           eventKind: KEventHotKeyPressed)
  var handler: EventHandlerRef
  let status = installEventHandler(getApplicationEventTarget(), hotKeyHandler,
                                   1, addr spec, nil, addr handler)
  if status != 0:
    return false
  gState.shortcutHandler = handler
  gState.shortcutsInstalled = true
  result = true

proc keyCode(key: string): int =
  case key.toLowerAscii
  of "a": 0
  of "s": 1
  of "d": 2
  of "f": 3
  of "h": 4
  of "g": 5
  of "z": 6
  of "x": 7
  of "c": 8
  of "v": 9
  of "b": 11
  of "q": 12
  of "w": 13
  of "e": 14
  of "r": 15
  of "y": 16
  of "t": 17
  of "1": 18
  of "2": 19
  of "3": 20
  of "4": 21
  of "6": 22
  of "5": 23
  of "=": 24
  of "9": 25
  of "7": 26
  of "-": 27
  of "8": 28
  of "0": 29
  of "]": 30
  of "o": 31
  of "u": 32
  of "[": 33
  of "i": 34
  of "p": 35
  of "return", "enter": 36
  of "l": 37
  of "j": 38
  of "'": 39
  of "k": 40
  of ";": 41
  of "\\": 42
  of ",": 43
  of "/": 44
  of "n": 45
  of "m": 46
  of ".": 47
  of "tab": 48
  of "space": 49
  of "`": 50
  of "backspace", "delete": 51
  of "escape", "esc": 53
  of "home": 115
  of "end": 119
  of "pageup": 116
  of "pagedown": 121
  of "left": 123
  of "right": 124
  of "down": 125
  of "up": 126
  of "f1": 122
  of "f2": 120
  of "f3": 99
  of "f4": 118
  of "f5": 96
  of "f6": 97
  of "f7": 98
  of "f8": 100
  of "f9": 101
  of "f10": 109
  of "f11": 103
  of "f12": 111
  else: -1

proc parseAccel(accel: string): tuple[code: int, mods: uint32] =
  var key = ""
  var mods = 0'u32
  for part in accel.split('+'):
    let p = part.strip.toLowerAscii
    case p
    of "cmd", "command", "super", "meta": mods = mods or ModCmd
    of "shift": mods = mods or ModShift
    of "alt", "option": mods = mods or ModOption
    of "ctrl", "control": mods = mods or ModControl
    else:
      if part.strip.len > 0:
        key = part.strip
  if key.len == 0 and accel.len == 1:
    key = accel
  result = (keyCode(key), mods)

proc registerShortcut(accel: string, fn: proc()): bool =
  if gState == nil or not ensureHandler():
    return false
  if gState.shortcutRefs.hasKey(accel):
    return false
  let parsed = parseAccel(accel)
  if parsed.code < 0:
    return false
  inc gState.nextShortcutId
  let id = gState.nextShortcutId
  var hotKeyRef: EventHotKeyRef
  let status = registerEventHotKey(uint32(parsed.code), parsed.mods,
                                   EventHotKeyID(signature: HotKeySignature,
                                                 id: id),
                                   getApplicationEventTarget(), 0, addr hotKeyRef)
  if status != 0 or hotKeyRef == nil:
    return false
  gState.shortcutRefs[accel] = hotKeyRef
  gState.shortcutCallbacks[id] = fn
  result = true

proc unregisterShortcut(accel: string): bool =
  if gState == nil:
    return false
  let hotKeyRef = gState.shortcutRefs.getOrDefault(accel)
  if hotKeyRef == nil:
    return false
  result = unregisterEventHotKey(hotKeyRef) == 0
  gState.shortcutRefs.del(accel)
  # Remove the callback by scanning the id table is not needed for a demo;
  # the id is reclaimed by the process lifetime. Keep the table bounded.
  if gState.shortcutCallbacks.len > 64:
    gState.shortcutCallbacks.clear()

proc unregisterAllShortcuts*() =
  if gState == nil:
    return
  for _, hotKeyRef in gState.shortcutRefs:
    discard unregisterEventHotKey(hotKeyRef)
  gState.shortcutRefs.clear()
  gState.shortcutCallbacks.clear()

proc installShortcutBackend*(b: Backend) =
  if b == nil:
    return
  b.registerShortcut = proc(accel: string, fn: proc()): bool =
    registerShortcut(accel, fn)
  b.unregisterShortcut = proc(accel: string): bool =
    unregisterShortcut(accel)
  b.unregisterAllShortcuts = proc() =
    unregisterAllShortcuts()
