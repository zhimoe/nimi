import std/[atomics, json, monotimes, os, strutils, tables, times, unittest]

import nimi/core/[ipc, ipcpool, window]
import nimi/platform/contract

proc poolEcho(args: string, context: IpcCallContext): string {.gcsafe.} =
  let values = parseJson(args)
  $(%*("bg:" & values[0].getStr))

proc poolFail(args: string, context: IpcCallContext): string {.gcsafe.} =
  raise newException(ValueError, "boom")

proc poolSlow(args: string, context: IpcCallContext): string {.gcsafe.} =
  sleep(80)
  poolEcho(args, context)

var waitCancelled: Atomic[bool]

proc poolWait(args: string, context: IpcCallContext): string {.gcsafe.} =
  while not context.isCancelled():
    sleep(5)
  waitCancelled.store(true)
  "cancelled"

bindBackgroundService("PoolTest", [
  backgroundMethod("echo", poolEcho,
    params = [ParamDef(name: "text", typ: "string")], resultType = "string"),
  backgroundMethod("slow", poolSlow,
    params = [ParamDef(name: "text", typ: "string")], resultType = "string"),
  backgroundMethod("fail", poolFail,
    params = [ParamDef(name: "text", typ: "string")], resultType = "string"),
  backgroundMethod("timeout", poolSlow,
    params = [ParamDef(name: "text", typ: "string")], resultType = "string",
    timeoutMs = 20),
  backgroundMethod("wait", poolWait,
    params = [ParamDef(name: "text", typ: "string")], resultType = "string",
    timeoutMs = 0)
])

proc waitFor(results: var seq[IpcResult], count: int, timeoutMs = 3000): bool =
  let deadline = getMonoTime() + initDuration(milliseconds = timeoutMs)
  while results.len < count and getMonoTime() < deadline:
    drainIpcPool()
    sleep(1)
  results.len >= count

suite "background IPC pool":
  test "window calls resolve through the main-thread completion hook":
    var evals: seq[string]
    let w = Window(id: 501, secret: "", token: "",
                   native: NativeWindow(eval: proc(js: string) = evals.add js))
    windows[501'u64] = w
    let msg = $(%*{"t": "call", "id": 7,
                   "method": "PoolTest.echo", "args": ["hi"]})
    w.handleMessage(msg)
    check evals.len == 0
    let deadline = getMonoTime() + initDuration(seconds = 3)
    while evals.len == 0 and getMonoTime() < deadline:
      drainIpcPool()
      sleep(1)
    check evals.len == 1
    check "_resolve(7" in evals[0]
    check "bg:hi" in evals[0]
    windows.del(501'u64)
    shutdownIpcPool()

  test "worker results and errors reach the completion handler":
    startIpcPool(workers = 2, maxInflight = 8)
    var results: seq[IpcResult]
    setIpcCompletion(proc(result: IpcResult) = results.add result)
    check submitIpc(0, 1, "PoolTest.echo", "[\"a\"]",
                    backgroundWork("PoolTest.echo"))
    check submitIpc(0, 2, "PoolTest.fail", "[\"a\"]",
                    backgroundWork("PoolTest.fail"))
    check waitFor(results, 2)
    var value, error: string
    for result in results:
      if result.callId == 1: value = result.value
      if result.callId == 2: error = result.error
    check value == "\"bg:a\""
    check error == "boom"
    shutdownIpcPool()
    check not submitIpc(0, 3, "PoolTest.echo", "[\"a\"]",
                        backgroundWork("PoolTest.echo"))

  test "in-flight admission is bounded without blocking the caller":
    startIpcPool(workers = 1, maxInflight = 1)
    var results: seq[IpcResult]
    setIpcCompletion(proc(result: IpcResult) = results.add result)
    check submitIpc(0, 1, "PoolTest.slow", "[\"slow\"]",
                    backgroundWork("PoolTest.slow"))
    check not submitIpc(0, 2, "PoolTest.echo", "[\"rejected\"]",
                        backgroundWork("PoolTest.echo"))
    check waitFor(results, 1)
    check results[0].value == "\"bg:slow\""
    check submitIpc(0, 3, "PoolTest.echo", "[\"after\"]",
                    backgroundWork("PoolTest.echo"))
    check waitFor(results, 2)
    check results[1].value == "\"bg:after\""
    shutdownIpcPool()

  test "a background error rejects the page promise":
    startIpcPool()
    setIpcCompletion(completeIpcCall)
    var evals: seq[string]
    let w = Window(id: 502, secret: "", token: "",
                   native: NativeWindow(eval: proc(js: string) = evals.add js))
    windows[502'u64] = w
    let msg = $(%*{"t": "call", "id": 9,
                   "method": "PoolTest.fail", "args": ["x"]})
    w.handleMessage(msg)
    let deadline = getMonoTime() + initDuration(seconds = 3)
    while evals.len == 0 and getMonoTime() < deadline:
      drainIpcPool()
      sleep(1)
    check evals.len == 1
    check "_reject(9" in evals[0]
    check "boom" in evals[0]
    windows.del(502'u64)
    shutdownIpcPool()

  test "a deadline rejects the promise and drops the late result":
    startIpcPool(workers = 1, maxInflight = 4)
    setIpcCompletion(completeIpcCall)
    var evals: seq[string]
    let w = Window(id: 503, secret: "", token: "",
                   native: NativeWindow(eval: proc(js: string) = evals.add js))
    windows[503'u64] = w
    let msg = $(%*{"t": "call", "id": 12,
                   "method": "PoolTest.timeout", "args": ["slow"]})
    w.handleMessage(msg)
    let deadline = getMonoTime() + initDuration(seconds = 3)
    while evals.len == 0 and getMonoTime() < deadline:
      drainIpcPool()
      sleep(1)
    check evals.len == 1
    check "_reject(12" in evals[0]
    check "timed out" in evals[0]
    sleep(120)
    drainIpcPool()
    check evals.len == 1
    windows.del(503'u64)
    shutdownIpcPool()

  test "closing a window cancels its background work":
    startIpcPool(workers = 1, maxInflight = 4)
    setIpcCompletion(completeIpcCall)
    waitCancelled.store(false)
    var evals: seq[string]
    let w = Window(id: 504, secret: "", token: "",
                   native: NativeWindow(eval: proc(js: string) = evals.add js))
    windows[504'u64] = w
    let msg = $(%*{"t": "call", "id": 13,
                   "method": "PoolTest.wait", "args": ["wait"]})
    w.handleMessage(msg)
    sleep(20)
    fireClosed(w)
    windows.del(504'u64)
    let deadline = getMonoTime() + initDuration(seconds = 3)
    while not waitCancelled.load() and getMonoTime() < deadline:
      drainIpcPool()
      sleep(1)
    check waitCancelled.load()
    sleep(30)
    drainIpcPool()
    check evals.len == 0
    shutdownIpcPool()
