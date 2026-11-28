## Nimi public facade.
##
## Keeps the default namespace minimal so application modules never hit symbol
## collisions; import `nimi/ui`, `nimi/shell`, `nimi/log`, `nimi/paths`, or
## `nimi/audio` explicitly when needed.

import nimi/core/app as appModule
import nimi/core/[clipboard, content, cookie, dialog, document, events, fileserver,
                  ipc, ipcpool, loop, menu, notification, nowplaying,
                  pageevents, screen, shortcut, theme, tray, watch, window]
import nimi/keys
import nimi/platform/contract

export appModule, clipboard, content, cookie, dialog, document, events, fileserver,
       ipc, ipcpool, loop, menu, notification, nowplaying,
       pageevents, screen, shortcut, theme, tray, watch, window
export contract, keys
