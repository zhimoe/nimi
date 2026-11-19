## Real Win32 display, cursor, theme, and global shortcut APIs.
import std/[monotimes, os, tempfiles, times]
import nimi
import nimi/platform/contract
when defined(windows):
  import nimi/platform/windows/app as winApp

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

  when defined(windows):
    let scale = winApp.textScale()
    doAssert scale >= 1.0 and scale <= 5.0
    discard winApp.highContrast()
    discard winApp.isElevated()
    let expanded = winApp.expandEnvironment("%SystemRoot%")
    doAssert expanded.len > 0
    doAssert '%' notin expanded

  var accel = "Ctrl+Alt+Shift+F24"
  var registered = registerGlobalShortcut(accel, proc() = discard)
  if not registered:
    accel = "Ctrl+Alt+Shift+F23"
    registered = registerGlobalShortcut(accel, proc() = discard)
  doAssert registered, "RegisterHotKey failed for both fallback accelerators"
  doAssert unregisterGlobalShortcut(accel)

  let directory = createTempDir("nimi-watch-", "")
  defer: removeDir(directory)
  let nested = directory / "子目录"
  createDir(nested)
  let watched = nested / "文档😀.txt"
  let renamed = nested / "renamed.txt"
  var directoryEvents, fileEvents: seq[FileEvent]
  let directoryWatcher = watch(directory, proc(e: FileEvent) =
    doAssert currentBackend.isMainThread()
    directoryEvents.add e)
  defer: directoryWatcher.close()
  var fileWatcher: FileWatcher
  fileWatcher = watch(watched, proc(e: FileEvent) =
    fileEvents.add e
    fileWatcher.close())
  defer: fileWatcher.close()
  proc received(events: seq[FileEvent], path: string, kind: FileEventKind): bool =
    for event in events:
      if event.path == path and event.kind == kind: return true
  proc waitForEvent(path: string, kind: FileEventKind) =
    let deadline = getMonoTime() + initDuration(seconds = 5)
    while not received(directoryEvents, path, kind) and getMonoTime() < deadline:
      currentBackend.step()
      sleep(10)
    doAssert received(directoryEvents, path, kind), "missing notification for " & path
  writeFile(nested / "ignored.txt", "sibling")
  writeFile(watched, "test")
  waitForEvent(watched, feCreated)
  let deadline = getMonoTime() + initDuration(seconds = 5)
  while fileEvents.len == 0 and getMonoTime() < deadline:
    currentBackend.step()
    sleep(10)
  doAssert fileEvents.len == 1 and fileEvents[0].path == watched
  moveFile(watched, renamed)
  waitForEvent(renamed, feRenamed)
  removeFile(renamed)
  waitForEvent(renamed, feRemoved)
  doAssert fileEvents.len == 1

  app.quit()
)
app.run()
echo "Windows display, cursor, theme, shortcut and file watch APIs passed"
