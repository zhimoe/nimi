import std/[strutils, unittest]

import nimi/platform/[contract, loginargs]

when defined(macosx):
  import nimi/platform/darwin/login as darwinLogin

  suite "darwin login items":
    test "launch agent plist carries the app and the launch marker":
      let plist = darwinLogin.loginAgentPlist(
        "com.example.nimi", "/Applications/A & B.app", openedAtLoginArg)
      check "<string>com.example.nimi</string>" in plist
      check "/Applications/A &amp; B.app" in plist
      check openedAtLoginArg in plist
      check "<key>RunAtLoad</key>" in plist

    test "no launch Apple Event outside application launch":
      check not darwinLogin.launchedAsLoginItem()

    test "an unbundled process reports no login item and refuses changes":
      if darwinLogin.bundlePath().endsWith(".app"):
        echo "running from an app bundle; skipping the unbundled checks"
        check true
      else:
        check not darwinLogin.openAtLogin()
        check not darwinLogin.wasOpenedAtLogin()
        expect BackendError:
          darwinLogin.setOpenAtLogin(true)

else:
  suite "darwin login items":
    test "requires macOS":
      check true
