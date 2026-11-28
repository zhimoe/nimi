## Two-pass flex, scroll, and text measurement & arrangement pass.

import ./node
import ../text/measure

proc textLayoutFor*(n: Node, width: float32) =
  let available = max(1.0'f32, width - leftPad(n) - rightPad(n))
  if n.singleLine:
    let layout = layoutText(n.text, n.fontSize, n.bold, 0, n.family)
    n.lineHeight = layout.lineHeight
    n.lines = @[ellipsizeText(n.text, n.fontSize, n.bold, n.family, available)]
    n.lineStarts = @[0]
  else:
    let wrapWidth = if n.wrap: available else: 0.0'f32
    let layout = layoutText(n.text, n.fontSize, n.bold, wrapWidth, n.family)
    n.lines = layout.lines
    n.lineStarts = layout.lineStarts
    n.lineHeight = layout.lineHeight

proc richMetrics*(n: Node): tuple[width, height: float32] =
  for run in n.richRuns:
    let m = measureText(run.text, n.fontSize, run.bold or n.bold, n.family)
    result.width += m.width
    result.height = max(result.height, m.height)
  if n.richRuns.len == 0:
    let m = measureText("", n.fontSize, n.bold, n.family)
    result.height = m.height

proc measure*(n: Node, availW, availH: float32) =
  case n.kind
  of nkText:
    let pad = leftPad(n) + rightPad(n)
    let wrapWidth =
      if n.fixedW > 0: max(1.0'f32, n.fixedW - pad)
      elif n.singleLine: 0.0'f32
      elif n.wrap and availW > pad: availW - pad
      else: 0.0'f32
    let layout = layoutText(n.text, n.fontSize, n.bold, wrapWidth, n.family)
    n.lines = layout.lines
    n.lineStarts = layout.lineStarts
    n.lineHeight = layout.lineHeight
    n.w = if n.fixedW > 0: n.fixedW else: layout.width + pad
    n.h = if n.fixedH > 0: n.fixedH
          else: layout.height + topPad(n) + bottomPad(n)
  of nkRichText:
    let m = richMetrics(n)
    n.w = if n.fixedW > 0: n.fixedW
          else: m.width + leftPad(n) + rightPad(n)
    n.h = if n.fixedH > 0: n.fixedH
          else: m.height + topPad(n) + bottomPad(n)
  of nkButton:
    let m = measureText(n.text, n.fontSize, n.bold, n.family)
    n.w = if n.fixedW > 0: n.fixedW
          else: m.width + leftPad(n) + rightPad(n)
    n.h = if n.fixedH > 0: n.fixedH
          else: m.height + topPad(n) + bottomPad(n)
  of nkCheckbox:
    let m = measureText(n.text, n.fontSize, false, n.family)
    n.w = if n.fixedW > 0: n.fixedW
          else: (if n.text.len > 0: n.boxSize + 8 + m.width else: n.boxSize) +
                leftPad(n) + rightPad(n)
    n.h = if n.fixedH > 0: n.fixedH
          else: max(n.boxSize, m.height) + topPad(n) + bottomPad(n)
  of nkSwitch:
    n.w = if n.fixedW > 0: n.fixedW else: 40 + leftPad(n) + rightPad(n)
    n.h = if n.fixedH > 0: n.fixedH else: 22 + topPad(n) + bottomPad(n)
  of nkSlider:
    n.w = if n.fixedW > 0: n.fixedW else: 160
    n.h = if n.fixedH > 0: n.fixedH else: 24
  of nkProgress:
    n.w = if n.fixedW > 0: n.fixedW else: 160
    n.h = if n.fixedH > 0: n.fixedH else: 8
  of nkDivider:
    n.w = if n.fixedW > 0: n.fixedW elif availW > 0: availW else: 0
    n.h = if n.fixedH > 0: n.fixedH else: 1
  of nkInput:
    if n.multiline:
      n.w = if n.fixedW > 0: n.fixedW
            elif availW > 0: availW
            else: 320.0'f32
      n.h = if n.fixedH > 0: n.fixedH else: 120.0'f32
      n.layoutInput()
    else:
      let sample = if n.displayText.len > 0: n.displayText else: n.placeholder
      let m = measureText(sample, n.fontSize, false, n.family)
      n.w = if n.fixedW > 0: n.fixedW
            else: max(200.0'f32, m.width + leftPad(n) + rightPad(n))
      n.h = if n.fixedH > 0: n.fixedH
            else: max(28.0'f32, m.height + topPad(n) + bottomPad(n))
  of nkImage:
    n.w = if n.fixedW > 0: n.fixedW else: 120
    n.h = if n.fixedH > 0: n.fixedH else: 120
  of nkCustom:
    n.w = if n.fixedW > 0: n.fixedW else: 24
    n.h = if n.fixedH > 0: n.fixedH else: 24
  of nkScroll:
    n.w = if n.fixedW > 0: n.fixedW
          elif availW > 0: availW
          else: 320.0'f32
    n.h = if n.fixedH > 0: n.fixedH
          elif availH > 0: availH
          else: 240.0'f32
    let contentW = max(1.0'f32, innerW(n))
    var sumH, maxW: float32
    for ch in n.children:
      measure(ch, max(0.0'f32, contentW - ch.marginL - ch.marginR),
              1_000_000'f32)
      sumH += ch.h + ch.marginT + ch.marginB
      maxW = max(maxW, ch.w + ch.marginL + ch.marginR)
    if n.children.len > 1:
      sumH += n.gap * float32(n.children.len - 1)
    n.contentH = if n.virtualList: max(float32(n.itemCount) * n.itemHeight, n.h)
                 else: max(sumH + topPad(n) + bottomPad(n), n.h)
    if n.fixedW <= 0 and maxW > 0:
      n.w = max(n.w, maxW + leftPad(n) + rightPad(n))
  of nkColumn, nkRow, nkButtonBase:
    let padX = leftPad(n) + rightPad(n)
    let padY = topPad(n) + bottomPad(n)
    var maxW, maxH, sumW, sumH: float32
    let childAvailW = (if n.fixedW > 0: n.fixedW else: availW) - padX
    let childAvailH = (if n.fixedH > 0: n.fixedH else: availH) - padY
    for ch in n.children:
      measure(ch, max(0.0'f32, childAvailW - ch.marginL - ch.marginR),
              max(0.0'f32, childAvailH - ch.marginT - ch.marginB))
      let cw = ch.w + ch.marginL + ch.marginR
      let chh = ch.h + ch.marginT + ch.marginB
      maxW = max(maxW, cw)
      maxH = max(maxH, chh)
      sumW += cw
      sumH += chh
      if n.kind == nkColumn and ch.basisSet:
        sumH += ch.basis - ch.prefH
      elif n.kind != nkColumn and ch.basisSet:
        sumW += ch.basis - ch.prefW
    if n.children.len > 1:
      let gaps = n.gap * float32(n.children.len - 1)
      sumW += gaps
      sumH += gaps
    let fillW = n.fill or n.fillW
    let fillH = n.fill or n.fillH
    if n.kind == nkColumn:
      n.w = if fillW and availW > 0: availW else: maxW + padX
      n.h = if fillH and availH > 0: availH else: sumH + padY
    else:
      n.w = if fillW and availW > 0: availW else: sumW + padX
      n.h = if fillH and availH > 0: availH else: maxH + padY
    if n.fixedW > 0: n.w = n.fixedW
    if n.fixedH > 0: n.h = n.fixedH
  if n.fixedW > 0: n.w = n.fixedW
  if n.fixedH > 0: n.h = n.fixedH
  n.applySizeLimits()
  n.prefW = n.w
  n.prefH = n.h

proc remeasureAllocated*(n: Node, w, h: float32) =
  if abs(n.w - w) < 0.01 and abs(n.h - h) < 0.01:
    return
  let prefW = n.prefW
  let prefH = n.prefH
  defer:
    n.prefW = prefW
    n.prefH = prefH
  case n.kind
  of nkText:
    n.w = w
    n.h = h
    n.textLayoutFor(w)
  of nkRichText, nkCustom, nkImage, nkDivider, nkButton, nkCheckbox,
     nkSwitch, nkSlider, nkProgress:
    n.w = w
    n.h = h
  of nkInput:
    n.w = w
    n.h = h
    if n.multiline:
      n.layoutInput()
  else:
    measure(n, w, h)
    n.w = w
    n.h = h

proc arrange*(n: Node, x, y, slotW, slotH: float32)

proc arrangeContainer*(n: Node, x, y, w, h: float32) =
  let vertical = n.kind == nkColumn
  let contentX = x + leftPad(n)
  let contentY = y + topPad(n)
  let contentW = max(0.0'f32, w - leftPad(n) - rightPad(n))
  let contentH = max(0.0'f32, h - topPad(n) - bottomPad(n))
  let contentMain = if vertical: contentH else: contentW
  let contentCross = if vertical: contentW else: contentH
  let count = n.children.len
  if count == 0:
    return
  var bases = newSeq[float32](count)
  var total: float32
  for i, ch in n.children:
    let base = if ch.basisSet: ch.basis
               elif vertical: ch.prefH
               else: ch.prefW
    bases[i] = base
    total += base + (if vertical: ch.marginT + ch.marginB
                     else: ch.marginL + ch.marginR)
  if count > 1:
    total += n.gap * float32(count - 1)
  let free = contentMain - total
  var sumGrow: float32
  for ch in n.children:
    if ch.grow > 0:
      sumGrow += ch.grow
  var extras = newSeq[float32](count)
  var distributed: float32
  if free > 0 and sumGrow > 0:
    for i, ch in n.children:
      if ch.grow > 0:
        extras[i] = free * ch.grow / sumGrow
        distributed += extras[i]
  let alignment =
    if n.alignItemsSet: n.alignItems
    elif n.center: aiCenter
    else: aiStart
  let justification =
    if n.justifySet: n.justify
    elif n.center: jcCenter
    else: jcStart
  let remainder = free - distributed
  var start = if vertical: contentY else: contentX
  var extraGap = 0.0'f32
  case justification
  of jcCenter:
    if remainder > 0: start += remainder / 2
  of jcEnd:
    if remainder > 0: start += remainder
  of jcSpaceBetween:
    if count > 1 and remainder > 0:
      extraGap = remainder / float32(count - 1)
  of jcStart:
    discard
  var cursor = start
  for i, ch in n.children:
    let mainStart = if vertical: ch.marginT else: ch.marginL
    let mainEnd = if vertical: ch.marginB else: ch.marginR
    var mainSize = bases[i] + extras[i]
    if vertical:
      if ch.minH > 0: mainSize = max(mainSize, ch.minH)
      if ch.maxH > 0: mainSize = min(mainSize, ch.maxH)
    else:
      if ch.minW > 0: mainSize = max(mainSize, ch.minW)
      if ch.maxW > 0: mainSize = min(mainSize, ch.maxW)
    let align = if ch.alignSelf != aiAuto: ch.alignSelf else: alignment
    let crossStart = if vertical: ch.marginL else: ch.marginT
    let crossEnd = if vertical: ch.marginR else: ch.marginB
    let crossAvail = max(0.0'f32, contentCross - crossStart - crossEnd)
    var crossSize = if vertical: ch.prefW else: ch.prefH
    let crossFixed = if vertical: ch.fixedW > 0 else: ch.fixedH > 0
    if align == aiStretch and not crossFixed:
      crossSize = crossAvail
    var crossPos = (if vertical: contentX else: contentY) + crossStart
    case align
    of aiCenter:
      crossPos += (crossAvail - crossSize) / 2
    of aiEnd:
      crossPos += crossAvail - crossSize
    of aiAuto, aiStart, aiStretch:
      discard
    let childX = if vertical: crossPos else: cursor + mainStart
    let childY = if vertical: cursor + mainStart else: crossPos
    let allocW = if vertical: crossSize else: mainSize
    let allocH = if vertical: mainSize else: crossSize
    remeasureAllocated(ch, allocW, allocH)
    arrange(ch, childX, childY, allocW, allocH)
    cursor += mainSize + mainStart + mainEnd + n.gap + extraGap

proc arrangeScroll*(n: Node, x, y, w, h: float32) =
  let contentW = max(1.0'f32, w - leftPad(n) - rightPad(n))
  var sumH, maxW: float32
  for ch in n.children:
    measure(ch, max(0.0'f32, contentW - ch.marginL - ch.marginR),
            1_000_000'f32)
    sumH += ch.h + ch.marginT + ch.marginB
    maxW = max(maxW, ch.w + ch.marginL + ch.marginR)
  if n.children.len > 1:
    sumH += n.gap * float32(n.children.len - 1)
  n.contentH = if n.virtualList: max(float32(n.itemCount) * n.itemHeight, h)
               else: max(sumH + topPad(n) + bottomPad(n), h)
  var cy = y + topPad(n) - n.scrollY
  if n.virtualList: cy += float32(n.firstItem) * n.itemHeight
  for ch in n.children:
    let cw = max(1.0'f32, contentW - ch.marginL - ch.marginR)
    measure(ch, cw, 1_000_000'f32)
    arrange(ch, x + leftPad(n) + ch.marginL, cy + ch.marginT, cw, ch.h)
    cy += ch.h + ch.marginT + ch.marginB + n.gap

proc arrange*(n: Node, x, y, slotW, slotH: float32) =
  var w = if slotW >= 0: slotW else: n.w
  var h = if slotH >= 0: slotH else: n.h
  if n.fixedW > 0: w = n.fixedW
  if n.fixedH > 0: h = n.fixedH
  if n.minW > 0: w = max(w, n.minW)
  if n.maxW > 0: w = min(w, n.maxW)
  if n.minH > 0: h = max(h, n.minH)
  if n.maxH > 0: h = min(h, n.maxH)
  n.x = x
  n.y = y
  n.w = w
  n.h = h
  case n.kind
  of nkText:
    n.textLayoutFor(w)
  of nkRichText, nkImage, nkCustom, nkDivider, nkButton, nkCheckbox,
     nkSwitch, nkSlider, nkProgress:
    discard
  of nkInput:
    if n.multiline:
      n.layoutInput()
  of nkScroll:
    n.arrangeScroll(x, y, w, h)
  of nkColumn, nkRow, nkButtonBase:
    n.arrangeContainer(x, y, w, h)
