## Snapshots (max 20), pending elevation edits and settings. Writes are
## atomic (temp file + move); corrupt history surfaces an error rather than
## being silently overwritten.

import std/[json, os, times]

import ./[model, theme]

const MaxSnapshots* = 20

type
  Snapshot* = object
    id*: string
    time*: string
    scope*: Scope
    note*: string
    variables*: seq[Variable]

  PendingEdits* = object
    scope*: Scope
    note*: string
    focus*: string
    fullReplace*: bool
    before*: seq[Variable]
    variables*: seq[Variable]

  Settings* = object
    theme*: ThemeMode
    windowX*, windowY*, windowWidth*, windowHeight*: int
    hasWindow*: bool

  StoreError* = object of CatchableError

  Store* = ref object
    dir*: string

proc jsonString(node: JsonNode, key: string, default = ""): string =
  if node.kind == JObject and node.hasKey(key) and node[key].kind == JString:
    node[key].getStr()
  else:
    default

proc jsonInt(node: JsonNode, key: string, default = 0): int =
  if node.kind == JObject and node.hasKey(key) and node[key].kind == JInt:
    int(node[key].getInt())
  else:
    default

proc variableToJson(value: Variable): JsonNode =
  %*{"name": value.name, "value": value.value, "kind": ord(value.kind)}

proc variableFromJson(node: JsonNode): Variable =
  if node.kind != JObject or not node.hasKey("name") or
      not node.hasKey("value") or not node.hasKey("kind") or
      node["kind"].kind != JInt or node["kind"].getInt notin 0 .. 1:
    raise newException(StoreError, "无效的变量备份")
  Variable(name: node.jsonString("name"), value: node.jsonString("value"),
           kind: EnvironmentKind(node["kind"].getInt))

proc variablesToJson(values: openArray[Variable]): JsonNode =
  result = newJArray()
  for value in values:
    result.add variableToJson(value)

proc variablesFromJson(node: JsonNode): seq[Variable] =
  if node.kind == JArray:
    for item in node:
      result.add variableFromJson(item)

proc scopeToJson(scope: Scope): JsonNode = %ord(scope)

proc scopeFromJson(node: JsonNode): Scope =
  let value = jsonInt(node, "scope", 0)
  if value == ord(esMachine): esMachine else: esUser

proc snapshotToJson(snapshot: Snapshot): JsonNode =
  %*{
    "id": snapshot.id,
    "time": snapshot.time,
    "scope": ord(snapshot.scope),
    "note": snapshot.note,
    "variables": variablesToJson(snapshot.variables)
  }

proc snapshotFromJson(node: JsonNode): Snapshot =
  Snapshot(
    id: node.jsonString("id"),
    time: node.jsonString("time"),
    scope: node.scopeFromJson(),
    note: node.jsonString("note"),
    variables: variablesFromJson(node["variables"]))

proc pendingToJson(pending: PendingEdits): JsonNode =
  %*{
    "scope": ord(pending.scope),
    "note": pending.note,
    "focus": pending.focus,
    "fullReplace": pending.fullReplace,
    "before": variablesToJson(pending.before),
    "variables": variablesToJson(pending.variables)
  }

proc pendingFromJson(node: JsonNode): PendingEdits =
  PendingEdits(
    scope: node.scopeFromJson(),
    note: node.jsonString("note"),
    focus: node.jsonString("focus"),
    fullReplace: node.kind == JObject and node.hasKey("fullReplace") and
      node["fullReplace"].kind == JBool and node["fullReplace"].getBool(),
    before: variablesFromJson(node["before"]),
    variables: variablesFromJson(node["variables"]))

proc newStore*(dir: string): Store =
  if dir.len == 0:
    raise newException(StoreError, "数据目录不能为空")
  try:
    createDir(dir)
  except OSError as e:
    raise newException(StoreError, "无法创建数据目录：" & e.msg)
  Store(dir: dir)

proc snapshotsPath(store: Store): string = store.dir / "snapshots.json"
proc pendingPath(store: Store): string = store.dir / "pending.json"
proc settingsPath(store: Store): string = store.dir / "settings.json"

