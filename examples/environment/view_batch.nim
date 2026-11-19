## Full-page batch editor with a live parsed-entry diff.

import std/[sequtils, strutils]

import nimi/ui

import ./[icons, model, state, theme, widgets]

proc transparent(): Color = Color()

proc targetChip(c: Context, app: AppState, pal: Palette, metrics: Metrics,
                name: string) =
  let batch = app.batch
  let active = sameName(batch.target, name)
  let item = buttonBase(c, "batch:target:" & lowerName(name),
    proc() = app.switchBatchTarget(name))
  item.height(metrics.controlSm)
  item.padding(space8, 0, space8, 0)
  item.radius(radiusControl)
  item.background(if active: pal.accentSoft else: pal.surface3)
  item.border(1, if active: pal.accentSoft2 else: transparent())
  item.hoverBg(if active: pal.accentSoft2 else: pal.line)
  item.children(c, proc() =
    text(c, name).fontSize(metrics.fontCaption).bold().
      color(if active: pal.accent else: pal.text3).singleLine()
  )

proc batchHeader(c: Context, app: AppState, pal: Palette, metrics: Metrics) =
  let batch = app.batch
  let targets = app.vars[batch.scope].filterIt(isBatchEditable(it))
  let showChips = c.width >= 860 and targets.len <= 3 and
    targets.allIt(it.name.len <= 18)
  column(c).height(metrics.pageHeaderH).fillWidth().children(c, proc() =
    row(c).height(metrics.pageHeaderH - 1).fillWidth().
      background(pal.sidebar).padding(space12, 0, space12, 0).
      gap(space8).alignItems(aiCenter).children(c, proc() =
        discard iconButton(c, pal, metrics, icArrowLeft, 24, pal.text2,
          proc() = app.closeBatch(), key = "batch:back")
        text(c, "批量编辑值").fontSize(metrics.fontSubtitle).bold().
          color(pal.text).singleLine()
        scopePill(c, pal, metrics, scopeLabel(batch.scope),
                  batch.scope == esMachine)
        if showChips:
          text(c, "变量").fontSize(metrics.fontCaption).
            color(pal.text3).singleLine()
          for variable in targets:
            targetChip(c, app, pal, metrics, variable.name)
          if c.width > 1020:
            row(c).gap(space4).alignItems(aiCenter).children(c, proc() =
              icon(c, icInfo, 11, pal.text3)
              text(c, "每行一个条目 · 支持 ; 与换行分隔").
                fontSize(metrics.fontCaption).color(pal.text3).singleLine()
            )
          spacer(c)
        else:
          let picker = buttonBase(c, "batch:pick", proc() =
            batch.targetPickerOpen = true
            batch.focusTarget = "batch:target:" & lowerName(batch.target))
          picker.grow(1).basis(0).maxWidth(220).height(metrics.controlSm).
            padding(space8, 0, space8, 0).gap(space4).alignItems(aiCenter).
            background(pal.surface).border(1, pal.line).radius(radiusControl).
            hoverBg(pal.surface2)
          picker.children(c, proc() =
            text(c, batch.target).grow(1).basis(0).singleLine().
              fontSize(metrics.fontCaption).color(pal.text2)
            icon(c, icChevronDown, 12, pal.text3)
          )
          spacer(c)
        discard button(c, pal, metrics, "取消", kind = bkSecondary,
          onClick = proc() = app.closeBatch(), key = "batch:cancel")
        let parsed = batchParse(batch.text)
        let label =
          if parsed.entries.len == 0 and batch.originalValue.len > 0:
            "清空变量"
          else:
            "应用更改"
        discard button(c, pal, metrics, label, kind = bkPrimary,
          enabled = app.batchDirty(),
          onClick = proc() = app.applyBatch(), key = "batch:apply")
      )
    column(c).height(1).fillWidth().background(pal.line)
  )

