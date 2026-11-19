## Application state and actions. Views stay in view*.nim; this module owns
## data, commit/merge/pending flows and dirty guards so they are testable
## without a window.

import std/[os, sequtils, sets, strutils, times]

import nimi

import ./[model, service, storage, theme]

type
  SheetMode* = enum
    smText, smList

  SheetState* = ref object
    create*: bool
    scope*: Scope
    originalName*, originalValue*: string
    originalKind*: EnvironmentKind
    name*, value*: string
    kind*: EnvironmentKind
    mode*: SheetMode
    entries*: seq[string]
    nameError*, status*: string
    focusTarget*: string

  BatchState* = ref object
    scope*: Scope
    target*, originalValue*, text*: string
    focusTarget*: string
    targetPickerOpen*: bool

  ModalKind* = enum
    mkInfo, mkConfirm, mkElevation

  ModalState* = ref object
    kind*: ModalKind
    title*, message*, confirmLabel*, cancelLabel*: string
    danger*: bool
    onConfirm*, onCancel*: proc() {.closure.}

  ToastState* = ref object
    message*: string
    isError*: bool
    actionLabel*: string
    action*: proc() {.closure.}
    expiresAt*: float64

  AppState* = ref object
    service*: Service
    store*: Store
    dataDir*: string
    vars*: array[Scope, seq[Variable]]
    loadErrors*: array[Scope, string]
    missing*: HashSet[string]
    missingVars*: HashSet[string]
    scope*: Scope
    filter*: ViewFilter
    query*: string
    sortDesc*: bool
    checked*: HashSet[string]
    expanded*: HashSet[string]
    focus*: array[Scope, int]
    admin*: bool
    sheet*: SheetState
    batch*: BatchState
    modal*: ModalState
    backupsOpen*: bool
    snapshots*: seq[Snapshot]
    snapshotsError*: string
    themeMode*: ThemeMode
    settings*: Settings
    systemDark*: bool
    highContrast*: bool
    textScale*: float32
    toast*: ToastState
    window*: Window
    startupToast*: string
    clipboardWrite*: proc(text: string) {.closure.}
    saveDialog*: proc(defaultName: string): string {.closure.}
    expandPath*: proc(path: string): string {.closure.}
    pathExists*: proc(path: string): bool {.closure.}
    elevated*: proc(): bool {.closure.}
    relaunchElevated*: proc(args: string): string {.closure.}
    quit*: proc() {.closure.}
    now*: proc(): float64 {.closure.}
    focusSearch*: bool
    resetTableScroll*: bool
    allowClose*: bool
    initialized*: bool

proc newAppState*(service: Service, store: Store, dataDir: string): AppState =
  result = AppState(
    service: service,
    store: store,
    dataDir: dataDir,
    scope: esUser,
    filter: vfAll,
    focus: [-1, -1],
    textScale: 1.0,
    clipboardWrite: proc(text: string) = discard,
    saveDialog: proc(defaultName: string): string = "",
    expandPath: proc(path: string): string = path,
    pathExists: proc(path: string): bool = false,
    elevated: proc(): bool = false,
    relaunchElevated: proc(args: string): string = "",
    quit: proc() = discard,
    now: proc(): float64 = epochTime())

proc sheetDirty*(app: AppState): bool
proc batchDirty*(app: AppState): bool
proc hasUnsaved*(app: AppState): bool
proc openDiscard*(app: AppState, title: string,
                  action: proc() {.closure.})
proc showToast*(app: AppState, message: string, isError = false,
                actionLabel = "", action: proc() {.closure.} = nil,
                seconds = 4.0)
proc restoreSnapshot*(app: AppState, snapshot: Snapshot)
proc openEdit*(app: AppState, variable: Variable)
proc openCreate*(app: AppState, prefill = "")

proc palette*(app: AppState): Palette =
  paletteFor(app.themeMode, app.systemDark, app.highContrast)

proc metrics*(app: AppState): Metrics =
  newMetrics(app.textScale)

proc effectiveDark*(app: AppState): bool =
  result = theme.effectiveDark(app.themeMode, app.systemDark)

