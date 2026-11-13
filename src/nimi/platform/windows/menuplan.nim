## Pure Windows menu planning: IDs, roles, effective enabled state and shortcuts.
import std/[strutils, sets]
import ../contract
export contract

type
  MenuCommand* = object
    nativeId*: uint16
    callbackId*: uint32
    role*: string
    enabled*: bool
  MenuShortcut* = object
    key*, command*: uint16
    flags*: uint8 # FVIRTKEY | FSHIFT | FCONTROL | FALT
  MenuNode* = object
    label*: string
    kind*: PlatformMenuItemKind
    command*: uint16
    enabled*, checked*: bool
    children*: seq[MenuNode]
  MenuPlan* = object
    nodes*: seq[MenuNode]
    commands*: seq[MenuCommand]
    shortcuts*: seq[MenuShortcut]

proc parseShortcut*(text: string): MenuShortcut =
  result.flags = 1
  var found = false
  for token in text.toLowerAscii.split('+'):
    let part = token.strip
    case part
    of "ctrl", "control", "cmd", "command", "meta", "super": result.flags = result.flags or 8
    of "shift": result.flags = result.flags or 4
    of "alt", "option": result.flags = result.flags or 16
    else:
      if found or part.len == 0: raise newException(BackendError, "Invalid menu shortcut: " & text)
      found = true
      if part.len == 1 and part[0] in {'a'..'z', '0'..'9'}:
        result.key = uint16(ord(part[0].toUpperAscii))
      elif part.len >= 2 and part[0] == 'f':
        var n: int
        try: n = parseInt(part[1..^1])
        except ValueError: discard
        if n notin 1..24: raise newException(BackendError, "Invalid function key: " & text)
        result.key = uint16(111 + n)
      else:
        result.key = case part
          of "enter", "return": 13
          of "tab": 9
          of "escape", "esc": 27
          of "space": 32
          of "backspace": 8
          of "delete", "del": 46
          of "insert": 45
          of "home": 36
          of "end": 35
          of "pageup": 33
          of "pagedown": 34
          of "left": 37
          of "up": 38
          of "right": 39
          of "down": 40
          else: 0
        if result.key == 0: raise newException(UnsupportedBackendError, "Unsupported menu key: " & part)
  if not found: raise newException(BackendError, "Shortcut has no key: " & text)

proc planMenu*(menu: PlatformMenu): MenuPlan =
  var commands: seq[MenuCommand]
  var shortcuts: seq[MenuShortcut]
  var used: HashSet[uint32]
  proc visit(items: seq[PlatformMenuItem], parentEnabled: bool): seq[MenuNode] =
    for item in items:
      if '\0' in item.label: raise newException(BackendError, "Menu labels cannot contain NUL")
      var node = MenuNode(label: item.label, kind: item.kind,
        enabled: parentEnabled and item.enabled, checked: item.checked)
      if item.kind == pmiSubmenu:
        node.children = visit(item.submenu, node.enabled)
      elif item.kind != pmiSeparator:
        if item.role notin ["", "quit", "about", "hide", "showAll", "bringAllToFront",
            "close", "minimize", "zoom", "fullscreen", "undo", "redo", "cut", "copy", "paste", "selectAll", "delete"]:
          raise newException(UnsupportedBackendError, "Unsupported Windows menu role: " & item.role)
        if commands.len >= 65535: raise newException(BackendError, "Too many menu commands")
        node.command = uint16(commands.len + 1)
        if item.role.len == 0 and item.id == 0: node.enabled = false
        commands.add MenuCommand(nativeId: node.command, callbackId: item.id,
          role: item.role, enabled: node.enabled)
        if item.accelerator.len > 0:
          var shortcut = parseShortcut(item.accelerator)
          shortcut.command = node.command
          # Win32 uses tab to separate a menu caption from its shortcut display.
          node.label.add "\t" & item.accelerator
          if node.enabled:
            let identity = (uint32(shortcut.flags) shl 16) or uint32(shortcut.key)
            if identity in used: raise newException(BackendError, "Duplicate menu shortcut: " & item.accelerator)
            used.incl identity
            shortcuts.add shortcut
      result.add node
  result.nodes = visit(menu.items, true)
  result.commands = commands
  result.shortcuts = shortcuts
