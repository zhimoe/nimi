## Pure environment-variable logic: filtering, PATH/batch analysis, diff and
## merge. Ported from EnvMan's domain package, using Nimi's lossless registry
## value types.

import std/[algorithm, sequtils, sets, strutils]

import nimi/core/environment
export environment

type
  Scope* = EnvironmentScope
  Variable* = object
    name*: string
    value*: string
    kind*: EnvironmentKind

  ViewFilter* = enum
    vfAll
    vfPath
    vfMulti
    vfRefs
    vfMissing

  BatchInfo* = object
    original*: seq[string]
    added*: seq[string]
    removed*: seq[string]
    reordered*: bool
    hasChanges*: bool
    duplicates*: seq[string]

const
  ScopeUser* = esUser
  ScopeSystem* = esMachine

proc scopeLabel*(scope: Scope): string =
  case scope
  of esUser: "用户变量"
  of esMachine: "系统变量"

proc scopeShort*(scope: Scope): string =
  case scope
  of esUser: "user"
  of esMachine: "system"

proc filterLabel*(filter: ViewFilter): string =
  case filter
  of vfAll: "全部变量"
  of vfPath: "PATH 路径"
  of vfMulti: "多值变量"
  of vfRefs: "含变量引用"
  of vfMissing: "缺失路径"

proc lowerName*(name: string): string =
  name.toLowerAscii()

proc sameName*(a, b: string): bool =
  a.lowerName() == b.lowerName()

proc varKey*(scope: Scope, name: string): string =
  $ord(scope) & "\x00" & name.lowerName()

proc clone*(vars: openArray[Variable]): seq[Variable] =
  for value in vars:
    result.add value

proc findVariable*(vars: openArray[Variable], name: string): int =
  let wanted = name.lowerName()
  for i, value in vars:
    if value.name.lowerName() == wanted:
      return i
  -1

proc kindFor*(kind: EnvironmentKind, value: string): EnvironmentKind =
  ## Preserve the registry type on edits; infer expansion for new values.
  if kind == ekExpandString:
    ekExpandString
  elif '%' in value:
    ekExpandString
  else:
    ekString

proc kindLabel*(kind: EnvironmentKind): string =
  case kind
  of ekString: "字符串（REG_SZ）"
  of ekExpandString: "可展开字符串（REG_EXPAND_SZ）"

proc splitValue*(value: string): seq[string] =
  ## Display entries: trim and drop empty segments. An empty value renders as
  ## one empty entry, matching EnvMan's list summary.
  if value.len == 0:
    return @[""]
  let normalized = value.replace("\r\n", "\n")
  for raw in normalized.split({';', '\n', '\r'}):
    let part = raw.strip()
    if part.len > 0:
      result.add part
  if result.len == 0:
    result = @[""]

proc rawSplit*(value: string): seq[string] =
  ## Sheet list mode preserves empty and whitespace-only entries.
  if value.len == 0:
    return @[""]
  value.split(';')

proc pathJoined*(entries: openArray[string]): string =
  entries.join(";")

proc isMultiValue*(value: string): bool =
  splitValue(value).len > 1

proc hasRef*(value: string): bool =
  var i = 0
  while i < value.len:
    if value[i] == '%':
      var j = i + 1
      while j < value.len and value[j] notin {'%', ' ', '\t', '\n', '\r'}:
        inc j
      if j < value.len and value[j] == '%' and j > i + 1:
        return true
      i = j
    else:
      inc i

proc isListLike*(name: string): bool =
  name.lowerName() in [
    "path", "psmodulepath", "pathext", "pythonpath", "classpath",
    "include", "lib", "cmakeprefixpath", "node_path"]

proc isBatchEditable*(value: Variable): bool =
  isMultiValue(value.value) or isListLike(value.name)

proc multiCount*(vars: openArray[Variable]): int =
  for value in vars:
    if isMultiValue(value.value):
      inc result

proc refCount*(vars: openArray[Variable]): int =
  for value in vars:
    if hasRef(value.value):
      inc result

proc missingKey*(scope: Scope, name, entry: string): string =
  $ord(scope) & "\x00" & lowerName(name) & "\x00" & entry

proc missingCount*(scope: Scope, value: Variable,
                   missing: HashSet[string]): int =
  ## Counts entries whose key was reported missing by a scan.
  for entry in splitValue(value.value):
    if missingKey(scope, value.name, entry) in missing:
      inc result

proc filtered*(vars: openArray[Variable], filter: ViewFilter, query: string,
               sortDesc: bool): seq[Variable] =
  result = clone(vars)
  case filter
  of vfAll:
    discard
  of vfPath:
    result = result.filterIt(it.name.sameName("Path"))
  of vfMulti:
    result = result.filterIt(isMultiValue(it.value))
  of vfRefs:
    result = result.filterIt(hasRef(it.value))
  of vfMissing:
    # The view supplies a missing-key filter by pre-filtering; keep all here.
    discard
  let q = query.strip().lowerName()
  if q.len > 0:
    result = result.filterIt(q in it.name.lowerName() or
                             q in it.value.lowerName())
  result.sort(proc(a, b: Variable): int =
    let x = a.name.lowerName()
    let y = b.name.lowerName()
    if sortDesc: cmp(y, x) else: cmp(x, y))