proc saveSettings*(app: AppState) =
  app.settings.theme = app.themeMode
  try:
    app.store.saveSettings(app.settings)
  except CatchableError as e:
    app.showToast(e.msg, isError = true)

proc showToast*(app: AppState, message: string, isError = false,
                actionLabel = "", action: proc() {.closure.} = nil,
                seconds = 4.0) =
  let current = ToastState(message: message, isError: isError,
                           actionLabel: actionLabel, action: action,
                           expiresAt: app.now() + seconds)
  app.toast = current
  if app.window != nil:
    let window = app.window
    window.startAnimation(5, proc(time, dt: float64) =
      if app.toast == current and app.now() >= current.expiresAt:
        app.toast = nil
        window.stopAnimation()
        window.invalidate())

proc tickToast*(app: AppState) =
  if app.toast != nil and app.now() >= app.toast.expiresAt:
    app.toast = nil

proc openModal*(app: AppState, kind: ModalKind, title, message: string,
                confirmLabel = "确定", cancelLabel = "取消",
                danger = false,
                onConfirm: proc() {.closure.} = nil,
                onCancel: proc() {.closure.} = nil) =
  app.modal = ModalState(kind: kind, title: title, message: message,
                         confirmLabel: confirmLabel, cancelLabel: cancelLabel,
                         danger: danger, onConfirm: onConfirm,
                         onCancel: onCancel)

proc closeModal*(app: AppState) =
  app.modal = nil

proc cancelModal*(app: AppState) =
  if app.modal == nil:
    return
  let fn = app.modal.onCancel
  app.modal = nil
  if fn != nil:
    fn()

proc loadSnapshots*(app: AppState) =
  try:
    app.snapshots = app.store.loadSnapshots()
    app.snapshotsError = ""
  except CatchableError as e:
    app.snapshotsError = e.msg

proc checkablePath(app: AppState, entry: string): string =
  var value = entry.strip()
  if value.len >= 2 and value[0] == '"' and value[^1] == '"':
    value = value[1 .. ^2]
  if '"' in value:
    return ""
  if '%' in value:
    value = app.expandPath(value)
    if '%' in value:
      return ""
  if value.len < 3 or not value[0].isAlphaAscii or value[1] != ':' or
      value[2] notin {'\\', '/'}:
    return ""
  for ch in value:
    if ch in {';', '*', '?', '<', '>', '|'} or ord(ch) < 32:
      return ""
  for i in 0 ..< value.len - 1:
    if value[i] == ' ' and value[i + 1] in {'-', '/'}:
      return ""
  value

proc scanMissing*(app: AppState) =
  app.missing.clear()
  app.missingVars.clear()
  for scope in [esUser, esMachine]:
    for variable in app.vars[scope]:
      for entry in splitValue(variable.value):
        let checkable = app.checkablePath(entry)
        if checkable.len == 0:
          continue
        if not app.pathExists(checkable):
          app.missing.incl missingKey(scope, variable.name, entry.strip())
          app.missingVars.incl varKey(scope, variable.name)

proc reload*(app: AppState) =
  for scope in [esUser, esMachine]:
    try:
      app.vars[scope] = app.service.loadVariables(scope)
      app.loadErrors[scope] = ""
    except CatchableError as e:
      app.loadErrors[scope] = e.msg
  app.scanMissing()
  app.loadSnapshots()
  if not app.initialized:
    app.initialized = true
    let pathKey = varKey(esUser, "Path")
    if findVariable(app.vars[esUser], "Path") >= 0:
      app.expanded.incl pathKey

proc initApp*(app: AppState) =
  try:
    app.settings = app.store.loadSettings()
  except CatchableError as e:
    app.showToast(e.msg, isError = true)
  app.themeMode = app.settings.theme
  app.admin = app.elevated()
  app.reload()

proc scopeCount*(app: AppState, scope: Scope): int =
  app.vars[scope].len

proc pathCount*(app: AppState, scope: Scope): int =
  if findVariable(app.vars[scope], "Path") >= 0: 1 else: 0

proc multiCount*(app: AppState, scope: Scope): int =
  model.multiCount(app.vars[scope])

