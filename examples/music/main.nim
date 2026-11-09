## Native music integration slice. Local queue first; service adapters follow.
import std/[os, times, json]
import nimi
import nimi/ui
import nimi/audio
import nimi/core/tasks
import nimi/media/lyrics
import nimi/media/queue as queueModule
import ./session
import ./services/subsonic

let background = newTaskExecutor()
let downloads = newTaskExecutor(2)
var lyricTask: uint64
var lyricLines: seq[LyricLine]
proc readLyrics(path: string, context: TaskContext): string {.gcsafe.} =
  if context.isCancelled(): raise newException(IOError, "Lyrics load cancelled")
  let sidecar = changeFileExt(path, "lrc")
  if fileExists(sidecar):
    if getFileSize(sidecar) > 2_000_000: raise newException(IOError, "Lyrics file exceeds 2 MB")
    result = readFile(sidecar)
  if context.isCancelled(): raise newException(IOError, "Lyrics load cancelled")

var downloadId: uint64
var catalogTask: uint64
var catalog: seq[RemoteTrack]
var searchText = ""
var showServer = false
var catalogStatus = ""

proc searchServer() =
  let address = getEnv("NIMI_SUBSONIC_URL")
  let username = getEnv("NIMI_SUBSONIC_USER")
  let password = getEnv("NIMI_SUBSONIC_PASSWORD")
  if address.len == 0 or username.len == 0 or password.len == 0:
    catalogStatus = "Configure Subsonic connection environment first"
    return
  background.cancel(catalogTask)
  catalogStatus = "Loading…"
  catalogTask = background.submit($(%*{"address": address, "username": username,
    "password": password, "query": searchText}), searchTask, proc(r: TaskResult) =
      if r.error.len > 0: catalogStatus = r.error
      else:
        try:
          catalog = parseJson(r.value).to(seq[RemoteTrack])
          catalogStatus = $catalog.len & " server results (first page)"
        except CatchableError: catalogStatus = "Invalid catalog response"
  )
  if catalogTask == 0: catalogStatus = "Background queue is busy"

var player: AudioPlayer
var queue = initPlaybackQueue(getTime().toUnix)
var volume = 0.5'f32
var status = "Import music to begin"
var resumePosition = 0.0
let sessionPath = getConfigDir() / "nimi-music" / "session.json"

proc persist() =
  if player != nil and player.path.len > 0: resumePosition = player.position
  if not saveSession(sessionPath, MusicSession(queue: queue,
      position: resumePosition, volume: volume)):
    stderr.writeLine("Unable to save music session: " & sessionPath)

proc setCover(identity, path: string) =
  for index in 0 ..< queue.tracks.len:
    if queue.tracks[index].identity == identity:
      queue.tracks[index].coverPath = path
      return

proc updateNowPlaying() =
  if player == nil or queue.selected < 0 or queue.selected >= queue.tracks.len:
    clearNowPlaying()
    return
  let track = queue.tracks[queue.selected]
  setNowPlaying(NowPlayingInfo(
    title: track.displayTitle(), artist: track.artist, album: track.album,
    duration: player.duration, position: player.position,
    playing: player.playing,
    commands: {mcPlay, mcPause, mcTogglePlayPause, mcStop, mcNext,
               mcPrevious, mcSeek}))


proc selectTrack(index: int, previous = false, autoplay = true) =
  downloads.cancel(downloadId)
  if index < 0 or index >= queue.tracks.len: return
  let track = queue.tracks[index]
  try:
    let next = openAudio(track.path)
    next.setVolume(volume)
    player.close()
    player = next
    background.cancel(lyricTask)
    lyricLines.setLen(0)
    lyricTask = background.submit(track.path, readLyrics, proc(r: TaskResult) =
      if r.error.len == 0: lyricLines = parseLrc(r.value)
    )
    if previous: queue.selectPrevious(index)
    else: discard queue.select(index)
    player.onFinished = proc(success: bool) =
      if not success:
        status = "Playback failed"
        return
      let candidate = queue.nextIndex(automatic = true)
      if candidate >= 0: selectTrack(candidate)
      else: status = "Queue finished"
    if autoplay and not player.play(): status = "Audio output unavailable"
    else: status = track.displayTitle()
    updateNowPlaying()
  except CatchableError as e:
    status = e.msg

proc playRemote(track: RemoteTrack) =
  downloads.cancel(downloadId)
  catalogStatus = "Downloading " & track.title & "…"
  downloadId = downloads.submit($(%*{
    "address": getEnv("NIMI_SUBSONIC_URL"), "username": getEnv("NIMI_SUBSONIC_USER"),
    "password": getEnv("NIMI_SUBSONIC_PASSWORD"), "id": track.id,
    "cacheDir": getCacheDir() / "nimi-music" / "audio"}), downloadTask,
    proc(r: TaskResult) =
      if r.error.len > 0: catalogStatus = r.error
      else:
        let downloaded = Track(path: r.value, title: track.title,
          artist: track.artist, album: track.album, source: "subsonic",
          remoteId: track.id, coverId: track.coverId,
          duration: float64(track.duration))
        queue.add(downloaded)
        for index, item in queue.tracks:
          if item.identity == downloaded.identity:
            selectTrack(index)
            break
        catalogStatus = "Downloaded " & downloaded.displayTitle()
        if track.coverId.len > 0:
          let coverId = downloads.submit($(%*{
            "address": getEnv("NIMI_SUBSONIC_URL"),
            "username": getEnv("NIMI_SUBSONIC_USER"),
            "password": getEnv("NIMI_SUBSONIC_PASSWORD"),
            "coverId": track.coverId,
            "cacheDir": getCacheDir() / "nimi-music" / "covers"}), coverTask,
            proc(result: TaskResult) =
              if result.error.len == 0:
                setCover(downloaded.identity, result.value)
          )
          if coverId == 0: catalogStatus = catalogStatus & " (cover queue busy)"
  )
  if downloadId == 0: catalogStatus = "Background queue is busy"

