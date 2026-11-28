## Standard application directories, portable mode, atomic persistence,
## bundled resource lookup, and GUI environment PATH normalization.

import std/[json, monotimes, os, strutils]

proc sanitizeSlug*(name: string): string =
  var prevDash = false
  for ch in name.toLowerAscii():
    if ch in {'a'..'z', '0'..'9', '_', '.'}:
      result.add ch
      prevDash = false
    elif not prevDash:
      result.add '-'
      prevDash = true
  result = result.strip(chars = {'-', '.'})
  if result.len == 0:
    result = "nimi-app"

proc canWriteDirectory*(dir: string): bool =
  try:
    createDir(dir)
    let probe = dir / (".nimi-write-" & $getMonoTime().ticks)
    writeFile(probe, "1")
    removeFile(probe)
    true
  except CatchableError:
    false

proc isPortableMode*(slug: string = ""): bool =
  ## Portable mode activates when `<slug>.portable` or `portable` sits beside
  ## the executable and `<appDir>/data` is writable.
  let clean = sanitizeSlug(slug)
  let appDir = try: getAppDir() except CatchableError: ""
  if appDir.len == 0:
    return false
  let hasMarker =
    fileExists(appDir / (clean & ".portable")) or
    fileExists(appDir / "portable") or
    fileExists(appDir / "nimi.portable")
  if not hasMarker:
    return false
  canWriteDirectory(appDir / "data")

proc appDataDir*(slug: string = "nimi"): string =
  ## Cross-platform application data directory, honoring `<SLUG>_DATA_DIR`,
  ## `NIMI_DATA_DIR`, and portable mode (`<appDir>/data`).
  let clean = sanitizeSlug(slug)
  let envKey = clean.toUpperAscii().replace('-', '_').replace('.', '_') & "_DATA_DIR"
  let specificOverride = getEnv(envKey)
  if specificOverride.len > 0:
    return specificOverride
  let genericOverride = getEnv("NIMI_DATA_DIR")
  if genericOverride.len > 0:
    return genericOverride
  if isPortableMode(clean):
    return getAppDir() / "data"
  when defined(windows):
    let base = getEnv("APPDATA", getHomeDir() / "AppData" / "Roaming")
    result = base / clean
  elif defined(macosx):
    result = getHomeDir() / "Library" / "Application Support" / clean
  else:
    let xdg = getEnv("XDG_DATA_HOME")
    if xdg.len > 0:
      result = xdg / clean
    else:
      result = getHomeDir() / ".local" / "share" / clean

proc ensureAppDataDir*(slug: string = "nimi"): string =
  result = appDataDir(slug)
  createDir(result)

proc appConfigDir*(slug: string = "nimi"): string =
  let clean = sanitizeSlug(slug)
  if isPortableMode(clean) or getEnv("NIMI_DATA_DIR").len > 0:
    return appDataDir(clean)
  when defined(windows):
    result = appDataDir(clean)
  elif defined(macosx):
    result = getHomeDir() / "Library" / "Application Support" / clean
  else:
    let xdg = getEnv("XDG_CONFIG_HOME")
    if xdg.len > 0:
      result = xdg / clean
    else:
      result = getHomeDir() / ".config" / clean

proc appCacheDir*(slug: string = "nimi"): string =
  let clean = sanitizeSlug(slug)
  if isPortableMode(clean) or getEnv("NIMI_DATA_DIR").len > 0:
    return appDataDir(clean) / "cache"
  when defined(windows):
    let base = getEnv("LOCALAPPDATA", getHomeDir() / "AppData" / "Local")
    result = base / clean / "cache"
  elif defined(macosx):
    result = getHomeDir() / "Library" / "Caches" / clean
  else:
    let xdg = getEnv("XDG_CACHE_HOME")
    if xdg.len > 0:
      result = xdg / clean
    else:
      result = getHomeDir() / ".cache" / clean

proc appLogDir*(slug: string = "nimi"): string =
  let clean = sanitizeSlug(slug)
  if isPortableMode(clean) or getEnv("NIMI_DATA_DIR").len > 0:
    return appDataDir(clean) / "logs"
  when defined(windows):
    let base = getEnv("LOCALAPPDATA", getHomeDir() / "AppData" / "Local")
    result = base / clean / "logs"
  elif defined(macosx):
    result = getHomeDir() / "Library" / "Logs" / clean
  else:
    let xdg = getEnv("XDG_STATE_HOME")
    if xdg.len > 0:
      result = xdg / clean / "logs"
    else:
      result = getHomeDir() / ".local" / "state" / clean / "logs"

proc resourceDir*(subpath: string = "", envOverride: string = ""): string =
  ## Locate bundled application resources across packaged `.app` bundles,
  ## Windows/Linux `resources/` folders, and local working directories.
  if envOverride.len > 0:
    let val = getEnv(envOverride)
    if val.len > 0:
      return val
  let appDir = try: getAppDir() except CatchableError: getCurrentDir()
  let rel = subpath.strip(chars = {'/', '\\'})
  let bases = [
    appDir / "resources",
    parentDir(appDir) / "Resources",
    appDir,
    getCurrentDir() / "resources",
    getCurrentDir(),
  ]
  for base in bases:
    let candidate = if rel.len > 0: base / rel else: base
    if dirExists(candidate) or fileExists(candidate):
      return candidate
  if rel.len > 0:
    getCurrentDir() / rel
  else:
    appDir / "resources"

proc atomicWriteFile*(path: string, content: string) =
  ## Write `content` to a sibling temporary file and atomically replace `path`
  ## with short backoff retries for transient Windows file locks.
  let dir = path.parentDir
  if dir.len > 0:
    createDir(dir)
  let tmp = path & "." & $getMonoTime().ticks & ".tmp"
  writeFile(tmp, content)
  for attempt in 0 .. 2:
    try:
      moveFile(tmp, path)
      return
    except OSError:
      if attempt == 2:
        try: removeFile(tmp) except CatchableError: discard
        raise
      sleep(25 * (attempt + 1))

proc atomicWriteJson*(path: string, node: JsonNode, indent: int = 2) =
  atomicWriteFile(path, pretty(node, indent = indent))

proc fixGuiPath*(extraDirs: openArray[string] = []) =
  ## Enrich minimal GUI `.app` PATH on macOS/Linux so Finder/Dock-launched apps
  ## can locate user-installed CLI tools (git, homebrew, cargo, bun, etc.).
  when not defined(windows):
    let current = getEnv("PATH")
    var parts = if current.len > 0: current.split(':') else: @[]
    var prepend: seq[string]
    let home = try: getHomeDir() except CatchableError: ""
    var candidates = @[
      "/opt/homebrew/bin",
      "/opt/homebrew/sbin",
      "/usr/local/bin",
      "/usr/local/sbin",
    ]
    if home.len > 0:
      candidates.add home / ".local" / "bin"
      candidates.add home / ".cargo" / "bin"
      candidates.add home / ".bun" / "bin"
      candidates.add home / ".nimble" / "bin"
    for d in extraDirs:
      if d.len > 0:
        candidates.add d
    for dir in candidates:
      if dirExists(dir) and dir notin parts and dir notin prepend:
        prepend.add dir
    if prepend.len > 0:
      putEnv("PATH", (prepend & parts).join(":"))
