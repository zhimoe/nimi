import std/[json, strutils, unittest]

import nimi/core/ipc

type
  Note = object
    id: int
    title: string

  Greeter = ref object

proc greet(self: Greeter, name: string): string =
  "Hello " & name

proc add(self: Greeter, a, b: int): int =
  a + b

proc note(self: Greeter, title: string): Note =
  Note(id: 7, title: title)

proc notify(self: Greeter, text: string) =
  discard text

let greeter = Greeter()
bindService(greeter, greet, add, note, notify)

suite "ipc":
  test "string in, string out":
    check $dispatch("Greeter.greet", %*["world"]) == "\"Hello world\""

  test "numbers":
    check dispatch("Greeter.add", %*[2, 3]).getInt == 5

  test "object result":
    let n = dispatch("Greeter.note", %*["hello"]).to(Note)
    check n.id == 7
    check n.title == "hello"

  test "void result":
    check dispatch("Greeter.notify", %*["x"]).kind == JNull

  test "method names":
    check methodNames() == @[
      "Greeter.greet", "Greeter.add", "Greeter.note", "Greeter.notify"]

  test "unknown method":
    expect ValueError:
      discard dispatch("Greeter.missing", %*[])

  test "typescript":
    let ts = generateTypeScript()
    check "greet(name: string): Promise<string>" in ts
    check "add(a: number, b: number): Promise<number>" in ts
    check "call(\"Greeter.greet\", name)" in ts
