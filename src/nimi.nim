## Nimi public facade.
##
##   import nimi
##
##   type Greeter = ref object
##   proc greet(self: Greeter, name: string): string = "Hello " & name
##   let g = Greeter()
##   bindService(g, greet)
##
##   app.whenReady(proc() =
##     discard newWindow(WindowOptions(html: "<h1>Hello</h1>")))
##   app.run()

import nimi/core/app as appModule
import nimi/core/[clipboard, content, dialog, events, fileserver, ipc, loop, menu, notification, screen, shortcut, theme, tray, window]
import nimi/platform/contract

export appModule, clipboard, content, dialog, events, fileserver, ipc, loop, menu, notification, screen, shortcut, theme, tray, window
export contract
