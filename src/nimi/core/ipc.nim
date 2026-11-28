## Typed IPC: compile-time service registration, background service macros,
## streaming chunk/event helpers, and rich TypeScript schema generation.

import std/[atomics, json, macros, options, strutils, tables]

import ./pageevents

export options

type
  ParamDef* = object
    name*: string
    typ*: string
    tsType*: string

  TypeFieldDef* = object
    name*: string
    tsType*: string
    optional*: bool

  TypeSchemaKind* = enum
    tskInterface
    tskEnum

  TypeSchemaDef* = object
    name*: string
    kind*: TypeSchemaKind
    fields*: seq[TypeFieldDef]
    enumValues*: seq[string]

  MethodDef* = object
    name*: string
    params*: seq[ParamDef]
    resultType*: string
    tsResultType*: string
    call*: proc(args: JsonNode): JsonNode {.closure.}

  ServiceDef* = object
    name*: string
    methods*: seq[MethodDef]

  IpcCallContext* = object
    control: ptr Atomic[bool]
    windowId*: uint64
    callId*: int64

  IpcWork* = proc(args: string, context: IpcCallContext): string
    {.nimcall, gcsafe.}
    ## Runs on a worker thread. The argument and result are JSON strings; the
    ## work must not touch UI state or non-thread-safe application globals.
    ## Check context.isCancelled() at safe points in long operations.

  BackgroundMethod* = object
    name*: string
    params*: seq[ParamDef]
    resultType*: string
    tsResultType*: string
    streaming*: bool
    work*: IpcWork
    timeoutMs*: int

  BackgroundService* = object
    name*: string
    methods*: seq[BackgroundMethod]

  IpcAppError* = object of CatchableError
    kind*: string
    hint*: string

var services*: seq[ServiceDef]
var backgroundServices*: seq[BackgroundService]
var backgroundMethods*: Table[string, BackgroundMethod]
var typeSchemas*: seq[TypeSchemaDef]

proc newIpcError*(kind, message: string, hint: string = ""): ref IpcAppError =
  result = newException(IpcAppError, message)
  result.kind = kind
  result.hint = hint

proc registerTypeSchema*(schema: TypeSchemaDef) =
  if schema.name.len == 0:
    return
  for existing in typeSchemas:
    if existing.name == schema.name:
      return
  typeSchemas.add schema

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

proc newIpcCallContext*(control: ptr Atomic[bool],
                        windowId: uint64 = 0,
                        callId: int64 = 0): IpcCallContext =
  IpcCallContext(control: control, windowId: windowId, callId: callId)

proc sendChunk*(context: IpcCallContext, chunkJson: string): bool {.gcsafe.} =
  ## Stream an intermediate JSON payload chunk to the calling page promise.
  ## Returns false if the call has been cancelled or has no window receiver.
  if context.isCancelled() or context.windowId == 0 or context.callId <= 0:
    return false
  queueStreamChunk(context.windowId, context.callId, chunkJson)
  true

proc emit*(context: IpcCallContext, name: string,
           payloadJson: string = "{}") {.gcsafe.} =
  ## Thread-safe event push to the window that initiated this background call.
  if context.windowId != 0:
    queuePageEvent(context.windowId, name, payloadJson)

proc broadcast*(context: IpcCallContext, name: string,
                payloadJson: string = "{}") {.gcsafe.} =
  ## Thread-safe event broadcast from a background worker to all open windows.
  queuePageEvent(0, name, payloadJson)

proc backgroundMethod*(name: string, work: IpcWork,
                       params: openArray[ParamDef] = [],
                       resultType: string = "unknown",
                       timeoutMs: int = 30_000,
                       streaming: bool = false,
                       tsResultType: string = ""): BackgroundMethod =
  BackgroundMethod(
    name: name,
    params: @params,
    resultType: resultType,
    tsResultType: tsResultType,
    streaming: streaming,
    work: work,
    timeoutMs: timeoutMs)

proc bindBackgroundService*(service: string,
                            methods: openArray[BackgroundMethod]) =
  ## Register JSON-string methods that run off the UI thread. The same
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

proc parseArgsArray*(rawArgs: string): JsonNode =
  if rawArgs.len == 0:
    return newJArray()
  let parsed = parseJson(rawArgs)
  if parsed.kind == JArray:
    return parsed
  result = newJArray()
  result.add parsed

proc argAt*(args: JsonNode, index: int): JsonNode =
  if args != nil and args.kind == JArray and index < args.len:
    args[index]
  else:
    newJNull()

proc decodeArg*[T](n: JsonNode): T =
  when T is JsonNode:
    n
  else:
    n.to(T)

proc encodeResult*[T](v: T): JsonNode =
  when T is JsonNode:
    if v == nil: newJNull() else: v
  else:
    %*v

