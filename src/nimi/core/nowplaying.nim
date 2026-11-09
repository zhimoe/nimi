## Now Playing and media keys. The platform backend owns the native center;
## this module maps the public types and keeps the command callback.

import ../platform/contract
import ./loop

type
  MediaCommand* = enum
    mcPlay, mcPause, mcTogglePlayPause, mcStop, mcNext, mcPrevious, mcSeek

  NowPlayingInfo* = object
    title*, artist*, album*: string
    duration*, position*: float64
    playing*: bool
    commands*: set[MediaCommand]

var commandHandler: proc(cmd: MediaCommand, position: float64) {.closure.}

proc setNowPlaying*(info: NowPlayingInfo) =
  if currentBackend == nil or currentBackend.setNowPlaying == nil:
    return
  var platformCommands: set[PlatformMediaCommand]
  for command in info.commands:
    platformCommands.incl PlatformMediaCommand(ord(command))
  currentBackend.setNowPlaying(PlatformNowPlayingInfo(
    title: info.title, artist: info.artist, album: info.album,
    duration: info.duration, position: info.position,
    playing: info.playing, commands: platformCommands))

proc clearNowPlaying*() =
  if currentBackend != nil and currentBackend.clearNowPlaying != nil:
    currentBackend.clearNowPlaying()

proc onMediaCommand*(fn: proc(cmd: MediaCommand, position: float64)) =
  ## Main thread. Replaces the previous handler.
  commandHandler = fn
  if currentBackend != nil and currentBackend.setMediaCommandHandler != nil:
    currentBackend.setMediaCommandHandler(proc(cmd: PlatformMediaCommand,
                                               position: float64) =
      let callback = commandHandler
      if callback != nil:
        if isMainThread():
          callback(MediaCommand(ord(cmd)), position)
        else:
          discard postMain(proc() = callback(MediaCommand(ord(cmd)), position)))