proc overlap*(scope: Scope, name: string,
              userVars, systemVars: openArray[Variable]): int =
  ## 0 none, 1 this system variable is overridden by user scope,
  ## 2 this user variable overrides system scope.
  case scope
  of esUser:
    if findVariable(systemVars, name) >= 0: 2 else: 0
  of esMachine:
    if findVariable(userVars, name) >= 0: 1 else: 0

proc diff*(before, desired: openArray[Variable]):
           tuple[upserts: seq[Variable], deletions: seq[string]] =
  for value in desired:
    let idx = findVariable(before, value.name)
    if idx < 0 or before[idx] != value:
      result.upserts.add value
  for value in before:
    if findVariable(desired, value.name) < 0:
      result.deletions.add value.name

proc mergeChanges*(latest, before, desired: openArray[Variable]): seq[Variable] =
  ## Replay only the user's local changes onto the latest registry snapshot,
  ## preserving unrelated external writes and additions.
  result = clone(latest)
  var kept: seq[Variable]
  for value in result:
    if findVariable(before, value.name) >= 0 and
        findVariable(desired, value.name) < 0:
      continue
    kept.add value
  result = kept
  for next in desired:
    let beforeIdx = findVariable(before, next.name)
    if beforeIdx >= 0 and before[beforeIdx] == next:
      continue
    let idx = findVariable(result, next.name)
    if idx < 0:
      result.add next
    else:
      result[idx] = next

proc validate*(variables: openArray[Variable]): string =
  var seen: seq[string]
  for value in variables:
    let name = value.name.strip()
    if name.len == 0:
      return "变量名不能为空"
    if '=' in value.name or '\0' in value.name:
      return "无效的变量名：\"" & value.name & "\""
    if '\0' in value.value:
      return "变量 " & value.name & " 的值包含空字符"
    let key = name.lowerName()
    if key in seen:
      return "变量名重复：" & value.name
    seen.add key

proc batchParse*(text: string): tuple[entries: seq[string], ignored: int] =
  let normalized = text.replace("\r\n", "\n").replace(";", "\n")
  for raw in normalized.split('\n'):
    let part = raw.strip()
    if part.len == 0:
      inc result.ignored
    else:
      result.entries.add part

proc normalizedEntry*(value: string): string =
  value.strip().lowerName()

proc containsFold*(values: openArray[string], value: string): bool =
  let wanted = normalizedEntry(value)
  for item in values:
    if normalizedEntry(item) == wanted:
      return true

proc analyzeBatch*(originalValue, text: string): BatchInfo =
  var original = splitValue(originalValue)
  if originalValue.len == 0:
    original = @[]
  let parsed = batchParse(text)
  let entries = parsed.entries
  result.original = original

  var oldKeys: seq[string]
  for value in original:
    oldKeys.add normalizedEntry(value)
  var newKeys: seq[string]
  for value in entries:
    newKeys.add normalizedEntry(value)

  for value in entries:
    if normalizedEntry(value) notin oldKeys:
      result.added.add value
  for value in original:
    if normalizedEntry(value) notin newKeys:
      result.removed.add value

  var commonOld, commonNew, seenOld, seenNew: seq[string]
  for value in original:
    let key = normalizedEntry(value)
    if key in newKeys and key notin seenOld:
      commonOld.add key
      seenOld.add key
  for value in entries:
    let key = normalizedEntry(value)
    if key in oldKeys and key notin seenNew:
      commonNew.add key
      seenNew.add key
  result.reordered = commonOld != commonNew
  result.hasChanges = original != entries

  var seen: seq[string]
  for value in entries:
    let key = normalizedEntry(value)
    if key in seen:
      result.duplicates.add value
    else:
      seen.add key

proc selectedCount*(checked: seq[string]): int = checked.len

proc toVariables*(entries: openArray[EnvironmentEntry]): seq[Variable] =
  for entry in entries:
    result.add Variable(name: entry.name, value: entry.data.value,
                        kind: entry.data.kind)

proc toEnvironmentValue*(value: Variable): EnvironmentValue =
  EnvironmentValue(value: value.value, kind: value.kind)

proc exportLines*(vars: openArray[Variable],
                  checked: openArray[string]): string =
  ## NAME=VALUE lines with no trailing newline. Multi-line values remain raw.
  var wanted: seq[string]
  for key in checked:
    wanted.add key
  for value in vars:
    if wanted.len == 0 or varKey(esUser, value.name) in wanted or
        value.name.lowerName() in wanted:
      if result.len > 0:
        result.add '\n'
      result.add value.name & "=" & value.value

proc displayValue*(value: string): string =
  if value.len == 0: "（空值）" else: value
