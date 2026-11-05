## The M1 `nimi` CLI. Kept intentionally small: generate, dev, build, init,
## doctor. Packaging/signing/updater land in M7.

import std/[algorithm, json, os, osproc, strtabs, strutils, times]

const
  Version = "0.1.0"
  HelpText = """nimi — desktop apps in Nim

Usage:
  nimi init [dir] [--native]
  nimi generate [dir]
  nimi dev [dir]
  nimi build [dir]
  nimi doctor
  nimi version
  nimi help

A project has a nimi.json at its root. See docs/04-tooling-and-ipc.md.
"""

type
  Config = object
    name: string
    slug: string
    identifier: string
    version: string
    main: string
    bindings: string
    outDir: string
    projectDir: string
    icon: string
    signingIdentity: string
    dmgTitle: string
    notarize: bool
    keychainProfile: string
    entitlements: string
    resources: seq[string]
    urlSchemes: seq[string]

proc fail(msg: string): ref CatchableError =
  newException(CatchableError, msg)

proc libraryPath(): string =
  let fromEnv = getEnv("NIMI_LIB")
  if fromEnv.len > 0:
    return absolutePath(fromEnv)
  let local = getAppDir() / "src"
  if dirExists(local):
    return local
  result = "src"

proc runChecked(cmd: string): string =
  let (output, code) = execCmdEx(cmd)
  if code != 0:
    stderr.write(output)
    raise fail("command failed (" & $code & "): " & cmd)
  result = output

proc slugify(s: string): string =
  var prevDash = false
  for ch in s.toLowerAscii:
    if ch in {'a'..'z', '0'..'9'}:
      result.add ch
      prevDash = false
    elif not prevDash:
      result.add '-'
      prevDash = true
  result = result.strip(chars = {'-'})

proc loadConfig(dir: string): Config =
  result.projectDir = absolutePath(dir)
  let path = result.projectDir / "nimi.json"
  if not fileExists(path):
    raise fail("nimi.json not found in " & result.projectDir)
  let node = parseFile(path)
  result.name = node{"name"}.getStr("Nimi")
  result.slug = node{"slug"}.getStr(slugify(result.name))
  result.identifier = node{"identifier"}.getStr("com.example." & result.slug)
  result.version = node{"version"}.getStr("0.1.0")
  result.main = node{"main"}.getStr("src/main.nim")
  result.bindings = node{"bindings"}.getStr("frontend/nimi.ts")
  result.outDir = node{"out"}.getStr("dist")
  let macos = node{"macos"}
  proc strField(n: JsonNode, key, default: string): string =
    if n != nil and n.kind == JObject and n.hasKey(key):
      n[key].getStr(default)
    else:
      default
  result.icon = strField(node, "icon", "resources/icon.png")
  result.signingIdentity = strField(macos, "signingIdentity", "-")
  result.dmgTitle = strField(macos, "dmgTitle", result.name)
  result.notarize = macos != nil and macos.kind == JObject and
    macos.hasKey("notarize") and macos["notarize"].getBool(false)
  result.keychainProfile = strField(macos, "keychainProfile", "")
  result.entitlements = strField(macos, "entitlements", "")
  let resources = node{"resources"}
  if resources != nil and resources.kind == JArray:
    for item in resources:
      if item.kind == JString:
        result.resources.add item.getStr
  let schemes = node{"urlSchemes"}
  if schemes != nil and schemes.kind == JArray:
    for item in schemes:
      if item.kind == JString:
        result.urlSchemes.add item.getStr

