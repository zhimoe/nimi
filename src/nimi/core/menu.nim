## Menu model. The backend translates PlatformMenu to NSMenu/Win32/GTK.

type
  MenuItemKind* = enum
    miNormal
    miSeparator
    miSubmenu
    miCheckbox

  MenuItem* = ref object
    label*: string
    kind*: MenuItemKind
    role*: string
    accelerator*: string
    checked*: bool
    enabled*: bool
    onSelect*: proc() {.closure.}
    submenu*: seq[MenuItem]

  Menu* = ref object
    items*: seq[MenuItem]

proc menuItem*(label: string, onSelect: proc() = nil,
               accelerator: string = "", role: string = ""): MenuItem =
  MenuItem(label: label, kind: miNormal, role: role,
           accelerator: accelerator, enabled: true, onSelect: onSelect)

proc separator*(): MenuItem =
  MenuItem(kind: miSeparator, enabled: true)

proc submenu*(label: string, items: seq[MenuItem], role: string = ""): MenuItem =
  MenuItem(label: label, kind: miSubmenu, submenu: items, role: role, enabled: true)

proc checkItem*(label: string, checked: bool, onSelect: proc() = nil,
                accelerator: string = ""): MenuItem =
  MenuItem(label: label, kind: miCheckbox, checked: checked,
           accelerator: accelerator, enabled: true, onSelect: onSelect)

proc newMenu*(items: seq[MenuItem]): Menu =
  Menu(items: items)

proc defaultMenu*(appName: string): Menu =
  newMenu(@[
    submenu(appName, @[
      menuItem("About " & appName, role = "about"),
      separator(),
      menuItem("Hide " & appName, role = "hide", accelerator = "cmd+h"),
      menuItem("Hide Others", role = "hideOthers", accelerator = "cmd+alt+h"),
      menuItem("Show All", role = "showAll"),
      separator(),
      menuItem("Quit " & appName, role = "quit", accelerator = "cmd+q"),
    ]),
    submenu("File", @[
      menuItem("Close", role = "close", accelerator = "cmd+w"),
    ]),
    submenu("Edit", @[
      menuItem("Undo", role = "undo", accelerator = "cmd+z"),
      menuItem("Redo", role = "redo", accelerator = "shift+cmd+z"),
      separator(),
      menuItem("Cut", role = "cut", accelerator = "cmd+x"),
      menuItem("Copy", role = "copy", accelerator = "cmd+c"),
      menuItem("Paste", role = "paste", accelerator = "cmd+v"),
      menuItem("Select All", role = "selectAll", accelerator = "cmd+a"),
    ]),
    submenu("Window", @[
      menuItem("Minimize", role = "minimize", accelerator = "cmd+m"),
      menuItem("Zoom", role = "zoom"),
      separator(),
      menuItem("Bring All to Front", role = "bringAllToFront"),
    ]),
  ])

proc findItem*(items: seq[MenuItem], label: string): MenuItem =
  for item in items:
    if item.label == label:
      return item
    if item.kind == miSubmenu:
      let nested = findItem(item.submenu, label)
      if nested != nil:
        return nested
  result = nil

proc findItem*(m: Menu, label: string): MenuItem =
  if m == nil:
    return nil
  findItem(m.items, label)

proc setEnabled*(m: Menu, label: string, enabled: bool): bool =
  let item = findItem(m, label)
  if item == nil:
    return false
  item.enabled = enabled
  result = true

proc setChecked*(m: Menu, label: string, checked: bool): bool =
  let item = findItem(m, label)
  if item == nil:
    return false
  item.checked = checked
  result = true
