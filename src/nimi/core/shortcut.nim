## Global keyboard shortcuts. Registration is platform-specific; the core API
## only exposes accelerator strings and callbacks.

import ../platform/contract

proc registerGlobalShortcut*(accelerator: string, fn: proc()): bool =
  if currentBackend == nil or currentBackend.registerShortcut == nil:
    return false
  currentBackend.registerShortcut(accelerator, fn)

proc unregisterGlobalShortcut*(accelerator: string): bool =
  if currentBackend == nil or currentBackend.unregisterShortcut == nil:
    return false
  currentBackend.unregisterShortcut(accelerator)

proc unregisterAllGlobalShortcuts*() =
  if currentBackend != nil and currentBackend.unregisterAllShortcuts != nil:
    currentBackend.unregisterAllShortcuts()
