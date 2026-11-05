## NSOpenPanel / NSSavePanel / NSAlert.

import std/[os, strutils]

import ../contract
import ./objc

proc stringArray(items: seq[string]): Id =
  let arr = send0(loadClass("NSMutableArray"), sel("array"))
  for item in items:
    let normalized = item.strip(chars = {'.', ' '})
    if normalized.len > 0:
      sendVoidId(arr, sel("addObject:"), nsString(normalized))
  result = arr

proc openDialog(title, defaultPath: string, multiple, directory: bool,
                filters: seq[string] = @[]): seq[string] =
  let panel = send0(loadClass("NSOpenPanel"), sel("new"))
  defer: release(panel)
  sendVoidBool(panel, sel("setCanChooseFiles:"), not directory)
  sendVoidBool(panel, sel("setCanChooseDirectories:"), directory)
  sendVoidBool(panel, sel("setAllowsMultipleSelection:"), multiple)
  if title.len > 0:
    sendVoidId(panel, sel("setTitle:"), nsString(title))
  if defaultPath.len > 0:
    sendVoidId(panel, sel("setDirectoryURL:"), nsURL(defaultPath))
  if filters.len > 0 and not directory:
    sendVoidId(panel, sel("setAllowedFileTypes:"), stringArray(filters))
  if sendInt(panel, sel("runModal")) == 1:
    let urls = send0(panel, sel("URLs"))
    let count = int(sendInt(urls, sel("count")))
    for i in 0 ..< count:
      let url = sendIdUInt(urls, sel("objectAtIndex:"), NSUInteger(i))
      let path = goString(send0(url, sel("path")))
      if path.len > 0:
        result.add path

proc saveDialog(title, defaultPath, defaultExtension: string,
                filters: seq[string]): string =
  let panel = send0(loadClass("NSSavePanel"), sel("new"))
  defer: release(panel)
  if title.len > 0:
    sendVoidId(panel, sel("setTitle:"), nsString(title))
  if defaultPath.len > 0:
    var name = lastPathPart(defaultPath)
    if defaultExtension.len > 0 and splitFile(name).ext.len == 0:
      name.add "." & defaultExtension.strip(chars = {'.'})
    if name.len > 0:
      sendVoidId(panel, sel("setNameFieldStringValue:"), nsString(name))
    let dir = parentDir(defaultPath)
    if dir.len > 0:
      sendVoidId(panel, sel("setDirectoryURL:"), nsURL(dir))
  if filters.len > 0:
    sendVoidId(panel, sel("setAllowedFileTypes:"), stringArray(filters))
    sendVoidBool(panel, sel("setAllowsOtherFileTypes:"), false)
  if sendInt(panel, sel("runModal")) == 1:
    let url = send0(panel, sel("URL"))
    result = goString(send0(url, sel("path")))

proc messageDialog(title, text: string, buttons: seq[string]): int =
  let alert = send0(loadClass("NSAlert"), sel("new"))
  defer: release(alert)
  sendVoidId(alert, sel("setMessageText:"), nsString(title))
  sendVoidId(alert, sel("setInformativeText:"), nsString(text))
  let labels = if buttons.len > 0: buttons else: @["OK"]
  for label in labels:
    discard sendId1(alert, sel("addButtonWithTitle:"), nsString(label))
  let response = sendInt(alert, sel("runModal"))
  if response >= NSAlertFirstButtonReturn:
    result = int(response - NSAlertFirstButtonReturn)
  else:
    result = int(response)

proc newDarwinDialogs*(): Dialogs =
  result = Dialogs()
  result.open = proc(title, defaultPath: string, multiple,
                     directory: bool): seq[string] =
    openDialog(title, defaultPath, multiple, directory)
  result.openWith = proc(title, defaultPath: string, multiple,
                         directory: bool, filters: seq[string]): seq[string] =
    openDialog(title, defaultPath, multiple, directory, filters)
  result.save = proc(title, defaultPath: string): string =
    saveDialog(title, defaultPath, "", @[])
  result.saveWith = proc(title, defaultPath, defaultExtension: string,
                         filters: seq[string]): string =
    saveDialog(title, defaultPath, defaultExtension, filters)
  result.message = proc(title, text: string): int =
    messageDialog(title, text, @[])
  result.messageWith = proc(title, text: string,
                            buttons: seq[string]): int =
    messageDialog(title, text, buttons)
