#!/usr/bin/env bash

set -euo pipefail

SOURCE_APP="${1:?usage: prepare-release-smoke-app.sh SOURCE_APP DESTINATION_APP BUNDLE_ID SIGNING_IDENTITY}"
DESTINATION_APP="${2:?usage: prepare-release-smoke-app.sh SOURCE_APP DESTINATION_APP BUNDLE_ID SIGNING_IDENTITY}"
BUNDLE_ID="${3:?usage: prepare-release-smoke-app.sh SOURCE_APP DESTINATION_APP BUNDLE_ID SIGNING_IDENTITY}"
SIGNING_IDENTITY="${4:?usage: prepare-release-smoke-app.sh SOURCE_APP DESTINATION_APP BUNDLE_ID SIGNING_IDENTITY}"

if [[ ! -d "${SOURCE_APP}" ]]; then
  echo "Missing source app: ${SOURCE_APP}" >&2
  exit 1
fi
if [[ -e "${DESTINATION_APP}" ]]; then
  echo "Destination already exists: ${DESTINATION_APP}" >&2
  exit 1
fi
if [[ ! "${BUNDLE_ID}" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "Invalid bundle identifier: ${BUNDLE_ID}" >&2
  exit 1
fi

ditto "${SOURCE_APP}" "${DESTINATION_APP}"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleIdentifier ${BUNDLE_ID}" \
  "${DESTINATION_APP}/Contents/Info.plist"

SPARKLE_FW="${DESTINATION_APP}/Contents/Frameworks/Sparkle.framework"
if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
  SIGN_ARGUMENTS=(--force --sign -)
else
  SIGN_ARGUMENTS=(
    --force
    --options runtime
    --timestamp
    --sign "${SIGNING_IDENTITY}"
  )
fi

sign_component() {
  local component="$1"
  shift
  if [[ -e "${component}" ]]; then
    codesign "${SIGN_ARGUMENTS[@]}" "$@" "${component}"
  fi
}

sign_component \
  "${SPARKLE_FW}/Versions/Current/XPCServices/Downloader.xpc" \
  --preserve-metadata=entitlements
for component in \
  "${SPARKLE_FW}/Versions/Current/XPCServices/Installer.xpc" \
  "${SPARKLE_FW}/Versions/Current/Autoupdate" \
  "${SPARKLE_FW}/Versions/Current/Updater.app" \
  "${SPARKLE_FW}"; do
  sign_component "${component}"
done
sign_component "${DESTINATION_APP}/Contents/Resources/okra"
codesign \
  "${SIGN_ARGUMENTS[@]}" \
  --entitlements okraPDF.entitlements \
  "${DESTINATION_APP}"

codesign --verify --strict --deep "${DESTINATION_APP}"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${DESTINATION_APP}/Contents/Info.plist")" == "${BUNDLE_ID}" ]]