proc refCount*(app: AppState, scope: Scope): int =
  model.refCount(app.vars[scope])

proc missingVarCount*(app: AppState, scope: Scope): int =
  for variable in app.vars[scope]:
    if varKey(scope, variable.name) in app.missingVars:
      inc result

proc missingCount*(app: AppState, scope: Scope,
                   variable: Variable): int =
  model.missingCount(scope, variable, app.missing)

proc filteredRows*(app: AppState, scope: Scope): seq[Variable] =
  result = filtered(app.vars[scope], app.filter, app.query, app.sortDesc)
  if app.filter == vfMissing:
    result = result.filterIt(app.missingCount(scope, it) > 0)

proc checkedCount*(app: AppState, scope: Scope): int =
  let prefix = $ord(scope) & "\x00"
  for key in app.checked:
    if key.startsWith(prefix):
      inc result

proc isChecked*(app: AppState, scope: Scope, name: string): bool =
  varKey(scope, name) in app.checked

proc toggleChecked*(app: AppState, scope: Scope, name: string) =
  let key = varKey(scope, name)
  if key in app.checked:
    app.checked.excl key
  else:
    app.checked.incl key

proc clearChecked*(app: AppState) =
  app.checked.clear()

proc allChecked*(app: AppState, scope: Scope,
                 rows: openArray[Variable]): bool =
  if rows.len == 0: return false
  for variable in rows:
    if not app.isChecked(scope, variable.name):
      return false
  true

proc mixedChecked*(app: AppState, scope: Scope,
                   rows: openArray[Variable]): bool =
  var checkedAny, uncheckedAny = false
  for variable in rows:
    if app.isChecked(scope, variable.name):
      checkedAny = true
    else:
      uncheckedAny = true
  checkedAny and uncheckedAny

proc toggleAllChecked*(app: AppState, scope: Scope,
                       rows: openArray[Variable]) =
  let all = app.allChecked(scope, rows)
  for variable in rows:
    let key = varKey(scope, variable.name)
    if all:
      app.checked.excl key
    else:
      app.checked.incl key

proc isExpanded*(app: AppState, scope: Scope, name: string): bool =
  varKey(scope, name) in app.expanded

proc toggleExpanded*(app: AppState, scope: Scope, name: string) =
  let key = varKey(scope, name)
  if key in app.expanded:
    app.expanded.excl key
  else:
    app.expanded.incl key

proc focusIndex*(app: AppState, scope: Scope): int =
  let rows = app.filteredRows(scope)
  if rows.len == 0:
    return -1
  max(0, min(app.focus[scope], rows.len - 1))

proc setFocusIndex*(app: AppState, scope: Scope, index: int) =
  let rows = app.filteredRows(scope)
  if rows.len == 0:
    app.focus[scope] = -1
  else:
    app.focus[scope] = max(0, min(index, rows.len - 1))

proc moveFocus*(app: AppState, scope: Scope, delta: int) =
  let rows = app.filteredRows(scope)
  if rows.len == 0:
    return
  let current = app.focusIndex(scope)
  app.setFocusIndex(scope, if current < 0: 0 else: current + delta)

proc currentRow*(app: AppState, scope: Scope): int =
  app.focusIndex(scope)

proc switchScope*(app: AppState, scope: Scope) =
  if scope == app.scope:
    return
  let action = proc() =
    app.scope = scope
    app.checked.clear()
    app.resetTableScroll = true
    app.sheet = nil
    app.batch = nil
    app.backupsOpen = false
    if app.focus[scope] < 0:
      app.focus[scope] = 0
  if app.hasUnsaved():
    app.openDiscard("切换变量范围", action)
  else:
    action()

proc switchView*(app: AppState, filter: ViewFilter) =
  app.filter = filter
  app.resetTableScroll = true
  app.checked.clear()
  app.focus[app.scope] = 0
  if filter == vfPath:
    let idx = findVariable(app.vars[app.scope], "Path")
    if idx >= 0:
      app.expanded.incl varKey(app.scope, app.vars[app.scope][idx].name)

