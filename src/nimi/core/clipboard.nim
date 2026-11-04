## The system clipboard. The backend installs the implementation.

import ../platform/contract

proc readText*(): string =
  if currentBackend == nil or currentBackend.clipboard == nil: return ""
  currentBackend.clipboard.readText()

proc writeText*(text: string) =
  if currentBackend != nil and currentBackend.clipboard != nil:
    currentBackend.clipboard.writeText(text)

proc readHTML*(): string =
  if currentBackend == nil or currentBackend.clipboard == nil: return ""
  currentBackend.clipboard.readHTML()

proc writeHTML*(html: string) =
  if currentBackend != nil and currentBackend.clipboard != nil:
    currentBackend.clipboard.writeHTML(html)

proc clear*() =
  if currentBackend != nil and currentBackend.clipboard != nil:
    currentBackend.clipboard.clear()
