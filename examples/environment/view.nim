## Root composition: main/batch page plus sheet, dialogs and toast.

import nimi/ui

import ./[icons, state, theme, view_batch, view_dialogs, view_main, view_sheet]

proc toastOverlay(c: Context, app: AppState, pal: Palette,
                  metrics: Metrics) =
  if app.toast == nil:
    return
  let toast = app.toast
  let layer = overlay(c, "toast", modal = false)
  layer.justifyContent(jcCenter)
  layer.alignItems(aiEnd)
  layer.padding(space16, space16, space16, space16)
  layer.children(c, proc() =
    let box = row(c).height(metrics.barH).padding(space12, 0, space12, 0).
      radius(radiusOverlay).background(
        if toast.isError: pal.danger else: pal.text).
      gap(space6).alignItems(aiCenter)
    box.blockClicks()
    box.children(c, proc() =
      icon(c, if toast.isError: icAlert else: icCheck, 14,
           if toast.isError: pal.dangerText else: pal.window)
      text(c, toast.message).fontSize(metrics.fontSmall).color(
        if toast.isError: pal.dangerText else: pal.window).
        maxWidth(420).singleLine()
      if toast.actionLabel.len > 0:
        let action = buttonBase(c, "toast:action", proc() =
          let fn = toast.action
          app.toast = nil
          if fn != nil:
            fn())
        action.height(metrics.controlXs)
        action.padding(space6, 0, space6, 0)
        action.radius(radiusControl)
        action.hoverBg(if toast.isError: pal.dangerSoft else: pal.surface3)
        action.children(c, proc() =
          text(c, toast.actionLabel).fontSize(metrics.fontSmall).bold().
            color(if toast.isError: pal.dangerText else: pal.accent).
            singleLine()
        )
    )
  )

proc registerShortcuts(app: AppState, c: Context) =
  if app.modal != nil:
    c.registerShortcut("escape", 0, proc() = app.cancelModal())
  elif app.sheet != nil:
    c.registerShortcut("s", KeyShortcut, proc() = app.saveSheet())
    c.registerShortcut("enter", KeyShortcut, proc() = app.saveSheet())
    c.registerShortcut("escape", 0, proc() = app.closeSheet())
  elif app.batch != nil and app.batch.targetPickerOpen:
    c.registerShortcut("escape", 0, proc() = app.closeBatchTargets())
  elif app.batch != nil:
    c.registerShortcut("s", KeyShortcut, proc() = app.applyBatch())
    c.registerShortcut("enter", KeyShortcut, proc() = app.applyBatch())
    c.registerShortcut("escape", 0, proc() = app.closeBatch())
  elif app.backupsOpen:
    c.registerShortcut("escape", 0, proc() = app.closeBackups())
  else:
    c.registerShortcut("k", KeyShortcut, proc() =
      c.requestFocus("search", selectAll = true))
    c.registerShortcut("n", KeyShortcut, proc() = app.openCreate())
    c.registerShortcut("e", KeyShortcut, proc() = app.openBatch())

proc appView*(app: AppState, c: Context) =
  app.tickToast()
  if app.batch != nil:
    viewBatch(c, app)
  else:
    viewMain(c, app)
  let pal = app.palette()
  let metrics = app.metrics()
  sheetOverlay(c, app)
  backupsOverlay(c, app)
  modalOverlay(c, app)
  toastOverlay(c, app, pal, metrics)
  registerShortcuts(app, c)