proc setQuery*(app: AppState, query: string) =
  app.query = query
  app.resetTableScroll = true
  app.checked.clear()
  app.focus[app.scope] = 0

proc toggleSort*(app: AppState) =
  app.sortDesc = not app.sortDesc
  app.resetTableScroll = true

proc submitSearch*(app: AppState) =
  let rows = app.filteredRows(app.scope)
  if rows.len == 1:
    app.openEdit(rows[0])
  elif rows.len == 0 and app.query.strip().len > 0:
    app.openCreate(app.query.strip())
  elif rows.len > 0:
    app.setFocusIndex(app.scope, 0)

proc multiRows*(app: AppState, scope: Scope): seq[Variable] =
  app.filteredRows(scope).filterIt(isMultiValue(it.value))

proc allMultiExpanded*(app: AppState, scope: Scope): bool =
  let rows = app.multiRows(scope)
  if rows.len == 0:
    return false
  for variable in rows:
    if not app.isExpanded(scope, variable.name):
      return false
  true

proc toggleExpandAll*(app: AppState, scope: Scope) =
  let rows = app.multiRows(scope)
  let collapse = app.allMultiExpanded(scope)
  for variable in rows:
    let key = varKey(scope, variable.name)
    if collapse:
      app.expanded.excl key
    else:
      app.expanded.incl key

proc themeModeLabel*(mode: ThemeMode): string =
  case mode
  of tmSystem: "跟随系统"
  of tmLight: "浅色外观"
  of tmDark: "深色外观"

proc cycleTheme*(app: AppState) =
  app.themeMode =
    case app.themeMode
    of tmSystem: tmLight
    of tmLight: tmDark
    of tmDark: tmSystem
  app.saveSettings()
  if app.window != nil:
    app.window.setDarkAppearance(app.effectiveDark())
    app.window.invalidate()

proc hasUnsaved*(app: AppState): bool =
  (app.sheet != nil and app.sheetDirty()) or
    (app.batch != nil and app.batchDirty())

proc openDiscard*(app: AppState, title: string, action: proc() {.closure.}) =
  app.openModal(mkConfirm, title,
    "关闭后，这个面板中的修改不会写入环境变量。",
    confirmLabel = "放弃更改", cancelLabel = "继续编辑", danger = true,
    onConfirm = proc() =
      app.modal = nil
      app.sheet = nil
      app.batch = nil
      action())

proc sheetDirty*(app: AppState): bool =
  let sheet = app.sheet
  if sheet == nil:
    return false
  if sheet.create:
    sheet.name.strip().len > 0 or sheet.value.len > 0 or
      sheet.kind != ekString
  else:
    sheet.value != sheet.originalValue or sheet.kind != sheet.originalKind

proc batchDirty*(app: AppState): bool =
  let batch = app.batch
  if batch == nil:
    return false
  let parsed = batchParse(batch.text)
  parsed.entries.join(";") != splitValue(batch.originalValue).join(";")

proc batchValue*(app: AppState): string =
  if app.batch == nil:
    return ""
  batchParse(app.batch.text).entries.join(";")

proc openCreate*(app: AppState, prefill = "") =
  if app.hasUnsaved():
    app.openDiscard("新建变量", proc() = app.openCreate(prefill))
    return
  app.sheet = SheetState(
    create: true, scope: app.scope, name: prefill, kind: ekString,
    mode: smText, entries: @[""], focusTarget: "sheet:name")
  app.batch = nil
  app.backupsOpen = false

proc openEdit*(app: AppState, variable: Variable) =
  if app.hasUnsaved():
    app.openDiscard("编辑变量", proc() = app.openEdit(variable))
    return
  let mode =
    if isMultiValue(variable.value) or isListLike(variable.name):
      smList
    else:
      smText
  app.sheet = SheetState(
    create: false, scope: app.scope,
    originalName: variable.name, originalValue: variable.value,
    originalKind: variable.kind,
    name: variable.name, value: variable.value, kind: variable.kind,
    mode: mode, entries: rawSplit(variable.value),
    focusTarget: if mode == smList: "sheet:entry:0" else: "sheet:value")
  app.batch = nil
  app.backupsOpen = false

