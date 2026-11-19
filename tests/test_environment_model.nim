import std/[strutils, unittest]

import ../examples/environment/model

proc v(name, value: string,
       kind: EnvironmentKind = ekString): Variable =
  Variable(name: name, value: value, kind: kind)

suite "environment model":
  test "display and raw splits preserve the difference":
    check splitValue("C:\\A;;C:\\B;").join("|") == "C:\\A|C:\\B"
    check rawSplit("C:\\A;;C:\\B;").join("|") == "C:\\A||C:\\B|"
    check splitValue("").len == 1
    check rawSplit("").len == 1
    check isMultiValue("a;b")
    check not isMultiValue("a")

  test "references and list-like names":
    check hasRef("%USERPROFILE%\\bin")
    check not hasRef("100% done")
    check isListLike("Path")
    check isListLike("PSModulePath")
    check not isListLike("JAVA_HOME")

  test "filter, search and sort":
    let vars = @[v("Path", "C:\\A;C:\\B"), v("JAVA_HOME", "%JAVA%"),
                 v("GOPATH", "C:\\go")]
    check filtered(vars, vfPath, "", false).len == 1
    check filtered(vars, vfMulti, "", false).len == 1
    check filtered(vars, vfRefs, "", false).len == 1
    check filtered(vars, vfAll, "go", false).len == 1
    let sorted = filtered(vars, vfAll, "", true)
    check sorted[0].name == "Path"

  test "overlap is directional":
    let user = @[v("Path", "user"), v("ONLY_USER", "x")]
    let system = @[v("Path", "system"), v("ONLY_SYSTEM", "y")]
    check overlap(esUser, "Path", user, system) == 2
    check overlap(esMachine, "Path", user, system) == 1
    check overlap(esUser, "ONLY_USER", user, system) == 0

  test "diff and merge preserve unrelated external changes":
    let before = @[v("A", "1"), v("B", "2")]
    let desired = @[v("A", "1"), v("B", "3"), v("C", "4")]
    let changes = diff(before, desired)
    check changes.upserts.len == 2
    check changes.deletions.len == 0

    let latest = @[v("A", "1"), v("B", "external"), v("D", "new")]
    let merged = mergeChanges(latest, before, desired)
    check merged.findVariable("A") >= 0
    check merged[merged.findVariable("B")].value == "3"
    check merged.findVariable("C") >= 0
    check merged.findVariable("D") >= 0

    let deleted = mergeChanges(latest, before, @[v("A", "1")])
    check deleted.findVariable("B") < 0
    check deleted.findVariable("D") >= 0

  test "validation rejects unsafe names and duplicates":
    check validate(@[v("A", "1")]).len == 0
    check validate(@[v("", "1")]).len > 0
    check validate(@[v("A=B", "1")]).len > 0
    check validate(@[v("a", "1"), v("A", "2")]).len > 0
    check validate(@[v("A", "1\0")]).len > 0

  test "batch parsing and diff analysis":
    let parsed = batchParse("C:\\A\n\nC:\\B; C:\\A\n")
    check parsed.entries == @["C:\\A", "C:\\B", "C:\\A"]
    check parsed.ignored == 2
    let info = analyzeBatch("C:\\A;C:\\B", "C:\\B\nC:\\A\nC:\\C")
    check info.added == @["C:\\C"]
    check info.removed.len == 0
    check info.reordered
    check info.hasChanges
    let duplicates = analyzeBatch("C:\\A", "C:\\A\nC:\\A")
    check duplicates.duplicates == @["C:\\A"]

  test "export uses checked variables and raw values":
    let vars = @[v("A", "1"), v("B", "x;y")]
    let keys = @[varKey(esUser, "A")]
    check exportLines(vars, keys) == "A=1"
    check exportLines(vars, @[]) == "A=1\nB=x;y"