proc encodeResultStr*[T](v: T): string =
  $encodeResult(v)

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

# --- compile-time AST -> TypeScript reflection -----------------------------

proc typeName(t: NimNode): string =
  case t.kind
  of nnkSym, nnkIdent:
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
  case t.kind
  of nnkRefTy, nnkPtrTy:
    typeNode(t[0])
  else:
    t

proc cleanIdentName(n: NimNode): string =
  case n.kind
  of nnkPostfix:
    cleanIdentName(n[1])
  of nnkPragmaExpr:
    cleanIdentName(n[0])
  of nnkSym, nnkIdent:
    n.strVal
  else:
    n.repr

proc resolveTsTypeAndEmitSchemas(t: NimNode, regStmts: NimNode,
                                 visited: var seq[string]): string

proc collectRecFields(recList: NimNode, fields: var NimNode,
                      regStmts: NimNode, visited: var seq[string]) =
  if recList.kind in {nnkEmpty, nnkNilLit}:
    return
  case recList.kind
  of nnkRecList:
    for item in recList:
      collectRecFields(item, fields, regStmts, visited)
  of nnkIdentDefs:
    if recList.len >= 3:
      let fieldType = recList[^2]
      let isOpt = fieldType.kind == nnkBracketExpr and
                  fieldType.len == 2 and
                  typeName(fieldType[0]) in ["Option", "options.Option"]
      let innerTs =
        if isOpt:
          resolveTsTypeAndEmitSchemas(fieldType[1], regStmts, visited) & " | null"
        else:
          resolveTsTypeAndEmitSchemas(fieldType, regStmts, visited)
      for j in 0 ..< recList.len - 2:
        let fname = cleanIdentName(recList[j])
        if fname.len > 0 and fname != "_":
          fields.add newTree(nnkObjConstr, bindSym"TypeFieldDef",
            newTree(nnkExprColonExpr, ident("name"), newLit(fname)),
            newTree(nnkExprColonExpr, ident("tsType"), newLit(innerTs)),
            newTree(nnkExprColonExpr, ident("optional"), newLit(isOpt)))
  of nnkRecCase:
    collectRecFields(recList[0], fields, regStmts, visited)
    for b in 1 ..< recList.len:
      let branch = recList[b]
      if branch.len > 0:
        collectRecFields(branch[^1], fields, regStmts, visited)
  else:
    discard

proc resolveTsTypeAndEmitSchemas(t: NimNode, regStmts: NimNode,
                                 visited: var seq[string]): string =
  if t.kind == nnkEmpty:
    return "void"
  if t.kind in {nnkRefTy, nnkPtrTy}:
    return resolveTsTypeAndEmitSchemas(t[0], regStmts, visited)
  if t.kind == nnkBracketExpr and t.len >= 2:
    let head = typeName(t[0])
    if head in ["seq", "openArray"]:
      let elem = resolveTsTypeAndEmitSchemas(t[1], regStmts, visited)
      if elem.contains(" | "):
        return "(" & elem & ")[]"
      return elem & "[]"
    if head in ["Option", "options.Option"]:
      let elem = resolveTsTypeAndEmitSchemas(t[1], regStmts, visited)
      return elem & " | null"
    if head in ["Table", "OrderedTable"] and t.len >= 3:
      let val = resolveTsTypeAndEmitSchemas(t[2], regStmts, visited)
      return "Record<string, " & val & ">"

  let name = typeName(t)
  case name
  of "string", "cstring":
    return "string"
  of "int", "int8", "int16", "int32", "int64",
     "uint", "uint8", "uint16", "uint32", "uint64",
     "float", "float32", "float64", "BiggestInt":
    return "number"
  of "bool":
    return "boolean"
  of "void":
    return "void"
  of "JsonNode":
    return "unknown"
  else:
    discard

  if t.kind == nnkSym:
    let symName = t.strVal
    let impl = getTypeImpl(t)
    var objNode = impl
    if objNode.kind in {nnkRefTy, nnkPtrTy} and objNode.len > 0:
      objNode = getTypeImpl(objNode[0])
    if objNode.kind == nnkObjectTy and symName.len > 0 and
        symName notin ["JsonNodeObj", "RootObj", "Exception", "CatchableError"]:
      if symName notin visited:
        visited.add symName
        var fieldsBracket = newNimNode(nnkBracket)
        if objNode.len >= 3:
          collectRecFields(objNode[2], fieldsBracket, regStmts, visited)
        let schemaExpr = newTree(nnkObjConstr, bindSym"TypeSchemaDef",
          newTree(nnkExprColonExpr, ident("name"), newLit(symName)),
          newTree(nnkExprColonExpr, ident("kind"), bindSym"tskInterface"),
          newTree(nnkExprColonExpr, ident("fields"),
            newTree(nnkPrefix, ident("@"), fieldsBracket)))
        regStmts.add newCall(bindSym"registerTypeSchema", schemaExpr)
      return symName
    elif objNode.kind == nnkEnumTy and symName.len > 0:
      if symName notin visited:
        visited.add symName
        var valsBracket = newNimNode(nnkBracket)
        for k in 1 ..< objNode.len:
          let ev = cleanIdentName(objNode[k])
          if ev.len > 0:
            valsBracket.add newLit(ev)
        let schemaExpr = newTree(nnkObjConstr, bindSym"TypeSchemaDef",
          newTree(nnkExprColonExpr, ident("name"), newLit(symName)),
          newTree(nnkExprColonExpr, ident("kind"), bindSym"tskEnum"),
          newTree(nnkExprColonExpr, ident("enumValues"),
            newTree(nnkPrefix, ident("@"), valsBracket)))
        regStmts.add newCall(bindSym"registerTypeSchema", schemaExpr)
      return symName
  "unknown"

