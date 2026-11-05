## macOS desktop API demo: screens, theme, window controls, dynamic menu.
##
##   nim c -r --path:src examples/desktop-native/main.nim
##   NIMI_SMOKE=desktop nim c -r --path:src examples/desktop-native/main.nim

import std/[os, strutils]

import nimi
import nimi/ui

type
  DesktopState = ref object
    win: Window
    alwaysOnTop: bool
    message: string
    focusCount: int
    statusTray: Tray

proc hexColor(c: Color): string =
  "#" & toHex(int(c.r * 255), 2) & toHex(int(c.g * 255), 2) &
    toHex(int(c.b * 255), 2)

proc toggleTop(s: DesktopState) =
  if s.win == nil:
    return
  s.alwaysOnTop = not s.alwaysOnTop
  s.win.setAlwaysOnTop(s.alwaysOnTop)
  discard app.setMenuItemChecked("Always on Top", s.alwaysOnTop)
  s.message = if s.alwaysOnTop: "window is always on top"
              else: "window level restored"
  s.win.invalidate()

proc centerWindow(s: DesktopState) =
  if s.win != nil:
    s.win.center()
    s.message = "window centered"

proc fullscreenWindow(s: DesktopState) =
  if s.win != nil:
    s.win.toggleFullScreen()
    s.message = "toggle fullscreen: " & $s.win.isFullScreen()

proc minimizeWindow(s: DesktopState) =
  if s.win != nil:
    s.win.minimize()
    s.message = "window minimized"

proc view(s: DesktopState, c: Context) =
  let theme = themeInfo()
  let displays = screens()
  let cursor = cursorPosition()
  let muted = rgb(0.55, 0.55, 0.60)
  let accent = theme.accent
  column(c).fill().padding(24, 24).gap(9).children(c, proc() =
    text(c, "macOS Desktop APIs").fontSize(27).bold()
    text(c, "Screens, appearance, window controls and dynamic menus from Nim.").
      fontSize(12).color(muted)
    divider(c)
    text(c, "theme: " & (if theme.dark: "dark" else: "light") &
         "   accent: " & hexColor(accent)).fontSize(13)
    text(c, "displays: " & $displays.len).fontSize(13)
    if displays.len > 0:
      let p = primaryDisplay()
      text(c, p.name & "  " & $int(p.width) & "×" & $int(p.height) &
           "  @" & $p.scale & "x").fontSize(12).color(muted)
      text(c, "work area " & $int(p.workWidth) & "×" & $int(p.workHeight) &
           " at " & $int(p.workX) & "," & $int(p.workY)).
        fontSize(12).color(muted)
    text(c, "cursor: " & $int(cursor.x) & ", " & $int(cursor.y)).
      fontSize(12).color(muted)
    text(c, "focused: " & (if s.win != nil and s.win.focused: "yes" else: "no") &
         "   focus events: " & $s.focusCount).fontSize(12).color(muted)
    divider(c)
    row(c).gap(8).children(c, proc() =
      button(c, "Center", proc() = centerWindow(s), key = "center")
      button(c, "Always on Top", proc() = toggleTop(s), key = "top")
      button(c, "Fullscreen", proc() = fullscreenWindow(s), key = "full")
      button(c, "Minimize", proc() = minimizeWindow(s), key = "min")
      button(c, "Notify", proc() =
        notify(NotificationOptions(
          title: "Nimi Desktop",
          body: "Screens, theme, tray and window APIs are live.")), key = "notify")
    )
    text(c, s.message).fontSize(12).color(accent)
  )

let state = DesktopState(message: "ready")
let content = uiView(proc(c: Context) = view(state, c))

proc menuFor(s: DesktopState): Menu =
  newMenu(@[
    submenu("Nimi Desktop", @[
      menuItem("About Nimi Desktop", role = "about"),
      separator(),
      menuItem("Quit Nimi Desktop", role = "quit", accelerator = "cmd+q"),
    ]),
    submenu("Window", @[
      menuItem("Center", accelerator = "cmd+shift+c",
               onSelect = proc() =
                 centerWindow(s)
                 if s.win != nil: s.win.invalidate()),
      checkItem("Always on Top", false,
                onSelect = proc() =
                  toggleTop(s)
                  if s.win != nil: s.win.invalidate()),
      menuItem("Fullscreen", accelerator = "ctrl+cmd+f",
               onSelect = proc() =
                 fullscreenWindow(s)
                 if s.win != nil: s.win.invalidate()),
      menuItem("Minimize", role = "minimize", accelerator = "cmd+m"),
    ]),
    submenu("View", @[
      menuItem("Refresh", accelerator = "cmd+r",
               onSelect = proc() =
                 if s.win != nil:
                   s.message = "screens/theme/cursor refreshed"
                   s.win.invalidate()),
    ]),
  ])

app.name = "Nimi Desktop"
app.version = "0.1.0"

app.whenReady(proc() =
  app.setMenu(menuFor(state))
  let w = newWindow(WindowOptions(
    title: "Nimi Desktop",
    width: 760,
    height: 560,
    content: content
  ))
  state.win = w
  w.onFocusChanged(proc(focused: bool) =
    if focused:
      inc state.focusCount
    w.invalidate())
  w.invalidate()

  let shortcutOk = registerGlobalShortcut("ctrl+alt+n", proc() =
    toggleTop(state)
    if state.win != nil: state.win.invalidate())

  state.statusTray = newTray(TrayOptions(
    title: "N",
    tooltip: "Nimi Desktop",
    menu: newMenu(@[
      menuItem("Show Window", onSelect = proc() =
        if state.win != nil:
          state.win.show()
          state.win.focus()),
      menuItem("Always on Top", onSelect = proc() =
        toggleTop(state)
        if state.win != nil: state.win.invalidate()),
      menuItem("Notify", onSelect = proc() =
        notify(NotificationOptions(title: "Nimi Desktop",
                                   body: "Hello from a status bar item."))),
      separator(),
      menuItem("Quit Nimi Desktop", onSelect = proc() = app.quit()),
    ])
  ))

  if existsEnv("NIMI_SMOKE"):
    let displays = screens()
    let theme = themeInfo()
    let cursor = cursorPosition()
    echo "screen count: ", displays.len
    if displays.len > 0:
      let p = primaryDisplay()
      echo "primary: ", p.name, " ", int(p.width), "x", int(p.height),
           " @", p.scale, "x work=", int(p.workWidth), "x", int(p.workHeight)
    echo "theme: ", (if theme.dark: "dark" else: "light"),
         " accent=", hexColor(theme.accent)
    echo "cursor: ", int(cursor.x), ",", int(cursor.y)
    toggleTop(state)
    echo "always on top: ", state.alwaysOnTop
    w.setSize(820, 600)
    w.setPosition(120, 120)
    w.center()
    echo "focused window: ", focusedWindow() != nil
    echo "window focused: ", w.focused
    echo "window isKey: ", w.isFocused()
    echo "focus events: ", state.focusCount
    echo "fullscreen: ", w.isFullScreen()
    echo "tray: ", state.statusTray != nil
    echo "global shortcut: ", shortcutOk
    w.focus()
    discard postMain(proc() =
      echo "focused later: ", w.focused
      echo "focus events later: ", state.focusCount
      app.quit())
)

app.run()
