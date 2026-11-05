## WebView cookie access. The initial implementation targets the default
## WKWebsiteDataStore; both calls are asynchronous and complete on the main
## queue. Ephemeral sessions keep their cookies in a non-persistent store and
## are not exposed by this default-store API yet.

import ../platform/contract

type
  Cookie* = object
    name*, value*, domain*, path*: string
    secure*, httpOnly*: bool

proc cookies*(cb: proc(cookies: seq[Cookie])) =
  if currentBackend == nil or currentBackend.getCookies == nil:
    cb(@[])
    return
  currentBackend.getCookies(proc(list: seq[PlatformCookie]) =
    var resultList: seq[Cookie]
    for c in list:
      resultList.add Cookie(name: c.name, value: c.value, domain: c.domain,
                            path: c.path, secure: c.secure, httpOnly: c.httpOnly)
    cb(resultList))

proc clearCookies*(cb: proc() = nil) =
  if currentBackend != nil and currentBackend.clearCookies != nil:
    currentBackend.clearCookies(cb)
  elif cb != nil:
    cb()