proc closeSheet*(app: AppState) =
  if app.sheet == nil:
    return
  if app.sheetDirty():
    app.openDiscard("放弃未保存的更改", proc() = app.sheet = nil)
  else:
    app.sheet = nil

proc sheetCurrentValue*(app: AppState): string =
  let sheet = app.sheet
  if sheet == nil:
    return ""
  if sheet.mode == smList:
    sheet.entries.join(";")
  else:
    sheet.value

proc syncSheetEntries*(app: AppState) =
  let sheet = app.sheet
  if sheet == nil:
    return
  if sheet.mode == smList:
    sheet.value = sheet.entries.join(";")

proc setSheetValue*(app: AppState, value: string) =
  if app.sheet != nil:
    app.sheet.value = value

proc setSheetMode*(app: AppState, mode: SheetMode) =
  let sheet = app.sheet
  if sheet == nil or sheet.mode == mode:
    return
  if mode == smList:
    sheet.entries = rawSplit(sheet.value)
  else:
    sheet.value = sheet.entries.join(";")
  sheet.mode = mode

proc setSheetEntry*(app: AppState, index: int, value: string) =
  let sheet = app.sheet
  if sheet == nil or index notin 0 ..< sheet.entries.len:
    return
  sheet.entries[index] = value
  app.syncSheetEntries()

proc addSheetEntry*(app: AppState) =
  let sheet = app.sheet
  if sheet == nil:
    return
  sheet.entries.add ""
  app.syncSheetEntries()
  sheet.focusTarget = "sheet:entry:" & $(sheet.entries.len - 1)

proc removeSheetEntry*(app: AppState, index: int) =
  let sheet = app.sheet
  if sheet == nil or index notin 0 ..< sheet.entries.len:
    return
  if sheet.entries.len == 1:
    sheet.entries[0] = ""
  else:
    sheet.entries.delete(index)
  app.syncSheetEntries()

proc moveSheetEntry*(app: AppState, index, delta: int) =
  let sheet = app.sheet
  if sheet == nil:
    return
  let target = index + delta
  if index in 0 ..< sheet.entries.len and target in 0 ..< sheet.entries.len:
    swap(sheet.entries[index], sheet.entries[target])
    app.syncSheetEntries()

proc sheetWarnings*(app: AppState): string =
  let sheet = app.sheet
  if sheet == nil:
    return ""
  var entries =
    if sheet.mode == smList: sheet.entries
    else: rawSplit(sheet.value)
  var seen: seq[string]
  var duplicates: seq[string]
  for entry in entries:
    let key = normalizedEntry(entry)
    if key.len == 0:
      continue
    if key in seen:
      duplicates.add entry
    else:
      seen.add key
  if duplicates.len > 0:
    var shown = duplicates
    if shown.len > 2:
      shown.setLen(2)
    return $duplicates.len & " 个重复条目 · " & shown.join("、") &
      "。重复项通常不会再次生效。"

proc openBatch*(app: AppState, preferred = "") =
  if app.hasUnsaved():
    app.openDiscard("批量编辑", proc() = app.openBatch(preferred))
    return
  var targets = app.vars[app.scope].filterIt(isBatchEditable(it))
  if targets.len == 0:
    app.showToast("当前范围没有可批量编辑的多值变量", isError = true)
    return
  var target = targets[0]
  if preferred.len > 0:
    for candidate in targets:
      if sameName(candidate.name, preferred):
        target = candidate
        break
  else:
    for candidate in targets:
      if sameName(candidate.name, "Path"):
        target = candidate
        break
  app.batch = BatchState(
    scope: app.scope, target: target.name, originalValue: target.value,
    text: splitValue(target.value).join("\n"),
    focusTarget: "batch:text")
  app.sheet = nil
  app.backupsOpen = false

proc closeBatch*(app: AppState) =
  if app.batch == nil:
    return
  if app.batchDirty():
    app.openDiscard("放弃批量编辑", proc() = app.batch = nil)
  else:
    app.batch = nil

