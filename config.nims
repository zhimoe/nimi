# M1 defaults. The memory manager is revisited at the end of M1 with a real
# IPC benchmark; see docs/00-feasibility.md §5.4.
--mm:atomicArc
--threads:on
--path:"src"

# macOS 27 SDK compatibility fallback.
#
# The macOS 27.2 SDK .tbd files describe arm64e.x1-macos, which the ld shipped
# with older Xcode versions does not understand. Prefer a newer Command Line
# Tools toolchain when one is installed; otherwise, when the active SDK is 27+
# and a 26.x SDK exists, compile and link against that SDK. Set NIMI_MACOS_SDK
# to an explicit path to override, or to `off` to disable the SDK fallback.
import std/[os, strutils]

proc sdkMajor(path: string): int =
  let name = path.extractFilename
  if not name.startsWith("MacOSX") or not name.endsWith(".sdk"):
    return 0
  let version = name[6 ..< name.len - 4]
  let dot = version.find('.')
  let major = if dot > 0: version[0 ..< dot] else: version
  try:
    result = parseInt(major)
  except ValueError:
    result = 0

proc resolvedSdk(path: string): string =
  let (target, code) = gorgeEx("readlink " & quoteShell(path))
  if code == 0 and target.strip.len > 0: target.strip else: path

proc compatibleMacSdk(): string =
  let override = getEnv("NIMI_MACOS_SDK")
  if override == "off":
    return ""
  if override.len > 0:
    return override
  let (activeRaw, activeCode) = gorgeEx("xcrun --show-sdk-path")
  if activeCode != 0:
    return ""
  let active = resolvedSdk(activeRaw.strip)
  if sdkMajor(active) < 27:
    return ""

  var best = ""
  var bestMajor = 0
  for directory in [
      "/Library/Developer/CommandLineTools/SDKs",
      "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs",
      "/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs"]:
    if not dirExists(directory):
      continue
    for kind, path in walkDir(directory):
      if kind notin {pcDir, pcLinkToDir} or not dirExists(path):
        continue
      let major = sdkMajor(path)
      if major > 0 and major < 27 and major > bestMajor:
        best = path
        bestMajor = major
  best

proc ldVersion(path: string): int =
  let (output, code) = gorgeEx(quoteShell(path) & " -v")
  if code != 0:
    return 0
  let marker = output.find("ld-")
  if marker < 0:
    return 0
  var index = marker + 3
  var digits = ""
  while index < output.len and output[index] in {'0'..'9'}:
    digits.add output[index]
    inc index
  try:
    result = parseInt(digits)
  except ValueError:
    result = 0

proc newerCltToolchain(): string =
  ## The Command Line Tools may be newer than the selected Xcode. Prefer the
  ## newer linker instead of forcing an older SDK.
  let clt = "/Library/Developer/CommandLineTools"
  if not dirExists(clt):
    return ""
  let (xcodeLd, code) = gorgeEx("xcrun -f ld")
  if code != 0:
    return ""
  if ldVersion(clt & "/usr/bin/ld") > ldVersion(xcodeLd.strip):
    clt
  else:
    ""

when hostOS == "macosx":
  var usingClt = false
  if getEnv("DEVELOPER_DIR").len == 0 and getEnv("NIMI_MACOS_SDK").len == 0:
    let clt = newerCltToolchain()
    when defined(nimiSdkDebug):
      echo "nimi sdk: clt=", clt, " xcodeLd=", gorgeEx("xcrun -f ld")[0].strip
    if clt.len > 0:
      putEnv("DEVELOPER_DIR", clt)
      usingClt = true
  elif getEnv("DEVELOPER_DIR") == "/Library/Developer/CommandLineTools" and
      getEnv("NIMI_MACOS_SDK").len == 0:
    # Nim evaluates config.nims again after putEnv; stay on the CLT toolchain.
    usingClt = true
  when defined(nimiSdkDebug):
    echo "nimi sdk: usingClt=", usingClt, " DEVELOPER_DIR=", getEnv("DEVELOPER_DIR")
  if not usingClt:
    let sdk = compatibleMacSdk()
    if sdk.len > 0:
      switch("passC", "-isysroot " & sdk)
      switch("passL", "-isysroot " & sdk)
