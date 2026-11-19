## Unicode Windows common item dialogs. Cancellation is empty; failures raise.
import std/[os, strutils, tempfiles, widestrs]
import ../contract
const header = (currentSourcePath.parentDir / "dialogs.h").replace('\\', '/')
{.compile: "dialogs.c".}
{.passL: "-lole32 -lshell32 -luuid".}
type Paths {.importc: "NimiPaths", header: header, bycopy.} = object
  paths: ptr UncheckedArray[WideCString]
  count: csize_t
proc fileDialog(save, multiple, directory: cint, title, folder, name, extension,
    pattern: WideCString, result: ptr Paths): int32 {.cdecl, importc: "nimi_file_dialog", header: header.}
proc pathsFree(paths: ptr Paths) {.cdecl, importc: "nimi_paths_free", header: header.}
proc taskDialog(manifest, title, text: WideCString, labels: ptr WideCString,
                count: cint, selected: ptr cint): int32
  {.cdecl, importc: "nimi_task_dialog", header: header.}

const controlsManifest = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity type="win32" name="Nimi.TaskDialog" version="1.0.0.0" processorArchitecture="*"/>
  <dependency><dependentAssembly>
    <assemblyIdentity type="win32" name="Microsoft.Windows.Common-Controls"
      version="6.0.0.0" processorArchitecture="*" publicKeyToken="6595b64144ccf1df" language="*"/>
  </dependentAssembly></dependency>
</assembly>"""

proc customMessage*(title, text: string, buttons: seq[string]): int =
  if buttons.len == 0 or buttons.len > int(high(cint)) - 100:
    raise newException(BackendError, "Invalid number of Windows message buttons")
  var storage = newSeqOfCap[WideCStringObj](buttons.len)
  var labels = newSeqOfCap[WideCString](buttons.len)
  for button in buttons:
    storage.add newWideCString(button)
    labels.add storage[^1]
  # The application may be built without a Common Controls v6 manifest.
  let (file, path) = createTempFile("nimi-controls-", ".manifest")
  defer: removeFile(path)
  try:
    file.write(controlsManifest)
  finally:
    file.close()
  var answer: cint
  let status = taskDialog(newWideCString(path), newWideCString(title), newWideCString(text),
                          addr labels[0], cint(labels.len), addr answer)
  if status < 0:
    raise newException(BackendError, "Windows message dialog failed: HRESULT 0x" &
                       toHex(cast[uint32](status), 8))
  int(answer)

proc extension(value: string): string =
  result = value.strip(chars = {'.', ' '})
  for ch in result:
    if ch in {';', '*', '?', '/', '\\', '\0', ':', '|', '<', '>', '"'}:
      raise newException(BackendError, "File filters must be extensions, such as txt or .json")

proc choose(save, multiple, directory: bool, title, defaultPath, defaultExtension: string,
            filters: seq[string]): seq[string] =
  var folder, name, pattern: string
  if defaultPath.len > 0:
    if dirExists(defaultPath): folder = defaultPath
    else:
      folder = parentDir(defaultPath)
      name = lastPathPart(defaultPath)
    if folder.len > 0: folder = absolutePath(folder)
  for filter in filters:
    let ext = extension(filter)
    if ext.len > 0:
      if pattern.len > 0: pattern.add ';'
      pattern.add "*." & ext
  let ext = extension(defaultExtension)
  var paths: Paths
  let status = fileDialog(cint(save), cint(multiple), cint(directory), newWideCString(title),
    newWideCString(folder), newWideCString(name), newWideCString(ext), newWideCString(pattern), addr paths)
  defer: pathsFree(addr paths)
  if cast[uint32](status) == 0x800704c7'u32: return # HRESULT_FROM_WIN32(ERROR_CANCELLED)
  if status < 0:
    raise newException(BackendError, "Windows file dialog failed: HRESULT 0x" & toHex(cast[uint32](status), 8))
  for i in 0..<int(paths.count): result.add $paths.paths[i]

proc installFileDialogs*(dialogs: Dialogs) =
  dialogs.open = proc(title, path: string, multiple, directory: bool): seq[string] =
    choose(false, multiple, directory, title, path, "", @[])
  dialogs.openWith = proc(title, path: string, multiple, directory: bool,
                          filters: seq[string]): seq[string] =
    choose(false, multiple, directory, title, path, "", filters)
  dialogs.save = proc(title, path: string): string =
    let paths = choose(true, false, false, title, path, "", @[])
    if paths.len > 0: paths[0] else: ""
  dialogs.saveWith = proc(title, path, ext: string, filters: seq[string]): string =
    let paths = choose(true, false, false, title, path, ext, filters)
    if paths.len > 0: paths[0] else: ""
