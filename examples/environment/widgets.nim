## Reusable controls for the environment UI.

import std/[strutils]

import nimi/ui

import ./[icons, theme]

type
  ButtonKind* = enum
    bkPrimary
    bkSecondary
    bkGhost
    bkDanger
    bkText
    bkQuiet

proc transparent(): Color = Color()

proc active*(n: Node, enabled: bool): Node {.discardable.}

proc button*(c: Context, pal: Palette, metrics: Metrics, label: string,
             iconName: IconName = icCheck, showIcon = false,
             kind: ButtonKind = bkSecondary, enabled = true,
             onClick: proc() {.closure.} = nil,
             key: string = ""): Node {.discardable.} =
  var fg = pal.text2
  var bg = pal.surface
  var border = pal.line
  var hover = pal.surface2
  var pressed = pal.lineSoft
  var height = metrics.controlMd
  var px = space12
  case kind
  of bkPrimary:
    fg = pal.accentText
    bg = pal.accent
    border = pal.accent
    hover = pal.accentHover
    pressed = pal.accentPress
  of bkSecondary:
    discard
  of bkGhost:
    bg = pal.surface3
    border = pal.surface3
    hover = pal.line
    fg = pal.text2
  of bkDanger:
    fg = pal.dangerText
    bg = pal.danger
    border = pal.danger
    hover = pal.danger
    pressed = pal.danger
  of bkText:
    height = metrics.controlXs
    px = space6
    fg = pal.accent
    bg = transparent()
    border = transparent()
    hover = pal.accentSoft
    pressed = pal.accentSoft2
  of bkQuiet:
    height = metrics.controlSm
    px = space8
    fg = pal.text2
    bg = transparent()
    hover = pal.surface2
    pressed = pal.surface3
  if not enabled:
    fg = pal.text3
    bg = if kind in {bkText, bkQuiet}: transparent() else: pal.surface3
    border = if kind in {bkText, bkQuiet}: transparent() else: pal.line
    hover = bg
    pressed = bg
  let action = if enabled: onClick else: nil
  result = buttonBase(c, key, action)
  result.height(height)
  result.padding(px, 0, px, 0)
  result.radius(if kind == bkPrimary: radiusControl else: radiusControl)
  result.background(bg)
  result.border(if kind in {bkText, bkQuiet}: 0.0 else: 1.0, border)
  result.hoverBg(hover)
  result.pressedBg(pressed)
  result.active(enabled)
  result.children(c, proc() =
    if showIcon:
      icon(c, iconName, 14, fg)
    text(c, label).fontSize(metrics.fontBody).bold().color(fg).singleLine()
  )

proc iconButton*(c: Context, pal: Palette, metrics: Metrics,
                 name: IconName, size: float32, color: Color,
                 onClick: proc() {.closure.} = nil,
                 key: string = "", hover = true): Node {.discardable.} =
  result = buttonBase(c, key, onClick)
  result.width(size)
  result.height(size)
  result.radius(radiusControl)
  result.background(transparent())
  result.hoverBg(if hover: pal.surface3 else: transparent())
  result.pressedBg(if hover: pal.surface2 else: transparent())
  result.children(c, proc() =
    icon(c, name, size * 0.58, color)
  )

proc chip*(c: Context, pal: Palette, metrics: Metrics, label: string,
           fg, bg: Color): Node {.discardable.} =
  discard pal
  row(c).padding(space4, 1.5, space4, 1.5).radius(radiusPill).
    background(bg).children(c, proc() =
      text(c, label).fontSize(metrics.fontCaption).bold().color(fg).
        singleLine()
    )

proc countPill*(c: Context, pal: Palette, metrics: Metrics, count: int,
                active = false): Node {.discardable.} =
  let fg = if active: pal.accent else: pal.text3
  let bg = if active: pal.accentSoft else: pal.surface3
  c.chip(pal, metrics, $count, fg, bg)

proc scopePill*(c: Context, pal: Palette, metrics: Metrics,
                label: string, system: bool): Node {.discardable.} =
  let fg = if system: pal.warn else: pal.accent
  let bg = if system: pal.warnSoft else: pal.accentSoft
  row(c).padding(space6, space2, space6, space2).radius(radiusPill).
    background(bg).gap(space4).alignItems(aiCenter).children(c, proc() =
      icon(c, if system: icShield else: icUser, 10, fg)
      text(c, label).fontSize(metrics.fontCaption).bold().color(fg).singleLine()
    )

proc sectionLabel*(c: Context, pal: Palette, metrics: Metrics,
                   label: string): Node {.discardable.} =
  text(c, label).fontSize(metrics.fontCaption).bold().color(pal.text3).
    padding(space8, 0, space8, 0)

