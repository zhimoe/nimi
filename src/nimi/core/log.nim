## Thread-safe rotating redacted logger, GUI-safe console output, and crash dumps.

import std/[locks, os, strutils, times]

import ./paths

type
  LogLevel* = enum
    llError = 0
    llWarn = 1
    llInfo = 2
    llDebug = 3

  LoggerConfig* = object
    slug*: string
    fileName*: string
    level*: LogLevel
    maxBytes*: int
    maxFiles*: int
    maxLineChars*: int
    redactSecrets*: bool
    redactHome*: bool

const
  DefaultSecretPrefixes = [
    "ghp_", "gho_", "github_pat_", "sk-", "xoxb-", "xoxp-", "Bearer "
  ]

var
  logLock: Lock
  currentConfig = LoggerConfig(
    slug: "nimi",
    fileName: "app.log",
    level: llInfo,
    maxBytes: 2 * 1024 * 1024,
    maxFiles: 5,
    maxLineChars: 500,
    redactSecrets: true,
    redactHome: true,
  )
  loggingEnabled = false

initLock(logLock)

proc parseLogLevel*(name: string): LogLevel =
  case name.toLowerAscii().strip()
  of "error": llError
  of "warn", "warning": llWarn
  of "debug": llDebug
  else: llInfo

proc safeEcho*(msg: string) =
  ## Write a diagnostic line to stdout without raising IOError in Windows
  ## `--app:gui` processes that have no attached console handle.
  try:
    stdout.writeLine(msg)
    stdout.flushFile()
  except CatchableError:
    discard

proc shortPathHash(p: string): string =
  let norm = p.replace('\\', '/').strip(chars = {'/'}, leading = false)
  var h: uint64 = 14695981039346656037'u64
  for ch in norm:
    h = (h xor uint64(ord(ch))) * 1099511628211'u64
  toHex(h, 16).toLowerAscii()[0 ..< 8]

proc redactTokens*(s: string): string =
  result = s
  for prefix in DefaultSecretPrefixes:
    var pos = result.find(prefix)
    while pos >= 0:
      var stop = pos + prefix.len
      while stop < result.len and
          result[stop] notin {' ', '\t', '\n', '\r', '"', '\'', '&', ';', ','}:
        inc stop
      result = result[0 ..< pos] & prefix & "[REDACTED]" & result[stop .. ^1]
      pos = result.find(prefix, pos + prefix.len + 10)

proc redactLogMessage*(message: string,
                       sensitivePaths: openArray[string] = [],
                       redactSecrets = true,
                       redactHome = true,
                       maxChars = 500): string =
  result = message.replace('\\', '/')
  for raw in sensitivePaths:
    let norm = raw.replace('\\', '/').strip(chars = {'/'}, leading = false)
    if norm.len >= 3:
      result = result.replace(norm, "path#" & shortPathHash(norm))
  if redactHome:
    let home = (try: getHomeDir() except CatchableError: "")
      .replace('\\', '/').strip(chars = {'/'}, leading = false)
    if home.len >= 3:
      result = result.replace(home, "~")
  if redactSecrets:
    result = redactTokens(result)
  if maxChars > 0 and result.len > maxChars:
    result = result[0 ..< maxChars] & "…"

proc configureLogger*(cfg: LoggerConfig, enabled = true) =
  acquire(logLock)
  currentConfig = cfg
  if currentConfig.slug.len == 0:
    currentConfig.slug = "nimi"
  if currentConfig.fileName.len == 0:
    currentConfig.fileName = sanitizeSlug(currentConfig.slug) & ".log"
  if currentConfig.maxBytes <= 0:
    currentConfig.maxBytes = 2 * 1024 * 1024
  if currentConfig.maxFiles <= 0:
    currentConfig.maxFiles = 5
  loggingEnabled = enabled
  release(logLock)

proc setLogLevel*(level: LogLevel) =
  acquire(logLock)
  currentConfig.level = level
  release(logLock)

proc currentLogPath*(): string =
  acquire(logLock)
  let slug = currentConfig.slug
  let fileName = currentConfig.fileName
  release(logLock)
  appLogDir(slug) / fileName

proc rotateIfNeeded(path: string, maxBytes, maxFiles: int) =
  if not fileExists(path):
    return
  try:
    if getFileSize(path) < maxBytes:
      return
    for i in countdown(maxFiles - 1, 1):
      let src = if i == 1: path else: path & "." & $(i - 1)
      let dst = path & "." & $i
      if fileExists(src):
        if fileExists(dst):
          removeFile(dst)
        moveFile(src, dst)
  except CatchableError:
    discard

proc writeLog*(level: LogLevel, scope, message: string,
               sensitivePaths: openArray[string] = []) =
  acquire(logLock)
  let enabled = loggingEnabled
  let cfg = currentConfig
  release(logLock)
  if not enabled or level > cfg.level:
    return
  let clean = redactLogMessage(
    message,
    sensitivePaths = sensitivePaths,
    redactSecrets = cfg.redactSecrets,
    redactHome = cfg.redactHome,
    maxChars = cfg.maxLineChars)
  let tag = case level
    of llError: "ERROR"
    of llWarn: "WARN"
    of llInfo: "INFO"
    of llDebug: "DEBUG"
  let stamp = now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  let line = stamp & " [" & tag & "] " & scope & ": " & clean & "\n"
  acquire(logLock)
  try:
    let path = appLogDir(cfg.slug) / cfg.fileName
    createDir(path.parentDir)
    rotateIfNeeded(path, cfg.maxBytes, cfg.maxFiles)
    let f = open(path, fmAppend)
    try:
      f.write(line)
    finally:
      f.close()
  except CatchableError:
    discard
  finally:
    release(logLock)

proc logError*(scope, message: string, sensitivePaths: openArray[string] = []) =
  writeLog(llError, scope, message, sensitivePaths)

proc logWarn*(scope, message: string, sensitivePaths: openArray[string] = []) =
  writeLog(llWarn, scope, message, sensitivePaths)

proc logInfo*(scope, message: string, sensitivePaths: openArray[string] = []) =
  writeLog(llInfo, scope, message, sensitivePaths)

proc logDebug*(scope, message: string, sensitivePaths: openArray[string] = []) =
  writeLog(llDebug, scope, message, sensitivePaths)

proc writeCrashLog*(stage, detail: string, slug: string = ""): string =
  ## Persist a fatal error report to `<appLogDir>/crash.log` (falling back to
  ## `<appDir>/crash.log` or `<tempDir>/<slug>-crash.log`). Returns the path written.
  acquire(logLock)
  let effectiveSlug = if slug.len > 0: sanitizeSlug(slug) else: sanitizeSlug(currentConfig.slug)
  release(logLock)
  let stamp = now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  let body = stamp & " [FATAL] " & stage & "\n" & redactTokens(detail) & "\n\n"
  let candidates = [
    (try: appLogDir(effectiveSlug) / "crash.log" except CatchableError: ""),
    (try: getAppDir() / (effectiveSlug & "-crash.log") except CatchableError: ""),
    (try: getTempDir() / (effectiveSlug & "-crash.log") except CatchableError: ""),
  ]
  for path in candidates:
    if path.len == 0:
      continue
    try:
      createDir(path.parentDir)
      let f = open(path, fmAppend)
      try:
        f.write(body)
      finally:
        f.close()
      return path
    except CatchableError:
      discard
  ""
