## Typed IPC: compile-time service registration and JSON dispatch.
##
## Nim has no runtime method-set reflection, so a service is bound explicitly:
##
##   type Greeter = ref object
##   proc greet(self: Greeter, name: string): string =
##     "Hello " & name
##
##   let greeter = Greeter()
##   bindService(greeter, greet)
##
## The macro generates a MethodDef per proc: JSON args are decoded into the
## proc's parameter types, the proc is called, and its result is encoded back.
## The same descriptors drive TypeScript generation (see ../tsgen.nim).

import std/[json, macros, strutils]

type
  ParamDef* = object
    name*: string
    typ*: string

  MethodDef* = object
    name*: string
    params*: seq[ParamDef]
    resultType*: string
    call*: proc(args: JsonNode): JsonNode {.closure.}

  ServiceDef* = object
    name*: string
    methods*: seq[MethodDef]

var services*: seq[ServiceDef]

proc bindServiceImpl*(s: ServiceDef) =
  for existing in services:
    if existing.name == s.name:
      raise newException(ValueError, "service already bound: " & s.name)
  services.add s

proc argAt*(args: JsonNode, index: int): JsonNode =
  ## Index helper bound by the macro. Keeping it here means user modules do
  ## not need to import std/json just to compile generated dispatch code.
  args[index]

proc decodeArg*[T](n: JsonNode): T =
  ## Decode one IPC argument. Instantiated by the bindService macro.
  n.to(T)

proc encodeResult*[T](v: T): JsonNode =
  ## Encode one IPC result. Instantiated by the bindService macro.
  %*v

proc dispatch*(methodName: string, args: JsonNode): JsonNode =
  ## Call "Service.method" with a JSON array of arguments.
  let dot = methodName.find('.')
  if dot <= 0 or dot == methodName.high:
    raise newException(ValueError, "invalid method name: " & methodName)
  let service = methodName[0 ..< dot]
  let name = methodName[dot + 1 .. ^1]
  for s in services:
    if s.name == service:
      for m in s.methods:
        if m.name == name:
          return m.call(args)
      raise newException(ValueError, "unknown method: " & methodName)
  raise newException(ValueError, "unknown service: " & service)

proc methodNames*(): seq[string] =
  ## Mostly for tests and diagnostics.
  for s in services:
    for m in s.methods:
      result.add s.name & "." & m.name

# --- macro -----------------------------------------------------------------

proc typeName(t: NimNode): string =
  case t.kind
  of nnkSym:
    t.strVal
  of nnkRefTy, nnkPtrTy:
    typeName(t[0])
  of nnkBracketExpr:
    var parts: seq[string]
    for i in 0 ..< t.len:
      parts.add typeName(t[i])
    parts.join(".")
  of nnkEmpty:
    "void"
  else:
    t.repr

proc typeNode(t: NimNode): NimNode =
  ## The type node used in generated generics. Strip ref/ptr wrappers.
  case t.kind
  of nnkRefTy, nnkPtrTy:
    typeNode(t[0])
  else:
    t

proc resolveProc(p: NimNode, serviceName: string): NimNode =
  ## Pick the overload whose first parameter is the service instance.
  if p.kind == nnkSym:
    return p
  if p.kind in {nnkClosedSymChoice, nnkOpenSymChoice}:
    var matches: seq[NimNode]
    for candidate in p:
      let t = getTypeImpl(candidate)
      if t.kind == nnkProcTy:
        let formal = t[0]
        if formal.len > 1 and typeName(formal[1][1]) == serviceName:
          matches.add candidate
    if matches.len == 1:
      return matches[0]
    if matches.len > 1:
      error("bindService: ambiguous method " & p.repr &
            "; rename it or bind a uniquely named proc", p)
    error("bindService: no overload of " & p.repr & " takes " &
          serviceName & " as its first parameter", p)
  error("bindService: expected a proc, got " & $p.kind, p)

