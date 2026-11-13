## Real Win32 display, cursor, theme, and global shortcut APIs.
import nimi

app.whenReady(proc() =
  let displays = screens()
  doAssert displays.len >= 1, "expected at least one display"
  for d in displays:
    doAssert d.width > 0 and d.height > 0
    doAssert d.workWidth > 0 and d.workHeight > 0
    doAssert d.scale > 0
    doAssert d.name.len > 0
  let primary = primaryDisplay()
  doAssert primary.width > 0 and primary.scale > 0
  discard cursorPosition()

  let theme = themeInfo()
  for channel in [theme.accent.r, theme.accent.g, theme.accent.b]:
    doAssert channel >= 0 and channel <= 1
  discard isDark()

  var accel = "Ctrl+Alt+Shift+F24"
  var registered = registerGlobalShortcut(accel, proc() = discard)
  if not registered:
    accel = "Ctrl+Alt+Shift+F23"
    registered = registerGlobalShortcut(accel, proc() = discard)
  doAssert registered, "RegisterHotKey failed for both fallback accelerators"
  doAssert unregisterGlobalShortcut(accel)

  app.quit()
)
app.run()
echo "Windows display, cursor, theme and shortcut APIs passed"
