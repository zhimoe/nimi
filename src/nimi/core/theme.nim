## System appearance and accent color.

import ../scene/scene
import ../platform/contract

type
  ThemeInfo* = object
    dark*: bool
    accent*: Color

var themeListeners: seq[proc() {.closure.}]
var themeHooked = false

proc ensureHook() =
  if themeHooked or currentBackend == nil:
    return
  themeHooked = true
  if currentBackend.onThemeChanged != nil:
    currentBackend.onThemeChanged(proc() =
      for fn in themeListeners:
        fn())

proc themeInfo*(): ThemeInfo =
  ensureHook()
  if currentBackend != nil and currentBackend.themeInfo != nil:
    let t = currentBackend.themeInfo()
    result = ThemeInfo(
      dark: t.dark,
      accent: rgb(t.accentR, t.accentG, t.accentB))
  else:
    result = ThemeInfo(dark: false, accent: rgb(0.0, 0.48, 1.0))

proc isDark*(): bool =
  themeInfo().dark

proc accentColor*(): Color =
  themeInfo().accent

proc onThemeChanged*(fn: proc()) =
  ensureHook()
  themeListeners.add fn
