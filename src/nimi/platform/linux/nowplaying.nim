## MPRIS2 now-playing metadata and media-key commands over GDBus.

import std/os

import ../contract
import ./[ffi, state]

const
  BusSessionType = 2
  MprisObjectPath = "/org/mpris/MediaPlayer2"
  MprisBusName = "org.mpris.MediaPlayer2.nimi"
  RootInterface = "org.mpris.MediaPlayer2"
  PlayerInterface = "org.mpris.MediaPlayer2.Player"
  PropertiesInterface = "org.freedesktop.DBus.Properties"

  MprisXml = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek">
      <arg name="Offset" type="x" direction="in"/>
    </method>
    <method name="SetPosition">
      <arg name="TrackId" type="o" direction="in"/>
      <arg name="Position" type="x" direction="in"/>
    </method>
    <method name="OpenUri">
      <arg name="Uri" type="s" direction="in"/>
    </method>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="LoopStatus" type="s" access="readwrite"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Shuffle" type="b" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""

type
  GDBusMethodCall = proc(connection: pointer, sender: pointer,
                         objectPath, interfaceName, methodName: pointer,
                         parameters, invocation: pointer,
                         userData: pointer) {.cdecl.}
  GDBusGetProperty = proc(connection: pointer, sender: pointer,
                          objectPath, interfaceName, propertyName: pointer,
                          error: pointer,
                          userData: pointer): pointer {.cdecl.}
  GDBusSetProperty = proc(connection: pointer, sender: pointer,
                          objectPath, interfaceName, propertyName,
                          value: pointer, error: pointer,
                          userData: pointer): cint {.cdecl.}
  GDBusInterfaceVTable {.bycopy.} = object
    methodCall: GDBusMethodCall
    getProperty: GDBusGetProperty
    setProperty: GDBusSetProperty
    padding: array[8, pointer]

  MprisState = ref object
    connection: pointer
    nodeInfo: pointer
    rootRegistration, playerRegistration: cuint
    ownerId: cuint
    info: PlatformNowPlayingInfo
    handler: proc(cmd: PlatformMediaCommand, position: float64) {.closure.}
    artPath: string
    volume: float64
    loopStatus: string
    shuffle: bool
    active: bool

var
  mpris: MprisState
  mprisDisabled = false

proc stringVariant(value: string): pointer =
  g_variant_new_string(value.cstring)

proc boolVariant(value: bool): pointer =
  g_variant_new_boolean(cint(value))

proc int64Variant(value: int64): pointer =
  g_variant_new_int64(value)

proc doubleVariant(value: float64): pointer =
  g_variant_new_double(cdouble(value))

proc stringArrayVariant(values: openArray[string]): pointer =
  let typeInfo = g_variant_type_new("as".cstring)
  let builder = g_variant_builder_new(typeInfo)
  g_variant_type_free(typeInfo)
  for value in values:
    g_variant_builder_add(builder, "s".cstring, value.cstring)
  result = g_variant_builder_end(builder)
  g_variant_builder_unref(builder)

proc playbackStatus(state: MprisState): string =
  if state.info.playing:
    "Playing"
  elif state.info.title.len > 0 or state.info.duration > 0:
    "Paused"
  else:
    "Stopped"

proc metadataVariant(state: MprisState): pointer =
  let typeInfo = g_variant_type_new("a{sv}".cstring)
  let builder = g_variant_builder_new(typeInfo)
  g_variant_type_free(typeInfo)
  let info = state.info
  g_variant_builder_add(builder, "{sv}".cstring, "mpris:trackid".cstring,
                        g_variant_new_object_path("/org/nimi/track/current".cstring))
  if info.title.len > 0:
    g_variant_builder_add(builder, "{sv}".cstring, "xesam:title".cstring,
                          stringVariant(info.title))
  if info.artist.len > 0:
    g_variant_builder_add(builder, "{sv}".cstring, "xesam:artist".cstring,
                          stringArrayVariant([info.artist]))
  if info.album.len > 0:
    g_variant_builder_add(builder, "{sv}".cstring, "xesam:album".cstring,
                          stringVariant(info.album))
  if info.duration > 0:
    g_variant_builder_add(builder, "{sv}".cstring, "mpris:length".cstring,
                          int64Variant(int64(info.duration * 1_000_000.0)))
  if state.artPath.len > 0:
    g_variant_builder_add(builder, "{sv}".cstring, "mpris:artUrl".cstring,
                          stringVariant("file://" & state.artPath))
  result = g_variant_builder_end(builder)
  g_variant_builder_unref(builder)

