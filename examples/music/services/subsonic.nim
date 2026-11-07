## Subsonic catalog adapter. Credentials stay in memory; authenticated URLs
## are sent to system curl through stdin, never command-line arguments/logs.
import std/[json, uri, strutils, md5, sysrand, osproc, streams, os, tempfiles, sha1]

import nimi/core/tasks

type
  ServerConfig* = object
    address*, username*, password*: string
  RemoteTrack* = object
    id*, title*, artist*, album*, coverId*: string
    duration*: int

proc endpoint*(config: ServerConfig, methodName: string,
               params: openArray[(string, string)] = []): string =
  var base = parseUri(config.address.strip)
  if base.scheme notin ["http", "https"] or base.hostname.len == 0 or
      base.username.len > 0 or base.password.len > 0 or base.query.len > 0 or
      base.anchor.len > 0 or config.username.len == 0 or config.password.len == 0:
    raise newException(ValueError, "Invalid music server configuration")
  if methodName notin ["ping", "search3", "getAlbumList2", "getAlbum", "stream", "getCoverArt"]:
    raise newException(ValueError, "Unsupported music server operation")
  var salt = ""
  for value in urandom(16): salt.add(toHex(value, 2))
  let token = getMD5(config.password & salt)
  var query = @[("u", config.username), ("t", token), ("s", salt),
                ("v", "1.16.1"), ("c", "NimiMusic"), ("f", "json")]
  for pair in params:
    if pair[0] in ["u", "t", "s", "p", "v", "c", "f"]:
      raise newException(ValueError, "Reserved authentication parameter")
    query.add(pair)
  base.path = base.path.strip(trailing = true, leading = false, chars = {'/'}) &
    "/rest/" & methodName & ".view"
  base.query = encodeQuery(query)
  result = $base

proc waitCancelable(process: Process, context: TaskContext): bool =
  ## Poll so a cooperative cancellation can terminate curl. Responses are
  ## written to a file, so waiting without draining stdout cannot deadlock.
  while process.running:
    if context.isCancelled():
      process.terminate()
      sleep(50)
      if process.running:
        process.kill()
      return false
    sleep(10)
  true

proc request*(config: ServerConfig, methodName: string,
              params: openArray[(string, string)] = [],
              context: TaskContext = TaskContext()): JsonNode {.gcsafe.} =
  let url = endpoint(config, methodName, params)
  if '\n' in url or '\r' in url: raise newException(ValueError, "Invalid server URL")
  let (responseFile, temporary) = createTempFile(
    ".nimi-response-", ".json", getTempDir())
  responseFile.close()
  defer:
    if fileExists(temporary): removeFile(temporary)
  let process = startProcess("/usr/bin/curl", args = ["-q", "--silent", "--fail",
    "--max-time", "15", "--max-filesize", "8388608",
    "--output", temporary, "--write-out", "%{http_code}", "--config", "-"],
    options = {poStdErrToStdOut})
  defer: process.close()
  process.inputStream.write("url = \"" & url.replace("\\", "\\\\").replace("\"", "\\\"") & "\"\n")
  process.inputStream.close()
  let completed = waitCancelable(process, context)
  let status = process.outputStream.readAll().strip
  let code = process.waitForExit()
  if not completed or context.isCancelled():
    raise newException(IOError, "Music server request cancelled")
  if code != 0 or status != "200":
    raise newException(IOError, "Music server request failed (transport " & $code & ")")
  if not fileExists(temporary):
    raise newException(IOError, "Invalid music server response")
  let body = readFile(temporary)
  if body.len > 8_388_608: raise newException(IOError, "Music server response exceeds limit")
  try:
    result = parseJson(body)["subsonic-response"]
    if result["status"].getStr != "ok":
      # Do not echo untrusted error messages that might contain credentials.
      raise newException(IOError, "Music server rejected request")
  except JsonParsingError, KeyError:
    raise newException(IOError, "Invalid music server response")