proc runGenerate(dir: string) =
  let cfg = loadConfig(dir)
  let mainPath = cfg.projectDir / cfg.main
  if not fileExists(mainPath):
    raise fail("main not found: " & mainPath)
  let bindingsPath = cfg.projectDir / cfg.bindings
  createDir(parentDir(bindingsPath))
  let cacheDir = cfg.projectDir / ".nimi"
  createDir(cacheDir)
  let exe = cacheDir / "generate"

  echo "Compiling " & cfg.main & " for client generation…"
  discard runChecked("nim c --hints:off --path:" & quoteShell(libraryPath()) &
    " -d:nimiGenerate --out:" & quoteShell(exe) & " " & quoteShell(mainPath))

  let (output, code) = execCmdEx(
    quoteShell(exe),
    options = {},
    env = block:
      var e = newStringTable()
      for k, v in envPairs():
        e[k] = v
      e["NIMI_GENERATE"] = bindingsPath
      e)
  if code != 0:
    stderr.write(output)
    raise fail("generation run failed (" & $code & ")")

  # A tiny runtime stub so the generated client type-checks before the
  # frontend installs nimi-runtime.
  let stub = parentDir(bindingsPath) / "nimi-runtime.ts"
  if not fileExists(stub):
    writeFile(stub, """declare global {
  interface Window {
    nimi: { call(method: string, ...args: unknown[]): Promise<unknown> };
    mygo?: { call(method: string, ...args: unknown[]): Promise<unknown> };
  }
}

export function call<T>(method: string, ...args: unknown[]): Promise<T> {
  return window.nimi.call(method, ...args) as Promise<T>;
}
""")
  echo "Generated " & bindingsPath

proc makeIcns(cfg: Config, resourcesDir: string): string =
  let iconPath = absolutePath(cfg.projectDir / cfg.icon)
  if not fileExists(iconPath):
    return ""
  if iconPath.endsWith(".icns"):
    let dst = resourcesDir / "AppIcon.icns"
    copyFile(iconPath, dst)
    return "AppIcon.icns"
  if not iconPath.endsWith(".png"):
    echo "icon: unsupported format, skipping: " & iconPath
    return ""
  let iconset = cfg.projectDir / ".nimi" / "AppIcon.iconset"
  removeDir(iconset)
  createDir(iconset)
  let sizes = [16, 32, 64, 128, 256, 512]
  for sz in sizes:
    for scale in [1, 2]:
      let px = sz * scale
      let name =
        if scale == 1: "icon_" & $sz & "x" & $sz & ".png"
        else: "icon_" & $sz & "x" & $sz & "@2x.png"
      discard execCmdEx("sips -z " & $px & " " & $px & " " &
        quoteShell(iconPath) & " --out " & quoteShell(iconset / name))
  let icns = cfg.projectDir / ".nimi" / "AppIcon.icns"
  let (output, code) = execCmdEx("iconutil -c icns " & quoteShell(iconset) &
    " -o " & quoteShell(icns))
  if code != 0:
    echo "icon: iconutil failed: " & output.strip()
    return ""
  let dst = resourcesDir / "AppIcon.icns"
  copyFile(icns, dst)
  result = "AppIcon.icns"

proc signApp(cfg: Config, appPath: string) =
  let identity = cfg.signingIdentity
  var cmd = "codesign --force --deep --sign " & quoteShell(identity)
  if identity != "-":
    cmd.add " --options runtime --timestamp"
    if cfg.entitlements.len > 0:
      let ent = cfg.projectDir / cfg.entitlements
      if fileExists(ent):
        cmd.add " --entitlements " & quoteShell(ent)
      else:
        echo "warning: entitlements not found: " & ent
  cmd.add " " & quoteShell(appPath)
  discard runChecked(cmd)
  echo "Signed (" & identity & ")."

proc makeDmg(cfg: Config, appPath, outRoot: string): string =
  let dmg = outRoot / (cfg.slug & "-" & cfg.version & ".dmg")
  if fileExists(dmg):
    removeFile(dmg)
  discard runChecked("hdiutil create -volname " & quoteShell(cfg.dmgTitle) &
    " -srcfolder " & quoteShell(appPath) & " -ov -format UDZO " & quoteShell(dmg))
  if cfg.signingIdentity != "-":
    discard runChecked("codesign --force --sign " & quoteShell(cfg.signingIdentity) &
      " " & quoteShell(dmg))
  result = dmg

