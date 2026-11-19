## Right-hand variable editor sheet.

import std/unicode

import nimi/ui

import ./[icons, model, state, theme, widgets]

proc sheetHeader(c: Context, app: AppState, pal: Palette, metrics: Metrics) =
  let sheet = app.sheet
  column(c).height(metrics.pageHeaderH).fillWidth().children(c, proc() =
    row(c).height(metrics.pageHeaderH - 1).fillWidth().
      padding(space16, 0, space12, 0).gap(space8).alignItems(aiCenter).
      children(c, proc() =
        text(c, if sheet.create: "新建变量" else: "编辑变量").
          fontSize(metrics.fontSubtitle).bold().color(pal.text).singleLine()
        scopePill(c, pal, metrics, scopeLabel(sheet.scope),
                  sheet.scope == esMachine)
        spacer(c)
        discard iconButton(c, pal, metrics, icX, 24, pal.text3,
          proc() = app.closeSheet(), key = "sheet:close")
      )
    column(c).height(1).fillWidth().background(pal.line)
  )

proc sheetEntryRow(c: Context, app: AppState, pal: Palette, metrics: Metrics,
                   index: int, entry: string) =
  let sheet = app.sheet
  row(c).fillWidth().padding(space4, space4, space4, space4).gap(space4).
    alignItems(aiCenter).children(c, proc() =
      text(c, $int(index + 1)).fontSize(metrics.fontCaption).
        family("mono").textAlign(taEnd).color(pal.text3).width(22).
        singleLine()
      let inputWidth = max(120.0'f32, 490 - 16 - 24 - 4 - 8 - 22 - 54 - 16)
      let inputBox = row(c).width(inputWidth).height(metrics.controlSm).
        radius(radiusControl).background(pal.surface).border(1, pal.line).
        padding(space8, 0, space8, 0).alignItems(aiCenter)
      inputBox.children(c, proc() =
        let input = textInput(c, entry,
          proc(value: string) = app.setSheetEntry(index, value)
        , key = "sheet:entry:" & $index, size = metrics.fontBody)
        input.plain()
        input.width(inputWidth - 16)
        input.height(metrics.controlSm - 2)
        input.mono()
        input.color(pal.text)
      )
      discard iconButton(c, pal, metrics, icChevronUp, 18, pal.text3,
        proc() = app.moveSheetEntry(index, -1),
        key = "sheet:up:" & $index)
      discard iconButton(c, pal, metrics, icChevronDown, 18, pal.text3,
        proc() = app.moveSheetEntry(index, 1),
        key = "sheet:down:" & $index)
      discard iconButton(c, pal, metrics, icX, 18, pal.text3,
        proc() = app.removeSheetEntry(index),
        key = "sheet:remove:" & $index)
    )

proc sheetListEditor(c: Context, app: AppState, pal: Palette,
                     metrics: Metrics) =
  let sheet = app.sheet
  let entries = if sheet.entries.len > 0: sheet.entries else: @[""]
  column(c).fillWidth().background(pal.surface2).border(1, pal.line).
    radius(radiusOverlay).padding(space2, space2, space2, space2).
    children(c, proc() =
      for i, entry in entries:
        sheetEntryRow(c, app, pal, metrics, i, entry)
      let add = buttonBase(c, "sheet:add", proc() = app.addSheetEntry())
      add.fillWidth()
      add.height(metrics.controlSm)
      add.radius(radiusControl)
      add.hoverBg(pal.surface)
      add.children(c, proc() =
        icon(c, icPlus, 12, pal.text2)
        text(c, "添加条目").fontSize(metrics.fontCaption).
          color(pal.text2).singleLine()
      )
    )

proc sheetBody(c: Context, app: AppState, pal: Palette, metrics: Metrics) =
  let sheet = app.sheet
  let body = scrollView(c, "sheet:body", height = 0).grow(1).basis(0).
    padding(space16, space16, space24, space16).gap(space12)
  body.children(c, proc() =
    row(c).fillWidth().alignItems(aiCenter).children(c, proc() =
      text(c, "变量名").fontSize(metrics.fontSmall).bold().
        color(pal.text2).singleLine()
      spacer(c)
      text(c, if sheet.create: "不区分大小写" else: "名称不可修改").
        fontSize(metrics.fontCaption).color(pal.text3).singleLine()
    )
    if sheet.create:
      let name = textInput(c, sheet.name,
        proc(value: string) = app.sheet.name = value
      , key = "sheet:name", placeholder = "例如：JAVA_HOME",
        size = metrics.fontBody)
      name.fillWidth()
      name.height(metrics.controlMd)
      name.mono()
      name.color(pal.text)
      name.placeholderColor(pal.text3)
    else:
      row(c).fillWidth().height(metrics.controlMd).radius(radiusControl).
        background(pal.surface2).border(1, pal.line).
        padding(space8, 0, space8, 0).alignItems(aiCenter).children(c, proc() =
          text(c, sheet.name).fontSize(metrics.fontBody).family("mono").
            color(pal.text2).width(434).singleLine()
        )
    if sheet.nameError.len > 0:
      row(c).fillWidth().gap(space4).alignItems(aiCenter).children(c, proc() =
        icon(c, icAlert, 11, pal.danger)
        text(c, sheet.nameError).fontSize(metrics.fontSmall).
          color(pal.danger).wrap()
      )

    row(c).fillWidth().alignItems(aiCenter).gap(space8).
      children(c, proc() =
        text(c, "值").fontSize(metrics.fontSmall).bold().
          color(pal.text2).singleLine()
        spacer(c)
        segmented(c, pal, metrics, ["文本", "列表"],
          if sheet.mode == smText: 0 else: 1,
          proc(index: int) =
            app.setSheetMode(if index == 0: smText else: smList),
          "sheet:mode")
      )

    if sheet.mode == smText:
      let area = textArea(c, sheet.value,
        proc(value: string) = app.setSheetValue(value)
      , key = "sheet:value",
        placeholder = "可以是空值，也可以包含 %USERPROFILE% 这样的引用",
        size = metrics.fontBody, height = 8 * metrics.lineBody,
        family = "mono")
      area.fillWidth()
      area.color(pal.text)
      area.placeholderColor(pal.text3)
    else:
      sheetListEditor(c, app, pal, metrics)

    let value = app.sheetCurrentValue()
    let entryCount =
      if sheet.mode == smList: max(1, sheet.entries.len)
      else: max(1, rawSplit(value).len)
    let meta =
      if value.len == 0: "当前为空值"
      elif entryCount > 1: $entryCount & " 个条目 · 以 ; 分隔"
      else: "单值 · " & $value.runeLen & " 个字符"
    row(c).fillWidth().alignItems(aiCenter).children(c, proc() =
      text(c, meta).fontSize(metrics.fontCaption).color(pal.text3).
        singleLine()
      spacer(c)
      text(c, "保存前自动备份").fontSize(metrics.fontCaption).
        color(pal.text3).singleLine()
    )

    let warning = app.sheetWarnings()
    if warning.len > 0:
      callout(c, pal, metrics, icAlert, pal.warn, pal.warnSoft,
              pal.warnSoft, warning)

    if '%' in value:
      let resolved = app.expandPath(value)
      if resolved != value:
        column(c).fillWidth().background(pal.surface2).border(1, pal.line).
          radius(radiusControl).padding(space8, space6, space8, space6).
          gap(space4).children(c, proc() =
            text(c, "解析预览").fontSize(metrics.fontCaption).bold().
              color(pal.text3).singleLine()
            text(c, resolved).fontSize(metrics.fontSmall).family("mono").
              color(pal.text2).wrap()
          )

    if isListLike(sheet.name):
      callout(c, pal, metrics, icInfo, pal.text3, pal.surface2, pal.line,
              "PATH 按从左到右的顺序查找程序。修改后会对新打开的终端生效。")

    column(c).height(1).fillWidth().background(pal.lineSoft)
    infoRow(c, pal, metrics, "值类型", kindLabel(kindFor(sheet.kind, value)))
    infoRow(c, pal, metrics, "作用范围",
            scopeLabel(sheet.scope) & " · 新终端生效")

    if not sheet.create:
      column(c).height(1).fillWidth().background(pal.lineSoft)
      row(c).fillWidth().alignItems(aiCenter).gap(space8).children(c, proc() =
        text(c, "删除后，新终端不再包含此变量").
          fontSize(metrics.fontCaption).color(pal.text3).grow(1).singleLine()
        let remove = buttonBase(c, "sheet:delete", proc() =
          app.deleteNames(@[sheet.originalName]))
        remove.height(metrics.controlXs)
        remove.padding(space6, 0, space6, 0)
        remove.radius(radiusControl)
        remove.hoverBg(pal.dangerSoft)
        remove.children(c, proc() =
          text(c, "删除变量").fontSize(metrics.fontSmall).bold().
            color(pal.danger).singleLine()
        )
      )
  )

proc sheetFooter(c: Context, app: AppState, pal: Palette, metrics: Metrics) =
  let sheet = app.sheet
  column(c).height(metrics.sheetFooterH).fillWidth().children(c, proc() =
    column(c).height(1).fillWidth().background(pal.line)
    row(c).height(metrics.sheetFooterH - 1).fillWidth().
      padding(space16, 0, space16, 0).gap(space8).alignItems(aiCenter).
      children(c, proc() =
        icon(c, icShieldDone, 12, pal.success)
        text(c, "保存前自动备份").fontSize(metrics.fontCaption).
          color(pal.text3).singleLine()
        spacer(c)
        discard button(c, pal, metrics, "取消", kind = bkSecondary,
          onClick = proc() = app.closeSheet(), key = "sheet:cancel")
        let enabled = sheet.create or app.sheetDirty()
        let saveLabel = if sheet.create: "创建变量" else: "保存更改"
        discard button(c, pal, metrics, saveLabel,
          kind = bkPrimary, enabled = enabled,
          onClick = proc() = app.saveSheet(), key = "sheet:save")
      )
  )

proc sheetOverlay*(c: Context, app: AppState) =
  let sheet = app.sheet
  if sheet == nil:
    return
  let pal = app.palette()
  let metrics = app.metrics()
  if sheet.focusTarget.len > 0:
    c.requestFocus(sheet.focusTarget,
                   selectAll = sheet.focusTarget == "sheet:name")
    sheet.focusTarget = ""
  let layer = overlay(c, "sheet", modal = true)
  layer.background(rgb(0, 0, 0, 0.32))
  layer.whenClicked(proc() = app.closeSheet())
  layer.justifyContent(jcEnd)
  layer.alignItems(aiStretch)
  layer.children(c, proc() =
    let panel = column(c).width(490).fillHeight().background(pal.surface).
      border(1, pal.line).blockClicks()
    panel.children(c, proc() =
      sheetHeader(c, app, pal, metrics)
      sheetBody(c, app, pal, metrics)
      sheetFooter(c, app, pal, metrics)
    )
  )