proc batchTargets(c: Context, app: AppState, pal: Palette, metrics: Metrics) =
  let batch = app.batch
  if not batch.targetPickerOpen: return
  let targets = app.vars[batch.scope].filterIt(isBatchEditable(it))
  let layer = overlay(c, "batch:targets")
  layer.background(rgb(0, 0, 0, 0.38)).justifyContent(jcCenter).
    alignItems(aiCenter).whenClicked(proc() = app.closeBatchTargets())
  layer.children(c, proc() =
    column(c).width(min(400'f32, max(1'f32, c.width - 32))).
      padding(space12, space12).gap(space8).background(pal.surface).
      border(1, pal.line).radius(radiusOverlay).blockClicks().children(c, proc() =
        row(c).fillWidth().alignItems(aiCenter).children(c, proc() =
          text(c, "选择批量编辑变量").fontSize(metrics.fontSubtitle).bold().color(pal.text)
          spacer(c)
          discard iconButton(c, pal, metrics, icX, 24, pal.text3,
            proc() = app.closeBatchTargets(), key = "batch:targets:close")
        )
        let height = min(max(36'f32, c.height - 100),
          max(metrics.controlSm, float32(targets.len) * (metrics.controlSm + space4)))
        if c.engine != nil and c.engine.focusRequest == ("batch:target:" & lowerName(batch.target)):
          for i, variable in targets:
            if sameName(batch.target, variable.name):
              c.engine.revealListRow("batch:targets:list", i, targets.len,
                                     metrics.controlSm + space4, height)
              break
        scrollView(c, "batch:targets:list", height).fillWidth().gap(space4).
          children(c, proc() =
            for variable in targets:
              let name = variable.name
              let current = sameName(batch.target, name)
              let item = buttonBase(c, "batch:target:" & lowerName(name), proc() =
                app.closeBatchTargets()
                app.switchBatchTarget(name))
              item.fillWidth().height(metrics.controlSm).padding(space8, 0).
                background(if current: pal.accentSoft else: pal.surface).
                hoverBg(pal.surface2).radius(radiusControl)
              item.children(c, proc() =
                text(c, name).fillWidth().fontSize(metrics.fontBody).
                  color(if current: pal.accent else: pal.text2).singleLine()
              )
          )
      )
  )

proc statChip(c: Context, pal: Palette, metrics: Metrics, label: string,
              fg, bg: Color) =
  row(c).padding(space4, space2, space4, space2).radius(radiusControl).
    background(bg).gap(space2).alignItems(aiCenter).children(c, proc() =
      text(c, label).fontSize(metrics.fontCaption).bold().color(fg).
        singleLine()
    )

proc diffRow(c: Context, pal: Palette, metrics: Metrics, number: int,
             mark: string, value: string, added, removed: bool) =
  let bg =
    if added: pal.successSoft
    elif removed: pal.dangerSoft
    else: transparent()
  row(c).fillWidth().padding(space4, space2, space4, space2).
    radius(radiusControl).background(bg).gap(space6).alignItems(aiCenter).
    children(c, proc() =
      text(c, align($number, 2)).fontSize(metrics.fontCaption).
        family("mono").textAlign(taEnd).color(pal.text3).width(24).
        singleLine()
      text(c, mark).fontSize(metrics.fontCaption).bold().
        color(if added: pal.success elif removed: pal.danger else: pal.text3).
        width(12).singleLine()
      text(c, value).fontSize(metrics.fontSmall).family("mono").
        color(if added: pal.success elif removed: pal.danger else: pal.text2).
        grow(1).basis(0).singleLine()
    )

