## Feasibility spike 4: compile-time type reflection for a typed IPC/TS client,
## and JSON (de)serialization of Nim objects.
##   nim c -r --mm:orc spike_meta.nim

import std/[macros, json, jsonutils, strutils]

type
  Note = object
    id: int
    title: string
    done: bool
  Greeter = ref object

proc greet(self: Greeter, name: string, times: int): string =
  result = ("Hello, " & name & "! ").repeat(times)

proc save(self: Greeter, note: Note): int =
  note.id

proc tsType(t: NimNode): string =
  case t.kind
  of nnkBracketExpr:
    if t[0].eqIdent("seq"): return "Array<" & tsType(t[1]) & ">"
    if t[0].eqIdent("Option"): return tsType(t[1]) & " | null"
    "unknown"
  else:
    case t.strVal
    of "string": "string"
    of "int", "int64", "float", "float64": "number"
    of "bool": "boolean"
    else: t.strVal

macro tsClient(procs: varargs[typed]): untyped =
  ## Emits TypeScript method signatures from Nim proc symbols.
  var lines: seq[string]
  for p in procs:
    let impl = getTypeImpl(p)
    echo "TYPE TREE for ", p.repr, ":\n", impl.treeRepr
    let params = impl[0]
    var args: seq[string]
    var ret = "void"
    for i in 1 ..< params.len:
      let name = params[i][0].strVal
      let typ = tsType(params[i][1])
      args.add(name & ": " & typ)
    let rt = params[0]
    if not (rt.kind == nnkEmpty or rt.repr == "void"):
      ret = tsType(rt)
    let procName = p.strVal.split('.')[^1]
    lines.add("  " & procName & "(" & args.join(", ") & "): Promise<" & ret & ">;")
  let text = "export interface Api {\n" & lines.join("\n") & "\n}\n"
  echo "GENERATED TYPESCRIPT:\n", text
  result = newLit(text)

const generatedTs = tsClient(greet, save)

when isMainModule:
  echo generatedTs
  let n = Note(id: 7, title: "hello", done: true)
  let j = %*n
  echo "to json: ", j
  let back = j.to(Note)
  echo "from json: ", back
  doAssert back == n
  echo "OK"
