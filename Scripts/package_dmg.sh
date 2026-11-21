#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="/Applications/AgentGauge.app"
OUT_DIR="${ROOT_DIR}/Website/downloads"
DMG_NAME="AgentGauge-v1.2.1-macOS.dmg"
DMG_PATH="${OUT_DIR}/${DMG_NAME}"
VOL_NAME="AgentGauge v1.2.1"

if [ ! -d "${APP_PATH}" ]; then
  echo "Error: ${APP_PATH} not found. Run Scripts/build_app.sh first." >&2
  exit 1
fi

SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || true)
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || true)
echo "Packaging ${APP_PATH} (version=${SHORT_VERSION}, build=${BUILD_VERSION})..."

codesign --verify --deep --strict "${APP_PATH}"

STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agentgauge-dmg-stage.XXXXXX")"
cleanup() {
  rm -rf "${STAGE_DIR}"
}
trap cleanup EXIT

cp -R "${APP_PATH}" "${STAGE_DIR}/AgentGauge.app"
ln -s /Applications "${STAGE_DIR}/Applications"

mkdir -p "${OUT_DIR}"
hdiutil detach "/Volumes/${VOL_NAME}" -force >/dev/null 2>&1 || true
rm -f "${DMG_PATH}" "${OUT_DIR}/AgentGauge-v1.1.0-macOS.dmg" "${OUT_DIR}/AgentGauge-v1.2.0-macOS.dmg"

hdiutil create \
  -volname "${VOL_NAME}" \
  -srcfolder "${STAGE_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

hdiutil verify "${DMG_PATH}"
ls -lh "${DMG_PATH}"
