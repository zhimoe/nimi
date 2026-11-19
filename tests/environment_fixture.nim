## Shared in-memory environment backend and app fixture for UI tests.

import std/[options, strutils]

import nimi/core/environment

import ../examples/environment/[model, service, state, storage]

type
  MemoryBackend* = ref object
    user*, system*: seq[EnvironmentEntry]
    notifications*: int

proc findName(entries: seq[EnvironmentEntry], name: string): int =
  for i, item in entries:
    if item.name.toLowerAscii() == name.toLowerAscii():
      return i
  -1

proc entry*(name, value: string,
            kind: EnvironmentKind = ekString): EnvironmentEntry =
  EnvironmentEntry(name: name,
                   data: EnvironmentValue(value: value, kind: kind))

proc memoryStore*(backend: MemoryBackend): EnvironmentStore =
  EnvironmentStore(
    read: proc(scope: EnvironmentScope,
               name: string): Option[EnvironmentValue] =
      let entries = if scope == esUser: backend.user else: backend.system
      let index = findName(entries, name)
      if index < 0: none(EnvironmentValue)
      else: some(entries[index].data),
    write: proc(scope: EnvironmentScope, name: string,
                value: EnvironmentValue) =
      let entries = if scope == esUser: addr backend.user else: addr backend.system
      let index = findName(entries[], name)
      let item = EnvironmentEntry(name: name, data: value)
      if index < 0: entries[].add item else: entries[][index] = item,
    remove: proc(scope: EnvironmentScope, name: string) =
      let entries = if scope == esUser: addr backend.user else: addr backend.system
      let index = findName(entries[], name)
      if index >= 0: entries[].delete(index),
    list: proc(scope: EnvironmentScope): seq[EnvironmentEntry] =
      if scope == esUser: backend.user else: backend.system,
    notify: proc(): bool =
      inc backend.notifications
      true)

proc valueOf*(backend: MemoryBackend, scope: EnvironmentScope,
              name: string): string =
  let entries = if scope == esUser: backend.user else: backend.system
  let index = findName(entries, name)
  if index < 0: "" else: entries[index].data.value

proc fixture*(): MemoryBackend =
  MemoryBackend(
    user: @[
      entry("Path", "C:\\A;C:\\Missing", ekExpandString),
      entry("GOPATH", "C:\\Users\\Ada\\go"),
      entry("PYTHONPATH", "C:\\Py;C:\\Py2", ekExpandString),
      entry("TMP", "%USERPROFILE%\\Temp", ekExpandString)
    ],
    system: @[
      entry("Path", "C:\\Windows\\System32", ekExpandString),
      entry("OS", "Windows_NT")
    ])

proc makeApp*(backend: MemoryBackend, dir: string): AppState =
  let backups = newStore(dir)
  let app = newAppState(newService(memoryStore(backend), backups), backups, dir)
  app.expandPath = proc(path: string): string =
    path.replace("%USERPROFILE%", "C:\\Users\\Ada")
  app.pathExists = proc(path: string): bool = "Missing" notin path
  app.now = proc(): float64 = 0.0
  app.initApp()
  app