proc searchTracks*(config: ServerConfig, query: string, offset = 0,
                   context: TaskContext = TaskContext()): seq[RemoteTrack] =
  let response = request(config, "search3", [("query", query),
    ("songCount", "100"), ("songOffset", $max(0, offset)),
    ("artistCount", "0"), ("albumCount", "0")], context)
  let songs = response{"searchResult3", "song"}
  if songs == nil: return
  if songs.kind != JArray: raise newException(IOError, "Invalid music catalog")
  for song in songs:
    let id = song{"id"}.getStr
    if id.len == 0: continue
    result.add(RemoteTrack(id: id, title: song{"title"}.getStr,
      artist: song{"artist"}.getStr, album: song{"album"}.getStr,
      coverId: song{"coverArt"}.getStr, duration: song{"duration"}.getInt))

proc searchTask*(input: string, context: TaskContext): string {.gcsafe.} =
  let data = parseJson(input)
  let config = ServerConfig(address: data["address"].getStr,
    username: data["username"].getStr, password: data["password"].getStr)
  let tracks = searchTracks(config, data["query"].getStr, context = context)
  result = $(%tracks)

proc downloadTrack*(config: ServerConfig, id, cacheDir: string,
                    cacheBudget: int64 = 1_073_741_824,
                    context: TaskContext = TaskContext()): string {.gcsafe.} =
  ## Download-before-play baseline. Cache identity includes server and account,
  ## never credentials. Only successful transfers replace the cache entry.
  if context.isCancelled(): raise newException(IOError, "Music download cancelled")
  if id.len == 0: raise newException(ValueError, "Missing song ID")
  let url = endpoint(config, "stream", [("id", id)])
  createDir(cacheDir)
  let key = $secureHash($(%*[config.address, config.username, id]))
  let target = cacheDir / (key & ".audio")
  if fileExists(target) and getFileSize(target) > 0: return target
  let (file, temporary) = createTempFile(".download-", ".part", cacheDir)
  file.close()
  defer:
    if fileExists(temporary): removeFile(temporary)
  let process = startProcess("/usr/bin/curl", args = ["-q", "--silent", "--fail",
    "--max-time", "60", "--max-filesize", "134217728", "--output", temporary,
    "--write-out", "%{http_code}", "--config", "-"], options = {poStdErrToStdOut})
  defer: process.close()
  if '\n' in url or '\r' in url: raise newException(ValueError, "Invalid server URL")
  process.inputStream.write("url = \"" & url.replace("\\", "\\\\").replace("\"", "\\\"") & "\"\n")
  process.inputStream.close()
  let completed = waitCancelable(process, context)
  let httpStatus = process.outputStream.readAll().strip
  let code = process.waitForExit()
  if not completed or context.isCancelled():
    raise newException(IOError, "Music download cancelled")
  if code != 0 or httpStatus != "200" or getFileSize(temporary) == 0:
    raise newException(IOError, "Music download failed")
  if getFileSize(temporary) > 134_217_728:
    raise newException(IOError, "Music download exceeds 128 MiB")
  # Protocol failures can be JSON/XML with HTTP 200; don't poison the cache.
  let stream = open(temporary, fmRead)
  var prefix = newString(64)
  prefix.setLen(stream.readChars(prefix))
  stream.close()
  let trimmed = prefix.strip
  if trimmed.startsWith("{") or trimmed.startsWith("<"):
    raise newException(IOError, "Music server returned an error instead of audio")
  var used = getFileSize(temporary)
  for cached in walkFiles(cacheDir / "*.audio"):
    used += getFileSize(cached)
  if used > cacheBudget:
    raise newException(IOError, "Audio cache is full; remove unused cached files before downloading")
  moveFile(temporary, target)
  result = target

proc downloadTask*(input: string, context: TaskContext): string {.gcsafe.} =
  let data = parseJson(input)
  result = downloadTrack(ServerConfig(address: data["address"].getStr,
    username: data["username"].getStr, password: data["password"].getStr),
    data["id"].getStr, data["cacheDir"].getStr, context = context)
