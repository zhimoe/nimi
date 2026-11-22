## GTK file and message dialogs.

import std/[os, strutils]

import ../contract
import ./[ffi, state]

const
  GtkFileChooserActionOpen = 0
  GtkFileChooserActionSave = 1
  GtkFileChooserActionSelectFolder = 2
  GtkResponseAccept = -3

proc extension(value: string): string =
  result = value.strip(chars = {'.', ' '})
  for ch in result:
    if ch in {';', '*', '?', '/', '\\', '\0', ':', '|', '<', '>', '"'}:
      raise newException(BackendError,
        "File filters must be extensions, such as txt or .json")

proc requireGtk() =
  if not ffi.gtkLoaded or linuxState == nil or not linuxState.initialized:
    raise newException(BackendError,
      "Dialogs require an initialized GTK backend")

proc dialogParent(): pointer =
  if lastFocusedWindow != nil:
    return lastFocusedWindow.window
  nil

proc addFilters(chooser: pointer, filters: seq[string]) =
  var patterns: seq[string]
  for filter in filters:
    let ext = extension(filter)
    if ext.len > 0:
      patterns.add "*." & ext
  if patterns.len == 0:
    return
  let filter = gtk_file_filter_new()
  if filter == nil:
    return
  gtk_file_filter_set_name(filter, "Allowed files")
  for pattern in patterns:
    gtk_file_filter_add_pattern(filter, pattern.cstring)
  gtk_file_chooser_add_filter(chooser, filter)

proc chooseFiles(title, defaultPath: string, multiple, directory: bool,
                 filters: seq[string]): seq[string] =
  requireGtk()
  let action: cint =
    if directory: cint(GtkFileChooserActionSelectFolder)
    else: cint(GtkFileChooserActionOpen)
  let accept = if directory: "Select" else: "Open"
  let dialog = gtk_file_chooser_native_new(title.cstring, dialogParent(),
    action, accept.cstring, "Cancel".cstring)
  if dialog == nil:
    raise newException(BackendError, "Cannot create a GTK file chooser")
  try:
    if defaultPath.len > 0:
      let folder =
        if dirExists(defaultPath): defaultPath
        else: parentDir(defaultPath)
      if folder.len > 0:
        discard gtk_file_chooser_set_current_folder(dialog, folder.cstring)
    if multiple:
      gtk_file_chooser_set_select_multiple(dialog, 1)
    if filters.len > 0 and not directory:
      addFilters(dialog, filters)
    if gtk_native_dialog_run(dialog) != GtkResponseAccept:
      return
    if multiple:
      let list = gtk_file_chooser_get_filenames(dialog)
      var item = list
      var visited = 0
      while item != nil and visited < 100000:
        inc visited
        if item.data != nil:
          let path = $cast[cstring](item.data)
          if path.len > 0:
            result.add path
          g_free(item.data)
        item = item.next
      if list != nil:
        g_slist_free(list)
    else:
      let path = gtk_file_chooser_get_filename(dialog)
      if path != nil:
        let value = $path
        g_free(cast[pointer](path))
        if value.len > 0:
          result.add value
  finally:
    gtk_native_dialog_destroy(dialog)

proc saveFile(title, defaultPath, defaultExtension: string,
              filters: seq[string]): string =
  requireGtk()
  let dialog = gtk_file_chooser_native_new(title.cstring, dialogParent(),
    GtkFileChooserActionSave, "Save".cstring, "Cancel".cstring)
  if dialog == nil:
    raise newException(BackendError, "Cannot create a GTK save dialog")
  try:
    if defaultPath.len > 0:
      var name = lastPathPart(defaultPath)
      let ext = defaultExtension.strip(chars = {'.'})
      if ext.len > 0 and splitFile(name).ext.len == 0:
        name.add "." & ext
      if name.len > 0:
        gtk_file_chooser_set_current_name(dialog, name.cstring)
      let folder = parentDir(defaultPath)
      if folder.len > 0:
        discard gtk_file_chooser_set_current_folder(dialog, folder.cstring)
    if filters.len > 0:
      addFilters(dialog, filters)
    if gtk_native_dialog_run(dialog) == GtkResponseAccept:
      let path = gtk_file_chooser_get_filename(dialog)
      if path != nil:
        result = $path
        g_free(cast[pointer](path))
  finally:
    gtk_native_dialog_destroy(dialog)

proc messageDialog*(title, text: string, buttons: seq[string]): int =
  requireGtk()
  let dialog = gtk_dialog_new()
  if dialog == nil:
    raise newException(BackendError, "Cannot create a GTK message dialog")
  try:
    gtk_window_set_title(dialog, title.cstring)
    let parent = dialogParent()
    if parent != nil:
      gtk_window_set_transient_for(dialog, parent)
    gtk_window_set_modal(dialog, 1)
    let labels = if buttons.len > 0: buttons else: @["OK"]
    for i, label in labels:
      discard gtk_dialog_add_button(dialog, label.cstring, cint(i))
    let content = gtk_dialog_get_content_area(dialog)
    let body = if text.len > 0: text else: title
    let label = gtk_label_new(body.cstring)
    if label != nil:
      gtk_label_set_line_wrap(label, 1)
      gtk_label_set_max_width_chars(label, 60)
      if content != nil:
        gtk_container_add(content, label)
    gtk_widget_show_all(dialog)
    let response = gtk_dialog_run(dialog)
    if response < 0:
      result = -1
    elif response < labels.len:
      result = int(response)
    else:
      result = 0
  finally:
    gtk_widget_destroy(dialog)

proc newLinuxDialogs*(): Dialogs =
  result = Dialogs()
  result.open = proc(title, defaultPath: string, multiple,
                     directory: bool): seq[string] =
    chooseFiles(title, defaultPath, multiple, directory, @[])
  result.openWith = proc(title, defaultPath: string, multiple,
                         directory: bool, filters: seq[string]): seq[string] =
    chooseFiles(title, defaultPath, multiple, directory, filters)
  result.save = proc(title, defaultPath: string): string =
    saveFile(title, defaultPath, "", @[])
  result.saveWith = proc(title, defaultPath, defaultExtension: string,
                         filters: seq[string]): string =
    saveFile(title, defaultPath, defaultExtension, filters)
  result.message = proc(title, text: string): int =
    discard messageDialog(title, text, @["OK"])
    0
  result.messageWith = proc(title, text: string,
                            buttons: seq[string]): int =
    if buttons.len == 0:
      discard messageDialog(title, text, @["OK"])
      0
    else:
      messageDialog(title, text, buttons)