proc importTracks() =
  let paths = dialog.open("Import music")
  for path in paths:
    queue.add(path)
  if queue.selected < 0 and queue.tracks.len > 0: selectTrack(0)

proc view(c: Context) =
  let engine = c.engine
  column(c).fill().padding(24, 24).gap(12).children(c, proc() =
    text(c, "Nimi Music", 28).bold()
    text(c, status, 13).wrap()
    if queue.selected >= 0 and queue.selected < queue.tracks.len:
      let current = queue.tracks[queue.selected]
      row(c).gap(12).children(c, proc() =
        if current.coverPath.len > 0:
          image(c, current.coverPath, 64, 64)
        column(c).gap(2).children(c, proc() =
          text(c, current.displayTitle(), 16).bold()
          let subtitle = current.displaySubtitle()
          if subtitle.len > 0: text(c, subtitle, 12)
        )
      )
    row(c).gap(12).children(c, proc() =
      button(c, "Import…", importTracks, key = "import")
      button(c, "Now playing", proc() =
        engine.revealListRow("queue.tracks", queue.selected, queue.tracks.len, 40, 280)
      , key = "reveal")
      button(c, "Previous", proc() = selectTrack(queue.previousIndex(), previous = true), key = "previous")
      button(c, (if player.playing: "Pause" else: "Play"), proc() =
        downloads.cancel(downloadId)
        if player.playing: player.pause()
        elif player != nil: discard player.play()
        elif queue.tracks.len > 0: selectTrack(0)
        updateNowPlaying()
      , key = "play")
      button(c, "Next", proc() = selectTrack(queue.nextIndex()), key = "next")
    )
    row(c).gap(12).children(c, proc() =
      button(c, "Repeat: " & $queue.repeatMode, proc() =
        queue.repeatMode = RepeatMode((ord(queue.repeatMode) + 1) mod 3)
      , key = "repeat")
      checkbox(c, "Shuffle", queue.shuffle, proc() = queue.shuffle = not queue.shuffle,
        key = "shuffle")
    )
    let line = lyricLines.activeLine(player.position)
    text(c, (if line >= 0: lyricLines[line].text else: ""), 16).height(24)
    let length = player.duration
    slider(c, float32(player.position), proc(v: float32) =
      player.seek(v)
      updateNowPlaying()
    , minValue = 0, maxValue = float32(max(1.0, length)), key = "seek").width(600)
    text(c, $int(player.position) & " / " & $int(length) & " s", 12)
    slider(c, volume, proc(v: float32) =
      volume = v
      player.setVolume(v)
    , key = "volume").width(200)
    row(c).gap(8).children(c, proc() =
      button(c, "Local queue", proc() = showServer = false, key = "local")
      button(c, "Server search", proc() = showServer = true, key = "server")
    )
    if showServer:
      textInput(c, searchText, proc(value: string) = searchText = value, key = "server-query")
      button(c, "Search", searchServer, key = "server-search")
      text(c, catalogStatus, 12)
      virtualList(c, "catalog", catalog.len, 36, 180, proc(c: Context, i: int) =
        let track = catalog[i]
        button(c, track.title & " — " & track.artist, proc() = playRemote(track),
          key = "remote-" & track.id).height(34)
      )
    else:
      virtualList(c, "queue.tracks", queue.tracks.len, 40, 280,
        proc(c: Context, i: int) =
          let index = i
          let track = queue.tracks[i]
          var label = (if i == queue.selected: "▶ " else: "") &
            track.displayTitle()
          let subtitle = track.displaySubtitle()
          if subtitle.len > 0: label &= " — " & subtitle
          button(c, label, proc() = selectTrack(index),
            key = "track-" & $i).height(36)
      )
  )

app.setName("Nimi Music")
app.whenReady(proc() =
  onMediaCommand(proc(cmd: MediaCommand, position: float64) =
    if player == nil:
      return
    case cmd
    of mcPlay:
      discard player.play()
    of mcPause:
      player.pause()
    of mcTogglePlayPause:
      if player.playing: player.pause()
      else: discard player.play()
    of mcStop:
      player.pause()
      player.seek(0)
    of mcNext:
      let candidate = queue.nextIndex()
      if candidate >= 0: selectTrack(candidate)
    of mcPrevious:
      let candidate = queue.previousIndex()
      if candidate >= 0: selectTrack(candidate, previous = true)
    of mcSeek:
      player.seek(position)
    updateNowPlaying()
  )
  let w = newWindow(WindowOptions(title: "Nimi Music", width: 760, height: 820,
    content: uiView(view)))
  let saved = loadSession(sessionPath)
  queue = saved.queue
  volume = saved.volume
  resumePosition = saved.position
  if queue.selected >= 0:
    selectTrack(queue.selected, autoplay = false)
    player.seek(saved.position)
  w.onClosed(proc() =
    persist()
    clearNowPlaying()
    background.close(100)
    downloads.close(100)
    player.close()
  )
  w.startAnimation(10, proc(time, dt: float64) =
    background.poll()
    downloads.poll()
  )
  for path in commandLineParams():
    if fileExists(path): queue.add(path)
)
app.onBeforeQuit(proc(e: var QuitEvent) = persist())
app.run()
clearNowPlaying()
downloads.close(100)
background.close(100)
player.close()
