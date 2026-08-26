#!/usr/bin/env bash

set -euo pipefail

DMG_PATH="${1:?usage: validate-release-dmg.sh DMG_PATH SMOKE_APP_PATH EXPECTED_BUNDLE_ID EXPECTED_VERSION}"
SOURCE_SMOKE_APP="${2:?usage: validate-release-dmg.sh DMG_PATH SMOKE_APP_PATH EXPECTED_BUNDLE_ID EXPECTED_VERSION}"
EXPECTED_BUNDLE_ID="${3:?usage: validate-release-dmg.sh DMG_PATH SMOKE_APP_PATH EXPECTED_BUNDLE_ID EXPECTED_VERSION}"
EXPECTED_VERSION="${4:?usage: validate-release-dmg.sh DMG_PATH SMOKE_APP_PATH EXPECTED_BUNDLE_ID EXPECTED_VERSION}"

if [[ ! -f "${DMG_PATH}" ]]; then
  echo "Missing DMG: ${DMG_PATH}" >&2
  exit 1
fi
if [[ ! -d "${SOURCE_SMOKE_APP}" ]]; then
  echo "Missing release smoke app: ${SOURCE_SMOKE_APP}" >&2
  exit 1
fi
if [[ ! "${EXPECTED_BUNDLE_ID}" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "Invalid bundle identifier: ${EXPECTED_BUNDLE_ID}" >&2
  exit 1
fi
if [[ ! "${EXPECTED_VERSION}" =~ ^[0-9A-Za-z.+-]+$ ]]; then
  echo "Invalid release version: ${EXPECTED_VERSION}" >&2
  exit 1
fi

WORKSPACE="$(mktemp -d "${RUNNER_TEMP:-/tmp}/okra-release-dmg.XXXXXX")"
MOUNT_PATH="${WORKSPACE}/mount"
COPIED_DMG="${WORKSPACE}/Okra.dmg"
SMOKE_APP="${WORKSPACE}/Okra Release Validation.app"
SMOKE_EXECUTABLE="${SMOKE_APP}/Contents/MacOS/Okra"
STATUS_OUTPUT="${WORKSPACE}/status.json"
MOUNTED=false

find_smoke_pids() {
  pgrep -f "${SMOKE_EXECUTABLE}" 2>/dev/null || true
}

cleanup() {
  local pid
  while IFS= read -r pid; do
    if [[ -n "${pid}" ]]; then
      kill -9 "${pid}" 2>/dev/null || true
    fi
  done < <(find_smoke_pids)

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

ditto "${SOURCE_SMOKE_APP}" "${SMOKE_APP}"
xattr -w \
  com.apple.quarantine \
  "0083;6696e1a0;Safari;D1A3A2E0-7D6E-4FE5-A8A4-2E9D2F2CFA01" \
  "${SMOKE_APP}"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${SMOKE_APP}/Contents/Info.plist")" == "${EXPECTED_BUNDLE_ID}" ]]

if ! run_with_timeout 45 \
  env \
    "CFFIXED_USER_HOME=${WORKSPACE}" \
    "HOME=${WORKSPACE}" \
    "OKRA_APP_PATH=${SMOKE_APP}" \
    "${MOUNTED_CLI}" status >"${STATUS_OUTPUT}" 2>&1; then
  cat "${STATUS_OUTPUT}" >&2
  echo "Final packaged CLI did not reach the quarantined app within 45 seconds" >&2
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

SMOKE_PID="$(find_smoke_pids | head -n 1)"
if [[ -z "${SMOKE_PID}" ]] || ! kill -0 "${SMOKE_PID}" 2>/dev/null; then
  echo "Release smoke app was not alive after the CLI status request" >&2
  exit 1
fi

kill -9 "${SMOKE_PID}"
for _ in {1..50}; do
  if ! kill -0 "${SMOKE_PID}" 2>/dev/null; then
    exit 0
  fi
  sleep 0.1
done

echo "Release smoke app process survived forced cleanup" >&2
exit 1
