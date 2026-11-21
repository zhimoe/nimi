## Minimal GStreamer playbin bindings for local audio playback. Loaded with
## dlopen so building Nimi never needs GStreamer headers.

import std/[dynlib, strutils]

import ../contract

type
  LibGroup = object
    name: string
    handle: LibHandle

var
  gstLib, gobjectLib, glibLib: LibGroup
  gstChecked, gstAvailable: bool

var
  gst_init_check*: proc(argc: ptr cint, argv: ptr pointer,
                         error: ptr pointer): cint {.cdecl.}
  gst_element_factory_make*: proc(factory: cstring, name: cstring): pointer {.cdecl.}
  gst_element_set_state*: proc(element: pointer, state: cint): cint {.cdecl.}
  gst_element_get_state*: proc(element: pointer, state: ptr cint,
                               pending: ptr cint, timeout: uint64): cint {.cdecl.}
  gst_element_get_bus*: proc(element: pointer): pointer {.cdecl.}
  gst_element_query_position*: proc(element: pointer, format: cint,
                                    position: ptr int64): cint {.cdecl.}
  gst_element_query_duration*: proc(element: pointer, format: cint,
                                    duration: ptr int64): cint {.cdecl.}
  gst_element_seek_simple*: proc(element: pointer, format: cint,
                                 flags: cint, position: int64): cint {.cdecl.}
  gst_bus_timed_pop_filtered*: proc(bus: pointer, timeout: uint64,
                                    types: cint): pointer {.cdecl.}
  gst_message_unref*: proc(message: pointer) {.cdecl.}
  gst_object_unref*: proc(obj: pointer) {.cdecl.}
  gst_filename_to_uri*: proc(filename: cstring, error: ptr pointer): cstring {.cdecl.}
  g_object_set*: proc(obj: pointer, firstProperty: cstring) {.cdecl, varargs.}
  g_free*: proc(mem: pointer) {.cdecl.}

const
  GstStateVoidPending* = 0
  GstStateNull* = 1
  GstStateReady* = 2
  GstStatePaused* = 3
  GstStatePlaying* = 4

  GstStateChangeFailure* = 0
  GstStateChangeSuccess* = 1
  GstStateChangeAsync* = 2
  GstStateChangeNoPreroll* = 3

  GstFormatTime* = 3
  GstSeekFlagFlush* = 1
  GstSeekFlagAccurate* = 2

  GstMessageEos* = 1
  GstMessageError* = 2

proc openGroup(pattern: string): LibGroup =
  for part in pattern.split('|'):
    let name = part.strip
    if name.len > 0:
      let handle = loadLib(name)
      if handle != nil:
        return LibGroup(name: name, handle: handle)

template mustBind(dst: untyped, lib: LibHandle, symbol: string) =
  dst = cast[typeof(dst)](symAddr(lib, symbol.cstring))
  if dst == nil:
    raise newException(BackendError,
      "Linux audio: a runtime library is too old; symbol " & symbol &
      " is missing")

proc ensureGst*(): bool =
  if gstChecked:
    return gstAvailable
  gstChecked = true
  gstLib = openGroup("libgstreamer-1.0.so.0|libgstreamer-1.0.so")
  if gstLib.handle == nil:
    return false
  gobjectLib = openGroup("libgobject-2.0.so.0|libgobject-2.0.so")
  glibLib = openGroup("libglib-2.0.so.0|libglib-2.0.so")
  if gobjectLib.handle == nil or glibLib.handle == nil:
    return false
  try:
    mustBind(gst_init_check, gstLib.handle, "gst_init_check")
    mustBind(gst_element_factory_make, gstLib.handle, "gst_element_factory_make")
    mustBind(gst_element_set_state, gstLib.handle, "gst_element_set_state")
    mustBind(gst_element_get_state, gstLib.handle, "gst_element_get_state")
    mustBind(gst_element_get_bus, gstLib.handle, "gst_element_get_bus")
    mustBind(gst_element_query_position, gstLib.handle,
             "gst_element_query_position")
    mustBind(gst_element_query_duration, gstLib.handle,
             "gst_element_query_duration")
    mustBind(gst_element_seek_simple, gstLib.handle, "gst_element_seek_simple")
    mustBind(gst_bus_timed_pop_filtered, gstLib.handle,
             "gst_bus_timed_pop_filtered")
    mustBind(gst_message_unref, gstLib.handle, "gst_message_unref")
    mustBind(gst_object_unref, gstLib.handle, "gst_object_unref")
    mustBind(gst_filename_to_uri, gstLib.handle, "gst_filename_to_uri")
    mustBind(g_object_set, gobjectLib.handle, "g_object_set")
    mustBind(g_free, glibLib.handle, "g_free")
  except BackendError:
    return false
  var argc: cint = 0
  if gst_init_check(addr argc, nil, nil) == 0:
    return false
  gstAvailable = true
  result = true
