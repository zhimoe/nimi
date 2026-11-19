## EnvMan's visual tokens: palette, type scale, spacing and heights.
## Chinese UI text uses the system font; measurements follow the same
## platform text metrics as the rest of Nimi.

import std/[math, strutils]

import nimi/scene/scene

type
  ThemeMode* = enum
    tmSystem
    tmLight
    tmDark

  Palette* = object
    window*: Color
    sidebar*: Color
    surface*: Color
    surface2*: Color
    surface3*: Color
    text*: Color
    text2*: Color
    text3*: Color
    line*: Color
    lineSoft*: Color
    accent*: Color
    accentHover*: Color
    accentPress*: Color
    accentText*: Color
    accentSoft*: Color
    accentSoft2*: Color
    warn*: Color
    warnSoft*: Color
    danger*: Color
    dangerText*: Color
    dangerSoft*: Color
    success*: Color
    successSoft*: Color
    hit*: Color
    dark*: bool

  Metrics* = object
    fontCaption*: float32
    fontSmall*: float32
    fontBody*: float32
    fontSubtitle*: float32
    fontTitle*: float32
    lineBody*: float32
    controlXs*: float32
    controlSm*: float32
    controlMd*: float32
    rowH*: float32
    barH*: float32
    titleBarH*: float32
    paneHeaderH*: float32
    pageHeaderH*: float32
    sheetFooterH*: float32

const
  space2* = 2.0'f32
  space4* = 4.0'f32
  space6* = 6.0'f32
  space8* = 8.0'f32
  space12* = 12.0'f32
  space16* = 16.0'f32
  space24* = 24.0'f32
  space32* = 32.0'f32

  radiusControl* = 4.0'f32
  radiusOverlay* = 8.0'f32
  radiusPill* = 99.0'f32
  sidebarMin* = 158.0'f32
  sidebarMid* = 172.0'f32
  sidebarMax* = 184.0'f32

proc tileRadius*(size: float32): float32 =
  if size < 32: radiusControl else: radiusOverlay