proc segmentItem(c: Context, pal: Palette, metrics: Metrics, label: string,
                 active: bool, onClick: proc() {.closure.}, key: string) =
  let item = buttonBase(c, key, onClick)
  item.height(metrics.controlSm - 4)
  item.padding(space8, 0, space8, 0)
  item.radius(radiusControl)
  item.background(if active: pal.surface else: transparent())
  item.border(if active: 1.0 else: 0.0, pal.line)
  item.hoverBg(if active: pal.surface else: pal.surface2)
  item.children(c, proc() =
    text(c, label).fontSize(metrics.fontSmall).
      color(if active: pal.text else: pal.text3).bold().singleLine()
  )

proc segmented*(c: Context, pal: Palette, metrics: Metrics,
                labels: openArray[string], selected: int,
                onSelect: proc(index: int) {.closure.},
                keyPrefix: string): Node {.discardable.} =
  let items = @labels
  row(c).height(metrics.controlSm).padding(space2, space2, space2, space2).
    radius(radiusControl).background(pal.surface3).gap(space2).
    alignItems(aiCenter).children(c, proc() =
      for i, label in items:
        let index = i
        let text = label
        segmentItem(c, pal, metrics, text, selected == index,
          proc() = onSelect(index), keyPrefix & ":" & $index)
    )

proc verticalDivider*(c: Context, pal: Palette, height: float32): Node
  {.discardable.} =
  column(c).width(1).height(height).background(pal.line)

proc horizontalDivider*(c: Context, pal: Palette): Node {.discardable.} =
  column(c).height(1).fill().background(pal.line)

proc active*(n: Node, enabled: bool): Node {.discardable.} =
  ## Disable interaction while keeping the visible disabled style set by the
  ## caller.
  if not enabled:
    n.focusable(false)
    n.tabStop(false)
    n.onClick = nil
    n.onActivate = nil
    n.onSpace = nil
  n

proc tableCheckbox*(c: Context, pal: Palette, metrics: Metrics,
                    checked, mixed: bool,
                    onToggle: proc() {.closure.},
                    key: string): Node {.discardable.} =
  result = checkbox(c, "", checked, onToggle, key = key)
  result.boxSize = 15
  result.accent(pal.accent)
  result.mixed = mixed
  result.padding(0, 0, 0, 0)
  result.focusable(false)
  result.tabStop(false)
  discard metrics

proc infoRow*(c: Context, pal: Palette, metrics: Metrics,
              label, value: string): Node {.discardable.} =
  row(c).fillWidth().gap(space8).alignItems(aiStart).children(c, proc() =
    text(c, label).fontSize(metrics.fontCaption).color(pal.text3).
      width(58).singleLine()
    text(c, value).fontSize(metrics.fontCaption).color(pal.text2).
      grow(1).wrap()
  )

proc callout*(c: Context, pal: Palette, metrics: Metrics,
              name: IconName, fg, bg, border: Color,
              textValue: string): Node {.discardable.} =
  row(c).padding(space8, space6, space8, space6).radius(radiusControl).
    background(bg).border(1, border).gap(space6).alignItems(aiStart).
    children(c, proc() =
      icon(c, name, 12, fg)
      text(c, textValue).fontSize(metrics.fontCaption).color(fg).
        grow(1).wrap()
    )

proc addRun(runs: var seq[TextRun], value: string, color: Color,
            bg: Color) =
  if value.len > 0:
    runs.add TextRun(text: value, color: color, bg: bg)

proc queryRuns(runs: var seq[TextRun], value: string, color: Color,
               bg: Color, hitBg: Color, query: string) =
  let q = query.strip().toLowerAscii()
  if q.len == 0:
    addRun(runs, value, color, bg)
    return
  let lower = value.toLowerAscii()
  var start = 0
  while true:
    let found = lower.find(q, start)
    if found < 0:
      addRun(runs, value[start .. ^1], color, bg)
      break
    if found > start:
      addRun(runs, value[start ..< found], color, bg)
    addRun(runs, value[found ..< found + q.len], color, hitBg)
    start = found + q.len
    if start >= value.len:
      break

proc valueRuns*(value, query: string, base: Color,
                pal: Palette): seq[TextRun] =
  ## Highlight %VAR% references in the accent color and search matches with
  ## the hit background. Empty values render as one muted placeholder by the
  ## caller.
  var pos = 0
  while pos < value.len:
    let start = value.find('%', pos)
    if start < 0:
      result.queryRuns(value[pos .. ^1], base, transparent(), pal.hit, query)
      break
    if start > pos:
      result.queryRuns(value[pos ..< start], base, transparent(),
                       pal.hit, query)
    var finish = -1
    var i = start + 1
    while i < value.len and value[i] notin {'%', ' ', '\t', '\n', '\r'}:
      inc i
    if i < value.len and value[i] == '%' and i > start + 1:
      finish = i
    if finish < 0:
      result.queryRuns(value[start .. ^1], base, transparent(),
                       pal.hit, query)
      break
    result.queryRuns(value[start .. finish], pal.accent, pal.accentSoft,
                     pal.hit, query)
    pos = finish + 1

proc nameRuns*(name, query: string, base: Color,
               pal: Palette): seq[TextRun] =
  result.queryRuns(name, base, transparent(), pal.hit, query)
