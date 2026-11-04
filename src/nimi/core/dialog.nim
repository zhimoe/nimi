## System file and message dialogs. These block until the user answers.

import ../platform/contract

proc open*(title: string, multiple: bool = false, directory: bool = false,
           defaultPath: string = ""): seq[string] =
  if currentBackend == nil or currentBackend.dialogs == nil:
    return @[]
  currentBackend.dialogs.open(title, defaultPath, multiple, directory)

proc save*(title: string, defaultPath: string = ""): string =
  if currentBackend == nil or currentBackend.dialogs == nil:
    return ""
  currentBackend.dialogs.save(title, defaultPath)

proc message*(title, text: string): int =
  if currentBackend == nil or currentBackend.dialogs == nil:
    return 0
  currentBackend.dialogs.message(title, text)
