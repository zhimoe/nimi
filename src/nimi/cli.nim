## The `nimi` CLI: init, generate, dev, build (native + Zig Windows cross-build
## + portable + macOS dylib bundling + Inno Setup script), smoke, and doctor.

import std/[algorithm, dynlib, json, os, osproc, strtabs, strutils, tables, times]

const
  Version = "0.2.0"
  HelpText = """nimi — desktop apps in Nim

Usage:
  nimi init [dir] [--native]
  nimi generate [dir]
  nimi dev [dir]
  nimi build [dir] [--target:windows-amd64|windows-arm64] [--portable] [--installer]
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
    windowsIcon: string
    signingIdentity: string
    dmgTitle: string
    notarize: bool
    keychainProfile: string
    entitlements: string
    mm: string
    nimFlags: seq[string]
    beforeBuildCommand: string
    devCommand: string
    devUrl: string
    watchDirs: seq[string]
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

proc runChecked(cmd: string, workingDir: string = ""): string =
  let (output, code) = execCmdEx(cmd, workingDir = workingDir)
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

proc strSeqField(node: JsonNode, key: string): seq[string] =
  let arr = node{key}
  if arr != nil and arr.kind == JArray:
    for item in arr:
      if item.kind == JString and item.getStr.len > 0:
        result.add item.getStr

proc loadConfig*(dir: string): Config =
  result.projectDir = absolutePath(dir)
  let path = result.projectDir / "nimi.json"
  if not fileExists(path):
    raise fail("nimi.json not found in " & result.projectDir)
  let node = parseFile(path)
  proc strField(n: JsonNode, key, default: string): string =
    if n != nil and n.kind == JObject and n.hasKey(key) and n[key].kind == JString:
      n[key].getStr(default)
    else:
      default
  result.name = strField(node, "name", "Nimi")
  result.slug = strField(node, "slug", slugify(result.name))
  result.identifier = strField(node, "identifier", "com.example." & result.slug)
  result.version = strField(node, "version", "0.1.0")
  result.main = strField(node, "main", "src/main.nim")
  result.bindings = strField(node, "bindings", "frontend/nimi.ts")
  result.outDir = strField(node, "out", "dist")
  result.mm = strField(node, "mm", "")
  result.nimFlags = strSeqField(node, "nimFlags")
  result.beforeBuildCommand = strField(node, "beforeBuildCommand", "")
  result.devCommand = strField(node, "devCommand", "")
  result.devUrl = strField(node, "devUrl", "")
  result.watchDirs = strSeqField(node, "watchDirs")
  let macos = node{"macos"}
  result.icon = strField(node, "icon", "resources/icon.png")
  let windows = node{"windows"}
  result.windowsIcon = strField(windows, "icon", result.icon)
  result.signingIdentity = strField(macos, "signingIdentity", "-")
  result.dmgTitle = strField(macos, "dmgTitle", result.name)
  result.notarize = macos != nil and macos.kind == JObject and
    macos.hasKey("notarize") and macos["notarize"].getBool(false)
  result.keychainProfile = strField(macos, "keychainProfile", "")
  result.entitlements = strField(macos, "entitlements", "")
  result.resources = strSeqField(node, "resources")
  result.urlSchemes = strSeqField(node, "urlSchemes")

proc nimCompilerFlags(cfg: Config, release: bool): string =
  var flags: seq[string]
  if release:
    flags.add "-d:release"
  flags.add "--hints:off"
  flags.add "--threads:on"
  # Respect explicit `mm` in nimi.json or project `config.nims` if it sets `--mm:`.
  var projectSetsMm = false
  let nimsPath = cfg.projectDir / "config.nims"
  if fileExists(nimsPath):
    try:
      let body = readFile(nimsPath)
      if "--mm:" in body:
        projectSetsMm = true
    except CatchableError:
      discard
  if cfg.mm.len > 0:
    flags.add "--mm:" & cfg.mm
  elif not projectSetsMm:
    flags.add "--mm:atomicArc"
  for extra in cfg.nimFlags:
    flags.add quoteShell(extra)
  flags.add "--path:" & quoteShell(libraryPath())
  flags.join(" ")

const runtimeTemplate* = """export interface StreamOptions<TChunk = unknown> {
  args?: unknown[];
  onChunk?: (chunk: TChunk) => void;
  signal?: AbortSignal;
}

export interface NimiBridge {
  call(method: string, ...args: unknown[]): Promise<unknown>;
  stream(method: string, options?: StreamOptions): Promise<unknown>;
  cancel(id: number): void;
  reportError(message: string): void;
  on(name: string, fn: (payload: unknown) => void): () => void;
}

