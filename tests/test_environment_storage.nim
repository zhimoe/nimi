import std/[os, tempfiles, unittest]

import ../examples/environment/[model, storage, theme]

proc v(name, value: string,
       kind: EnvironmentKind = ekString): Variable =
  Variable(name: name, value: value, kind: kind)

suite "environment storage":
  test "snapshots keep the newest twenty":
    let dir = createTempDir("nimi-env-store-", "")
    defer: removeDir(dir)
    let store = newStore(dir)
    for i in 0 ..< 25:
      discard store.saveSnapshot(esUser, "note " & $i,
                                 @[v("A", $i)])
    let snapshots = store.loadSnapshots()
    check snapshots.len == 20
    check snapshots[0].note == "note 24"
    check snapshots[^1].note == "note 5"
    check snapshots[0].variables[0].value == "24"

  test "pending claim and complete":
    let dir = createTempDir("nimi-env-store-", "")
    defer: removeDir(dir)
    let store = newStore(dir)
    store.writePending(PendingEdits(scope: esMachine, note: "done",
      focus: "Path", fullReplace: true, before: @[v("Path", "old")],
      variables: @[v("Path", "new")]))
    check store.hasPending()
    let pending = store.readPending()
    check pending.scope == esMachine
    check pending.focus == "Path"
    check pending.fullReplace
    check pending.variables[0].value == "new"
    let claimed = store.claimPending()
    check claimed.len > 0
    check not store.hasPending()
    let claimedPending = readPendingAt(store.dir / claimed)
    check claimedPending.scope == esMachine
    store.completePending(claimed)
    check not fileExists(store.dir / claimed)

  test "settings roundtrip":
    let dir = createTempDir("nimi-env-store-", "")
    defer: removeDir(dir)
    let store = newStore(dir)
    var settings = Settings(theme: tmDark, hasWindow: true, windowX: 10,
                            windowY: 20, windowWidth: 900, windowHeight: 640)
    store.saveSettings(settings)
    let loaded = store.loadSettings()
    check loaded.theme == tmDark
    check loaded.hasWindow
    check loaded.windowX == 10
    check loaded.windowWidth == 900

  test "corrupt snapshot history is reported":
    let dir = createTempDir("nimi-env-store-", "")
    defer: removeDir(dir)
    let store = newStore(dir)
    writeFile(dir / "snapshots.json", "{not json")
    expect StoreError:
      discard store.loadSnapshots()