proc closeBatchTargets*(app: AppState) =
  if app.batch != nil:
    app.batch.targetPickerOpen = false
    app.batch.focusTarget = "batch:pick"

proc switchBatchTarget*(app: AppState, name: string) =
  let batch = app.batch
  if batch == nil or sameName(batch.target, name):
    return
  let scope = batch.scope
  let idx = findVariable(app.vars[scope], name)
  if idx < 0:
    app.showToast("变量不存在：" & name, isError = true)
    return
  let variable = app.vars[scope][idx]
  let action = proc() =
    if app.batch == nil:
      app.batch = BatchState(scope: scope, target: variable.name,
        originalValue: variable.value,
        text: splitValue(variable.value).join("\n"),
        focusTarget: "batch:text")
    else:
      app.batch.target = variable.name
      app.batch.originalValue = variable.value
      app.batch.text = splitValue(variable.value).join("\n")
  if app.batchDirty():
    app.openDiscard("切换批量目标", action)
  else:
    action()

proc normalizeBatch*(app: AppState) =
  if app.batch != nil:
    app.batch.text = batchParse(app.batch.text).entries.join("\n")

proc openBackups*(app: AppState) =
  if app.hasUnsaved():
    app.openDiscard("备份历史", proc() = app.openBackups())
    return
  app.loadSnapshots()
  app.backupsOpen = true
  app.sheet = nil
  app.batch = nil

proc closeBackups*(app: AppState) =
  app.backupsOpen = false

proc clearFocus*(app: AppState) =
  if app.window != nil:
    # The engine clears focus when the sheet closes on the next frame; the
    # view also stops rendering the focused key.
    discard

proc hasExternalChanges*(app: AppState, scope: Scope,
                         before, desired: openArray[Variable]): bool =
  ## Only names the edit actually touches are checked. Unrelated external
  ## changes are preserved by mergeChanges.
  let changes = diff(before, desired)
  let latest = app.service.loadVariables(scope)
  for value in changes.upserts:
    let baseIdx = findVariable(before, value.name)
    let latestIdx = findVariable(latest, value.name)
    if baseIdx >= 0:
      if latestIdx < 0 or latest[latestIdx] != before[baseIdx]:
        return true
    elif latestIdx >= 0:
      return true
  for name in changes.deletions:
    let baseIdx = findVariable(before, name)
    if baseIdx < 0:
      continue
    let latestIdx = findVariable(latest, name)
    if latestIdx < 0 or latest[latestIdx] != before[baseIdx]:
      return true
  false

proc commit*(app: AppState, scope: Scope, desired: seq[Variable],
             note, success, focusName: string,
             before: seq[Variable], fullReplace = false) =
  let problem = validate(desired)
  if problem.len > 0:
    app.showToast(problem, isError = true)
    return
  if scope == esMachine and not app.admin:
    app.openModal(mkElevation, "需要管理员权限",
      "修改系统变量会影响这台电脑上的所有用户。Nimi Env 将以管理员身份重新启动，Windows 会显示 UAC 授权提示。",
      confirmLabel = "以管理员身份重启", cancelLabel = "取消", danger = false,
      onConfirm = proc() =
        app.modal = nil
        try:
          discard app.store.saveSnapshot(scope, note,
            app.service.loadVariables(scope))
          app.store.writePending(PendingEdits(
            scope: scope, note: success, focus: focusName,
            fullReplace: fullReplace, before: before, variables: desired))
        except CatchableError as e:
          app.showToast("无法准备提权后的写入：" & e.msg, isError = true)
          return
        let error = app.relaunchElevated(
          "--data-dir=\"" & app.dataDir & "\"")
        if error.len > 0:
          try: app.store.clearPending()
          except CatchableError: discard
          app.showToast(error, isError = true)
          return
        app.quit())
    return
  try:
    if not fullReplace and app.hasExternalChanges(scope, before, desired):
      app.showToast("变量已在外部修改，请刷新后重试", isError = true)
      return
    let result = app.service.apply(scope, before, desired, note,
                                   fullReplace = fullReplace)
    app.reload()
    app.scope = scope
    app.checked.clear()
    app.resetTableScroll = true
    app.sheet = nil
    app.batch = nil
    if focusName.len > 0:
      let rows = app.filteredRows(scope)
      for i, variable in rows:
        if sameName(variable.name, focusName):
          app.focus[scope] = i
          app.expanded.incl varKey(scope, variable.name)
          break
    var message = success
    if not result.notified:
      message.add("；环境变更通知超时，重启相关程序后生效")
    let post = clone(app.vars[scope])
    app.showToast(message, actionLabel = "撤销",
      action = proc() =
        app.commit(scope, result.snapshot.variables, "撤销更改",
                   "已撤销更改", focusName, post),
      seconds = 8.0)
  except EnvironmentApplyError as e:
    app.reload()
    var message = "部分成功：已写入 " & $e.upserts & " 项、删除 " &
      $e.deletions & " 项；" & e.msg
    app.showToast(message, isError = true, actionLabel = "恢复备份",
      action = proc() =
        if app.snapshots.len > 0:
          app.restoreSnapshot(app.snapshots[0]),
      seconds = 8.0)
  except CatchableError as e:
    app.showToast("保存失败：" & e.msg, isError = true)

