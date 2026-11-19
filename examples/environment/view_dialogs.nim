## Modal confirmations and the backup history overlay.

import nimi/ui

import ./[icons, model, state, storage, theme, widgets]

proc modalOverlay*(c: Context, app: AppState) =
  let modal = app.modal
  if modal == nil:
    return
  let pal = app.palette()
  let metrics = app.metrics()
  let cancel = proc() =
    let fn = modal.onCancel
    app.modal = nil
    if fn != nil:
      fn()
  let layer = overlay(c, "modal", modal = true)
  layer.background(rgb(0, 0, 0, 0.44))
  layer.whenClicked(cancel)
  layer.justifyContent(jcCenter)
  layer.alignItems(aiCenter)
  layer.children(c, proc() =
    let panel = column(c).width(400).padding(space16, space16, space16, space16).
      radius(radiusOverlay).background(pal.surface).border(1, pal.line).
      gap(space8).blockClicks()
    let danger = modal.danger or modal.kind == mkElevation
    let icoBg =
      if modal.kind == mkElevation: pal.warnSoft
      elif modal.danger: pal.dangerSoft
      else: pal.accentSoft
    let icoFg =
      if modal.kind == mkElevation: pal.warn
      elif modal.danger: pal.danger
      else: pal.accent
    let ico =
      if modal.kind == mkElevation: icShield
      elif modal.danger: icAlert
      else: icInfo
    panel.children(c, proc() =
      row(c).width(34).height(34).radius(radiusOverlay).background(icoBg).
        center().children(c, proc() =
          icon(c, ico, 17, icoFg)
        )
      text(c, modal.title).fontSize(metrics.fontSubtitle).bold().
        color(pal.text).wrap()
      text(c, modal.message).fontSize(metrics.fontSmall).
        color(pal.text2).wrap()
      row(c).fillWidth().justifyContent(jcEnd).gap(space8).
        padding(0, space8, 0, 0).children(c, proc() =
          if modal.cancelLabel.len > 0:
            discard button(c, pal, metrics, modal.cancelLabel,
              kind = bkSecondary, onClick = cancel, key = "modal:cancel")
          let confirm = proc() =
            let fn = modal.onConfirm
            app.modal = nil
            if fn != nil:
              fn()
          discard button(c, pal, metrics, modal.confirmLabel,
            kind = if danger: bkDanger else: bkPrimary,
            onClick = confirm, key = "modal:confirm")
        )
    )
  )

proc snapshotRow(c: Context, app: AppState, pal: Palette, metrics: Metrics,
                 snapshot: Snapshot) =
  row(c).fillWidth().background(pal.surface2).border(1, pal.line).
    radius(radiusOverlay).padding(space8, space8, space8, space8).
    gap(space8).alignItems(aiCenter).children(c, proc() =
      row(c).width(27).height(27).radius(tileRadius(27)).
        background(pal.surface3).center().children(c, proc() =
          icon(c, icClock, 13, pal.text3)
        )
      column(c).grow(1).children(c, proc() =
        row(c).gap(space6).alignItems(aiCenter).children(c, proc() =
          let note = if snapshot.note.len > 0: snapshot.note else: "环境变量快照"
          text(c, note).fontSize(metrics.fontSmall).bold().
            color(pal.text).singleLine()
          scopePill(c, pal, metrics, scopeLabel(snapshot.scope),
                    snapshot.scope == esMachine)
        )
        text(c, snapshot.time & " · " & $snapshot.variables.len & " 个变量").
          fontSize(metrics.fontCaption).color(pal.text3).singleLine()
      )
      discard button(c, pal, metrics, "恢复", kind = bkText,
        onClick = proc() = app.restoreSnapshot(snapshot),
        key = "restore:" & snapshot.id)
    )

proc backupsOverlay*(c: Context, app: AppState) =
  if not app.backupsOpen:
    return
  let pal = app.palette()
  let metrics = app.metrics()
  let layer = overlay(c, "backups", modal = true)
  layer.background(rgb(0, 0, 0, 0.38))
  layer.whenClicked(proc() = app.closeBackups())
  layer.justifyContent(jcCenter)
  layer.alignItems(aiCenter)
  layer.children(c, proc() =
    let panel = column(c).width(500).padding(space16, space16, space16, space16).
      radius(radiusOverlay).background(pal.surface).border(1, pal.line).
      gap(space12).blockClicks()
    panel.children(c, proc() =
      row(c).gap(space8).alignItems(aiCenter).children(c, proc() =
        row(c).width(32).height(32).radius(radiusOverlay).
          background(pal.accentSoft).center().children(c, proc() =
            icon(c, icClock, 16, pal.accent)
          )
        column(c).grow(1).children(c, proc() =
          text(c, "备份历史").fontSize(metrics.fontSubtitle).bold().
            color(pal.text).singleLine()
          text(c, "每次应用更改前自动创建快照，最多保留 20 份。").
            fontSize(metrics.fontCaption).color(pal.text3).singleLine()
        )
        discard iconButton(c, pal, metrics, icX, 24, pal.text3,
          proc() = app.closeBackups(), key = "backups:close")
      )
      if app.snapshotsError.len > 0:
        text(c, app.snapshotsError).fontSize(metrics.fontSmall).
          color(pal.danger).wrap()
      elif app.snapshots.len == 0:
        column(c).fillWidth().height(140).center().gap(space6).
          children(c, proc() =
            icon(c, icClock, 22, pal.text3)
            text(c, "还没有备份").fontSize(metrics.fontSmall).
              color(pal.text3).singleLine()
            text(c, "应用更改后，这里会出现快照。").
              fontSize(metrics.fontCaption).color(pal.text3).singleLine()
          )
      else:
        let listHeight = min(430.0'f32,
          max(64.0'f32, float32(app.snapshots.len) * 52 + 8))
        let list = scrollView(c, "backups:list", height = listHeight)
        list.gap(space4).children(c, proc() =
          for snapshot in app.snapshots:
            snapshotRow(c, app, pal, metrics, snapshot)
        )
      row(c).fillWidth().justifyContent(jcEnd).gap(space8).children(c, proc() =
        discard button(c, pal, metrics, "关闭", kind = bkSecondary,
          onClick = proc() = app.closeBackups(), key = "backups:done")
      )
    )
  )