declare global {
  interface Window {
    nimi: NimiBridge;
    mygo?: NimiBridge;
  }
}

export function call<T>(method: string, ...args: unknown[]): Promise<T> {
  return window.nimi.call(method, ...args) as Promise<T>;
}

export function stream<TResult = unknown, TChunk = unknown>(
  method: string,
  options?: StreamOptions<TChunk>,
): Promise<TResult> {
  return window.nimi.stream(method, options as StreamOptions) as Promise<TResult>;
}

export function on<TPayload = unknown>(
  name: string,
  fn: (payload: TPayload) => void,
): () => void {
  return window.nimi.on(name, fn as (payload: unknown) => void);
}
"""

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
  discard runChecked("nim c " & nimCompilerFlags(cfg, release = false) &
    " -d:nimiGenerate --out:" & quoteShell(exe) & " " & quoteShell(mainPath),
    workingDir = cfg.projectDir)

  let (output, code) = execCmdEx(
    quoteShell(exe),
    workingDir = cfg.projectDir,
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

  let stub = parentDir(bindingsPath) / "nimi-runtime.ts"
  if not fileExists(stub):
    writeFile(stub, runtimeTemplate)
  echo "Generated " & bindingsPath

proc runBeforeBuild(cfg: Config) =
  if cfg.beforeBuildCommand.len > 0:
    echo "Running beforeBuildCommand: " & cfg.beforeBuildCommand
    discard runChecked(cfg.beforeBuildCommand, workingDir = cfg.projectDir)

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

proc otoolNonSystemDeps(binaryPath: string): seq[string] =
  let (outText, code) = execCmdEx("otool -L " & quoteShell(binaryPath))
  if code != 0:
    return @[]
  let lines = outText.splitLines()
  for i in 1 ..< lines.len:
    let trimmed = lines[i].strip()
    if trimmed.len == 0:
      continue
    let dep = trimmed.split(' ')[0]
    if dep.len == 0 or
        dep.startsWith("/System/") or
        dep.startsWith("/usr/lib/") or
        dep.startsWith("@executable_path/") or
        dep.startsWith("@loader_path/") or
        dep.startsWith("@rpath/"):
      continue
    if fileExists(dep):
      result.add dep

proc bundleMacosDylibs*(exePath, frameworksDir: string): seq[string] =
  ## Recursively copy non-system Homebrew / local `.dylib` dependencies into
  ## `Contents/Frameworks` and rewrite install names so `.app` is self-contained.
  var queue = @[exePath]
  var visited: seq[string]
  var bundledByBase = initOrderedTable[string, string]()
  while queue.len > 0:
    let current = queue[0]
    queue.delete(0)
    if current in visited:
      continue
    visited.add current
    let deps = otoolNonSystemDeps(current)
    for dep in deps:
      createDir(frameworksDir)
      let base = lastPathPart(dep)
      let dest = frameworksDir / base
      if not bundledByBase.hasKey(base):
        copyFile(dep, dest)
        setFilePermissions(dest, {fpUserRead, fpUserWrite, fpUserExec,
                                  fpGroupRead, fpGroupExec,
                                  fpOthersRead, fpOthersExec})
        discard runChecked("install_name_tool -id " &
          quoteShell("@executable_path/../Frameworks/" & base) & " " &
          quoteShell(dest))
        bundledByBase[base] = dest
        queue.add dest
        result.add dest
      discard runChecked("install_name_tool -change " & quoteShell(dep) & " " &
        quoteShell("@executable_path/../Frameworks/" & base) & " " &
        quoteShell(current))

proc signApp(cfg: Config, appPath: string, dylibs: openArray[string] = []) =
  let identity = cfg.signingIdentity
  var commonFlags = "--force --sign " & quoteShell(identity)
  if identity != "-":
    commonFlags.add " --options runtime --timestamp"
  # Sign embedded dylibs inside-out before signing the outer bundle.
  for lib in dylibs:
    if fileExists(lib):
      discard runChecked("codesign " & commonFlags & " " & quoteShell(lib))
  var appCmd = "codesign " & commonFlags
  if identity != "-" and cfg.entitlements.len > 0:
    let ent = cfg.projectDir / cfg.entitlements
    if fileExists(ent):
      appCmd.add " --entitlements " & quoteShell(ent)
    else:
      echo "warning: entitlements not found: " & ent
  appCmd.add " " & quoteShell(appPath)
  discard runChecked(appCmd)
  echo "Signed (" & identity & ")."

proc makeDmg(cfg: Config, appPath, outRoot: string): string =
  let dmg = outRoot / (cfg.slug & "-" & cfg.version & ".dmg")
  if fileExists(dmg):
    removeFile(dmg)
  let staging = cfg.projectDir / ".nimi" / "dmg-staging"
  if dirExists(staging):
    removeDir(staging)
  createDir(staging)
  try:
    copyDir(appPath, staging / lastPathPart(appPath))
    try:
      createSymlink("/Applications", staging / "Applications")
    except CatchableError:
      discard
    let createCmd = "hdiutil create -volname " & quoteShell(cfg.dmgTitle) &
      " -srcfolder " & quoteShell(staging) & " -ov -format UDZO " & quoteShell(dmg)
    for attempt in 0 .. 2:
      let (outText, code) = execCmdEx(createCmd)
      if code == 0:
        break
      if attempt == 2:
        stderr.write(outText)
        raise fail("command failed (" & $code & "): " & createCmd)
      sleep(1000 * (attempt + 1))
  finally:
    try: removeDir(staging) except CatchableError: discard
  if cfg.signingIdentity != "-":
    discard runChecked("codesign --force --sign " & quoteShell(cfg.signingIdentity) &
      " " & quoteShell(dmg))
  result = dmg

proc copyResources(cfg: Config, dstDir: string) =
  for res in cfg.resources:
    let src = if isAbsolute(res): res else: cfg.projectDir / res
    let dst = dstDir / lastPathPart(src)
    if dirExists(src):
      if dirExists(dst):
        removeDir(dst)
      copyDir(src, dst)
    elif fileExists(src):
      copyFile(src, dst)

proc appendU16Le(s: var string, value: int) =
  s.add char(value and 0xff)
  s.add char((value shr 8) and 0xff)

proc appendU32Le(s: var string, value: int) =
  s.add char(value and 0xff)
  s.add char((value shr 8) and 0xff)
  s.add char((value shr 16) and 0xff)
  s.add char((value shr 24) and 0xff)

proc pngDimensions*(png: string): tuple[width, height: int] =
  const signature = "\x89PNG\r\n\x1a\n"
  if png.len < 24 or png[0 ..< 8] != signature or png[12 ..< 16] != "IHDR":
    return (0, 0)
  proc be(at: int): int =
    (ord(png[at]) shl 24) or (ord(png[at + 1]) shl 16) or
      (ord(png[at + 2]) shl 8) or ord(png[at + 3])
  (be(16), be(20))

proc pngToIco*(png: string): string =
  ## Wrap a PNG in a single-entry ICO. Windows Vista+ accepts PNG payloads;
  ## ICO directory dimensions are 0..255, where 0 means 256.
  let (width, height) = pngDimensions(png)
  if width <= 0 or height <= 0:
    raise fail("icon is not a PNG with a valid IHDR")
  if width > 256 or height > 256:
    raise fail("PNG icons must be at most 256x256; use an .ico for larger sizes")
  result = newStringOfCap(22 + png.len)
  result.appendU16Le(0)
  result.appendU16Le(1)
  result.appendU16Le(1)
  result.add char(if width == 256: 0 else: width)
  result.add char(if height == 256: 0 else: height)
  result.add '\0'
  result.add '\0'
  result.appendU16Le(1)
  result.appendU16Le(32)
  result.appendU32Le(png.len)
  result.appendU32Le(22)
  result.add png

proc xmlEscape(value: string): string =
  result = value.replace("&", "&amp;")
  result = result.replace("<", "&lt;")
  result = result.replace(">", "&gt;")
  result = result.replace("\"", "&quot;")

proc winVersion(version: string): string =
  var parts = version.strip.split('.')
  while parts.len < 4:
    parts.add "0"
  parts.setLen(4)
  for i in 0 ..< parts.len:
    var numeric = parts[i].len > 0
    for ch in parts[i]:
      if ch notin {'0'..'9'}:
        numeric = false
    if not numeric:
      parts[i] = "0"
  result = parts.join(".")

proc windowsManifest*(name, identifier, version: string): string =
  result = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity type="win32" name="__IDENTIFIER__" version="__VERSION__" processorArchitecture="*"/>
  <description>__NAME__</description>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
    </application>
  </compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
      <longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>
    </windowsSettings>
  </application>
</assembly>
"""
  result = result.replace("__IDENTIFIER__", xmlEscape(identifier))
  result = result.replace("__VERSION__", xmlEscape(winVersion(version)))
  result = result.replace("__NAME__", xmlEscape(name))

