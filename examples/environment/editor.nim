## Platform-independent controller for the environment editor.
import std/[algorithm, json, os, strutils, sysrand, times]
import nimi/core/environment
export environment

type Editor* = ref object
  store*: EnvironmentStore
  scope*: EnvironmentScope
  entries*: seq[EnvironmentEntry]
  name*, value*: string
  kind*: EnvironmentKind
  selected*: string
  expected*: Option[EnvironmentValue]
  status*, backupPath*: string
  backupDir*: string

proc refresh*(e: Editor) =
  e.entries = e.store.list(e.scope)
  e.entries.sort(proc(a, b: EnvironmentEntry): int = cmp(a.name.toLowerAscii, b.name.toLowerAscii))

proc switchScope*(e: Editor, scope: EnvironmentScope) =
  # Read first; failed reads must not label the old list as a different scope.
  var entries = e.store.list(scope)
  entries.sort(proc(a, b: EnvironmentEntry): int = cmp(a.name.toLowerAscii, b.name.toLowerAscii))
  e.scope = scope
  e.entries = entries
  e.selected = ""
  e.name = ""
  e.value = ""
  e.kind = ekString
  e.expected = none(EnvironmentValue)

proc choose*(e: Editor, name: string) =
  let value = e.store.read(e.scope, name)
  e.selected = name
  e.name = name
  e.expected = value
  e.value = if value.isSome: value.get.value else: ""
  e.kind = if value.isSome: value.get.kind else: ekString

proc newVariable*(e: Editor) =
  e.selected = ""
  e.name = ""
  e.value = ""
  e.kind = ekString
  e.expected = none(EnvironmentValue)

proc dirty*(e: Editor): bool =
  if e.selected.len == 0:
    e.name.len > 0 or e.value.len > 0 or e.kind != ekString
  else:
    some(EnvironmentValue(value: e.value, kind: e.kind)) != e.expected

proc valueJson(value: Option[EnvironmentValue]): JsonNode =
  if value.isNone: return newJNull()
  %*{"value": value.get.value, "kind": ord(value.get.kind)}

proc fromJson(value: JsonNode): Option[EnvironmentValue] =
  if value.kind == JNull: return none(EnvironmentValue)
  if value.kind != JObject or not value.hasKey("value") or not value.hasKey("kind") or
      value["value"].kind != JString or value["kind"].kind != JInt or
      value["kind"].getInt notin 0..1:
    raise newException(EnvironmentError, "Invalid backup value")
  let data = EnvironmentValue(value: value["value"].getStr, kind: EnvironmentKind(value["kind"].getInt))
  validateEnvironmentValue(data)
  some(data)

proc apply(e: Editor, name: string, before, after: Option[EnvironmentValue]): bool =
  validateEnvironmentName(name)
  if after.isSome: validateEnvironmentValue(after.get)
  if e.store.read(e.scope, name) != before:
    raise newException(EnvironmentConflictError, "Variable changed externally; refresh before saving")
  createDir(e.backupDir)
  var suffix = ""
  for b in urandom(8): suffix.add toHex(b, 2)
  let path = e.backupDir / ($int64(epochTime()) & "-" & suffix & ".json")
  let journal = %*{"version": 1, "scope": ord(e.scope), "name": name,
                    "before": valueJson(before), "after": valueJson(after)}
  # A failed backup prevents any registry mutation. Keep the journal even if
  # the following mutation fails; restoring it will compare the expected value.
  writeFile(path, pretty(journal))
  e.backupPath = path
  result = e.store.applyEnvironmentEdit(e.scope, name, before, after)

proc save*(e: Editor) =
  let name = if e.selected.len > 0: e.selected else: e.name
  let notified = e.apply(name, e.expected, some(EnvironmentValue(value: e.value, kind: e.kind)))
  e.choose(name)
  e.refresh()
  e.status = if notified: "Saved. New processes receive the updated environment."
             else: "Saved; change notification timed out. Restart affected applications."

proc deleteSelected*(e: Editor) =
  if e.selected.len == 0: raise newException(EnvironmentError, "Select a variable first")
  let notified = e.apply(e.selected, e.expected, none(EnvironmentValue))
  e.newVariable()
  e.refresh()
  e.status = if notified: "Deleted; backup retained." else: "Deleted; notification timed out."

proc restore*(e: Editor, path: string) =
  let node = parseFile(path)
  if node.kind != JObject or not node.hasKey("version") or node["version"].getInt != 1 or
      not node.hasKey("scope") or node["scope"].kind != JInt or node["scope"].getInt notin 0..1 or
      not node.hasKey("name") or node["name"].kind != JString or
      not node.hasKey("before") or not node.hasKey("after"):
    raise newException(EnvironmentError, "Invalid environment backup")
  let scope = EnvironmentScope(node["scope"].getInt)
  if scope != e.scope:
    raise newException(EnvironmentError, "Switch to the backup's scope before restoring")
  let name = node["name"].getStr
  let before = fromJson(node["before"])
  let after = fromJson(node["after"])
  let notified = e.apply(name, after, before)
  e.newVariable()
  e.refresh()
  e.status = if notified: "Backup restored." else: "Restored; notification timed out."