proc resolveProc(p: NimNode, serviceName: string): NimNode =
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
  ## Register a UI-thread service instance and the procs pages may call.
  let serviceName = typeName(getTypeInst(instance))
  var methodDefs = newNimNode(nnkBracket)
  var schemaRegs = newStmtList()
  var visited: seq[string]

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
      let paramType = typeNode(formal[i][1])
      let tsParam = resolveTsTypeAndEmitSchemas(formal[i][1], schemaRegs, visited)
      for j in 0 ..< formal[i].len - 2:
        let paramName = formal[i][j].strVal
        let decodeInst = newTree(nnkBracketExpr, bindSym"decodeArg", paramType)
        let argNode = newCall(bindSym"argAt", ident("args"), newLit(argIndex))
        callNode.add newCall(decodeInst, argNode)
        paramDefs.add newTree(nnkObjConstr, bindSym"ParamDef",
          newTree(nnkExprColonExpr, ident("name"), newLit(paramName)),
          newTree(nnkExprColonExpr, ident("typ"), newLit(typeName(formal[i][1]))),
          newTree(nnkExprColonExpr, ident("tsType"), newLit(tsParam)))
        inc argIndex

    let isVoid = retType.kind == nnkEmpty or retType.repr == "void"
    let tsRet = if isVoid: "void"
                else: resolveTsTypeAndEmitSchemas(retType, schemaRegs, visited)
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
      newTree(nnkExprColonExpr, ident("tsResultType"), newLit(tsRet)),
      newTree(nnkExprColonExpr, ident("call"), lambda))

  let serviceDef = newTree(nnkObjConstr, bindSym"ServiceDef",
    newTree(nnkExprColonExpr, ident("name"), newLit(serviceName)),
    newTree(nnkExprColonExpr, ident("methods"),
             newTree(nnkPrefix, ident("@"), methodDefs)))

  let bindBlock = newStmtList(
    schemaRegs,
    newTree(nnkLetSection,
            newIdentDefs(ident("inst"), newEmptyNode(), instance)),
    newCall(bindSym"bindServiceImpl", serviceDef))

  result = newTree(nnkBlockStmt, newEmptyNode(), bindBlock)

