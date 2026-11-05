## System file and message dialogs. These block until the user answers.

import ../platform/contract

proc open*(title: string, multiple: bool = false, directory: bool = false,
           defaultPath: string = "",
           filters: seq[string] = @[]): seq[string] =
  if currentBackend == nil or currentBackend.dialogs == nil:
    return @[]
  if filters.len > 0 and currentBackend.dialogs.openWith != nil:
    currentBackend.dialogs.openWith(title, defaultPath, multiple, directory,
                                    filters)
  else:
    currentBackend.dialogs.open(title, defaultPath, multiple, directory)

proc save*(title: string, defaultPath: string = "",
           defaultExtension: string = "",
           filters: seq[string] = @[]): string =
  if currentBackend == nil or currentBackend.dialogs == nil:
    return ""
  if currentBackend.dialogs.saveWith != nil:
    currentBackend.dialogs.saveWith(title, defaultPath, defaultExtension,
                                    filters)
  else:
    currentBackend.dialogs.save(title, defaultPath)

proc message*(title, text: string): int =
  if currentBackend == nil or currentBackend.dialogs == nil:
    return 0
  currentBackend.dialogs.message(title, text)

proc message*(title, text: string, buttons: seq[string]): int =
  if currentBackend == nil or currentBackend.dialogs == nil:
    return 0
  if buttons.len > 0 and currentBackend.dialogs.messageWith != nil:
    currentBackend.dialogs.messageWith(title, text, buttons)
  else:
    currentBackend.dialogs.message(title, text)

proc confirm*(title, text: string): bool =
  result = message(title, text, @["OK", "Cancel"]) == 0
