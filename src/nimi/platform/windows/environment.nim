## Persistent Windows environment store; no shell/setx and no value expansion.
when not defined(windows):
  {.error: "Windows registry environment store requires Windows".}

import std/widestrs
import ../../core/environment
export environment

type HKey = pointer
proc RegOpenKeyExW(key: HKey, path: WideCString, options, access: uint32,
                  opened: ptr HKey): int32 {.stdcall, dynlib: "advapi32.dll", importc.}
proc RegCreateKeyExW(key: HKey, path: WideCString, reserved: uint32,
    class: pointer, options, access: uint32, security: pointer,
    opened: ptr HKey, disposition: ptr uint32): int32 {.stdcall, dynlib: "advapi32.dll", importc.}
proc RegCloseKey(key: HKey): int32 {.stdcall, dynlib: "advapi32.dll", importc.}
proc RegQueryValueExW(key: HKey, name: WideCString, reserved: pointer,
    kind: ptr uint32, data: pointer, size: ptr uint32): int32 {.stdcall, dynlib: "advapi32.dll", importc.}
proc RegSetValueExW(key: HKey, name: WideCString, reserved, kind: uint32,
    data: pointer, size: uint32): int32 {.stdcall, dynlib: "advapi32.dll", importc.}
proc RegDeleteValueW(key: HKey, name: WideCString): int32 {.stdcall, dynlib: "advapi32.dll", importc.}
proc RegEnumValueW(key: HKey, index: uint32, name: WideCString,
    count: ptr uint32, reserved: pointer, kind: ptr uint32,
    data: pointer, size: ptr uint32): int32 {.stdcall, dynlib: "advapi32.dll", importc.}
proc SendMessageTimeoutW(window: pointer, message: uint32, wp: uint,
    lp: pointer, flags, timeout: uint32, response: ptr uint): int {.stdcall, dynlib: "user32.dll", importc.}

proc checked(code: int32, action: string) =
  if code != 0:
    raise newException(EnvironmentError, action & " (Windows error " & $code & ")")

proc openKey(scope: EnvironmentScope, write = false): HKey =
  let root = cast[HKey](if scope == esUser: cast[int32](0x80000001'u32) else: cast[int32](0x80000002'u32))
  let path = newWideCString(if scope == esUser: "Environment"
    else: "SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment")
  let code = if write:
    RegCreateKeyExW(root, path, 0, nil, 0, 0x0002, nil, addr result, nil)
  else:
    RegOpenKeyExW(root, path, 0, 0x0001, addr result)
  if code == 2 and not write: return nil
  checked(code, "Open environment registry key")

proc readValue(scope: EnvironmentScope, name: string): Option[EnvironmentValue] =
  validateEnvironmentName(name)
  let key = openKey(scope)
  if key == nil: return none(EnvironmentValue)
  defer: discard RegCloseKey(key)
  let wide = newWideCString(name)
  # Retry when another application grows the value between the two queries.
  for attempt in 0..7:
    var kind, size: uint32
    let code = RegQueryValueExW(key, wide, nil, addr kind, nil, addr size)
    if code == 2: return none(EnvironmentValue)
    checked(code, "Read variable size")
    if size > 1024 * 1024: raise newException(EnvironmentError, "Variable exceeds editor size limit")
    var data = newSeq[uint16](int(size div 2) + 2)
    var actual = size
    let readCode = RegQueryValueExW(key, wide, nil, addr kind, addr data[0], addr actual)
    if readCode == 234: continue
    if readCode == 2: return none(EnvironmentValue)
    checked(readCode, "Read variable")
    if kind notin [1'u32, 2'u32] or actual mod 2 != 0:
      raise newException(EnvironmentError, "Unsupported registry value type or malformed UTF-16")
    var count = int(actual div 2)
    if count > 0 and data[count - 1] == 0: dec count
    for i in 0..<count:
      if data[i] == 0: raise newException(EnvironmentError, "Variable contains embedded NUL")
      if data[i] in 0xd800'u16..0xdbff'u16:
        if i + 1 >= count or data[i + 1] notin 0xdc00'u16..0xdfff'u16:
          raise newException(EnvironmentError, "Variable contains invalid UTF-16")
      elif data[i] in 0xdc00'u16..0xdfff'u16:
        if i == 0 or data[i - 1] notin 0xd800'u16..0xdbff'u16:
          raise newException(EnvironmentError, "Variable contains invalid UTF-16")
    let value = $cast[WideCString](addr data[0])
    return some(EnvironmentValue(value: value, kind: if kind == 1: ekString else: ekExpandString))
  raise newException(EnvironmentConflictError, "Variable kept changing while reading")

proc newWindowsEnvironmentStore*(): EnvironmentStore =
  result = EnvironmentStore(read: readValue)
  result.write = proc(scope: EnvironmentScope, name: string, value: EnvironmentValue) =
    validateEnvironmentName(name)
    validateEnvironmentValue(value)
    let wideName = newWideCString(name)
    let data = newWideCString(value.value)
    if data.len > 32766: raise newException(EnvironmentError, "Variable exceeds 32766 UTF-16 units")
    let key = openKey(scope, true)
    defer: discard RegCloseKey(key)
    checked(RegSetValueExW(key, wideName, 0,
      (if value.kind == ekString: 1'u32 else: 2'u32),
      cast[pointer](WideCString(data)), uint32((data.len + 1) * 2)), "Save variable")
  result.remove = proc(scope: EnvironmentScope, name: string) =
    validateEnvironmentName(name)
    let key = openKey(scope, true)
    defer: discard RegCloseKey(key)
    let code = RegDeleteValueW(key, newWideCString(name))
    if code != 2: checked(code, "Delete variable")
  result.list = proc(scope: EnvironmentScope): seq[EnvironmentEntry] =
    let key = openKey(scope)
    if key == nil: return
    defer: discard RegCloseKey(key)
    var index = 0'u32
    while true:
      var name = newWideCString(16384)
      var count = 16384'u32
      var kind: uint32
      let code = RegEnumValueW(key, index, name, addr count, nil, addr kind, nil, nil)
      if code == 259: break
      checked(code, "List variables")
      inc index
      # Non-string registry values are not environment variables; never modify them.
      if kind notin [1'u32, 2'u32]: continue
      let text = $name
      if text.len == 0: continue
      let value = readValue(scope, text)
      if value.isSome: result.add EnvironmentEntry(name: text, data: value.get)
  result.notify = proc(): bool =
    let environment = newWideCString("Environment")
    var response: uint
    SendMessageTimeoutW(cast[pointer](0xffff), 0x001a, 0,
      cast[pointer](WideCString(environment)), 0x0002, 2000, addr response) != 0