proc readJson(path: string): JsonNode =
  if not fileExists(path):
    return nil
  try:
    parseFile(path)
  except CatchableError as e:
    raise newException(StoreError, "读取 " & path & " 失败：" & e.msg)

proc writeJson(path: string, node: JsonNode) =
  let temporary = path & ".tmp"
  try:
    writeFile(temporary, pretty(node))
    moveFile(temporary, path)
  except OSError as e:
    raise newException(StoreError, "写入 " & path & " 失败：" & e.msg)

proc loadSnapshots*(store: Store): seq[Snapshot] =
  let node = readJson(store.snapshotsPath())
  if node == nil:
    return @[]
  if node.kind != JArray:
    raise newException(StoreError, "备份历史格式无效")
  for item in node:
    result.add snapshotFromJson(item)

proc saveSnapshot*(store: Store, scope: Scope, note: string,
                   variables: openArray[Variable]): Snapshot =
  let now = now()
  result = Snapshot(
    id: now.format("yyyyMMdd-HHmmss") & "-" & $now.nanosecond,
    time: now.format("yyyy-MM-dd HH:mm:ss"),
    scope: scope,
    note: note,
    variables: clone(variables))
  var snapshots = store.loadSnapshots()
  snapshots.insert(result, 0)
  if snapshots.len > MaxSnapshots:
    snapshots.setLen(MaxSnapshots)
  var arrayNode = newJArray()
  for item in snapshots:
    arrayNode.add snapshotToJson(item)
  writeJson(store.snapshotsPath(), arrayNode)

proc readPending*(store: Store): PendingEdits =
  let node = readJson(store.pendingPath())
  if node == nil:
    return PendingEdits(scope: esUser)
  pendingFromJson(node)

proc readPendingAt*(path: string): PendingEdits =
  let node = readJson(path)
  if node == nil:
    return PendingEdits(scope: esUser)
  pendingFromJson(node)

proc hasPending*(store: Store): bool = fileExists(store.pendingPath())

proc writePending*(store: Store, pending: PendingEdits) =
  writeJson(store.pendingPath(), pendingToJson(pending))

proc clearPending*(store: Store) =
  if fileExists(store.pendingPath()):
    removeFile(store.pendingPath())

proc claimPending*(store: Store): string =
  let name = "pending-" & now().format("yyyyMMdd-HHmmss") &
    ".interrupted.json"
  moveFile(store.pendingPath(), store.dir / name)
  name

proc completePending*(store: Store, name: string) =
  if name.len == 0 or name.contains(DirSep) or name == "." or name == "..":
    raise newException(StoreError, "无效的待应用文件名")
  let path = store.dir / name
  if fileExists(path):
    removeFile(path)

proc themeValue(mode: ThemeMode): string =
  case mode
  of tmSystem: "system"
  of tmLight: "light"
  of tmDark: "dark"

proc themeFromValue(value: string): ThemeMode =
  case value
  of "light": tmLight
  of "dark": tmDark
  else: tmSystem

proc loadSettings*(store: Store): Settings =
  result = Settings(theme: tmSystem)
  let node = readJson(store.settingsPath())
  if node == nil:
    return
  result.theme = themeFromValue(node.jsonString("theme", "system"))
  if node.kind == JObject and node.hasKey("window") and
      node["window"].kind == JObject:
    let window = node["window"]
    result.windowX = jsonInt(window, "x", 0)
    result.windowY = jsonInt(window, "y", 0)
    result.windowWidth = jsonInt(window, "width", 0)
    result.windowHeight = jsonInt(window, "height", 0)
    result.hasWindow = result.windowWidth > 0 and result.windowHeight > 0

proc saveSettings*(store: Store, settings: Settings) =
  var node = %*{"theme": themeValue(settings.theme)}
  if settings.hasWindow:
    node["window"] = %*{
      "x": settings.windowX, "y": settings.windowY,
      "width": settings.windowWidth, "height": settings.windowHeight}
  writeJson(store.settingsPath(), node)
