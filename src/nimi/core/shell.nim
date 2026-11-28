## OS shell integration: reveal files in Finder/Explorer, open files with their
## associated application, open external URLs safely, and launch editors.

import std/[locks, os, osproc, strutils, uri]

var
  procLock: Lock
  spawnedProcs: seq[Process]

initLock(procLock)

proc reapSpawnedProcs*() =
  acquire(procLock)
  try:
    var alive: seq[Process]
    for p in spawnedProcs:
      try:
        if p.peekExitCode() >= 0:
          p.close()
        else:
          alive.add p
      except CatchableError:
        alive.add p
    spawnedProcs = alive
  finally:
    release(procLock)

proc trackSpawn(cmd: string, args: seq[string]): bool =
  reapSpawnedProcs()
  try:
    let p = startProcess(cmd, args = args, options = {poUsePath})
    acquire(procLock)
    spawnedProcs.add p
    release(procLock)
    true
  except CatchableError:
    false

proc revealInFolder*(path: string): bool =
  ## Highlight `path` in Finder / Windows Explorer, or open its containing
  ## directory on Linux.
  if path.len == 0 or (not fileExists(path) and not dirExists(path)):
    return false
  let full = expandFilename(absolutePath(path))
  when defined(macosx):
    if dirExists(full):
      trackSpawn("open", @[full])
    else:
      trackSpawn("open", @["-R", full])
  elif defined(windows):
    let winPath = full.replace('/', '\\')
    if dirExists(full):
      trackSpawn("explorer.exe", @[winPath])
    else:
      trackSpawn("explorer.exe", @["/select," & winPath])
  else:
    let target = if dirExists(full): full else: full.parentDir
    trackSpawn("xdg-open", @[target])

proc openPath*(path: string): bool =
  ## Open a local file or directory with the OS default handler without
  ## shell metacharacter injection (`cmd /c start` is avoided on Windows).
  if path.len == 0 or (not fileExists(path) and not dirExists(path)):
    return false
  let full = expandFilename(absolutePath(path))
  when defined(macosx):
    trackSpawn("open", @[full])
  elif defined(windows):
    trackSpawn("rundll32", @["url.dll,FileProtocolHandler", full.replace('/', '\\')])
  else:
    trackSpawn("xdg-open", @[full])

proc isSafeExternalUrl*(rawUrl: string,
                        allowedSchemes: openArray[string] = ["https", "http", "mailto"]): bool =
  let trimmed = rawUrl.strip()
  if trimmed.len == 0:
    return false
  for ch in trimmed:
    if ord(ch) < 0x20 or ord(ch) == 0x7f:
      return false
  try:
    let parsed = parseUri(trimmed)
    let scheme = parsed.scheme.toLowerAscii()
    if scheme.len == 0:
      return false
    for allowed in allowedSchemes:
      if scheme == allowed.toLowerAscii():
        if scheme in ["http", "https"] and parsed.hostname.len == 0:
          return false
        return true
  except ValueError:
    return false
  false

proc openExternal*(url: string,
                   allowedSchemes: openArray[string] = ["https", "http", "mailto"]): bool =
  ## Open an external URL in the user's default browser after validating its
  ## URI scheme against `allowedSchemes` (blocks `file:`, `javascript:`, etc.).
  if not isSafeExternalUrl(url, allowedSchemes):
    return false
  let clean = url.strip()
  when defined(macosx):
    trackSpawn("open", @[clean])
  elif defined(windows):
    trackSpawn("rundll32", @["url.dll,FileProtocolHandler", clean])
  else:
    trackSpawn("xdg-open", @[clean])

proc openInEditor*(path: string, line: int = 1, col: int = 1,
                   editorCommand: string = "",
                   editorArgs: openArray[string] = []): bool =
  ## Launch a configured external editor (`{file}`, `{line}`, `{col}` templates)
  ## and fall back to `openPath` when no editor is configured or launch fails.
  if path.len == 0:
    return false
  let cmd = editorCommand.strip()
  if cmd.len > 0:
    var args: seq[string]
    var replaced = false
    for raw in editorArgs:
      if "{file}" in raw or "{line}" in raw or "{col}" in raw:
        args.add raw
          .replace("{file}", path)
          .replace("{line}", $max(1, line))
          .replace("{col}", $max(1, col))
        replaced = true
      else:
        args.add raw
    if not replaced:
      args.add path
    if trackSpawn(cmd, args):
      return true
  openPath(path)
