## NSOpenPanel / NSSavePanel / NSAlert.

import std/os

import ../contract
import ./objc

proc openDialog(title, defaultPath: string, multiple, directory: bool): seq[string] =
  let panel = send0(loadClass("NSOpenPanel"), sel("new"))
  defer: release(panel)
  sendVoidBool(panel, sel("setCanChooseFiles:"), not directory)
  sendVoidBool(panel, sel("setCanChooseDirectories:"), directory)
  sendVoidBool(panel, sel("setAllowsMultipleSelection:"), multiple)
  if title.len > 0:
    sendVoidId(panel, sel("setTitle:"), nsString(title))
  if defaultPath.len > 0:
    sendVoidId(panel, sel("setDirectoryURL:"), nsURL(defaultPath))
  if sendInt(panel, sel("runModal")) == 1:
    let urls = send0(panel, sel("URLs"))
    let count = int(sendInt(urls, sel("count")))
    for i in 0 ..< count:
      let url = sendIdUInt(urls, sel("objectAtIndex:"), NSUInteger(i))
      let path = goString(send0(url, sel("path")))
      if path.len > 0:
        result.add path

proc saveDialog(title, defaultPath: string): string =
  let panel = send0(loadClass("NSSavePanel"), sel("new"))
  defer: release(panel)
  if title.len > 0:
    sendVoidId(panel, sel("setTitle:"), nsString(title))
  if defaultPath.len > 0:
    let name = lastPathPart(defaultPath)
    if name.len > 0:
      sendVoidId(panel, sel("setNameFieldStringValue:"), nsString(name))
    let dir = parentDir(defaultPath)
    if dir.len > 0:
      sendVoidId(panel, sel("setDirectoryURL:"), nsURL(dir))
  if sendInt(panel, sel("runModal")) == 1:
    let url = send0(panel, sel("URL"))
    result = goString(send0(url, sel("path")))

proc messageDialog(title, text: string): int =
  let alert = send0(loadClass("NSAlert"), sel("new"))
  defer: release(alert)
  sendVoidId(alert, sel("setMessageText:"), nsString(title))
  sendVoidId(alert, sel("setInformativeText:"), nsString(text))
  discard sendId1(alert, sel("addButtonWithTitle:"), nsString("OK"))
  result = int(sendInt(alert, sel("runModal")))

proc newDarwinDialogs*(): Dialogs =
  result = Dialogs()
  result.open = proc(title, defaultPath: string, multiple,
                     directory: bool): seq[string] =
    openDialog(title, defaultPath, multiple, directory)
  result.save = proc(title, defaultPath: string): string =
    saveDialog(title, defaultPath)
  result.message = proc(title, text: string): int =
    messageDialog(title, text)
