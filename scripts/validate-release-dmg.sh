#!/usr/bin/env bash

set -euo pipefail

DMG_PATH="${1:?usage: validate-release-dmg.sh DMG_PATH EXPECTED_VERSION}"
EXPECTED_VERSION="${2:?usage: validate-release-dmg.sh DMG_PATH EXPECTED_VERSION}"

if [[ ! -f "${DMG_PATH}" ]]; then
  echo "Missing DMG: ${DMG_PATH}" >&2
  exit 1
fi
if [[ ! "${EXPECTED_VERSION}" =~ ^[0-9A-Za-z.+-]+$ ]]; then
  echo "Invalid release version: ${EXPECTED_VERSION}" >&2
  exit 1
fi

WORKSPACE="$(mktemp -d "${RUNNER_TEMP:-/tmp}/okra-release-dmg.XXXXXX")"
MOUNT_PATH="${WORKSPACE}/mount"
COPIED_DMG="${WORKSPACE}/Okra.dmg"
STATUS_OUTPUT="${WORKSPACE}/status.json"
MOUNTED=false

find_app_pids() {
  pgrep -x Okra 2>/dev/null || true
}

cleanup() {
  local pid
  while IFS= read -r pid; do
    if [[ -n "${pid}" ]]; then
      kill -9 "${pid}" 2>/dev/null || true
    fi
  done < <(find_app_pids)

  if [[ "${MOUNTED}" == "true" ]]; then
    hdiutil detach -force "${MOUNT_PATH}" >/dev/null 2>&1 || true
  fi
  rm -rf "${WORKSPACE}"
}
trap cleanup EXIT

run_with_timeout() {
  local timeout_seconds="$1"
  shift
  local command_pid
  local deadline

  "$@" &
  command_pid=$!
  deadline=$((SECONDS + timeout_seconds))

  while kill -0 "${command_pid}" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
      kill "${command_pid}" 2>/dev/null || true
      wait "${command_pid}" 2>/dev/null || true
      return 124
    fi
    sleep 1
  done
  wait "${command_pid}"
}

ditto "${DMG_PATH}" "${COPIED_DMG}"
xattr -w \
  com.apple.quarantine \
  "0083;6696e1a0;Safari;D1A3A2E0-7D6E-4FE5-A8A4-2E9D2F2CFA01" \
  "${COPIED_DMG}"

# A headless runner cannot acknowledge macOS's first-open confirmation UI.
# Prove Gatekeeper accepts the Internet-quarantined disk image, then remove
# only that download metadata before exercising the exact packaged app/CLI
# pair unattended. The signed and notarized disk-image bytes are unchanged.
spctl --assess \
  --type open \
  --context context:primary-signature \
  --verbose=4 \
  "${COPIED_DMG}"
xattr -d com.apple.quarantine "${COPIED_DMG}"

mkdir -p "${MOUNT_PATH}"
hdiutil attach \
  "${COPIED_DMG}" \
  -nobrowse \
  -readonly \
  -mountpoint "${MOUNT_PATH}" >/dev/null
MOUNTED=true

MOUNTED_APP="${MOUNT_PATH}/Okra.app"
MOUNTED_CLI="${MOUNTED_APP}/Contents/Resources/okra"
[[ -d "${MOUNTED_APP}" ]]
[[ -x "${MOUNTED_APP}/Contents/MacOS/Okra" ]]
[[ -x "${MOUNTED_CLI}" ]]
[[ -L "${MOUNT_PATH}/Applications" ]]
[[ "$(readlink "${MOUNT_PATH}/Applications")" == "/Applications" ]]
[[ -s "${MOUNT_PATH}/.DS_Store" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${MOUNTED_APP}/Contents/Info.plist")" == "com.okrapdf.desktop" ]]

if [[ -n "$(find_app_pids)" ]]; then
  echo "A pre-existing Okra process would invalidate the clean packaged CLI smoke" >&2
  exit 1
fi

if ! run_with_timeout 45 \
  env \
    "OKRA_APP_PATH=${MOUNTED_APP}" \
    "${MOUNTED_CLI}" status >"${STATUS_OUTPUT}" 2>&1; then
  cat "${STATUS_OUTPUT}" >&2
  echo "Final packaged CLI did not reach the packaged app within 45 seconds" >&2
  exit 1
fi

cat "${STATUS_OUTPUT}"
python3 - "${STATUS_OUTPUT}" "${EXPECTED_VERSION}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as status_file:
    payload = json.load(status_file)

if payload.get("healthy") is not True:
    raise SystemExit("CLI status did not report a healthy app")
if payload.get("version") != sys.argv[2]:
    raise SystemExit(
        f"CLI status version {payload.get('version')!r} did not match {sys.argv[2]!r}"
    )
PY

APP_PID="$(find_app_pids | head -n 1)"
if [[ -z "${APP_PID}" ]] || ! kill -0 "${APP_PID}" 2>/dev/null; then
  echo "Packaged app was not alive after the CLI status request" >&2
  exit 1
fi

kill -9 "${APP_PID}"
for _ in {1..50}; do
  if ! kill -0 "${APP_PID}" 2>/dev/null; then
    exit 0
  fi
  sleep 0.1
done

echo "Packaged app process survived forced cleanup" >&2
exit 1
