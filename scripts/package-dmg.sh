#!/bin/bash
# Package Okra.app in an install-friendly, intentionally arranged disk image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYOUT_SCRIPT="${SCRIPT_DIR}/configure-dmg-layout.applescript"
VOLUME_NAME="Okra"
APP_NAME="Okra.app"
APPLICATIONS_LINK_NAME="Applications"

WORK_ROOT=""
MOUNT_DIR=""
IS_MOUNTED=false

stage_dmg_contents() {
  local app_path="$1"
  local staging_dir="$2"

  if [[ ! -d "${app_path}" ]]; then
    echo "Missing app bundle: ${app_path}" >&2
    return 1
  fi
  if [[ "$(basename "${app_path}")" != "${APP_NAME}" ]]; then
    echo "Expected an ${APP_NAME} bundle: ${app_path}" >&2
    return 1
  fi

  mkdir -p "${staging_dir}"
  /usr/bin/ditto "${app_path}" "${staging_dir}/${APP_NAME}"
  /bin/ln -s /Applications "${staging_dir}/${APPLICATIONS_LINK_NAME}"
}

cleanup() {
  if [[ "${IS_MOUNTED}" == true && -n "${MOUNT_DIR}" ]]; then
    /usr/bin/hdiutil detach -force "${MOUNT_DIR}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${WORK_ROOT}" && -d "${WORK_ROOT}" ]]; then
    /bin/rm -rf "${WORK_ROOT}"
  fi
}

package_dmg() {
  local app_path="$1"
  local output_path="$2"
  local staging_dir
  local read_write_dmg

  if [[ ! -f "${LAYOUT_SCRIPT}" ]]; then
    echo "Missing Finder layout script: ${LAYOUT_SCRIPT}" >&2
    return 1
  fi

  mkdir -p "$(dirname "${output_path}")"
  /bin/rm -f "${output_path}"

  WORK_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/private/tmp}/okra-dmg.XXXXXX")"
  staging_dir="${WORK_ROOT}/staging"
  read_write_dmg="${WORK_ROOT}/Okra-read-write.dmg"
  MOUNT_DIR="${WORK_ROOT}/mount"
  trap cleanup EXIT

  stage_dmg_contents "${app_path}" "${staging_dir}"

  /usr/bin/hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${staging_dir}" \
    -fs HFS+ \
    -ov \
    -format UDRW \
    "${read_write_dmg}" >/dev/null

  mkdir -p "${MOUNT_DIR}"
  /usr/bin/hdiutil attach \
    "${read_write_dmg}" \
    -nobrowse \
    -readwrite \
    -mountpoint "${MOUNT_DIR}" >/dev/null
  IS_MOUNTED=true

  /usr/bin/osascript \
    "${LAYOUT_SCRIPT}" \
    "${MOUNT_DIR}" \
    "${APP_NAME}" \
    "${APPLICATIONS_LINK_NAME}" >/dev/null

  if [[ ! -s "${MOUNT_DIR}/.DS_Store" ]]; then
    echo "Finder did not persist the DMG window layout" >&2
    return 1
  fi

  /bin/sync
  /usr/bin/hdiutil detach "${MOUNT_DIR}" >/dev/null
  IS_MOUNTED=false

  /usr/bin/hdiutil convert \
    "${read_write_dmg}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "${output_path}" >/dev/null
}

main() {
  if [[ "$#" -ne 2 ]]; then
    echo "usage: $0 /path/to/Okra.app /path/to/Okra-version.dmg" >&2
    exit 64
  fi

  package_dmg "$1" "$2"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
