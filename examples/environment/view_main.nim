## Main list page: sidebar, header, toolbar, table, inline entries, footer.

import std/[sequtils, sets, strutils, tables]

import nimi/ui
import nimi/text/measure

import ./[icons, model, state, theme, widgets]

proc transparent(): Color = Color()

proc cardWidth(c: Context, metrics: Metrics): float32 =
  max(320.0'f32, c.width - sidebarWidth(metrics, c.width) - 1 - 48)

proc valueWidth(c: Context, metrics: Metrics): float32 =
  max(120.0'f32, cardWidth(c, metrics) - 34 - 200 - 72 - 8)

proc chipWidth(label: string, metrics: Metrics): float32 =
  measureText(label, metrics.fontCaption, true, "").width + 10

proc fixedSpace(c: Context, height: float32): Node {.discardable.} =
  column(c).height(height)

proc sideItem(c: Context, app: AppState, pal: Palette, metrics: Metrics,
              label: string, name: IconName, count: int, active: bool,
              accent: Color, locked: bool,
              onClick: proc() {.closure.}, key: string) =
  let item = buttonBase(c, key, onClick)
  item.height(metrics.controlMd)
  item.padding(space8, 0, space8, 0)
  item.radius(radiusControl)
  item.gap(space8)
  item.alignItems(aiCenter)
  item.background(if active: pal.surface else: transparent())
  item.border(1, if active: pal.line else: transparent())
  item.hoverBg(if active: pal.surface else: pal.surface2)
  item.pressedBg(pal.surface3)
  item.children(c, proc() =
    icon(c, name, 15, if active: accent else: pal.text3)
    text(c, label).fontSize(metrics.fontBody).bold().
      color(if active: pal.text else: pal.text2).grow(1).singleLine()
    if locked:
      icon(c, icLock, 11, pal.text3)
    if count >= 0:
      countPill(c, pal, metrics, count, active)
  )

proc adminCard(c: Context, app: AppState, pal: Palette, metrics: Metrics) =
  let bg = if app.admin: pal.successSoft else: pal.surface
  let border = if app.admin: pal.successSoft else: pal.line
  let icoBg = if app.admin: pal.successSoft else: pal.warnSoft
  let icoFg = if app.admin: pal.success else: pal.warn
  column(c).fillWidth().radius(radiusOverlay).background(bg).
    border(1, border).padding(space8, space8, space8, space8).gap(space4).
    children(c, proc() =
      row(c).gap(space8).alignItems(aiCenter).children(c, proc() =
        row(c).width(24).height(24).radius(tileRadius(24)).background(icoBg).
          center().children(c, proc() =
            icon(c, if app.admin: icShieldDone else: icShield, 14, icoFg)
          )
        column(c).grow(1).children(c, proc() =
          text(c, if app.admin: "管理员权限" else: "标准权限").
            fontSize(metrics.fontSmall).bold().color(pal.text).singleLine()
          text(c, if app.admin: "可修改系统变量" else: "保存系统变量时提权").
            fontSize(metrics.fontCaption).color(pal.text3).singleLine()
        )
      )
      if not app.admin:
        let link = buttonBase(c, "admin", proc() = app.requestAdmin())
        link.height(metrics.controlXs)
        link.padding(0, 0, 0, 0)
        link.gap(space2)
        link.alignItems(aiCenter)
        link.hoverBg(pal.warnSoft)
        link.children(c, proc() =
          text(c, "以管理员身份重启").fontSize(metrics.fontCaption).
            bold().color(pal.warn).singleLine()
          icon(c, icArrowRight, 10, pal.warn)
        )
    )

proc sidebar(c: Context, app: AppState, pal: Palette, metrics: Metrics) =
  let scope = app.scope
  let width = sidebarWidth(metrics, c.width)
  column(c).width(width).fillHeight().background(pal.sidebar).
    padding(space8, space12, space8, space8).gap(space2).
    alignItems(aiStretch).children(c, proc() =
      row(c).height(40).gap(space8).alignItems(aiCenter).children(c, proc() =
        row(c).width(21).height(21).radius(tileRadius(21)).
          background(pal.accent).center().children(c, proc() =
            icon(c, icSliders, 15, pal.accentText)
          )
        text(c, "Nimi Env").fontSize(metrics.fontBody).bold().color(pal.text).
          singleLine()
      )
      fixedSpace(c, space12)
      sectionLabel(c, pal, metrics, "变量范围")
      sideItem(c, app, pal, metrics, "用户变量", icUser,
        app.scopeCount(esUser), scope == esUser, pal.accent, false,
        proc() = app.switchScope(esUser), "scope:user")
      sideItem(c, app, pal, metrics, "系统变量", icShield,
        app.scopeCount(esMachine), scope == esMachine, pal.warn,
        not app.admin, proc() = app.switchScope(esMachine), "scope:system")
      fixedSpace(c, space16)
      sectionLabel(c, pal, metrics, "快速查看")
      sideItem(c, app, pal, metrics, "全部变量", icLayers,
        app.scopeCount(scope), app.filter == vfAll, pal.accent, false,
        proc() = app.switchView(vfAll), "filter:all")
      sideItem(c, app, pal, metrics, "PATH 路径", icRoute,
        -1, app.filter == vfPath, pal.accent, false,
        proc() = app.switchView(vfPath), "filter:path")
      sideItem(c, app, pal, metrics, "多值变量", icList,
        app.multiCount(scope), app.filter == vfMulti, pal.accent, false,
        proc() = app.switchView(vfMulti), "filter:multi")
      sideItem(c, app, pal, metrics, "含变量引用", icBraces,
        app.refCount(scope), app.filter == vfRefs, pal.accent, false,
        proc() = app.switchView(vfRefs), "filter:refs")
      let missingCount = app.missingVarCount(scope)
      if missingCount > 0:
        sideItem(c, app, pal, metrics, "缺失路径", icAlert,
          missingCount, app.filter == vfMissing, pal.danger, false,
          proc() = app.switchView(vfMissing), "filter:missing")
      spacer(c)
      let themeItem = buttonBase(c, "theme", proc() = app.cycleTheme())
      themeItem.height(metrics.controlMd)
      themeItem.padding(space8, 0, space8, 0)
      themeItem.radius(radiusControl)
      themeItem.gap(space8)
      themeItem.alignItems(aiCenter)
      themeItem.hoverBg(pal.surface2)
      themeItem.children(c, proc() =
        icon(c, if app.effectiveDark(): icSun else: icMoon, 14, pal.text3)
        text(c, themeModeLabel(app.themeMode)).fontSize(metrics.fontBody).
          color(pal.text2).grow(1).singleLine()
      )
      sideItem(c, app, pal, metrics, "备份历史", icClock,
        app.snapshots.len, false, pal.accent, false,
        proc() = app.openBackups(), "backups")
      fixedSpace(c, space6)
      adminCard(c, app, pal, metrics)
    )

proc mainHeader(c: Context, app: AppState, pal: Palette, metrics: Metrics) =
  let scope = app.scope
  let count = app.scopeCount(scope)
  let system = scope == esMachine
  row(c).padding(space24, space16, space24, 0).gap(space12).
    alignItems(aiStart).children(c, proc() =
      column(c).grow(1).gap(space4).children(c, proc() =
        row(c).gap(space8).alignItems(aiCenter).children(c, proc() =
          statusDot(c, 7, if system: pal.warn else: pal.accent)
          text(c, scopeLabel(scope)).fontSize(metrics.fontTitle).bold().
            color(pal.text).singleLine()
          countPill(c, pal, metrics, count)
        )
        row(c).gap(space4).alignItems(aiCenter).children(c, proc() =
          if system:
            icon(c, if app.admin: icShieldDone else: icLock, 11,
                 if app.admin: pal.success else: pal.warn)
          let subtitle =
            if system:
              (if app.admin: "影响所有用户 · 管理员模式"
               else: "影响所有用户 · 需要管理员权限才能修改")
            else:
              "仅影响当前用户 · 新终端生效"
          text(c, subtitle).fontSize(metrics.fontSmall).
            color(if system and not app.admin: pal.warn else: pal.text3).
            singleLine()
        )
      )
      row(c).gap(space6).alignItems(aiCenter).children(c, proc() =
        let hasBatch = app.vars[scope].anyIt(isBatchEditable(it))
        discard button(c, pal, metrics, "批量编辑", iconName = icList,
          showIcon = true, kind = bkSecondary, enabled = hasBatch,
          onClick = proc() = app.openBatch(), key = "batch")
        discard button(c, pal, metrics, "新建变量", iconName = icPlus,
          showIcon = true, kind = bkPrimary,
          onClick = proc() = app.openCreate(), key = "new")
      )
    )

proc searchField(c: Context, app: AppState, pal: Palette,
                 metrics: Metrics): Node {.discardable.} =
  let contentWidth = c.width - sidebarWidth(metrics, c.width) - 1 - 48
  let fieldWidth = min(500.0'f32, max(240.0'f32, contentWidth - 280))
  let outer = row(c).key("search:box").width(fieldWidth).height(metrics.controlMd).
    radius(radiusControl).background(pal.surface).border(1, pal.line).
    padding(space8, 0, space8, 0).gap(space6).alignItems(aiCenter)
  outer.whenClicked(proc() = c.requestFocus("search", selectAll = false))
  outer.children(c, proc() =
    icon(c, icSearch, 13, pal.text3)
    let input = textInput(c, app.query,
      proc(value: string) =
        app.setQuery(value)
    , key = "search", placeholder = "搜索变量名或值…",
      size = metrics.fontBody)
    input.plain()
    let clearWidth = if app.query.len > 0: 24.0'f32 else: 0.0'f32
    input.width(fieldWidth - 16 - 13 - 6 - clearWidth)
    input.height(metrics.controlMd - 2)
    input.color(pal.text)
    input.placeholderColor(pal.text3)
    input.whenSubmitted(proc() = app.submitSearch())
    if app.query.len > 0:
      discard iconButton(c, pal, metrics, icX, 18, pal.text3,
        proc() =
          app.setQuery("")
          c.requestFocus("search"),
        key = "search:clear")
  )
  outer

proc toolbar(c: Context, app: AppState, pal: Palette, metrics: Metrics) =
  let scope = app.scope
  row(c).padding(space24, space12, space24, space8).gap(space8).
    alignItems(aiCenter).children(c, proc() =
      let search = searchField(c, app, pal, metrics)
      discard search
      spacer(c)
      let rows = app.filteredRows(scope)
      if app.query.len > 0 or app.filter != vfAll:
        text(c, $rows.len & " 个结果").fontSize(metrics.fontSmall).
          color(pal.text3).singleLine()
      let multi = app.multiRows(scope)
      let collapse = app.allMultiExpanded(scope)
      let label =
        if multi.len > 0 and collapse: "收起全部多值" else: "展开全部多值"
      discard button(c, pal, metrics, label,
        iconName = (if collapse: icFold else: icUnfold), showIcon = true,
        kind = bkQuiet, enabled = multi.len > 0,
        onClick = proc() = app.toggleExpandAll(scope), key = "expand:all")
    )

proc errorBanner(c: Context, app: AppState, pal: Palette,
                 metrics: Metrics, scope: Scope) =
  let message = app.loadErrors[scope]
  if message.len == 0:
    return
  row(c).margin(space24, 0, space24, space8).height(metrics.barH).
    padding(space8, 0, space8, 0).radius(radiusOverlay).
    background(pal.dangerSoft).border(1, pal.dangerSoft).
    gap(space6).alignItems(aiCenter).children(c, proc() =
      icon(c, icAlert, 14, pal.danger)
      text(c, message).fontSize(metrics.fontSmall).color(pal.danger).
        grow(1).singleLine()
      let retry = buttonBase(c, "retry", proc() = app.reload())
      retry.height(metrics.controlXs)
      retry.padding(space6, 0, space6, 0)
      retry.radius(radiusControl)
      retry.hoverBg(pal.dangerSoft)
      retry.children(c, proc() =
        text(c, "重试").fontSize(metrics.fontSmall).bold().
          color(pal.danger).singleLine()
      )
    )

proc readonlyBanner(c: Context, app: AppState, pal: Palette,
                    metrics: Metrics) =
  if app.scope != esMachine or app.admin:
    return
  row(c).margin(space24, 0, space24, space8).height(metrics.barH).
    padding(space8, 0, space8, 0).radius(radiusOverlay).
    background(pal.warnSoft).border(1, pal.warnSoft).
    gap(space6).alignItems(aiCenter).children(c, proc() =
      icon(c, icShield, 14, pal.warn)
      text(c, "可编辑系统变量，保存时会请求管理员权限。").
        fontSize(metrics.fontSmall).color(pal.warn).grow(1).singleLine()
      let elevate = buttonBase(c, "elevate", proc() = app.requestAdmin())
      elevate.height(metrics.controlXs)
      elevate.padding(space6, 0, space6, 0)
      elevate.radius(radiusControl)
      elevate.hoverBg(pal.warnSoft)
      elevate.children(c, proc() =
        text(c, "立即提权").fontSize(metrics.fontSmall).bold().
          color(pal.warn).singleLine()
      )
    )

proc selectionBar(c: Context, app: AppState, pal: Palette, metrics: Metrics) =
  let scope = app.scope
  let count = app.checkedCount(scope)
  if count == 0:
    return
  row(c).margin(space24, 0, space24, space8).height(metrics.paneHeaderH).
    padding(space12, 0, space6, 0).radius(radiusOverlay).
    background(pal.accentSoft).border(1, pal.accentSoft2).
    gap(space6).alignItems(aiCenter).children(c, proc() =
      row(c).width(15).height(15).radius(radiusPill).background(pal.accent).
        center().children(c, proc() =
          icon(c, icCheck, 10, pal.accentText)
        )
      text(c, "已选择 " & $count & " 项").fontSize(metrics.fontSmall).
        color(pal.text2).singleLine()
      spacer(c)
      discard button(c, pal, metrics, "复制", kind = bkText,
        onClick = proc() = app.copyChecked(), key = "copy:checked")
      discard button(c, pal, metrics, "导出 .env", kind = bkText,
        onClick = proc() = app.exportChecked(), key = "export:checked")
      verticalDivider(c, pal, 16)
      discard button(c, pal, metrics, "删除", iconName = icTrash,
        showIcon = true, kind = bkText,
        onClick = proc() = app.deleteChecked(), key = "delete:checked")
      discard iconButton(c, pal, metrics, icX, 24, pal.text2,
        proc() = app.clearChecked(), key = "clear:checked")
    )

proc overlapChip(c: Context, pal: Palette, metrics: Metrics,
                 scope: Scope, name: string, app: AppState) =
  let overlap = overlap(scope, name, app.vars[esUser], app.vars[esMachine])
  if overlap == 2:
    discard chip(c, pal, metrics, "覆盖系统", pal.warn, pal.warnSoft)
  elif overlap == 1:
    discard chip(c, pal, metrics, "被覆盖", pal.text3, pal.surface3)

proc entryRuns(app: AppState, scope: Scope, name: string,
               entries: openArray[string]): seq[TextRun] =
  let pal = app.palette()
  for i, entry in entries:
    if i > 0:
      result.add TextRun(text: ";", color: pal.text3)
    let base =
      if missingKey(scope, name, entry) in app.missing:
        pal.danger
      else:
        pal.text2
    for run in valueRuns(entry, app.query, base, pal):
      result.add run

proc valueCell(c: Context, app: AppState, pal: Palette, metrics: Metrics,
               scope: Scope, variable: Variable, index: int,
               available: float32) =
  let entries = splitValue(variable.value)
  let missing = app.missingCount(scope, variable)
  if variable.value.len == 0:
    text(c, "（空值）").fontSize(metrics.fontSmall).color(pal.text3).
      singleLine()
    return
  if isMultiValue(variable.value):
    row(c).grow(1).height(metrics.rowH - 1).alignItems(aiCenter).
      gap(space6).children(c, proc() =
        let expanded = app.isExpanded(scope, variable.name)
        let toggle = buttonBase(c, "row:toggle:" & scopeShort(scope) & ":" &
          lowerName(variable.name), proc() =
          app.toggleExpanded(scope, variable.name))
        toggle.width(17)
        toggle.height(17)
        toggle.radius(radiusControl)
        toggle.background(if expanded: pal.accentSoft else: pal.surface3)
        toggle.hoverBg(if expanded: pal.accentSoft2 else: pal.line)
        toggle.children(c, proc() =
          icon(c, if expanded: icChevronDown else: icChevron, 10,
               if expanded: pal.accent else: pal.text3)
        )
        let label =
          if missing > 0: $entries.len & " 项 · " & $missing & " 缺失"
          else: $entries.len & " 项"
        discard chip(c, pal, metrics, label,
          if missing > 0: pal.danger else: pal.text3,
          if missing > 0: pal.dangerSoft else: pal.surface2)
        let textWidth = max(40.0'f32, available - 12 - 17 - 12 -
          chipWidth(label, metrics))
        let summary = richText(c,
          entryRuns(app, scope, variable.name, entries),
          size = metrics.fontBody, family = "mono")
        summary.width(textWidth)
        summary.height(20)
      )
  else:
    let base = if missing > 0: pal.danger else: pal.text2
    let value = richText(c, valueRuns(variable.value, app.query, base, pal),
      size = metrics.fontBody, family = "mono")
    value.width(max(40.0'f32, available - 12))
    value.height(20)

proc entryRow(c: Context, app: AppState, pal: Palette, metrics: Metrics,
              scope: Scope, variableName, entry: string, index: int,
              panelWidth: float32) =
  let missing = missingKey(scope, variableName, entry) in app.missing
  row(c).height(22).fillWidth().alignItems(aiCenter).gap(space6).
    children(c, proc() =
      text(c, align($(index + 1), 2)).fontSize(metrics.fontSmall).
        family("mono").textAlign(taEnd).color(pal.text3).width(24).
        singleLine()
      let chipW = if missing: chipWidth("路径不存在", metrics) else: 0.0'f32
      let textWidth = max(60.0'f32,
        panelWidth - 8 - 24 - 18 - 18 - chipW)
      let value = richText(c, valueRuns(entry, app.query,
        if missing: pal.danger else: pal.text2, pal),
        size = metrics.fontSmall, family = "mono")
      value.width(textWidth)
      value.height(18)
      if missing:
        discard chip(c, pal, metrics, "路径不存在", pal.danger,
          pal.dangerSoft)
      discard iconButton(c, pal, metrics, icCopy, 18, pal.text3,
        proc() =
          app.clipboardWrite(entry)
          app.showToast("已复制条目"),
        key = "copy-entry:" & scopeShort(scope) & ":" &
          lowerName(variableName) & ":" & $index)
    )

proc expandedPanel(c: Context, app: AppState, pal: Palette,
                   metrics: Metrics, scope: Scope, variable: Variable) =
  let entries = splitValue(variable.value)
  let missing = app.missingCount(scope, variable)
  let left = if c.width >= 1050: 234.0'f32 else: 34.0'f32
  let right = if c.width >= 1050: 84.0'f32 else: 12.0'f32
  let panelWidth = max(160.0'f32, cardWidth(c, metrics) - left - right)
  column(c).fillWidth().padding(left, 0, right, space4).children(c, proc() =
    column(c).fillWidth().background(pal.surface2).border(1, pal.line).
      radius(radiusControl).padding(space4, space4, space4, space4).
      gap(space2).children(c, proc() =
        row(c).height(22).fillWidth().alignItems(aiCenter).gap(space6).
          children(c, proc() =
            text(c, $entries.len & " 个条目 · 以 ; 分隔").
              fontSize(metrics.fontCaption).color(pal.text3).singleLine()
            if missing > 0:
              text(c, $missing & " 个路径不存在").
                fontSize(metrics.fontCaption).bold().color(pal.danger).
                singleLine()
            spacer(c)
            discard button(c, pal, metrics, "整段编辑", kind = bkText,
              onClick = proc() = app.openBatch(variable.name),
              key = "row:batch:" & scopeShort(scope) & ":" &
                lowerName(variable.name))
          )
        for i, entry in entries:
          entryRow(c, app, pal, metrics, scope, variable.name, entry, i,
                   panelWidth)
      )
  )

proc variableBlock(c: Context, app: AppState, pal: Palette, metrics: Metrics,
                   scope: Scope, variable: Variable, index: int) =
  let focused = app.focusIndex(scope) == index
  let checked = app.isChecked(scope, variable.name)
  let rowKey = "row:" & scopeShort(scope) & ":" & lowerName(variable.name)
  let rowBlock = column(c).key(rowKey)
  rowBlock.fillWidth()
  rowBlock.alignItems(aiStretch)
  rowBlock.focusable(true)
  rowBlock.tabStop(false)
  rowBlock.background(
    if checked: over(pal.accentSoft2, pal.surface)
    elif focused: over(pal.accentSoft, pal.surface)
    else: pal.surface)
  rowBlock.hoverBg(over(pal.surface2, pal.surface))
  rowBlock.whenClicked(proc() = app.setFocusIndex(scope, index))
  rowBlock.whenDoubleClicked(proc() = app.openEdit(variable))
  rowBlock.whenActivated(proc() = app.openEdit(variable))
  rowBlock.whenSpacePressed(proc() =
    if isMultiValue(variable.value):
      app.toggleExpanded(scope, variable.name)
    else:
      app.toggleChecked(scope, variable.name))
  rowBlock.children(c, proc() =
    row(c).height(metrics.rowH - 1).fillWidth().
      alignItems(aiCenter).children(c, proc() =
        row(c).width(34).height(metrics.rowH - 1).alignItems(aiCenter).
          padding(space12, 0, 0, 0).children(c, proc() =
            tableCheckbox(c, pal, metrics, checked, false,
              proc() = app.toggleChecked(scope, variable.name),
              "check:" & scopeShort(scope) & ":" & lowerName(variable.name))
          )
        row(c).width(200).height(metrics.rowH - 1).alignItems(aiCenter).
          gap(space6).padding(0, 0, space12, 0).children(c, proc() =
            let overlapValue =
              overlap(scope, variable.name,
                      app.vars[esUser], app.vars[esMachine])
            let overlapLabel =
              if overlapValue == 2: "覆盖系统"
              elif overlapValue == 1: "被覆盖"
              else: ""
            let chipW =
              if overlapLabel.len > 0: chipWidth(overlapLabel, metrics)
              else: 0.0'f32
            let rich = richText(c,
              nameRuns(variable.name, app.query, pal.text, pal),
              size = metrics.fontBody, family = "mono", bold = true)
            rich.width(188 - (if chipW > 0: chipW + 6 else: 0))
            rich.height(20)
            if overlapLabel.len > 0:
              overlapChip(c, pal, metrics, scope, variable.name, app)
          )
        let available = valueWidth(c, metrics)
        row(c).width(available).height(metrics.rowH - 1).
          alignItems(aiCenter).padding(0, 0, space12, 0).children(c, proc() =
            valueCell(c, app, pal, metrics, scope, variable, index,
                      available)
          )
        row(c).width(72).height(metrics.rowH - 1).alignItems(aiCenter).
          justifyContent(jcEnd).gap(space2).padding(0, space6, 0, 0).
          children(c, proc() =
            discard iconButton(c, pal, metrics, icPencil, 24, pal.text3,
              proc() = app.openEdit(variable),
              key = "edit:" & scopeShort(scope) & ":" &
                lowerName(variable.name))
            discard iconButton(c, pal, metrics, icTrash, 24, pal.text3,
              proc() = app.deleteNames(@[variable.name]),
              key = "delete:" & scopeShort(scope) & ":" &
                lowerName(variable.name))
          )
        column(c).width(8).height(metrics.rowH - 1)
      )
    column(c).height(1).fillWidth().background(pal.lineSoft)
  )
  if app.isExpanded(scope, variable.name):
    expandedPanel(c, app, pal, metrics, scope, variable)

proc emptyState(c: Context, app: AppState, pal: Palette, metrics: Metrics) =
  let scope = app.scope
  let hasQuery = app.query.strip().len > 0
  let title =
    if hasQuery: "没有匹配的变量"
    elif app.filter == vfPath: "没有 PATH 变量"
    elif app.filter == vfMulti: "没有多值变量"
    elif app.filter == vfRefs: "没有含变量引用的变量"
    elif app.filter == vfMissing: "没有缺失路径"
    else: "还没有环境变量"
  let description =
    if hasQuery: "试试其他关键词，或直接新建一个变量。"
    elif app.filter == vfPath: "当前范围中没有 Path 变量。"
    elif app.filter == vfMulti: "值中包含 ; 分隔项的变量会出现在这里。"
    elif app.filter == vfRefs: "包含 %VARIABLE% 引用的变量会出现在这里。"
    elif app.filter == vfMissing: "当前范围内的路径都存在。"
    else: "点击“新建变量”开始管理当前范围。"
  column(c).fillWidth().padding(0, 48, 0, 48).alignItems(aiCenter).
    gap(space8).children(c, proc() =
      row(c).width(48).height(48).radius(radiusOverlay).
        background(pal.surface2).border(1, pal.line).center().
        children(c, proc() =
          icon(c, if hasQuery: icSearch else: icLayers, 22, pal.text3)
        )
      text(c, title).fontSize(metrics.fontSubtitle).bold().color(pal.text).
        singleLine()
      let descriptionWidth = min(360'f32, max(160'f32, c.width - 120))
      text(c, description).fontSize(metrics.fontSmall).color(pal.text3).
        width(descriptionWidth).textAlign(taCenter).wrap()
      row(c).gap(space6).alignItems(aiCenter).children(c, proc() =
        if hasQuery:
          discard button(c, pal, metrics, "清除搜索", kind = bkSecondary,
            onClick = proc() = app.setQuery(""), key = "empty:clear")
        discard button(c, pal, metrics, "新建变量", iconName = icPlus,
          showIcon = true, kind = bkPrimary,
          onClick = proc() = app.openCreate(app.query.strip()),
          key = "empty:new")
      )
    )

proc tableHeader(c: Context, app: AppState, pal: Palette,
                 metrics: Metrics, rows: seq[Variable]) =
  let scope = app.scope
  column(c).height(metrics.barH + 1).fillWidth().children(c, proc() =
    row(c).height(metrics.barH).fillWidth().background(pal.surface2).
      alignItems(aiCenter).children(c, proc() =
        row(c).width(34).height(metrics.barH).alignItems(aiCenter).
          padding(space12, 0, 0, 0).children(c, proc() =
            tableCheckbox(c, pal, metrics, app.allChecked(scope, rows),
              app.mixedChecked(scope, rows),
              proc() = app.toggleAllChecked(scope, rows), "check:all")
          )
        let sortButton = buttonBase(c, "sort:name", proc() = app.toggleSort())
        sortButton.width(200)
        sortButton.height(metrics.barH)
        sortButton.padding(0, 0, space12, 0)
        sortButton.alignItems(aiCenter)
        sortButton.justifyContent(jcStart)
        sortButton.gap(space4)
        sortButton.hoverBg(pal.surface3)
        sortButton.children(c, proc() =
          text(c, "变量名").fontSize(metrics.fontCaption).bold().
            color(pal.text3).singleLine()
          icon(c, icSort, 11, pal.text3)
        )
        row(c).grow(1).height(metrics.barH).alignItems(aiCenter).
          padding(0, 0, space12, 0).children(c, proc() =
            text(c, "值").fontSize(metrics.fontCaption).bold().
              color(pal.text3).singleLine()
          )
        row(c).width(72).height(metrics.barH)
        column(c).width(8).height(metrics.barH)
      )
    column(c).height(1).fillWidth().background(pal.line)
  )

proc tableFooter(c: Context, app: AppState, pal: Palette, metrics: Metrics,
                 shown: int) =
  let scope = app.scope
  let total = app.scopeCount(scope)
  column(c).height(metrics.barH + 1).fillWidth().children(c, proc() =
    column(c).height(1).fillWidth().background(pal.line)
    row(c).height(metrics.barH).fillWidth().background(pal.surface2).
      padding(space8, 0, space8, 0).gap(space6).alignItems(aiCenter).
      children(c, proc() =
        statusDot(c, 5, pal.success)
        let textValue =
          if app.query.len > 0 or app.filter != vfAll:
            "显示 " & $shown & " / " & $total & " 个变量 · 保存前自动备份"
          else:
            $total & " 个变量 · 保存前自动备份"
        text(c, textValue).fontSize(metrics.fontCaption).
          color(pal.text3).singleLine()
        spacer(c)
        let hint =
          if c.width > 1040:
            "双击编辑  空格展开  Ctrl K 搜索"
          else:
            "双击编辑 · 空格展开"
        text(c, hint).fontSize(metrics.fontCaption).color(pal.text3).
          singleLine()
      )
  )

proc tableCard(c: Context, app: AppState, pal: Palette, metrics: Metrics) =
  let scope = app.scope
  let rows = app.filteredRows(scope)
  let card = column(c).grow(1).basis(0).margin(space24, 0, space24, space12).
    radius(radiusOverlay).background(pal.surface).border(1, pal.line).
    clipChildren().alignItems(aiStretch)
  card.children(c, proc() =
    tableHeader(c, app, pal, metrics, rows)
    let body = scrollView(c, "table", height = 0).grow(1).basis(0)
    body.children(c, proc() =
      if rows.len == 0:
        emptyState(c, app, pal, metrics)
      else:
        for index, variable in rows:
          variableBlock(c, app, pal, metrics, scope, variable, index)
    )
    tableFooter(c, app, pal, metrics, rows.len)
  )

proc variableHeight(metrics: Metrics, app: AppState, scope: Scope,
                    variable: Variable): float32 =
  result = metrics.rowH
  if app.isExpanded(scope, variable.name):
    let entries = splitValue(variable.value).len
    result += 34 + 24 * float32(entries)

proc revealTableFocus(c: Context, app: AppState, metrics: Metrics,
                      scope: Scope) =
  let rows = app.filteredRows(scope)
  let index = app.focusIndex(scope)
  if index < 0 or index >= rows.len:
    return
  var top: float32
  for i in 0 ..< index:
    top += variableHeight(metrics, app, scope, rows[i])
  let height = variableHeight(metrics, app, scope, rows[index])
  var region: ScrollRegion
  var found = false
  for candidate in c.engine.scrollRegions:
    if candidate.key == "table":
      region = candidate
      found = true
      break
  if not found or region.rect.h <= 0:
    return
  let maxOff = max(0.0'f32, region.contentH - region.rect.h)
  var offset = c.engine.scrollOffsets.getOrDefault("table", 0)
  if top < offset:
    offset = top
  elif top + height > offset + region.rect.h:
    offset = top + height - region.rect.h
  c.engine.scrollOffsets["table"] =
    max(0.0'f32, min(offset, maxOff))
  if c.engine.requestFrame != nil:
    c.engine.requestFrame()

proc viewMain*(c: Context, app: AppState) =
  let pal = app.palette()
  let metrics = app.metrics()
  if app.focusSearch:
    c.requestFocus("search", selectAll = true)
    app.focusSearch = false
  if app.resetTableScroll:
    if c.engine != nil:
      c.engine.scrollOffsets["table"] = 0
    app.resetTableScroll = false
  if app.sheet == nil and app.batch == nil and app.modal == nil and
      not app.backupsOpen:
    let scope = app.scope
    var moved = false
    while c.keyPressed("up"):
      app.moveFocus(scope, -1)
      moved = true
    while c.keyPressed("down"):
      app.moveFocus(scope, 1)
      moved = true
    if moved:
      revealTableFocus(c, app, metrics, scope)
    if c.keyPressed("delete"):
      app.deleteFocused()
  row(c).fill().background(pal.window).children(c, proc() =
    sidebar(c, app, pal, metrics)
    column(c).width(1).fillHeight().background(pal.line)
    column(c).grow(1).basis(0).fillHeight().alignItems(aiStretch).children(c, proc() =
      mainHeader(c, app, pal, metrics)
      toolbar(c, app, pal, metrics)
      errorBanner(c, app, pal, metrics, app.scope)
      readonlyBanner(c, app, pal, metrics)
      selectionBar(c, app, pal, metrics)
      tableCard(c, app, pal, metrics)
    )
  )