macro bindBackground*(serviceName: static[string],
                      procs: varargs[typed]): untyped =
  ## Macro-driven typed background IPC registration!
  ## Binds `{.gcsafe.}` Nim procs directly to the background worker pool with
  ## automatic JSON argument decoding, result encoding, optional trailing
  ## `IpcCallContext` injection, and full TypeScript interface generation.
  var bgMethods = newNimNode(nnkBracket)
  var wrapperProcs = newStmtList()
  var schemaRegs = newStmtList()
  var visited: seq[string]

  for idx, p in procs:
    let chosen =
      if p.kind == nnkSym: p
      elif p.kind in {nnkClosedSymChoice, nnkOpenSymChoice} and p.len == 1: p[0]
      else:
        error("bindBackground: expected an unambiguous proc symbol, got " & p.repr, p)
    let impl = getTypeImpl(chosen)
    let formal = impl[0]
    let retType = formal[0]
    let procName = chosen.strVal.split('.')[^1]
    let wrapperName = genSym(nskProc, "bgWrap_" & procName)

    var paramDefs = newNimNode(nnkBracket)
    var callNode = newCall(chosen)
    let rawArgsSym = ident("rawArgs")
    let ctxSym = ident("ctx")
    let parsedArgsSym = genSym(nskLet, "parsedArgs")

    var argIndex = 0
    for i in 1 ..< formal.len:
      let pType = formal[i][^2]
      let pTypeName = typeName(pType)
      for j in 0 ..< formal[i].len - 2:
        let pName = formal[i][j].strVal
        if pTypeName == "IpcCallContext":
          callNode.add ctxSym
        else:
          let tsParam = resolveTsTypeAndEmitSchemas(pType, schemaRegs, visited)
          let decodeInst = newTree(nnkBracketExpr, bindSym"decodeArg", typeNode(pType))
          let argNode = newCall(bindSym"argAt", parsedArgsSym, newLit(argIndex))
          callNode.add newCall(decodeInst, argNode)
          paramDefs.add newTree(nnkObjConstr, bindSym"ParamDef",
            newTree(nnkExprColonExpr, ident("name"), newLit(pName)),
            newTree(nnkExprColonExpr, ident("typ"), newLit(pTypeName)),
            newTree(nnkExprColonExpr, ident("tsType"), newLit(tsParam)))
          inc argIndex

    let isVoid = retType.kind == nnkEmpty or retType.repr == "void"
    let tsRet = if isVoid: "void"
                else: resolveTsTypeAndEmitSchemas(retType, schemaRegs, visited)

    let invokeStmt =
      if isVoid:
        newStmtList(callNode, newLit("null"))
      else:
        let encStrInst = newTree(nnkBracketExpr, bindSym"encodeResultStr",
                                 typeNode(retType))
        newStmtList(newCall(encStrInst, callNode))

    let wrapperBody = newStmtList(
      newTree(nnkLetSection,
        newIdentDefs(parsedArgsSym, newEmptyNode(),
          newCall(bindSym"parseArgsArray", rawArgsSym))),
      newTree(nnkPragmaBlock,
        newTree(nnkPragma, ident("gcsafe")),
        invokeStmt)
    )

    let wrapperProc = newTree(nnkProcDef,
      wrapperName,
      newEmptyNode(),
      newEmptyNode(),
      newTree(nnkFormalParams,
        bindSym"string",
        newIdentDefs(rawArgsSym, bindSym"string"),
        newIdentDefs(ctxSym, bindSym"IpcCallContext")),
      newTree(nnkPragma, ident("nimcall"), ident("gcsafe")),
      newEmptyNode(),
      wrapperBody)
    wrapperProcs.add wrapperProc

    bgMethods.add newCall(bindSym"backgroundMethod",
      newLit(procName),
      wrapperName,
      newTree(nnkExprEqExpr, ident("params"), paramDefs),
      newTree(nnkExprEqExpr, ident("resultType"),
        newLit(if isVoid: "void" else: typeName(retType))),
      newTree(nnkExprEqExpr, ident("tsResultType"), newLit(tsRet)))

  result = newTree(nnkBlockStmt, newEmptyNode(), newStmtList(
    schemaRegs,
    wrapperProcs,
    newCall(bindSym"bindBackgroundService", newLit(serviceName), bgMethods)
  ))

# --- TypeScript ------------------------------------------------------------

proc fallbackTsType(t: string): string =
  case t
  of "string", "cstring":
    "string"
  of "int", "int8", "int16", "int32", "int64",
     "uint", "uint8", "uint16", "uint32", "uint64",
     "float", "float32", "float64", "BiggestInt":
    "number"
  of "bool":
    "boolean"
  of "void":
    "void"
  else:
    "unknown"

proc effectiveTsParam(p: ParamDef): string =
  if p.tsType.len > 0: p.tsType else: fallbackTsType(p.typ)

proc effectiveTsResult(rawType, richType: string): string =
  if richType.len > 0: richType else: fallbackTsType(rawType)

proc generateTypeScript*(): string =
  ## Emit the client and all reflected Nim object/enum schemas.
  result = "// Code generated by `nimi generate`. DO NOT EDIT.\n\n"
  result.add "import { call } from \"./nimi-runtime\";\n\n"

  for schema in typeSchemas:
    case schema.kind
    of tskInterface:
      result.add "export interface " & schema.name & " {\n"
      for f in schema.fields:
        let optMark = if f.optional: "?" else: ""
        result.add "  " & f.name & optMark & ": " & f.tsType & ";\n"
      result.add "}\n\n"
    of tskEnum:
      if schema.enumValues.len > 0:
        var literals: seq[string]
        for v in schema.enumValues:
          literals.add "\"" & v & "\""
        result.add "export type " & schema.name & " = " &
                   literals.join(" | ") & ";\n\n"

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
          params.add p.name & ": " & effectiveTsParam(p)
        let ret = effectiveTsResult(m.resultType, m.tsResultType)
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
          params.add p.name & ": " & effectiveTsParam(p)
        let ret = effectiveTsResult(m.resultType, m.tsResultType)
        result.add "  " & m.name & "(" & params.join(", ") & "): Promise<" &
                   ret & "> {\n"
        result.add "    return call(\"" & name & "." & m.name & "\""
        for p in m.params:
          result.add ", " & p.name
        result.add ") as Promise<" & ret & ">;\n"
        result.add "  },\n"
    result.add "} as const;\n\n"
