## MPNowPlayingInfoCenter and MPRemoteCommandCenter. The framework is loaded
## lazily so apps that never play media do not touch MediaPlayer.
import std/dynlib

import ../contract
import ./objc

type
  BlockDescriptor {.bycopy.} = object
    reserved: uint
    size: uint
  BlockLiteral {.bycopy.} = object
    isa: pointer
    flags: int32
    reserved: int32
    invoke: pointer
    descriptor: ptr BlockDescriptor

const
  commandNames = ["playCommand", "pauseCommand", "togglePlayPauseCommand",
                  "stopCommand", "nextTrackCommand", "previousTrackCommand",
                  "changePlaybackPositionCommand"]

var
  mediaLib: LibHandle
  mediaTried = false
  blocksReady = false
  commandsRegistered = false
  descriptors: array[7, BlockDescriptor]
  blocks: array[7, BlockLiteral]
  artworkDescriptor: BlockDescriptor
  artworkBlock: BlockLiteral
  artworkBytes: string
  mediaHandler: proc(cmd: PlatformMediaCommand, position: float64) {.closure.}

proc dispatchCommand(cmd: PlatformMediaCommand, event: Id) =
  var position = 0.0
  if cmd == pmcSeek and event != nil:
    position = sendDouble(event, sel("positionTime"))
  if mediaHandler != nil:
    mediaHandler(cmd, position)

template defineHandler(name, command) =
  proc name(blk: pointer, event: Id): NSInteger {.cdecl.} =
    dispatchCommand(command, event)
    0

defineHandler(playHandler, pmcPlay)
defineHandler(pauseHandler, pmcPause)
defineHandler(toggleHandler, pmcTogglePlayPause)
defineHandler(stopHandler, pmcStop)
defineHandler(nextHandler, pmcNext)
defineHandler(previousHandler, pmcPrevious)
defineHandler(seekHandler, pmcSeek)

proc artworkHandler(blk: pointer, width, height: cdouble): Id {.cdecl.} =
  if artworkBytes.len == 0:
    return nil
  let image = sendId1(send0(loadClass("NSImage"), sel("alloc")),
                      sel("initWithData:"), nsData(artworkBytes))
  if image != nil:
    autorelease(image)
  image

proc ensureArtworkBlock() =
  if artworkBlock.isa != nil:
    return
  artworkDescriptor = BlockDescriptor(reserved: 0,
                                      size: uint(sizeof(BlockLiteral)))
  artworkBlock = BlockLiteral(
    isa: globalBlockIsa, flags: int32(1 shl 28), reserved: 0,
    invoke: cast[pointer](artworkHandler), descriptor: addr artworkDescriptor)

proc ensureMedia(): bool =
  if mediaTried:
    return mediaLib != nil
  mediaTried = true
  mediaLib = loadLib("/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer",
                     globalSymbols = true)
  result = mediaLib != nil

proc ensureBlocks(): bool =
  if blocksReady:
    return true
  if globalBlockIsa == nil:
    return false
  let handlers = [cast[pointer](playHandler), cast[pointer](pauseHandler),
                  cast[pointer](toggleHandler), cast[pointer](stopHandler),
                  cast[pointer](nextHandler), cast[pointer](previousHandler),
                  cast[pointer](seekHandler)]
  for i in 0 ..< blocks.len:
    descriptors[i] = BlockDescriptor(reserved: 0, size: uint(sizeof(BlockLiteral)))
    blocks[i] = BlockLiteral(
      isa: globalBlockIsa,
      flags: int32(1 shl 28),
      reserved: 0,
      invoke: handlers[i],
      descriptor: addr descriptors[i])
  blocksReady = true
  true

proc commandCenter(): tuple[center, commands: Id] =
  try:
    result.center = send0(loadClass("MPNowPlayingInfoCenter"), sel("defaultCenter"))
    result.commands = send0(loadClass("MPRemoteCommandCenter"),
                            sel("sharedCommandCenter"))
  except ValueError:
    result = (nil, nil)

