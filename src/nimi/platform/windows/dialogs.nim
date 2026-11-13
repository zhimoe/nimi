## Unicode Windows common item dialogs. Cancellation is empty; failures raise.
import std/[os, strutils, widestrs]
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
