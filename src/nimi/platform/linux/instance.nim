## Single-instance D-Bus endpoint and deep-link forwarding.
##
## The first process owns org.nimi.Instance.<hash-of-exe>; later launches
## forward their URL argument to it and exit without opening a window.

import std/[os, strutils]

import ../contract
import ./[ffi, state]

const
  InstanceBusPrefix = "org.nimi.Instance.x"
  InstanceObjectPath = "/org/nimi/Instance"
  InstanceInterface = "org.nimi.Instance"
  DbusBusName = "org.freedesktop.DBus"
  DbusObjectPath = "/org/freedesktop/DBus"
  DbusInterface = "org.freedesktop.DBus"
  RequestNameDoNotQueue = 4'u32
  BusSessionType = 2

  InstanceXml = """
<node>
  <interface name="org.nimi.Instance">
    <method name="OpenURL">
      <arg name="Url" type="s" direction="in"/>
    </method>
    <method name="Raise"/>
  </interface>
</node>
"""

type
  MethodCall = proc(connection: pointer, sender: pointer,
                    objectPath, interfaceName, methodName: pointer,
                    parameters, invocation: pointer,
                    userData: pointer) {.cdecl.}
  GetProperty = proc(connection: pointer, sender: pointer,
                     objectPath, interfaceName, propertyName: pointer,
                     error: pointer, userData: pointer): pointer {.cdecl.}
  SetProperty = proc(connection: pointer, sender: pointer,
                     objectPath, interfaceName, propertyName, value: pointer,
                     error: pointer, userData: pointer): cint {.cdecl.}
  InterfaceVTable {.bycopy.} = object
    methodCall: MethodCall
    getProperty: GetProperty
    setProperty: SetProperty
    padding: array[8, pointer]

  InstanceState = ref object
    connection: pointer
    nodeInfo: pointer
    registration: cuint
    busName: string
    secondary: bool
    initialURLs: seq[string]

var
  instance: InstanceState
  instanceTried = false

proc hashPath(path: string): string =
  var hash: uint64 = 0xcbf29ce484222325'u64
  for ch in path:
    hash = (hash xor uint64(ord(ch))) * 0x100000001b3'u64
  toHex(hash, 16).toLowerAscii

proc urlArguments(): seq[string] =
  for arg in commandLineParams():
    if "://" in arg:
      result.add arg

proc stringVariant(value: string): pointer =
  g_variant_new_string(value.cstring)

proc uint32Variant(value: uint32): pointer =
  g_variant_new_uint32(value)

proc methodCall(connection: pointer, sender: pointer, objectPath: pointer,
                interfaceName: pointer, methodName: pointer,
                parameters: pointer, invocation: pointer,
                userData: pointer) {.cdecl.} =
  if interfaceName == nil or methodName == nil:
    g_dbus_method_invocation_return_value(invocation, nil)
    return
  let methodText = $cast[cstring](methodName)
  try:
    if methodText == "OpenURL":
      var url = ""
      if parameters != nil:
        let child = g_variant_get_child_value(parameters, 0)
        if child != nil:
          let value = g_variant_get_string(child, nil)
          if value != nil:
            url = $value
          g_variant_unref(child)
      if url.len > 0 and linuxState != nil and
          linuxState.handler.openURL != nil:
        linuxState.handler.openURL(url)
    elif methodText == "Raise":
      if lastFocusedWindow != nil:
        gtk_widget_show_all(lastFocusedWindow.window)
        gtk_window_present(lastFocusedWindow.window)
    g_dbus_method_invocation_return_value(invocation, nil)
  except CatchableError:
    g_dbus_method_invocation_return_value(invocation, nil)

proc requestName(connection: pointer, name: string): uint32 =
  var children = [stringVariant(name), uint32Variant(RequestNameDoNotQueue)]
  let parameters = g_variant_new_tuple(addr children[0], 2)
  let replyType = g_variant_type_new("(u)".cstring)
  var error: pointer
  let reply = g_dbus_connection_call_sync(connection, DbusBusName.cstring,
    DbusObjectPath.cstring, DbusInterface.cstring, "RequestName".cstring,
    parameters, replyType, 0, 5000, nil, addr error)
  g_variant_type_free(replyType)
  if reply == nil:
    return 0
  defer: g_variant_unref(reply)
  let child = g_variant_get_child_value(reply, 0)
  if child == nil:
    return 0
  defer: g_variant_unref(child)
  result = g_variant_get_uint32(child)

proc forward(connection: pointer, busName: string, methodName: string,
             url: string) =
  if connection == nil or busName.len == 0:
    return
  var parameters: pointer
  if methodName == "OpenURL":
    var children = [stringVariant(url)]
    parameters = g_variant_new_tuple(addr children[0], 1)
  let reply = g_dbus_connection_call_sync(connection, busName.cstring,
    InstanceObjectPath.cstring, InstanceInterface.cstring, methodName.cstring,
    parameters, nil, 0, 5000, nil, nil)
  if reply != nil:
    g_variant_unref(reply)

proc initInstance*(handler: AppHandler): bool =
  ## Returns true when the process owns the instance name (or D-Bus is
  ## unavailable). A secondary process forwards its URL and reports false.
  if instanceTried:
    return instance == nil or not instance.secondary
  instanceTried = true
  let state = InstanceState(busName: InstanceBusPrefix &
    hashPath(expandFilename(getAppFilename())),
    initialURLs: urlArguments())
  instance = state
  let connection = g_bus_get_sync(BusSessionType, nil, nil)
  if connection == nil:
    return true
  let status = requestName(connection, state.busName)
  if status notin [1'u32, 4'u32]:
    state.secondary = true
    if state.initialURLs.len > 0:
      for url in state.initialURLs:
        forward(connection, state.busName, "OpenURL", url)
    else:
      forward(connection, state.busName, "Raise", "")
    g_object_unref(connection)
    return false

  state.connection = connection
  let nodeInfo = g_dbus_node_info_new_for_xml(InstanceXml.cstring, nil)
  if nodeInfo == nil:
    g_object_unref(connection)
    state.connection = nil
    return true
  state.nodeInfo = nodeInfo
  let interfaceInfo = g_dbus_node_info_lookup_interface(nodeInfo,
                                                        InstanceInterface.cstring)
  if interfaceInfo == nil:
    g_dbus_node_info_unref(nodeInfo)
    g_object_unref(connection)
    state.nodeInfo = nil
    state.connection = nil
    return true
  let vtable = InterfaceVTable(methodCall: methodCall,
                               getProperty: nil, setProperty: nil)
  state.registration = g_dbus_connection_register_object(connection,
    InstanceObjectPath.cstring, interfaceInfo, cast[pointer](unsafeAddr vtable),
    nil, nil, nil)
  true

proc isSecondaryInstance*(): bool =
  instance != nil and instance.secondary

proc initialURLs*(): seq[string] =
  if instance != nil: instance.initialURLs else: @[]

proc instanceBusName*(): string =
  if instance != nil: instance.busName else: ""

proc shutdownInstance*() =
  if instance == nil:
    return
  if instance.connection != nil:
    if instance.registration != 0:
      discard g_dbus_connection_unregister_object(instance.connection,
                                                  instance.registration)
      instance.registration = 0
    if instance.nodeInfo != nil:
      g_dbus_node_info_unref(instance.nodeInfo)
      instance.nodeInfo = nil
    g_object_unref(instance.connection)
    instance.connection = nil
  instance.initialURLs.setLen(0)
