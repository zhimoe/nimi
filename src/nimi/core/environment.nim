## Lossless environment-variable editing. Registry values are not expanded here.
import std/[options, strutils]
export options

type
  EnvironmentScope* = enum
    esUser, esMachine
  EnvironmentKind* = enum
    ekString, ekExpandString
  EnvironmentValue* = object
    value*: string
    kind*: EnvironmentKind
  EnvironmentEntry* = object
    name*: string
    data*: EnvironmentValue
  EnvironmentError* = object of CatchableError
  EnvironmentConflictError* = object of EnvironmentError
  EnvironmentStore* = ref object
    read*: proc(scope: EnvironmentScope, name: string): Option[EnvironmentValue]
    write*: proc(scope: EnvironmentScope, name: string, value: EnvironmentValue)
    remove*: proc(scope: EnvironmentScope, name: string)
    list*: proc(scope: EnvironmentScope): seq[EnvironmentEntry]
    notify*: proc(): bool

proc validateEnvironmentName*(name: string) =
  if name.len == 0 or '=' in name or '\0' in name:
    raise newException(EnvironmentError, "Variable name must be nonempty and contain neither '=' nor NUL")

proc validateEnvironmentValue*(value: EnvironmentValue) =
  if '\0' in value.value:
    raise newException(EnvironmentError, "Variable value must not contain NUL")

proc pathEntries*(value: string): seq[string] =
  ## Preserve empty segments, duplicates, spelling, expansion tokens and order.
  value.split(';')

proc pathValue*(entries: openArray[string]): string =
  for entry in entries:
    if ';' in entry or '\0' in entry:
      raise newException(EnvironmentError, "A PATH entry cannot contain ';' or NUL")
  entries.join(";")

proc applyEnvironmentEdit*(store: EnvironmentStore, scope: EnvironmentScope,
    name: string, expected, replacement: Option[EnvironmentValue]): bool =
  ## Check immediately before mutation. Not a registry transaction: another writer
  ## can still race between read and write. False means saved, broadcast timed out.
  validateEnvironmentName(name)
  if replacement.isSome: validateEnvironmentValue(replacement.get)
  if store.read(scope, name) != expected:
    raise newException(EnvironmentConflictError,
      "Variable changed outside this editor; refresh before saving")
  if replacement == expected: return true
  if replacement.isSome:
    store.write(scope, name, replacement.get)
  else:
    store.remove(scope, name)
  store.notify()