proc batchBody(c: Context, app: AppState, pal: Palette, metrics: Metrics) =
  let batch = app.batch
  let info = analyzeBatch(batch.originalValue, batch.text)
  let parsed = batchParse(batch.text)
  let entries = parsed.entries
  let stacked = c.width < 740
  let originalCount =
    if batch.originalValue.len == 0: 0
    else: splitValue(batch.originalValue).len
  let body = if stacked: column(c) else: row(c)
  body.fillWidth().grow(1).basis(0).children(c, proc() =
    let editor = column(c).grow(1.12).basis(0).background(pal.surface)
    if stacked: editor.fillWidth()
    else: editor.fillHeight()
    editor.
      children(c, proc() =
        row(c).height(metrics.paneHeaderH).fillWidth().
          padding(space12, 0, space12, 0).gap(space8).alignItems(aiCenter).
          children(c, proc() =
            text(c, "当前 " & $originalCount & " 个条目").
              fontSize(metrics.fontCaption).color(pal.text3).singleLine()
            spacer(c)
            discard button(c, pal, metrics, "整理为多行", iconName = icList,
              showIcon = true, kind = bkQuiet,
              onClick = proc() = app.normalizeBatch(), key = "batch:normalize")
          )
        column(c).grow(1).basis(0).fillWidth().
          padding(space12, space12, space12, space12).children(c, proc() =
            let box = column(c).grow(1).basis(0).fillWidth().
              background(pal.surface).border(1, pal.line).
              radius(radiusOverlay).clipChildren()
            box.children(c, proc() =
              let area = textArea(c, batch.text,
                proc(value: string) = batch.text = value,
                key = "batch:text",
                placeholder = "C:\\Program Files\\Tool\\bin\n" &
                  "C:\\Users\\Ada\\.local\\bin\nC:\\Windows\\System32",
                size = metrics.fontBody, height = 0, family = "mono")
              area.grow(1).basis(0).fillWidth()
              area.noWrap()
              area.lineNumbers(pal.text3)
              area.color(pal.text)
              area.placeholderColor(pal.text3)
            )
          )
        row(c).height(metrics.barH).fillWidth().background(pal.surface).
          padding(space12, 0, space12, 0).gap(space6).alignItems(aiCenter).
          children(c, proc() =
            icon(c, icShieldDone, 11, pal.success)
            text(c, "应用前自动创建备份").fontSize(metrics.fontCaption).
              color(pal.text3).grow(1).singleLine()
            var meta = $entries.len & " 个条目"
            if parsed.ignored > 0:
              meta.add(" · 忽略 " & $parsed.ignored & " 个空条目")
            text(c, meta).fontSize(metrics.fontCaption).color(pal.text3).
              singleLine()
          )
      )
    let separator = column(c).background(pal.line)
    if stacked: separator.height(1).fillWidth()
    else: separator.width(1).fillHeight()
    let preview = column(c).grow(0.88).basis(0).background(pal.surface2)
    if stacked: preview.fillWidth()
    else: preview.fillHeight()
    preview.
      children(c, proc() =
        row(c).height(metrics.paneHeaderH).fillWidth().
          padding(space12, 0, space12, 0).gap(space6).alignItems(aiCenter).
          children(c, proc() =
            text(c, "解析结果").fontSize(metrics.fontSmall).bold().
              color(pal.text2).singleLine()
            discard chip(c, pal, metrics, $entries.len, pal.text3, pal.surface3)
            text(c, batch.target & " · " & $info.original.len & " → " &
              $entries.len & " 项").fontSize(metrics.fontCaption).
              color(pal.text3).grow(1).basis(0).textAlign(taEnd).singleLine()
          )
        let scroll = scrollView(c, "batch:diff", height = 0).
          grow(1).basis(0).padding(space12, space6, space12, space6).
          gap(space6)
        scroll.children(c, proc() =
          row(c).gap(space4).fillWidth().children(c, proc() =
            if info.added.len > 0:
              statChip(c, pal, metrics, "+" & $info.added.len & " 新增",
                       pal.success, pal.successSoft)
            if info.removed.len > 0:
              statChip(c, pal, metrics, "−" & $info.removed.len & " 移除",
                       pal.danger, pal.dangerSoft)
            if info.reordered:
              statChip(c, pal, metrics, "顺序调整", pal.warn, pal.warnSoft)
            if not info.hasChanges:
              statChip(c, pal, metrics, "与当前值一致", pal.success,
                       pal.successSoft)
          )
          if entries.len == 0:
            callout(c, pal, metrics, icAlert, pal.danger, pal.dangerSoft,
                    pal.dangerSoft, "应用后此变量的值为空。")
          elif not info.hasChanges:
            callout(c, pal, metrics, icCheck, pal.success, pal.successSoft,
                    pal.successSoft, "内容与当前值一致，无需应用。")
          if info.reordered:
            callout(c, pal, metrics, icUnfold, pal.warn, pal.warnSoft,
                    pal.warnSoft, "条目顺序已调整，PATH 会按新顺序查找程序。")
          if info.duplicates.len > 0:
            var shown = info.duplicates
            if shown.len > 2:
              shown.setLen(2)
            callout(c, pal, metrics, icAlert, pal.warn, pal.warnSoft,
                    pal.warnSoft, $info.duplicates.len & " 个重复条目 · " &
                    shown.join("、") & "。重复项通常不会再次生效。")

          text(c, "新值条目  " & $entries.len).fontSize(metrics.fontSmall).
            bold().color(pal.text2).singleLine()
          let originalKeys = info.original.mapIt(normalizedEntry(it))
          for i, entry in entries:
            let added = normalizedEntry(entry) notin originalKeys
            diffRow(c, pal, metrics, i + 1, if added: "+" else: "", entry,
                    added, false)
          if info.removed.len > 0:
            text(c, "将移除  " & $info.removed.len).
              fontSize(metrics.fontSmall).bold().color(pal.text2).singleLine()
            for i, entry in info.removed:
              diffRow(c, pal, metrics, i + 1, "−", entry, false, true)
        )
      )
  )

proc viewBatch*(c: Context, app: AppState) =
  let pal = app.palette()
  let metrics = app.metrics()
  let batch = app.batch
  if batch == nil:
    return
  if batch.focusTarget.len > 0:
    c.requestFocus(batch.focusTarget, selectAll = false)
    batch.focusTarget = ""
  column(c).fill().background(pal.window).children(c, proc() =
    batchHeader(c, app, pal, metrics)
    batchBody(c, app, pal, metrics)
  )
  batchTargets(c, app, pal, metrics)