proc put(info: Id, name: string, value: Id) =
  if value == nil or mediaLib == nil:
    return
  let key = nsConstant(mediaLib, name)
  if key != nil:
    sendVoidId2(info, sel("setObject:forKey:"), value, key)

proc applyNowPlaying(info: PlatformNowPlayingInfo) =
  if not ensureMedia() or not ensureBlocks():
    return
  let (center, commands) = commandCenter()
  if center == nil or commands == nil:
    return
  if not commandsRegistered:
    for i, name in commandNames:
      let command = send0(commands, sel(name))
      if command != nil:
        discard sendId1(command, sel("addTargetWithHandler:"),
                        cast[Id](addr blocks[i]))
    commandsRegistered = true
  for i, name in commandNames:
    let command = send0(commands, sel(name))
    if command != nil:
      sendVoidBool(command, sel("setEnabled:"),
                   PlatformMediaCommand(i) in info.commands)
  let dictionary = send0(loadClass("NSMutableDictionary"), sel("dictionary"))
  put(dictionary, "MPMediaItemPropertyTitle", nsString(info.title))
  put(dictionary, "MPMediaItemPropertyArtist", nsString(info.artist))
  put(dictionary, "MPMediaItemPropertyAlbumTitle", nsString(info.album))
  if info.artwork.len > 0:
    artworkBytes = newString(info.artwork.len)
    copyMem(addr artworkBytes[0], unsafeAddr info.artwork[0], info.artwork.len)
    ensureArtworkBlock()
    let artwork = cast[proc(a: Id, s: SEL, size: NSSize,
                            handler: pointer): Id {.cdecl.}](msgSend)(
      send0(loadClass("MPMediaItemArtwork"), sel("alloc")),
      sel("initWithBoundsSize:requestHandler:"),
      NSSize(w: 512, h: 512), addr artworkBlock)
    if artwork != nil:
      autorelease(artwork)
      put(dictionary, "MPMediaItemPropertyArtwork", artwork)
  else:
    artworkBytes.setLen(0)
  if info.duration > 0:
    put(dictionary, "MPMediaItemPropertyPlaybackDuration",
        nsNumberDouble(info.duration))
  put(dictionary, "MPNowPlayingInfoPropertyMediaType", nsNumberInt(1))
  put(dictionary, "MPNowPlayingInfoPropertyElapsedPlaybackTime",
      nsNumberDouble(max(0.0, info.position)))
  put(dictionary, "MPNowPlayingInfoPropertyDefaultPlaybackRate", nsNumberDouble(1))
  put(dictionary, "MPNowPlayingInfoPropertyPlaybackRate",
      nsNumberDouble(if info.playing: 1.0 else: 0.0))
  sendVoidId(center, sel("setNowPlayingInfo:"), dictionary)
  sendVoidInt(center, sel("setPlaybackState:"),
              if info.playing: 1 else: 2)

proc clearNowPlaying() =
  if not ensureMedia():
    return
  let (center, commands) = commandCenter()
  if center == nil:
    return
  sendVoidId(center, sel("setNowPlayingInfo:"), nil)
  sendVoidInt(center, sel("setPlaybackState:"), 3)
  if commands != nil:
    for name in commandNames:
      let command = send0(commands, sel(name))
      if command != nil:
        sendVoidBool(command, sel("setEnabled:"), false)

proc installNowPlayingBackend*(b: Backend) =
  if b == nil:
    return
  b.setNowPlaying = proc(info: PlatformNowPlayingInfo) =
    applyNowPlaying(info)
  b.clearNowPlaying = proc() =
    clearNowPlaying()
  b.setMediaCommandHandler = proc(fn: proc(cmd: PlatformMediaCommand,
                                           position: float64)) =
    mediaHandler = fn
