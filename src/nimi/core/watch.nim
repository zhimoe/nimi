## File/directory watching. The initial Darwin backend uses FSEvents with
## per-file event flags; callbacks arrive on the main queue.

import ./../platform/contract

type
  FileEventKind* = enum
    feCreated, feModified, feRemoved, feRenamed

  FileEvent* = object
    path*: string
    kind*: FileEventKind

  FileWatcher* = ref object
    native*: NativeFileWatcher

proc watch*(path: string, fn: proc(e: FileEvent)): FileWatcher =
  if currentBackend == nil or currentBackend.watchFiles == nil:
    return nil
  let native = currentBackend.watchFiles(path, proc(e: PlatformFileEvent) =
    let kind =
      case e.kind
      of pfeCreated: feCreated
      of pfeModified: feModified
      of pfeRemoved: feRemoved
      of pfeRenamed: feRenamed
    fn(FileEvent(path: e.path, kind: kind)))
  if native != nil:
    result = FileWatcher(native: native)

proc close*(w: FileWatcher) =
  if w != nil and w.native != nil:
    if w.native.close != nil:
      w.native.close()
    w.native = nil