proc hasCommand(state: MprisState, command: PlatformMediaCommand): bool =
  command in state.info.commands

proc rootProperty(state: MprisState, name: string): pointer =
  case name
  of "CanQuit", "CanRaise", "HasTrackList":
    boolVariant(false)
  of "Identity":
    stringVariant(if linuxState != nil and linuxState.appName.len > 0:
                    linuxState.appName else: "Nimi")
  of "DesktopEntry":
    stringVariant("nimi")
  of "SupportedUriSchemes":
    stringArrayVariant(["file"])
  of "SupportedMimeTypes":
    stringArrayVariant(["audio/mpeg", "audio/ogg", "audio/flac",
                        "audio/wav", "audio/x-wav", "audio/mp4"])
  else:
    nil

proc playerProperty(state: MprisState, name: string): pointer =
  case name
  of "PlaybackStatus":
    stringVariant(state.playbackStatus())
  of "LoopStatus":
    stringVariant(state.loopStatus)
  of "Rate", "MinimumRate", "MaximumRate":
    doubleVariant(1.0)
  of "Shuffle":
    boolVariant(state.shuffle)
  of "Metadata":
    metadataVariant(state)
  of "Volume":
    doubleVariant(state.volume)
  of "Position":
    int64Variant(int64(max(0.0, state.info.position) * 1_000_000.0))
  of "CanGoNext":
    boolVariant(state.hasCommand(pmcNext))
  of "CanGoPrevious":
    boolVariant(state.hasCommand(pmcPrevious))
  of "CanPlay":
    boolVariant(state.hasCommand(pmcPlay))
  of "CanPause":
    boolVariant(state.hasCommand(pmcPause))
  of "CanSeek":
    boolVariant(state.hasCommand(pmcSeek))
  of "CanControl":
    boolVariant(true)
  else:
    nil

proc getProperty(connection: pointer, sender: pointer, objectPath: pointer,
                 interfaceName: pointer, propertyName: pointer,
                 error: pointer, userData: pointer): pointer {.cdecl.} =
  let state = cast[MprisState](userData)
  if state == nil or interfaceName == nil or propertyName == nil:
    return nil
  try:
    let interfaceText = $cast[cstring](interfaceName)
    let propertyText = $cast[cstring](propertyName)
    if interfaceText == RootInterface:
      return rootProperty(state, propertyText)
    elif interfaceText == PlayerInterface:
      return playerProperty(state, propertyText)
  except CatchableError:
    discard
  nil

proc setProperty(connection: pointer, sender: pointer, objectPath: pointer,
                 interfaceName: pointer, propertyName: pointer, value: pointer,
                 error: pointer, userData: pointer): cint {.cdecl.} =
  let state = cast[MprisState](userData)
  if state == nil or propertyName == nil:
    return 0
  let name = $cast[cstring](propertyName)
  case name
  of "LoopStatus", "Rate", "Shuffle", "Volume":
    # Accepted for MPRIS client compatibility; audio state is owned by the
    # application, not the D-Bus layer.
    return 1
  else:
    return 0

proc dispatchCommand(state: MprisState, command: PlatformMediaCommand,
                     position: float64) =
  if state == nil or state.handler == nil:
    return
  try:
    state.handler(command, position)
  except CatchableError:
    discard

proc finish(invocation: pointer) =
  g_dbus_method_invocation_return_value(invocation, nil)

proc fail(invocation: pointer, message: string) =
  g_dbus_method_invocation_return_dbus_error(invocation,
    "org.freedesktop.DBus.Error.NotSupported".cstring, message.cstring)