proc innoSetupScript*(name, slug, identifier, version: string): string =
  ## Generate an Inno Setup 6 `.iss` installer definition for Windows builds.
  let exeName = (if slug.len > 0: slug else: "app") & ".exe"
  result = """[Setup]
AppId={{""" & identifier & """}
AppName=""" & name & """
AppVersion=""" & version & """
DefaultDirName={localappdata}\Programs\""" & slug & """
DefaultGroupName=""" & name & """
PrivilegesRequired=lowest
OutputDir=installer
OutputBaseFilename=""" & slug & "-setup-" & version & """
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\""" & exeName & """

[Files]
Source: """" & exeName & """"; DestDir: "{app}"; Flags: ignoreversion
Source: "WebView2Loader.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "resources\*"; DestDir: "{app}\resources"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

[Icons]
Name: "{group}\""" & name & """"; Filename: "{app}\""" & exeName & """"
Name: "{group}\{cm:UninstallProgram,""" & name & """}"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\""" & exeName & """"; Flags: nowait postinstall skipifsilent
"""

proc quoteRc(path: string): string =
  "\"" & path.replace('\\', '/').replace("\"", "\\\"") & "\""

proc preparePngForIco(workDir, pngPath: string): string =
  let raw = readFile(pngPath)
  let (w, h) = pngDimensions(raw)
  if w > 256 or h > 256:
    let sips = findExe("sips")
    if sips.len > 0:
      let resized = workDir / "icon_256.png"
      let (_, code) = execCmdEx(quoteShell(sips) & " -z 256 256 " &
        quoteShell(pngPath) & " --out " & quoteShell(resized))
      if code == 0 and fileExists(resized):
        return readFile(resized)
  raw

proc buildWindowsResources(cfg: Config): string =
  let workDir = cfg.projectDir / ".nimi"
  createDir(workDir)
  let manifestPath = workDir / "app.manifest"
  writeFile(manifestPath, windowsManifest(cfg.name, cfg.identifier, cfg.version))
  var iconPath = ""
  let iconSource =
    if isAbsolute(cfg.windowsIcon): cfg.windowsIcon
    else: cfg.projectDir / cfg.windowsIcon
  if fileExists(iconSource):
    let lower = iconSource.toLowerAscii
    if lower.endsWith(".ico"):
      iconPath = iconSource
    elif lower.endsWith(".png"):
      try:
        let icoPath = workDir / "app.ico"
        writeFile(icoPath, pngToIco(preparePngForIco(workDir, iconSource)))
        iconPath = icoPath
      except CatchableError as e:
        echo "icon: " & e.msg & "; building without an icon"
    else:
      echo "icon: unsupported format, skipping: " & iconSource
  let windres = findExe("windres")
  if windres.len == 0:
    echo "resources: windres not found; building without icon/manifest"
    return ""
  let rcPath = workDir / "app.rc"
  var rc = ""
  if iconPath.len > 0:
    rc.add "1 ICON " & quoteRc(iconPath) & "\n"
  rc.add "1 24 " & quoteRc(manifestPath) & "\n"
  writeFile(rcPath, rc)
  let resPath = workDir / "app.res"
  discard runChecked(quoteShell(windres) & " -O coff -i " & quoteShell(rcPath) &
    " -o " & quoteShell(resPath))
  result = " --passL:" & quoteShell(resPath)

proc assembleWindowsExtras(cfg: Config, outRoot: string,
                           portable: bool, installer: bool) =
  if portable:
    writeFile(outRoot / (cfg.slug & ".portable"), "")
    echo "Enabled portable marker: " & (outRoot / (cfg.slug & ".portable"))
  if installer:
    let issPath = outRoot / (cfg.slug & ".iss")
    writeFile(issPath, innoSetupScript(cfg.name, cfg.slug, cfg.identifier, cfg.version))
    echo "Generated Inno Setup script: " & issPath
    let iscc = findExe("ISCC")
    if iscc.len > 0:
      discard runChecked(quoteShell(iscc) & " " & quoteShell(issPath), workingDir = outRoot)

proc runBuildWindowsCross(dir, arch: string, portable, installer: bool) =
  ## Cross-compile a Windows x64/arm64 package from macOS/Linux via `zig cc`.
  let zig = findExe("zig")
  if zig.len == 0:
    raise fail("zig is required to cross-compile Windows targets from non-Windows hosts")
  let cfg = loadConfig(dir)
  runBeforeBuild(cfg)
  let mainPath = cfg.projectDir / cfg.main
  if not fileExists(mainPath):
    raise fail("main not found: " & mainPath)
  let zigTarget = if arch == "arm64": "aarch64-windows-gnu" else: "x86_64-windows-gnu"
  let loaderArch = if arch == "arm64": "arm64" else: "x64"
  let outRoot = cfg.projectDir / cfg.outDir / ("windows-" & arch &
    (if portable: "-portable" else: ""))
  createDir(outRoot)
  let resourcesDir = outRoot / "resources"
  createDir(resourcesDir)
  copyResources(cfg, resourcesDir)
  let loader = libraryPath() / "nimi" / "platform" / "windows" / "webview2" /
    "sdk" / loaderArch / "WebView2Loader.dll"
  if fileExists(loader):
    copyFile(loader, outRoot / "WebView2Loader.dll")

  let workDir = cfg.projectDir / ".nimi" / ("zig-win-" & arch)
  createDir(workDir)
  let wrapper = workDir / "cc.sh"
  writeFile(wrapper, "#!/bin/sh\nexec zig cc -target " & zigTarget & " \"$@\"\n")
  setFilePermissions(wrapper, {fpUserRead, fpUserWrite, fpUserExec,
                               fpGroupRead, fpGroupExec, fpOthersRead, fpOthersExec})
  let exeName = if cfg.slug.len > 0: cfg.slug else: "app"
  let exe = outRoot / (exeName & ".exe")
  echo "Cross-building " & cfg.name & " (" & zigTarget & ")…"
  discard runChecked("nim c " & nimCompilerFlags(cfg, release = true) &
    " --os:windows --cpu:" & arch & " --cc:clang --app:gui" &
    " --passC:-Os --passL:-Wl,--subsystem,windows --passL:-s" &
    " --clang.exe:" & quoteShell(wrapper) &
    " --clang.linkerexe:" & quoteShell(wrapper) &
    " --nimcache:" & quoteShell(workDir / "nimcache") &
    " --out:" & quoteShell(exe) & " " & quoteShell(mainPath),
    workingDir = cfg.projectDir)
  assembleWindowsExtras(cfg, outRoot, portable, installer)
  echo "Built " & exe

proc runBuildWindows(dir: string, portable = false, installer = false) =
  let cfg = loadConfig(dir)
  runBeforeBuild(cfg)
  let mainPath = cfg.projectDir / cfg.main
  if not fileExists(mainPath):
    raise fail("main not found: " & mainPath)
  const arch =
    when defined(arm64): "arm64"
    else: "amd64"
  let outRoot = cfg.projectDir / cfg.outDir / ("windows-" & arch &
    (if portable: "-portable" else: ""))
  createDir(outRoot)
  let resourcesDir = outRoot / "resources"
  createDir(resourcesDir)
  copyResources(cfg, resourcesDir)
  let loader = libraryPath() / "nimi" / "platform" / "windows" / "webview2" /
    "sdk" / (if arch == "arm64": "arm64" else: "x64") / "WebView2Loader.dll"
  if fileExists(loader):
    copyFile(loader, outRoot / "WebView2Loader.dll")
  else:
    echo "warning: WebView2Loader.dll not found at " & loader
  let exeName = if cfg.slug.len > 0: cfg.slug else: "app"
  let exe = outRoot / (exeName & ".exe")
  let resources = buildWindowsResources(cfg)
  echo "Building " & cfg.name & "…"
  discard runChecked("nim c " & nimCompilerFlags(cfg, release = true) &
    " --passL:-Wl,--subsystem,windows" & resources &
    " --out:" & quoteShell(exe) & " " & quoteShell(mainPath),
    workingDir = cfg.projectDir)
  assembleWindowsExtras(cfg, outRoot, portable, installer)
  echo "Built " & exe

proc runBuildMacos(dir: string) =
  let cfg = loadConfig(dir)
  runBeforeBuild(cfg)
  let mainPath = cfg.projectDir / cfg.main
  if not fileExists(mainPath):
    raise fail("main not found: " & mainPath)
  const macArch =
    when defined(arm64): "arm64"
    elif defined(amd64): "amd64"
    else: "unknown"
  let outRoot = cfg.projectDir / cfg.outDir / ("darwin-" & macArch)
  let appPath = outRoot / (cfg.name & ".app")
  let macosDir = appPath / "Contents" / "MacOS"
  let resourcesDir = appPath / "Contents" / "Resources"
  let frameworksDir = appPath / "Contents" / "Frameworks"
  createDir(macosDir)
  createDir(resourcesDir)
  copyResources(cfg, resourcesDir)

  echo "Building " & cfg.name & "…"
  let exe = macosDir / cfg.name
  discard runChecked("nim c " & nimCompilerFlags(cfg, release = true) &
    " --out:" & quoteShell(exe) & " " & quoteShell(mainPath),
    workingDir = cfg.projectDir)

  let bundledDylibs = bundleMacosDylibs(exe, frameworksDir)
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

  signApp(cfg, appPath, bundledDylibs)
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

proc desktopEntry(cfg: Config, execPath, iconName: string): string =
  result = "[Desktop Entry]\nType=Application\n" &
    "Name=" & cfg.name & "\n" &
    "Comment=" & cfg.name & "\n" &
    "Exec=" & execPath & "\n" &
    "Terminal=false\n" &
    "Categories=Utility;\n"
  if iconName.len > 0:
    result.add "Icon=" & iconName & "\n"
  if cfg.urlSchemes.len > 0:
    var mime = ""
    for scheme in cfg.urlSchemes:
      if mime.len > 0:
        mime.add ";"
      mime.add "x-scheme-handler/" & scheme
    result.add "MimeType=" & mime & ";\n"

proc packageName(value: string): string =
  for ch in value.toLowerAscii:
    if ch in {'a'..'z', '0'..'9', '+', '-', '.'}:
      result.add ch
    else:
      result.add '-'

proc normalizePackageTree(root, executable: string) =
  setFilePermissions(root, {fpUserRead, fpUserWrite, fpUserExec,
                            fpGroupRead, fpGroupExec,
                            fpOthersRead, fpOthersExec})
  for path in walkDirRec(root, yieldFilter = {pcDir, pcFile}):
    if dirExists(path):
      setFilePermissions(path, {fpUserRead, fpUserWrite, fpUserExec,
                                fpGroupRead, fpGroupExec,
                                fpOthersRead, fpOthersExec})
    elif path == executable:
      setFilePermissions(path, {fpUserRead, fpUserWrite, fpUserExec,
                                fpGroupRead, fpGroupExec,
                                fpOthersRead, fpOthersExec})
    else:
      setFilePermissions(path, {fpUserRead, fpUserWrite,
                                fpGroupRead, fpOthersRead})

proc buildDeb(cfg: Config, outRoot, exeName: string, arch: string,
              iconSource: string): string =
  let dpkgDeb = findExe("dpkg-deb")
  if dpkgDeb.len == 0:
    echo "deb: dpkg-deb not found; skipping package"
    return ""
  let pkg = packageName(if cfg.slug.len > 0: cfg.slug else: cfg.name)
  if pkg.len == 0:
    echo "deb: empty package name; skipping package"
    return ""
  let stage = outRoot / ".deb-stage"
  if dirExists(stage):
    removeDir(stage)
  let appDir = stage / "opt" / exeName
  let binDir = stage / "usr" / "bin"
  let applicationsDir = stage / "usr" / "share" / "applications"
  let debianDir = stage / "DEBIAN"
  createDir(appDir)
  createDir(binDir)
  createDir(applicationsDir)
  createDir(debianDir)
  setFilePermissions(debianDir, {fpUserRead, fpUserWrite, fpUserExec,
                                 fpGroupRead, fpGroupExec,
                                 fpOthersRead, fpOthersExec})
  copyFile(outRoot / exeName, appDir / exeName)
  setFilePermissions(appDir / exeName, {fpUserRead, fpUserWrite, fpUserExec,
                                        fpGroupRead, fpGroupExec,
                                        fpOthersRead, fpOthersExec})
  let resources = outRoot / "resources"
  if dirExists(resources):
    copyDir(resources, appDir / "resources")
  var iconName = ""
  if fileExists(iconSource):
    iconName = packageName(pkg) & splitFile(iconSource).ext
    copyFile(iconSource, appDir / iconName)
    if splitFile(iconSource).ext.toLowerAscii == ".png":
      let iconDir = stage / "usr" / "share" / "icons" / "hicolor" /
        "256x256" / "apps"
      createDir(iconDir)
      copyFile(iconSource, iconDir / iconName)
  createSymlink("/opt/" & exeName & "/" & exeName, binDir / exeName)
  let desktopPath = applicationsDir / (pkg & ".desktop")
  let debExec = "/opt/" & exeName & "/" & exeName &
    (if cfg.urlSchemes.len > 0: " %u" else: "")
  writeFile(desktopPath, desktopEntry(cfg, debExec, iconName))
  setFilePermissions(desktopPath, {fpUserRead, fpUserWrite,
                                   fpGroupRead, fpOthersRead})
  let control = "Package: " & pkg & "\n" &
    "Version: " & cfg.version & "\n" &
    "Section: utils\n" &
    "Priority: optional\n" &
    "Architecture: " & arch & "\n" &
    "Maintainer: Nimi contributors <noreply@nimi.zhi.moe>\n" &
    "Depends: libgtk-3-0t64 | libgtk-3-0, libnotify4, libgstreamer1.0-0, " &
    "gstreamer1.0-plugins-base, gstreamer1.0-plugins-good, " &
    "libwebkit2gtk-4.1-0 | libwebkit2gtk-4.0-37\n" &
    "Recommends: gstreamer1.0-plugins-ugly, gstreamer1.0-libav\n" &
    "Description: " & cfg.name & "\n" &
    " A desktop application built with Nimi.\n"
  let controlPath = debianDir / "control"
  writeFile(controlPath, control)
  setFilePermissions(controlPath, {fpUserRead, fpUserWrite,
                                   fpGroupRead, fpOthersRead})
  normalizePackageTree(stage, appDir / exeName)
  let debPath = outRoot / (pkg & "_" & cfg.version & "_" & arch & ".deb")
  if fileExists(debPath):
    removeFile(debPath)
  try:
    discard runChecked(quoteShell(dpkgDeb) & " --root-owner-group --build " &
      quoteShell(stage) & " " & quoteShell(debPath))
  finally:
    removeDir(stage)
  result = debPath

proc runBuildLinux(dir: string) =
  let cfg = loadConfig(dir)
  runBeforeBuild(cfg)
  let mainPath = cfg.projectDir / cfg.main
  if not fileExists(mainPath):
    raise fail("main not found: " & mainPath)
  const arch =
    when defined(arm64): "arm64"
    else: "amd64"
  let outRoot = cfg.projectDir / cfg.outDir / ("linux-" & arch)
  createDir(outRoot)
  let resourcesDir = outRoot / "resources"
  createDir(resourcesDir)
  copyResources(cfg, resourcesDir)
  let iconSource =
    if isAbsolute(cfg.icon): cfg.icon
    else: cfg.projectDir / cfg.icon
  if fileExists(iconSource):
    copyFile(iconSource, outRoot / lastPathPart(iconSource))
  let exeName = if cfg.slug.len > 0: cfg.slug else: "app"
  let exe = outRoot / exeName
  echo "Building " & cfg.name & "…"
  discard runChecked("nim c " & nimCompilerFlags(cfg, release = true) &
    " --out:" & quoteShell(exe) & " " & quoteShell(mainPath),
    workingDir = cfg.projectDir)

  var iconName = ""
  if fileExists(iconSource):
    iconName = lastPathPart(iconSource)
  let execArg = if cfg.urlSchemes.len > 0: exeName & " %u" else: exeName
  writeFile(outRoot / (exeName & ".desktop"),
    desktopEntry(cfg, execArg, iconName))
  echo "Built " & exe
  let deb = buildDeb(cfg, outRoot, exeName, arch, iconSource)
  if deb.len > 0:
    echo "Built " & deb

proc runBuild(dir: string, args: seq[string]) =
  var target = ""
  var portable = false
  var installer = false
  for arg in args:
    if arg.startsWith("--target:"):
      target = arg["--target:".len .. ^1]
    elif arg.startsWith("--target="):
      target = arg["--target=".len .. ^1]
    elif arg == "--portable":
      portable = true
    elif arg == "--installer":
      installer = true

  if target in ["windows", "windows-amd64", "windows-x64"]:
    when defined(windows):
      runBuildWindows(dir, portable, installer)
    else:
      runBuildWindowsCross(dir, "amd64", portable, installer)
    return
  elif target == "windows-arm64":
    when defined(windows):
      runBuildWindows(dir, portable, installer)
    else:
      runBuildWindowsCross(dir, "arm64", portable, installer)
    return

  when defined(windows):
    runBuildWindows(dir, portable, installer)
  elif defined(macosx):
    runBuildMacos(dir)
  elif defined(linux):
    runBuildLinux(dir)
  else:
    raise fail("nimi build does not support this platform")

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
  for name in ["nimi.json", "nimi.nims", "config.nims"]:
    let p = projectDir / name
    if fileExists(p):
      let info = getFileInfo(p)
      parts.add p & ":" & $info.lastWriteTime.toUnix & ":" & $info.size
  parts.sort()
  result = parts.join("|")

proc buildDev(cfg: Config, exe: string) =
  discard runChecked("nim c " & nimCompilerFlags(cfg, release = false) &
    " --out:" & quoteShell(exe) & " " &
    quoteShell(cfg.projectDir / cfg.main),
    workingDir = cfg.projectDir)

var devProcess: Process
var frontendProcess: Process
var devStopping = false

proc stopProcessSafe(p: var Process) =
  if p != nil:
    try:
      if running(p):
        terminate(p)
        discard waitForExit(p)
      close(p)
    except CatchableError:
      discard
    p = nil

proc stopDev() {.noconv.} =
  devStopping = true
  stopProcessSafe(devProcess)
  stopProcessSafe(frontendProcess)

proc spawnDevApp(cfg: Config, exe: string): Process =
  var env = newStringTable()
  for k, v in envPairs():
    env[k] = v
  env["NIMI_DEV"] = "1"
  if cfg.devUrl.len > 0:
    env["NIMI_DEV_URL"] = cfg.devUrl
  startProcess(exe, workingDir = cfg.projectDir, env = env,
               options = {poParentStreams})

proc runDev(dir: string) =
  let cfg = loadConfig(dir)
  let mainPath = cfg.projectDir / cfg.main
  if not fileExists(mainPath):
    raise fail("main not found: " & mainPath)
  let cacheDir = cfg.projectDir / ".nimi"
  createDir(cacheDir)
  let exe = cacheDir / (cfg.slug & "-dev")

  if cfg.devCommand.len > 0:
    echo "Starting frontend devCommand: " & cfg.devCommand
    when defined(windows):
      frontendProcess = startProcess("cmd", workingDir = cfg.projectDir,
        args = @["/c", cfg.devCommand], options = {poParentStreams, poUsePath})
    else:
      frontendProcess = startProcess("/bin/sh", workingDir = cfg.projectDir,
        args = @["-c", cfg.devCommand], options = {poParentStreams})

  echo "Building " & cfg.main & "…"
  buildDev(cfg, exe)
  var signature = sourceSignature(cfg)
  echo "Running " & exe & " (watching src/ and nimi.json; Ctrl+C to stop)"
  devProcess = spawnDevApp(cfg, exe)
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
        stopProcessSafe(devProcess)
        buildDev(cfg, exe)
        echo "Restarting…"
        devProcess = spawnDevApp(cfg, exe)
  finally:
    stopProcessSafe(devProcess)
    stopProcessSafe(frontendProcess)

proc haveLib(names: openArray[string]): bool =
  for name in names:
    if loadLib(name) != nil:
      return true

proc runDoctor() =
  echo "nimi " & Version
  when defined(linux):
    let commands = ["nim --version", "cc --version"]
  elif defined(windows):
    let commands = ["nim --version", "gcc --version"]
  else:
    let commands = ["nim --version", "clang --version",
                    "xcrun --show-sdk-version", "zig version"]
  for cmd in commands:
    let (output, code) = execCmdEx(cmd)
    if code == 0:
      echo "\n$ " & cmd & "\n" & output.splitLines()[0]
    else:
      echo "\n$ " & cmd & "\n  not available"
  when defined(linux):
    proc status(label: string, names: openArray[string]) =
      echo label & ": " & (if haveLib(names): "available" else: "missing")
    status("gtk3", ["libgtk-3.so.0", "libgtk-3.so"])
    status("webkitgtk", ["libwebkit2gtk-4.1.so.0", "libwebkit2gtk-4.0.so.37"])
    status("libnotify", ["libnotify.so.4", "libnotify.so"])
    status("gstreamer", ["libgstreamer-1.0.so.0", "libgstreamer-1.0.so"])
    status("x11", ["libX11.so.6", "libX11.so"])
    echo "display: " & (
      if getEnv("DISPLAY").len > 0: "X11 " & getEnv("DISPLAY")
      elif getEnv("WAYLAND_DISPLAY").len > 0: "Wayland " & getEnv("WAYLAND_DISPLAY")
      else: "missing (set DISPLAY/WAYLAND_DISPLAY or use xvfb-run)")

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
import nimi/ui

var count = 0

proc view(c: Context) =
  c.column().fill().padding(24, 24).gap(12).children(c, proc() =
    c.text("Hello from Nimi Native UI", size = 18, bold = true)
    c.button("Count: " & $count, proc() = inc count)
  )

app.whenReady(proc() =
  discard newWindow(WindowOptions(
    title: "My App",
    width: 480,
    height: 320,
    content: uiView(view)
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
      runBuild(dir, args[1 .. ^1])
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
