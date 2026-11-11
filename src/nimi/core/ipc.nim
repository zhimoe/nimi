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

import std/[atomics, json, macros, strutils, tables]

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

  IpcCallContext* = object
    control: ptr Atomic[bool]

  IpcWork* = proc(args: string, context: IpcCallContext): string
    {.nimcall, gcsafe.}
    ## Runs on a worker thread. The argument and result are JSON strings; the
    ## work must not touch UI state or non-thread-safe application globals.
    ## Check context.isCancelled() at safe points in long operations.

  BackgroundMethod* = object
    name*: string
    params*: seq[ParamDef]
    resultType*: string
    work*: IpcWork
    timeoutMs*: int

  BackgroundService* = object
    name*: string
    methods*: seq[BackgroundMethod]

var services*: seq[ServiceDef]
var backgroundServices*: seq[BackgroundService]
var backgroundMethods*: Table[string, BackgroundMethod]

proc bindServiceImpl*(s: ServiceDef) =
  for existing in services:
    if existing.name == s.name:
      raise newException(ValueError, "service already bound: " & s.name)
  for m in s.methods:
    let key = s.name & "." & m.name
    if backgroundMethods.hasKey(key):
      raise newException(ValueError,
        "method already bound in the background pool: " & key)
  services.add s

proc isCancelled*(context: IpcCallContext): bool {.inline.} =
  context.control != nil and context.control[].load()

proc newIpcCallContext*(control: ptr Atomic[bool]): IpcCallContext =
  IpcCallContext(control: control)

proc backgroundMethod*(name: string, work: IpcWork,
                       params: openArray[ParamDef] = [],
                       resultType: string = "unknown",
                       timeoutMs: int = 30_000): BackgroundMethod =
  ## Describe one method that runs in the IPC worker pool. A positive timeout
  ## rejects the page promise when the deadline passes; work should also check
  ## its IpcCallContext to stop early.
  BackgroundMethod(name: name, params: @params, resultType: resultType,
                   work: work, timeoutMs: timeoutMs)

proc bindBackgroundService*(service: string,
                            methods: openArray[BackgroundMethod]) =
  ## Register JSON-string methods that may run off the UI thread. The same
  ## service name may also have synchronous bindService methods; TypeScript
  ## generation merges both under one client object.
  if service.len == 0 or service.contains('.'):
    raise newException(ValueError, "invalid background service name: " & service)
  for existing in services:
    if existing.name == service:
      for syncMethod in existing.methods:
        for bm in methods:
          if syncMethod.name == bm.name:
            raise newException(ValueError,
              "method already bound on the UI thread: " & service & "." &
              bm.name)
  var index = -1
  for i, existing in backgroundServices:
    if existing.name == service:
      index = i
      break
  if index < 0:
    backgroundServices.add BackgroundService(name: service)
    index = backgroundServices.high
  for bm in methods:
    if bm.name.len == 0 or bm.name.contains('.'):
      raise newException(ValueError, "invalid background method name: " &
                         bm.name)
    if bm.work == nil:
      raise newException(ValueError, "background method has no work: " &
                         service & "." & bm.name)
    if bm.timeoutMs < 0:
      raise newException(ValueError, "invalid background method timeout: " &
                         service & "." & bm.name)
    let key = service & "." & bm.name
    if backgroundMethods.hasKey(key):
      raise newException(ValueError, "background method already bound: " & key)
    backgroundMethods[key] = bm
    backgroundServices[index].methods.add bm

proc hasBackgroundMethod*(methodName: string): bool =
  backgroundMethods.hasKey(methodName)

proc backgroundWork*(methodName: string): IpcWork =
  if backgroundMethods.hasKey(methodName):
    backgroundMethods[methodName].work
  else:
    nil

proc backgroundTimeout*(methodName: string): int =
  if backgroundMethods.hasKey(methodName):
    backgroundMethods[methodName].timeoutMs
  else:
    0

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
  ## Mostly for tests and diagnostics. UI-thread methods come first.
  for s in services:
    for m in s.methods:
      result.add s.name & "." & m.name
  for s in backgroundServices:
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
  ## Synchronous and background methods of the same service share one object.
  result = "// Code generated by `nimi generate`. DO NOT EDIT.\n\n"
  result.add "import { call } from \"./nimi-runtime\";\n\n"
  var names: seq[string]
  for svc in services:
    if svc.name notin names: names.add svc.name
  for svc in backgroundServices:
    if svc.name notin names: names.add svc.name
  for name in names:
    result.add "export const " & name & " = {\n"
    for svc in services:
      if svc.name != name:
        continue
      for m in svc.methods:
        var params: seq[string]
        for p in m.params:
          params.add p.name & ": " & tsType(p.typ)
        let ret = tsType(m.resultType)
        result.add "  " & m.name & "(" & params.join(", ") & "): Promise<" &
                   ret & "> {\n"
        result.add "    return call(\"" & name & "." & m.name & "\""
        for p in m.params:
          result.add ", " & p.name
        result.add ") as Promise<" & ret & ">;\n"
        result.add "  },\n"
    for svc in backgroundServices:
      if svc.name != name:
        continue
      for m in svc.methods:
        var params: seq[string]
        for p in m.params:
          params.add p.name & ": " & tsType(p.typ)
        let ret = tsType(m.resultType)
        result.add "  " & m.name & "(" & params.join(", ") & "): Promise<" &
                   ret & "> {\n"
        result.add "    return call(\"" & name & "." & m.name & "\""
        for p in m.params:
          result.add ", " & p.name
        result.add ") as Promise<" & ret & ">;\n"
        result.add "  },\n"
    result.add "} as const;\n\n"