proc methodCall(connection: pointer, sender: pointer, objectPath: pointer,
                interfaceName: pointer, methodName: pointer,
                parameters: pointer, invocation: pointer,
                userData: pointer) {.cdecl.} =
  let state = cast[MprisState](userData)
  if state == nil or interfaceName == nil or methodName == nil:
    return
  let interfaceText = $cast[cstring](interfaceName)
  let methodText = $cast[cstring](methodName)
  try:
    if interfaceText == RootInterface:
      if methodText == "Raise":
        if lastFocusedWindow != nil:
          gtk_widget_show_all(lastFocusedWindow.window)
          gtk_window_present(lastFocusedWindow.window)
        finish(invocation)
      elif methodText == "Quit":
        fail(invocation, "Quit is disabled")
      else:
        fail(invocation, "Unknown method")
      return
    if interfaceText != PlayerInterface:
      fail(invocation, "Unknown interface")
      return
    case methodText
    of "Play":
      state.dispatchCommand(pmcPlay, 0)
    of "Pause":
      state.dispatchCommand(pmcPause, 0)
    of "PlayPause":
      state.dispatchCommand(pmcTogglePlayPause, 0)
    of "Stop":
      state.dispatchCommand(pmcStop, 0)
    of "Next":
      state.dispatchCommand(pmcNext, 0)
    of "Previous":
      state.dispatchCommand(pmcPrevious, 0)
    of "Seek":
      var offset: int64
      if parameters != nil:
        let child = g_variant_get_child_value(parameters, 0)
        if child != nil:
          offset = g_variant_get_int64(child)
          g_variant_unref(child)
      state.dispatchCommand(pmcSeek,
        max(0.0, state.info.position + float64(offset) / 1_000_000.0))
    of "SetPosition":
      var position: int64
      if parameters != nil:
        let child = g_variant_get_child_value(parameters, 1)
        if child != nil:
          position = g_variant_get_int64(child)
          g_variant_unref(child)
      state.dispatchCommand(pmcSeek, max(0.0, float64(position) / 1_000_000.0))
    of "OpenUri":
      fail(invocation, "OpenUri is not implemented")
      return
    else:
      fail(invocation, "Unknown method")
      return
    finish(invocation)
  except CatchableError:
    fail(invocation, "Internal error")

proc emptyStringArray(): pointer =
  let typeInfo = g_variant_type_new("as".cstring)
  let builder = g_variant_builder_new(typeInfo)
  g_variant_type_free(typeInfo)
  result = g_variant_builder_end(builder)
  g_variant_builder_unref(builder)

proc changedProperties(state: MprisState): pointer =
  let typeInfo = g_variant_type_new("a{sv}".cstring)
  let builder = g_variant_builder_new(typeInfo)
  g_variant_type_free(typeInfo)
  g_variant_builder_add(builder, "{sv}".cstring, "PlaybackStatus".cstring,
                        stringVariant(state.playbackStatus()))
  g_variant_builder_add(builder, "{sv}".cstring, "Metadata".cstring,
                        metadataVariant(state))
  g_variant_builder_add(builder, "{sv}".cstring, "CanGoNext".cstring,
                        boolVariant(state.hasCommand(pmcNext)))
  g_variant_builder_add(builder, "{sv}".cstring, "CanGoPrevious".cstring,
                        boolVariant(state.hasCommand(pmcPrevious)))
  g_variant_builder_add(builder, "{sv}".cstring, "CanPlay".cstring,
                        boolVariant(state.hasCommand(pmcPlay)))
  g_variant_builder_add(builder, "{sv}".cstring, "CanPause".cstring,
                        boolVariant(state.hasCommand(pmcPause)))
  g_variant_builder_add(builder, "{sv}".cstring, "CanSeek".cstring,
                        boolVariant(state.hasCommand(pmcSeek)))
  result = g_variant_builder_end(builder)
  g_variant_builder_unref(builder)

proc emitChanged(state: MprisState) =
  if state == nil or not state.active or state.connection == nil:
    return
  var children = [stringVariant(PlayerInterface),
                  changedProperties(state),
                  emptyStringArray()]
  let parameters = g_variant_new_tuple(addr children[0], 3)
  discard g_dbus_connection_emit_signal(state.connection, nil,
    MprisObjectPath.cstring, PropertiesInterface.cstring,
    "PropertiesChanged".cstring, parameters, nil)

proc removeArtwork(state: MprisState) =
  if state.artPath.len > 0:
    try:
      removeFile(state.artPath)
    except OSError:
      discard
    state.artPath = ""

proc updateArtwork(state: MprisState) =
  removeArtwork(state)
  if state.info.artwork.len == 0:
    return
  var extension = ".png"
  if state.info.artwork.len >= 2 and state.info.artwork[0] == 0xff'u8 and
      state.info.artwork[1] == 0xd8'u8:
    extension = ".jpg"
  let path = getTempDir() / ("nimi-mpris-" & $getCurrentProcessId() & extension)
  try:
    var data = newString(state.info.artwork.len)
    copyMem(addr data[0], unsafeAddr state.info.artwork[0], data.len)
    writeFile(path, data)
    state.artPath = path
  except CatchableError:
    state.artPath = ""

