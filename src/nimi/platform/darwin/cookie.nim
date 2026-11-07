## WKHTTPCookieStore access using global Objective-C blocks.

import std/deques
import ../contract
import ./objc

type
  BlockDescriptor {.bycopy.} = object
    reserved: uint
    size: uint
  BlockLiteral {.bycopy.} = object
    isa: pointer
    flags: int32
    reserved: int32
    invoke: pointer
    descriptor: ptr BlockDescriptor

var
  cookieDescriptor: BlockDescriptor
  cookieBlock: BlockLiteral
  clearDescriptor: BlockDescriptor
  clearBlock: BlockLiteral
  pendingCookieCallback: proc(cookies: seq[PlatformCookie]) {.closure.}
  pendingClearCallback: proc() {.closure.}

var operations: Deque[proc()]
var operationActive = false

proc advanceOperation() =
  operationActive = false
  if operations.len > 0:
    operationActive = true
    let operation = operations.popFirst()
    operation()

proc enqueueOperation(operation: proc()) =
  operations.addLast(operation)
  if not operationActive:
    advanceOperation()

proc cookiesDone(blk: pointer, cookies: Id) {.cdecl.}
proc clearDone(blk: pointer) {.cdecl.}

proc ensureBlocks() =
  if cookieBlock.isa != nil:
    return
  cookieDescriptor = BlockDescriptor(reserved: 0, size: uint(sizeof(BlockLiteral)))
  cookieBlock = BlockLiteral(
    isa: globalBlockIsa,
    flags: int32(1 shl 28),
    reserved: 0,
    invoke: cast[pointer](cookiesDone),
    descriptor: addr cookieDescriptor)
  clearDescriptor = BlockDescriptor(reserved: 0, size: uint(sizeof(BlockLiteral)))
  clearBlock = BlockLiteral(
    isa: globalBlockIsa,
    flags: int32(1 shl 28),
    reserved: 0,
    invoke: cast[pointer](clearDone),
    descriptor: addr clearDescriptor)

proc cookiesDone(blk: pointer, cookies: Id) {.cdecl.} =
  var list: seq[PlatformCookie]
  if cookies != nil:
    let count = int(sendInt(cookies, sel("count")))
    for i in 0 ..< count:
      let c = sendIdUInt(cookies, sel("objectAtIndex:"), NSUInteger(i))
      if c == nil:
        continue
      list.add PlatformCookie(
        name: goString(send0(c, sel("name"))),
        value: goString(send0(c, sel("value"))),
        domain: goString(send0(c, sel("domain"))),
        path: goString(send0(c, sel("path"))),
        secure: sendBool(c, sel("isSecure")),
        httpOnly: sendBool(c, sel("isHTTPOnly")))
  let cb = pendingCookieCallback
  pendingCookieCallback = nil
  try:
    if cb != nil: cb(list)
  finally:
    advanceOperation()

proc clearDone(blk: pointer) {.cdecl.} =
  let cb = pendingClearCallback
  pendingClearCallback = nil
  try:
    if cb != nil: cb()
  finally:
    advanceOperation()

proc getCookies(cb: proc(cookies: seq[PlatformCookie])) =
  ensureBlocks()
  pendingCookieCallback = cb
  let store = send0(loadClass("WKWebsiteDataStore"), sel("defaultDataStore"))
  let cookieStore = if store != nil: send0(store, sel("httpCookieStore")) else: nil
  if cookieStore == nil:
    pendingCookieCallback = nil
    try:
      if cb != nil: cb(@[])
    finally:
      advanceOperation()
    return
  sendVoidId(cookieStore, sel("getAllCookies:"), cast[pointer](addr cookieBlock))

proc clearCookies(cb: proc()) =
  ensureBlocks()
  pendingClearCallback = cb
  let store = send0(loadClass("WKWebsiteDataStore"), sel("defaultDataStore"))
  if store == nil:
    pendingClearCallback = nil
    try:
      if cb != nil: cb()
    finally:
      advanceOperation()
    return
  let cookieType = nsConstant(webkit, "WKWebsiteDataTypeCookies")
  let types = sendId1(loadClass("NSSet"), sel("setWithObject:"),
                      if cookieType != nil: cookieType
                      else: nsString("WKWebsiteDataTypeCookies"))
  let epoch = sendIdDouble(loadClass("NSDate"),
                           sel("dateWithTimeIntervalSince1970:"), 0.0)
  sendVoidId3(store, sel("removeDataOfTypes:modifiedSince:completionHandler:"),
              types, epoch, cast[Id](addr clearBlock))

proc installCookieBackend*(b: Backend) =
  if b == nil:
    return
  b.getCookies = proc(cb: proc(cookies: seq[PlatformCookie])) =
    enqueueOperation(proc() = getCookies(cb))
  b.clearCookies = proc(cb: proc()) =
    enqueueOperation(proc() = clearCookies(cb))