proc hexColor*(value: string, alpha = 1.0'f32): Color =
  var hex = value
  if hex.len > 0 and hex[0] == '#':
    hex = hex[1 .. ^1]
  if hex.len != 6:
    return rgb(1, 0, 1)
  proc byteAt(index: int): float32 =
    float32(parseHexInt(hex[index ..< index + 2])) / 255.0
  rgb(byteAt(0), byteAt(2), byteAt(4), alpha)

proc over*(fg, bg: Color): Color =
  ## Composite fg over an opaque bg.
  let a = fg.a
  Color(
    r: fg.r * a + bg.r * (1 - a),
    g: fg.g * a + bg.g * (1 - a),
    b: fg.b * a + bg.b * (1 - a),
    a: max(fg.a, bg.a))

proc lightPalette*(): Palette =
  Palette(
    window: hexColor("#f5f6f8"),
    sidebar: hexColor("#eff1f4"),
    surface: hexColor("#ffffff"),
    surface2: hexColor("#f8f9fb"),
    surface3: hexColor("#f1f2f6"),
    text: hexColor("#1b1c21"),
    text2: hexColor("#5b5e68"),
    text3: hexColor("#626570"),
    line: hexColor("#e5e7ec"),
    lineSoft: hexColor("#edeef2"),
    accent: hexColor("#4a5cf0"),
    accentHover: hexColor("#3d4ddb"),
    accentPress: hexColor("#3342c4"),
    accentText: hexColor("#ffffff"),
    accentSoft: hexColor("#4a5cf0", 0.09),
    accentSoft2: hexColor("#4a5cf0", 0.16),
    warn: hexColor("#a95c08"),
    warnSoft: hexColor("#c46c10", 0.11),
    danger: hexColor("#bd2934"),
    dangerText: hexColor("#ffffff"),
    dangerSoft: hexColor("#dc3d43", 0.09),
    success: hexColor("#13753e"),
    successSoft: hexColor("#188a4a", 0.10),
    hit: hexColor("#ffc600", 0.28))

proc darkPalette*(): Palette =
  Palette(
    window: hexColor("#0f1014"),
    sidebar: hexColor("#0c0d11"),
    surface: hexColor("#17181e"),
    surface2: hexColor("#1c1e25"),
    surface3: hexColor("#20222b"),
    text: hexColor("#eceef3"),
    text2: hexColor("#a7abb7"),
    text3: hexColor("#7f8492"),
    line: hexColor("#242731"),
    lineSoft: hexColor("#1f222a"),
    accent: hexColor("#8090ff"),
    accentHover: hexColor("#93a1ff"),
    accentPress: hexColor("#6d7df0"),
    accentText: hexColor("#10121a"),
    accentSoft: hexColor("#8090ff", 0.12),
    accentSoft2: hexColor("#8090ff", 0.20),
    warn: hexColor("#e5a44a"),
    warnSoft: hexColor("#e5a44a", 0.12),
    danger: hexColor("#ff6a70"),
    dangerText: hexColor("#10121a"),
    dangerSoft: hexColor("#ff6a70", 0.12),
    success: hexColor("#4ecb85"),
    successSoft: hexColor("#4ecb85", 0.12),
    hit: hexColor("#ffd250", 0.22),
    dark: true)

proc contrastPalette*(dark: bool): Palette =
  ## Deterministic fallback; the framework exposes the contrast preference
  ## but not the user's custom Windows contrast colors.
  result =
    if dark: darkPalette()
    else: lightPalette()
  let bg = if dark: hexColor("#000000") else: hexColor("#ffffff")
  let fg = if dark: hexColor("#ffffff") else: hexColor("#000000")
  let accent = if dark: hexColor("#ffff00") else: hexColor("#000080")
  result.window = bg
  result.sidebar = bg
  result.surface = bg
  result.surface2 = bg
  result.surface3 = bg
  result.text = fg
  result.text2 = fg
  result.text3 = fg
  result.line = fg
  result.lineSoft = fg
  result.accent = accent
  result.accentHover = accent
  result.accentPress = accent
  result.accentText = bg
  result.accentSoft = bg
  result.accentSoft2 = bg
  result.warn = fg
  result.warnSoft = bg
  result.danger = fg
  result.dangerText = bg
  result.dangerSoft = bg
  result.success = fg
  result.successSoft = bg
  result.hit = accent
  result.dark = dark

proc effectiveDark*(mode: ThemeMode, systemDark: bool): bool =
  case mode
  of tmSystem: systemDark
  of tmLight: false
  of tmDark: true

proc paletteFor*(mode: ThemeMode, systemDark, highContrast: bool): Palette =
  let dark = effectiveDark(mode, systemDark)
  if highContrast:
    contrastPalette(dark)
  elif dark:
    darkPalette()
  else:
    lightPalette()

proc newMetrics*(textScale: float32): Metrics =
  var scale = textScale
  if scale < 1 or scale > 5 or scale != scale:
    scale = 1
  proc font(base: float32): float32 =
    round(float64(base) * float64(scale) * 2) / 2
  result.fontCaption = font(10)
  result.fontSmall = font(11)
  result.fontBody = font(12)
  result.fontSubtitle = font(14)
  result.fontTitle = font(18)
  proc line(size: float32): float32 =
    ceil(float64(size) * 4.0 / 3.0)
  let body = line(result.fontBody)
  result.lineBody = body
  result.controlXs = body + space8
  result.controlSm = body + space12
  result.controlMd = body + 2 * space8
  result.rowH = result.controlMd
  result.barH = result.controlMd
  result.titleBarH = result.controlMd + 2 * space4
  result.paneHeaderH = result.controlXs + 2 * space8
  result.pageHeaderH = result.controlMd + 2 * space8
  result.sheetFooterH = result.controlMd + 3 * space8

proc sidebarWidth*(metrics: Metrics, windowWidth: float32): float32 =
  discard metrics
  if windowWidth < 1000: sidebarMin
  elif windowWidth < 1120: sidebarMid
  else: sidebarMax
