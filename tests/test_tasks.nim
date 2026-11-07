import std/[unittest, monotimes, times, os]
import nimi/core/tasks

proc echoWork(input: string, context: TaskContext): string {.gcsafe.} = input & "!"
proc failingWork(input: string, context: TaskContext): string {.gcsafe.} =
  raise newException(ValueError, input)
proc slowWork(input: string, context: TaskContext): string {.gcsafe.} =
  for _ in 0 ..< 100:
    if context.isCancelled(): return "cancelled"
    sleep(2)
  input
proc waitForContext(input: string, context: TaskContext): string {.gcsafe.} =
  while not context.isCancelled():
    sleep(2)
  "stopped"
proc stuckWork(input: string, context: TaskContext): string {.gcsafe.} =
  sleep(500)
  input

proc finish(executor: TaskExecutor) =
  let deadline = getMonoTime() + initDuration(seconds = 10)
  while executor.pending > 0 and getMonoTime() < deadline:
    executor.poll()
    sleep(1)
  check executor.pending == 0

suite "background tasks":
  test "work returns values and failures through owning-thread polling":
    let executor = newTaskExecutor()
    defer: executor.close()
    var values: seq[string]
    var errors: seq[string]
    discard executor.submit("你好", echoWork, proc(r: TaskResult) = values.add(r.value))
    discard executor.submit("failure", failingWork, proc(r: TaskResult) = errors.add(r.error))
    check values.len == 0
    executor.finish()
    check values == @["你好!"]
    check errors == @["failure"]

  test "cancelled result cannot overwrite replacement and capacity is bounded":
    let executor = newTaskExecutor(2)
    defer: executor.close()
    var value = ""
    let stale = executor.submit("stale", echoWork, proc(r: TaskResult) = value = r.value)
    executor.cancel(stale)
    check executor.submit("fresh", echoWork, proc(r: TaskResult) = value = r.value) != 0
    check executor.submit("overflow", echoWork, nil) == 0
    executor.finish()
    check value == "fresh!"

  test "close drops callbacks and rejects further work":
    let executor = newTaskExecutor()
    var called = false
    discard executor.submit("x", echoWork, proc(r: TaskResult) = called = true)
    executor.close()
    executor.poll()
    check not called
    check executor.submit("late", echoWork, nil) == 0
    executor.close()

  test "callback can close executor during poll":
    let executor = newTaskExecutor()
    defer: executor.close()
    discard executor.submit("x", echoWork, proc(r: TaskResult) = executor.close())
    executor.finish()

  test "timeout reports an error and discards the late result":
    let executor = newTaskExecutor()
    defer: executor.close()
    var results: seq[string]
    discard executor.submit("slow", slowWork,
      proc(r: TaskResult) = results.add(r.error), timeoutMs = 10)
    sleep(40)
    executor.poll()
    check results == @["Task timed out"]
    sleep(300)
    executor.poll()
    check results == @["Task timed out"]
    executor.finish()

  test "cancellation reaches work cooperatively":
    let executor = newTaskExecutor()
    defer: executor.close()
    var called = false
    let id = executor.submit("wait", waitForContext,
      proc(r: TaskResult) = called = true)
    sleep(10)
    executor.cancel(id)
    executor.finish()
    check not called

  test "close is bounded when work ignores cancellation":
    let executor = newTaskExecutor()
    discard executor.submit("stuck", stuckWork, nil)
    sleep(10)
    let started = getMonoTime()
    executor.close(20)
    let elapsed = getMonoTime() - started
    check elapsed < initDuration(milliseconds = 500)
    check executor.submit("late", echoWork, nil) == 0