proc runBuild(dir: string) =
  let cfg = loadConfig(dir)
  let mainPath = cfg.projectDir / cfg.main
  if not fileExists(mainPath):
    raise fail("main not found: " & mainPath)
  let outRoot = cfg.projectDir / cfg.outDir / "darwin-arm64"
  let appPath = outRoot / (cfg.name & ".app")
  let macosDir = appPath / "Contents" / "MacOS"
  let resourcesDir = appPath / "Contents" / "Resources"
  createDir(macosDir)
  createDir(resourcesDir)
  for res in cfg.resources:
    let src = cfg.projectDir / res
    let dst = resourcesDir / lastPathPart(src)
    if dirExists(src):
      if dirExists(dst):
        removeDir(dst)
      copyDir(src, dst)
    elif fileExists(src):
      copyFile(src, dst)

  echo "Building " & cfg.name & "…"
  let exe = macosDir / cfg.name
  discard runChecked("nim c -d:release --hints:off --mm:atomicArc --threads:on " &
    "--path:" & quoteShell(libraryPath()) & " --out:" & quoteShell(exe) & " " &
    quoteShell(mainPath))

  let iconFile = makeIcns(cfg, resourcesDir)
  var plist = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>""" & cfg.name & """</string>
  <key>CFBundleDisplayName</key><string>""" & cfg.name & """</string>
  <key>CFBundleIdentifier</key><string>""" & cfg.identifier & """</string>
  <key>CFBundleExecutable</key><string>""" & cfg.name & """</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>""" & cfg.version & """</string>
  <key>CFBundleVersion</key><string>""" & cfg.version & """</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
"""
  if iconFile.len > 0:
    plist = plist.replace("</dict>\n</plist>",
      "  <key>CFBundleIconFile</key><string>" & iconFile & "</string>\n</dict>\n</plist>")
  if cfg.urlSchemes.len > 0:
    var urlTypes = "  <key>CFBundleURLTypes</key>\n  <array>\n    <dict>\n" &
      "      <key>CFBundleURLName</key><string>" & cfg.identifier &
      "</string>\n      <key>CFBundleURLSchemes</key>\n      <array>\n"
    for scheme in cfg.urlSchemes:
      urlTypes.add "        <string>" & scheme & "</string>\n"
    urlTypes.add "      </array>\n    </dict>\n  </array>\n"
    plist = plist.replace("</dict>\n</plist>", urlTypes & "</dict>\n</plist>")
  writeFile(appPath / "Contents" / "Info.plist", plist)
  writeFile(appPath / "Contents" / "PkgInfo", "APPL????")

  signApp(cfg, appPath)
  echo "Built " & appPath

  let dmg = makeDmg(cfg, appPath, outRoot)
  echo "Built " & dmg

  if cfg.notarize:
    if cfg.signingIdentity == "-" or cfg.keychainProfile.len == 0:
      echo "notarize: skipped (needs a real signingIdentity and macos.keychainProfile)"
    else:
      echo "Notarizing " & dmg & "…"
      discard runChecked("xcrun notarytool submit " & quoteShell(dmg) &
        " --keychain-profile " & quoteShell(cfg.keychainProfile) & " --wait")
      discard runChecked("xcrun stapler staple " & quoteShell(dmg))
      discard runChecked("xcrun stapler staple " & quoteShell(appPath))
      echo "Notarized and stapled."

proc sourceSignature(cfg: Config): string =
  var parts: seq[string]
  let projectDir = cfg.projectDir
  for path in walkDirRec(projectDir):
    if path.contains(DirSep & ".nimi" & DirSep) or
       path.contains(DirSep & "dist" & DirSep) or
       path.contains(DirSep & "node_modules" & DirSep):
      continue
    if path.endsWith(".nim") or path.endsWith(".nims"):
      let info = getFileInfo(path)
      parts.add path & ":" & $info.lastWriteTime.toUnix & ":" & $info.size
  for name in ["nimi.json", "nimi.nims"]:
    let p = projectDir / name
    if fileExists(p):
      let info = getFileInfo(p)
      parts.add p & ":" & $info.lastWriteTime.toUnix & ":" & $info.size
  parts.sort()
  result = parts.join("|")

proc buildDev(cfg: Config, exe: string) =
  discard runChecked("nim c --hints:off --path:" & quoteShell(libraryPath()) &
    " --out:" & quoteShell(exe) & " " &
    quoteShell(cfg.projectDir / cfg.main))

var devProcess: Process
var devStopping = false

proc stopDev() {.noconv.} =
  devStopping = true
  if devProcess != nil:
    try:
      if running(devProcess):
        terminate(devProcess)
        discard waitForExit(devProcess)
    except CatchableError:
      discard

proc runDev(dir: string) =
  let cfg = loadConfig(dir)
  let mainPath = cfg.projectDir / cfg.main
  if not fileExists(mainPath):
    raise fail("main not found: " & mainPath)
  let cacheDir = cfg.projectDir / ".nimi"
  createDir(cacheDir)
  let exe = cacheDir / (cfg.slug & "-dev")

  echo "Building " & cfg.main & "…"
  buildDev(cfg, exe)
  var signature = sourceSignature(cfg)
  echo "Running " & exe & " (watching src/ and nimi.json; Ctrl+C to stop)"
  devProcess = startProcess(exe, options = {poParentStreams})
  setControlCHook(stopDev)
  try:
    while not devStopping:
      let code = peekExitCode(devProcess)
      if code != -1:
        let finalCode = waitForExit(devProcess)
        close(devProcess)
        devProcess = nil
        if finalCode != 0:
          raise fail("app exited with " & $finalCode)
        return
      sleep(400)
      let nextSignature = sourceSignature(cfg)
      if nextSignature != signature:
        signature = nextSignature
        echo "Change detected; rebuilding…"
        if running(devProcess):
          terminate(devProcess)
          discard waitForExit(devProcess)
        close(devProcess)
        buildDev(cfg, exe)
        echo "Restarting…"
        devProcess = startProcess(exe, options = {poParentStreams})
  finally:
    if devProcess != nil:
      try:
        if running(devProcess):
          terminate(devProcess)
          discard waitForExit(devProcess)
        close(devProcess)
      except CatchableError:
        discard

proc runDoctor() =
  echo "nimi " & Version
  for cmd in ["nim --version", "clang --version", "xcrun --show-sdk-version"]:
    let (output, code) = execCmdEx(cmd)
    if code == 0:
      echo "\n$ " & cmd & "\n" & output.splitLines()[0]
    else:
      echo "\n$ " & cmd & "\n  not available"

proc runInit(dir: string, native: bool) =
  let root = absolutePath(dir)
  var nonEmpty = false
  if dirExists(root):
    for _ in walkDir(root):
      nonEmpty = true
      break
  if nonEmpty:
    raise fail("directory is not empty: " & root)
  createDir(root / "src")
  createDir(root / "resources")
  let name = "My App"
  writeFile(root / "nimi.json", """{
  "name": """" & name & """",
  "slug": "my-app",
  "identifier": "com.example.my-app",
  "version": "0.1.0",
  "main": "src/main.nim",
  "bindings": "frontend/nimi.ts"
}
""")
  if native:
    writeFile(root / "src" / "main.nim", """import nimi