proc saveSheet*(app: AppState) =
  let sheet = app.sheet
  if sheet == nil:
    return
  if not sheet.create and not app.sheetDirty():
    app.showToast("没有需要保存的更改")
    return
  sheet.nameError = ""
  let name = sheet.name.strip()
  if name.len == 0:
    sheet.nameError = "请输入变量名"
    return
  if '=' in name:
    sheet.nameError = "变量名不能包含 ="
    return
  if sheet.create and findVariable(app.vars[sheet.scope], name) >= 0:
    sheet.nameError = "此范围中已存在变量 “" & name & "”"
    return
  var desired = clone(app.vars[sheet.scope])
  let value = app.sheetCurrentValue()
  let kind = kindFor(sheet.kind, value)
  let idx = findVariable(desired, name)
  if idx < 0:
    desired.add Variable(name: name, value: value, kind: kind)
  else:
    desired[idx] = Variable(name: desired[idx].name, value: value,
                            kind: kind)
  let before = clone(app.vars[sheet.scope])
  app.commit(sheet.scope, desired, "编辑变量 " & name,
             "已保存 “" & name & "”", name, before)

proc restoreSnapshot*(app: AppState, snapshot: Snapshot) =
  app.openModal(mkConfirm, "恢复此快照？",
    "将把" & scopeLabel(snapshot.scope) & "恢复到 " & snapshot.time &
      " 的状态，共 " & $snapshot.variables.len & " 个变量。\n\n" &
      "当前状态会先自动备份。",
    confirmLabel = "恢复快照", cancelLabel = "取消", danger = true,
    onConfirm = proc() =
      app.modal = nil
      app.commit(snapshot.scope, snapshot.variables, "恢复快照",
                 "已恢复备份快照", "Path", @[],
                 fullReplace = true))

proc deleteNames*(app: AppState, names: seq[string]) =
  if names.len == 0:
    return
  var shown = names
  if shown.len > 6:
    shown.setLen(6)
  var message = shown.join("\n")
  if names.len > shown.len:
    message.add("\n… 还有 " & $(names.len - shown.len) & " 个")
  let title =
    if names.len == 1: "删除这个变量？"
    else: "删除 " & $names.len & " 个变量？"
  app.openModal(mkConfirm, title,
    message & "\n\n删除前会自动备份，可在 8 秒内撤销。",
    confirmLabel = "删除", cancelLabel = "取消", danger = true,
    onConfirm = proc() =
      app.modal = nil
      let scope = app.scope
      var desired: seq[Variable]
      for variable in app.vars[scope]:
        if not names.containsFold(variable.name):
          desired.add variable
      app.commit(scope, desired, "删除变量", "已删除 " & $names.len &
        " 个变量", "", clone(app.vars[scope])))

proc deleteChecked*(app: AppState) =
  let scope = app.scope
  var names: seq[string]
  for variable in app.vars[scope]:
    if app.isChecked(scope, variable.name):
      names.add variable.name
  app.deleteNames(names)

