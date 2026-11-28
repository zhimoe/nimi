## Headless screenshot harness for the environment UI. Uses the same Tester
## and scene as the window, with an in-memory registry backend.

import std/[os, sets, strutils, times]

import nimi/ui
when defined(macosx):
  import nimi/render/cg

import ./[envstore, model, service, state, storage, theme, view]

proc entry(name, value: string,
           kind: EnvironmentKind = ekString): EnvironmentEntry =
  EnvironmentEntry(name: name,
                   data: EnvironmentValue(value: value, kind: kind))

proc findName(entries: seq[EnvironmentEntry], name: string): int =
  for i, item in entries:
    if item.name.toLowerAscii() == name.toLowerAscii():
      return i
  -1

proc fixtureBackend(): EnvironmentStore =
  var user = @[
    entry("TMP", "%USERPROFILE%\\AppData\\Local\\Temp", ekExpandString),
    entry("TEMP", "%USERPROFILE%\\AppData\\Local\\Temp", ekExpandString),
    entry("SCALA_HOME", "C:\\Users\\zhimoe\\scoop\\apps\\scala\\current"),
    entry("RUSTUP_HOME", "C:\\Users\\zhimoe\\scoop\\persist\\rustup\\.rustup"),
    entry("Path", "C:\\Users\\zhimoe\\.pi\\agent\\bin;" &
      "C:\\Users\\zhimoe\\scoop\\apps\\git\\current\\bin;" &
      "C:\\Windows\\System32;" &
      "C:\\Users\\zhimoe\\AppData\\Local\\Programs\\Microsoft VS Code\\bin;" &
      "C:\\NotExist\\bin;" &
      "%USERPROFILE%\\scoop\\shims", ekExpandString),
    entry("OneDrive", "C:\\Users\\zhimoe\\OneDrive"),
    entry("JAVA_HOME", "C:\\Users\\zhimoe\\scoop\\apps\\openjdk24\\current"),
    entry("HERMES_GIT_BASH_PATH", "C:\\Program Files\\Git\\bin\\bash.exe"),
    entry("GOPATH", "C:\\Users\\zhimoe\\go"),
    entry("GIT_INSTALL_ROOT", "C:\\Users\\zhimoe\\scoop\\apps\\git\\current"),
    entry("ERLANG_HOME", "C:\\Users\\zhimoe\\scoop\\apps\\erlang\\current"),
    entry("PYTHONPATH", "C:\\Tools\\Python;C:\\Users\\zhimoe\\py")
  ]
  var system = @[
    entry("Path", "C:\\Windows\\system32;C:\\Windows;C:\\Windows\\System32\\Wbem",
          ekExpandString),
    entry("TMP", "C:\\Windows\\Temp"),
    entry("TEMP", "C:\\Windows\\Temp"),
    entry("OS", "Windows_NT"),
    entry("ComSpec", "C:\\Windows\\system32\\cmd.exe"),
    entry("PATHEXT", ".COM;.EXE;.BAT;.CMD;.VBS", ekExpandString)
  ]
  EnvironmentStore(
    read: proc(scope: EnvironmentScope,
               name: string): Option[EnvironmentValue] =
      let entries = if scope == esUser: user else: system
      let index = findName(entries, name)
      if index < 0: none(EnvironmentValue)
      else: some(entries[index].data),
    write: proc(scope: EnvironmentScope, name: string,
                value: EnvironmentValue) =
      var entries = if scope == esUser: addr user else: addr system
      let index = findName(entries[], name)
      let item = EnvironmentEntry(name: name, data: value)
      if index < 0: entries[].add item else: entries[][index] = item,
    remove: proc(scope: EnvironmentScope, name: string) =
      var entries = if scope == esUser: addr user else: addr system
      let index = findName(entries[], name)
      if index >= 0: entries[].delete(index),
    list: proc(scope: EnvironmentScope): seq[EnvironmentEntry] =
      if scope == esUser: user else: system,
    notify: proc(): bool = true)

proc capture(outDir, scene: string) =
  if not dirExists(outDir):
    createDir(outDir)
  let dataDir = getTempDir() / "nimi-env-capture-" & $int(epochTime())
  let backups = newStore(dataDir)
  let service = newService(fixtureBackend(), backups)
  let app = newAppState(service, backups, dataDir)
  app.expandPath = proc(path: string): string =
    path.replace("%USERPROFILE%", "C:\\Users\\zhimoe").
      replace("%SystemRoot%", "C:\\Windows").
      replace("%ProgramFiles%", "C:\\Program Files")
  app.pathExists = proc(path: string): bool =
    "NotExist" notin path
  app.now = proc(): float64 = 0.0
  app.initApp()
  app.admin = scene != "readonly"
  app.textScale = 1.0
  app.highContrast = false
  app.themeMode = tmLight
  case scene
  of "dark":
    app.themeMode = tmDark
    app.systemDark = true
  of "selection":
    app.checked.incl varKey(esUser, "TMP")
    app.checked.incl varKey(esUser, "TEMP")
    app.checked.incl varKey(esUser, "GOPATH")
  of "empty":
    app.setQuery("zzz")
  of "readonly":
    app.admin = false
    app.scope = esMachine
  of "sheet":
    let idx = findVariable(app.vars[esUser], "Path")
    if idx >= 0:
      app.openEdit(app.vars[esUser][idx])
  of "create":
    app.openCreate("JAVA_HOME")
  of "sheet-text":
    let idx = findVariable(app.vars[esUser], "GOPATH")
    if idx >= 0:
      app.openEdit(app.vars[esUser][idx])
  of "batch":
    app.openBatch("Path")
  of "batch-diff":
    app.openBatch("Path")
    if app.batch != nil:
      app.batch.text.add("\nC:\\New\\bin")
  of "backups":
    discard backups.saveSnapshot(esUser, "编辑变量 Path", app.vars[esUser])
    discard backups.saveSnapshot(esMachine, "批量编辑 Path", app.vars[esMachine])
    discard backups.saveSnapshot(esUser, "删除变量 GOPATH", app.vars[esUser])
    app.openBackups()
  of "modal":
    app.deleteNames(@["GOPATH"])
  of "toast":
    app.showToast("已保存 “Path”")
  else:
    discard
  if scene != "backups":
    app.snapshots = @[Snapshot(id: "1", time: "2026-11-15 10:42:00",
      scope: esUser, note: "编辑变量 Path", variables: @[])]
  let narrow = scene == "narrow"
  let width = if narrow: 900.0'f32 else: 1180.0'f32
  let height = if narrow: 620.0'f32 else: 780.0'f32
  let tester = newTester(proc(c: Context) = app.appView(c), width, height)
  discard tester.render()
  when defined(macosx):
    let path = outDir / ("env-" & scene & ".png")
    if renderSceneToPng(tester.scene, path):
      echo path
    else:
      echo "failed to render ", path
  else:
    echo "capture requires macOS CoreGraphics"
  removeDir(dataDir)

when isMainModule:
  let args = commandLineParams()
  let outDir = if args.len > 0: args[0] else: "dist/screenshots"
  let scene = if args.len > 1: args[1] else: "main"
  capture(outDir, scene)
