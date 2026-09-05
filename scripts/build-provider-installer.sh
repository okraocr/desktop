#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_CONTENTS="${1:?usage: build-provider-installer.sh APP_CONTENTS}"
SERVICE_ID=com.okrapdf.desktop.provider-installer
SERVICE_CONTENTS="${APP_CONTENTS}/XPCServices/${SERVICE_ID}.xpc/Contents"
mkdir -p "${SERVICE_CONTENTS}/MacOS" "${SERVICE_CONTENTS}/Resources"
swiftc -parse-as-library -O -target "$(uname -m)-apple-macosx13.0" \
  scripts/provider-installer/main.swift \
  OkraPDF/LocalProcessing/ProviderRuntimeXPCProtocol.swift \
  OkraPDF/LocalProcessing/TrustedPythonInterpreter.swift \
  OkraPDF/LocalProcessing/LocalCommandRunner.swift \
  OkraPDF/LocalProcessing/LocalCommandProcessBox.swift \
  OkraPDF/LocalProcessing/LocalProcessEnvironment.swift \
  OkraPDF/LocalProcessing/LocalExclusiveFileLock.swift \
  -o "${SERVICE_CONTENTS}/MacOS/ProviderInstaller"
cp -R OkraPDF/ProviderScripts "${SERVICE_CONTENTS}/Resources/"
cat > "${SERVICE_CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>${SERVICE_ID}</string>
  <key>CFBundleExecutable</key><string>ProviderInstaller</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>XPCService</key><dict><key>ServiceType</key><string>Application</string></dict>
</dict></plist>
PLIST