proc ensureMpris(state: MprisState): bool =
  if mprisDisabled:
    return false
  if state.active:
    return true
  let connection = g_bus_get_sync(BusSessionType, nil, nil)
  if connection == nil:
    return false
  state.connection = connection
  let nodeInfo = g_dbus_node_info_new_for_xml(MprisXml.cstring, nil)
  if nodeInfo == nil:
    g_object_unref(connection)
    state.connection = nil
    return false
  state.nodeInfo = nodeInfo
  let rootInfo = g_dbus_node_info_lookup_interface(nodeInfo, RootInterface.cstring)
  let playerInfo = g_dbus_node_info_lookup_interface(nodeInfo,
                                                     PlayerInterface.cstring)
  if rootInfo == nil or playerInfo == nil:
    g_dbus_node_info_unref(nodeInfo)
    g_object_unref(connection)
    state.nodeInfo = nil
    state.connection = nil
    return false
  let rootVtable = GDBusInterfaceVTable(methodCall: methodCall,
                                        getProperty: getProperty,
                                        setProperty: setProperty)
  state.rootRegistration = g_dbus_connection_register_object(connection,
    MprisObjectPath.cstring, rootInfo, cast[pointer](unsafeAddr rootVtable),
    cast[pointer](state), nil, nil)
  let playerVtable = GDBusInterfaceVTable(methodCall: methodCall,
                                          getProperty: getProperty,
                                          setProperty: setProperty)
  state.playerRegistration = g_dbus_connection_register_object(connection,
    MprisObjectPath.cstring, playerInfo, cast[pointer](unsafeAddr playerVtable),
    cast[pointer](state), nil, nil)
  if state.rootRegistration == 0 or state.playerRegistration == 0:
    if state.playerRegistration != 0:
      discard g_dbus_connection_unregister_object(connection,
                                                  state.playerRegistration)
    if state.rootRegistration != 0:
      discard g_dbus_connection_unregister_object(connection,
                                                  state.rootRegistration)
    g_dbus_node_info_unref(nodeInfo)
    g_object_unref(connection)
    state.nodeInfo = nil
    state.connection = nil
    return false
  state.ownerId = g_bus_own_name_on_connection(connection, MprisBusName.cstring,
                                               0, nil, nil, nil, nil)
  state.active = true
  true

proc ensureState(): MprisState =
  if mpris == nil:
    mpris = MprisState(volume: 1.0, loopStatus: "None")
  mpris

proc applyNowPlaying(info: PlatformNowPlayingInfo) =
  let state = ensureState()
  state.info = info
  if not ensureMpris(state):
    return
  updateArtwork(state)
  emitChanged(state)

proc clearNowPlaying() =
  let state = ensureState()
  state.info = PlatformNowPlayingInfo()
  state.removeArtwork()
  emitChanged(state)

proc shutdownNowPlaying*() =
  mprisDisabled = true
  let state = mpris
  if state == nil:
    return
  state.active = false
  state.removeArtwork()
  if state.connection != nil:
    if state.ownerId != 0:
      g_bus_unown_name(state.ownerId)
      state.ownerId = 0
    if state.playerRegistration != 0:
      discard g_dbus_connection_unregister_object(state.connection,
                                                  state.playerRegistration)
      state.playerRegistration = 0
    if state.rootRegistration != 0:
      discard g_dbus_connection_unregister_object(state.connection,
                                                  state.rootRegistration)
      state.rootRegistration = 0
    if state.nodeInfo != nil:
      g_dbus_node_info_unref(state.nodeInfo)
      state.nodeInfo = nil
    g_object_unref(state.connection)
    state.connection = nil
  state.handler = nil
  state.info = PlatformNowPlayingInfo()

proc mprisActive*(): bool =
  mpris != nil and mpris.active

proc installNowPlayingBackend*(b: Backend) =
  if b == nil:
    return
  b.setNowPlaying = proc(info: PlatformNowPlayingInfo) =
    applyNowPlaying(info)
  b.clearNowPlaying = proc() =
    clearNowPlaying()
  b.setMediaCommandHandler = proc(fn: proc(cmd: PlatformMediaCommand,
                                           position: float64)) =
    ensureState().handler = fn
