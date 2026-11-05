## Local notifications. macOS uses NSUserNotification for now; the platform
## contract can move to UserNotifications without changing this API.

import ../platform/contract

type
  NotificationOptions* = object
    title*: string
    subtitle*: string
    body*: string

proc notify*(opts: NotificationOptions) =
  if currentBackend != nil and currentBackend.notify != nil:
    currentBackend.notify(PlatformNotification(
      title: opts.title,
      subtitle: opts.subtitle,
      body: opts.body))

proc notify*(title, body: string) =
  notify(NotificationOptions(title: title, body: body))
