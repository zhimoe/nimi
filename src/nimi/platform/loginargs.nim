## The command line a login item starts the app with.

const openedAtLoginArg* = "--nimi-opened-at-login"

proc hasOpenedAtLoginArg*(args: openArray[string]): bool =
  ## Whether the system started this process as a login item. macOS 12's
  ## LaunchAgent fallback passes the marker; newer macOS reports it through
  ## the launch Apple Event instead.
  for arg in args:
    if arg == openedAtLoginArg:
      return true
  false
