## The smallest Nimi app: one window, one bound method, called from the page.
##
##   nim c -r --path:src examples/hello/main.nim

import std/os

import nimi

type
  Greeter = ref object

proc greet(self: Greeter, name: string): string =
  echo "Greeter.greet called from the page: ", name
  "Hello " & name & ", from Nim " & NimVersion & "!"

let greeter = Greeter()
bindService(greeter, greet)

let ping = newEvent[string]("ping")

type AppControl = ref object

proc emitPing(self: AppControl) =
  let w = focusedWindow()
  if w != nil:
    ping.emitPage(w, "hello from a Nim event")

proc report(self: AppControl, text: string) =
  echo "page event text: ", text

proc quit(self: AppControl) =
  # Close after the IPC reply is delivered, not in the middle of dispatch.
  discard postMain(proc() =
    app.quit())

proc closeWindow(self: AppControl) =
  let w = focusedWindow()
  if w != nil:
    discard postMain(proc() = w.close())

let control = AppControl()
bindService(control, quit, closeWindow, emitPing, report)

const page = """
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Hello Nimi</title>
  <style>
    :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
    body { height: 100vh; margin: 0; display: grid; place-content: center;
           text-align: center; gap: 16px; }
    h1 { margin: 0; }
    #greeting { font-size: 18px; min-height: 1.4em; }
    button { font: inherit; padding: 8px 16px; border-radius: 8px; }
  </style>
</head>
<body>
  <h1>Hello Nimi</h1>
  <p id="greeting">waiting for Nim…</p>
  <p id="event" style="opacity:.7">waiting for an event…</p>
  <button id="greet">Call Nim again</button>
  <script>
    window.nimi.on("ping", function (text) {
      document.getElementById("event").textContent = text;
    });
    async function greet() {
      try {
        const text = await window.nimi.call("Greeter.greet", "world");
        document.getElementById("greeting").textContent = text;
        await window.nimi.call("AppControl.emitPing");
      } catch (e) {
        document.getElementById("greeting").textContent = "error: " + e.message;
      }
    }
    document.getElementById("greet").addEventListener("click", greet);
    greet();
    setTimeout(function () {
      window.nimi.call("AppControl.report",
        document.getElementById("event").textContent);
    }, 600);
  </script>
</body>
</html>
"""

app.whenReady(proc() =
  var html = page
  if existsEnv("NIMI_SMOKE"):
    let mode = getEnv("NIMI_SMOKE")
    if mode == "close":
      html.add "<script>setTimeout(function(){window.nimi.call('AppControl.closeWindow')}, 1200)</script>"
    elif mode == "quit":
      html.add "<script>setTimeout(function(){window.nimi.call('AppControl.quit')}, 1200)</script>"
    else:
      html.add "<script>setTimeout(async function(){for(let i=0;i<50;i++){await window.nimi.call('Greeter.greet','x'+i)};window.nimi.call('AppControl.quit')}, 800)</script>"
  discard newWindow(WindowOptions(
    title: "Hello Nimi",
    width: 480,
    height: 320,
    html: html
  ))
)

app.run()