proc deleteFocused*(app: AppState) =
  let scope = app.scope
  let rows = app.filteredRows(scope)
  let idx = app.focusIndex(scope)
  if idx >= 0 and idx < rows.len:
    app.deleteNames(@[rows[idx].name])

proc copyChecked*(app: AppState) =
  let scope = app.scope
  var lines: seq[string]
  for variable in app.vars[scope]:
    if app.isChecked(scope, variable.name):
      lines.add variable.name & "=" & variable.value
  if lines.len == 0:
    return
  app.clipboardWrite(lines.join("\n"))
  app.showToast("已复制 " & $lines.len & " 个变量")

proc exportChecked*(app: AppState) =
  let scope = app.scope
  var lines: seq[string]
  for variable in app.vars[scope]:
    if app.isChecked(scope, variable.name):
      lines.add variable.name & "=" & variable.value
  if lines.len == 0:
    return
  let defaultName = "nimi-env-" & scopeShort(scope) & ".env"
  let path = app.saveDialog(defaultName)
  if path.len == 0:
    return
  try:
    writeFile(path, lines.join("\n"))
    app.showToast("已导出 " & $lines.len & " 个变量")
  except CatchableError as e:
    app.showToast("导出失败：" & e.msg, isError = true)

proc applyBatch*(app: AppState) =
  let batch = app.batch
  if batch == nil:
    return
  let parsed = batchParse(batch.text)
  let value = parsed.entries.join(";")
  if value == splitValue(batch.originalValue).join(";"):
    app.showToast("没有需要应用的更改")
    return
  let action = proc() =
    var desired = clone(app.vars[batch.scope])
    let idx = findVariable(desired, batch.target)
    if idx < 0:
      app.showToast("变量不存在：" & batch.target, isError = true)
      return
    desired[idx] = Variable(name: desired[idx].name, value: value,
                            kind: kindFor(desired[idx].kind, value))
    app.commit(batch.scope, desired, "批量编辑 " & batch.target,
               "已更新 “" & batch.target & "”", batch.target,
               clone(app.vars[batch.scope]))
  if parsed.entries.len == 0 and batch.originalValue.len > 0:
    app.openModal(mkConfirm, "清空变量值？",
      "将把 “" & batch.target & "” 的值清空。应用前会自动备份，可在 8 秒内撤销。",
      confirmLabel = "清空并应用", cancelLabel = "取消", danger = true,
      onConfirm = proc() =
        app.modal = nil
        action())
  else:
    action()

proc requestAdmin*(app: AppState) =
  if app.admin:
    return
  app.openModal(mkElevation, "需要管理员权限",
    "以管理员身份重新启动后，才能修改系统变量。Windows 会显示 UAC 授权提示。",
    confirmLabel = "以管理员身份重启", cancelLabel = "取消",
    onConfirm = proc() =
      app.modal = nil
      try:
        app.store.clearPending()
      except CatchableError as e:
        app.showToast("无法清理待应用更改：" & e.msg, isError = true)
        return
      let error = app.relaunchElevated("--data-dir=\"" & app.dataDir & "\"")
      if error.len > 0:
        app.showToast(error, isError = true)
        return
      app.quit())

proc applyPending*(app: AppState) =
  if not app.admin or not app.store.hasPending():
    return
  var claimed = ""
  try:
    claimed = app.store.claimPending()
    let pending = readPendingAt(app.store.dir / claimed)
    discard app.service.apply(pending.scope, pending.before,
      pending.variables, "提权后应用更改前备份",
      fullReplace = pending.fullReplace)
    app.store.completePending(claimed)
    app.reload()
    app.scope = pending.scope
    if pending.focus.len > 0:
      let rows = app.filteredRows(app.scope)
      for i, variable in rows:
        if sameName(variable.name, pending.focus):
          app.focus[app.scope] = i
          break
    app.startupToast = if pending.note.len > 0:
      pending.note
    else:
      "已应用系统变量更改"
  except CatchableError as e:
    app.startupToast = "提权后应用失败：" & e.msg
    if claimed.len > 0:
      app.startupToast.add("（恢复文件：" & claimed & "）")