macro bindService*(instance: typed, procs: varargs[typed]): untyped =
  ## Register a service instance and the procs pages may call.
  ## The first parameter of every proc is the instance (self); it is not
  ## exposed to the page.
  let serviceName = typeName(getTypeInst(instance))
  var methodDefs = newNimNode(nnkBracket)

  for p in procs:
    let chosen = resolveProc(p, serviceName)
    let impl = getTypeImpl(chosen)
    let formal = impl[0]
    let retType = formal[0]
    let procName = chosen.strVal.split('.')[^1]

    var paramDefs = newNimNode(nnkBracket)
    var callNode = newCall(chosen)
    callNode.add ident("inst")

    var argIndex = 0
    for i in 2 ..< formal.len:
      let paramName = formal[i][0].strVal
      let paramType = typeNode(formal[i][1])
      let decodeInst = newTree(nnkBracketExpr, bindSym"decodeArg", paramType)
      let argNode = newCall(bindSym"argAt", ident("args"), newLit(argIndex))
      callNode.add newCall(decodeInst, argNode)
      paramDefs.add newTree(nnkObjConstr, bindSym"ParamDef",
        newTree(nnkExprColonExpr, ident("name"), newLit(paramName)),
        newTree(nnkExprColonExpr, ident("typ"), newLit(typeName(formal[i][1]))))
      inc argIndex

    let isVoid = retType.kind == nnkEmpty or retType.repr == "void"
    let body =
      if isVoid:
        newStmtList(callNode, newCall(bindSym"newJNull"))
      else:
        let encInst = newTree(nnkBracketExpr, bindSym"encodeResult",
                              typeNode(retType))
        newStmtList(newTree(nnkReturnStmt, newCall(encInst, callNode)))

    let lambda = newProc(
      params = @[bindSym"JsonNode",
                 newIdentDefs(ident("args"), bindSym"JsonNode")],
      body = body,
      procType = nnkLambda)

    methodDefs.add newTree(nnkObjConstr, bindSym"MethodDef",
      newTree(nnkExprColonExpr, ident("name"), newLit(procName)),
      newTree(nnkExprColonExpr, ident("params"),
               newTree(nnkPrefix, ident("@"), paramDefs)),
      newTree(nnkExprColonExpr, ident("resultType"),
               newLit(if isVoid: "void" else: typeName(retType))),
      newTree(nnkExprColonExpr, ident("call"), lambda))

  let serviceDef = newTree(nnkObjConstr, bindSym"ServiceDef",
    newTree(nnkExprColonExpr, ident("name"), newLit(serviceName)),
    newTree(nnkExprColonExpr, ident("methods"),
             newTree(nnkPrefix, ident("@"), methodDefs)))

  let bindBlock = newStmtList(
    newTree(nnkLetSection,
            newIdentDefs(ident("inst"), newEmptyNode(), instance)),
    newCall(bindSym"bindServiceImpl", serviceDef))

  result = newTree(nnkBlockStmt, newEmptyNode(), bindBlock)

# --- TypeScript ------------------------------------------------------------

proc tsType(t: string): string =
  case t
  of "string":
    "string"
  of "int", "int8", "int16", "int32", "int64",
     "uint", "uint8", "uint16", "uint32", "uint64",
     "float", "float32", "float64":
    "number"
  of "bool":
    "boolean"
  of "void":
    "void"
  else:
    "unknown"

proc generateTypeScript*(): string =
  ## Emit the client. The method name is the Nim proc name (camelCase).
  result = "// Code generated by `nimi generate`. DO NOT EDIT.\n\n"
  result.add "import { call } from \"./nimi-runtime\";\n\n"
  for svc in services:
    result.add "export const " & svc.name & " = {\n"
    for m in svc.methods:
      var params: seq[string]
      for p in m.params:
        params.add p.name & ": " & tsType(p.typ)
      let ret = tsType(m.resultType)
      result.add "  " & m.name & "(" & params.join(", ") & "): Promise<" &
                 ret & "> {\n"
      result.add "    return call(\"" & svc.name & "." & m.name & "\""
      for p in m.params:
        result.add ", " & p.name
      result.add ") as Promise<" & ret & ">;\n"
      result.add "  },\n"
    result.add "} as const;\n\n"