app.whenReady(proc() =
  discard newWindow(WindowOptions(
    title: "My App",
    width: 480,
    height: 320,
    html: "<h1>Hello from Nimi</h1>"
  ))
)
app.run()
""")
  else:
    writeFile(root / "src" / "main.nim", """import nimi

type
  Greeter = ref object

proc greet(self: Greeter, name: string): string =
  "Hello " & name & "!"

let greeter = Greeter()
bindService(greeter, greet)

const page = "<!doctype html><html><body><h1>Hello Nimi</h1><p id='out'>...</p><script>window.nimi.call('Greeter.greet', 'world').then(function(t){document.getElementById('out').textContent=t})</script></body></html>"

app.whenReady(proc() =
  discard newWindow(WindowOptions(html: page))
)
app.run()
""")
  echo "Created " & root
  echo "Next: nimi dev " & dir

proc main() =
  let args = commandLineParams()
  if args.len == 0 or args[0] in ["help", "--help", "-h"]:
    echo HelpText
    return
  let cmd = args[0]
  let dir = if args.len > 1 and not args[1].startsWith("-"): args[1] else: "."
  try:
    case cmd
    of "version", "--version", "-v":
      echo "nimi " & Version
    of "doctor":
      runDoctor()
    of "generate", "gen":
      runGenerate(dir)
    of "build":
      runBuild(dir)
    of "dev":
      runDev(dir)
    of "init":
      runInit(dir, "--native" in args)
    else:
      echo "unknown command: " & cmd
      echo HelpText
      quit(2)
  except CatchableError as e:
    stderr.writeLine("nimi: " & e.msg)
    quit(1)

when isMainModule:
  main()
