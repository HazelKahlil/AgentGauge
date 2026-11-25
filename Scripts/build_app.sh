#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../VERSION
source "${ROOT_DIR}/VERSION"
APP_NAME="AgentGauge"
BUNDLE_ID="com.kahlil.AgentGauge"
INSTALL_DIR="/Applications"
APP_BUNDLE="${INSTALL_DIR}/${APP_NAME}.app"

cd "${ROOT_DIR}"
echo "Building ${APP_NAME} & AgentGaugeCleanup (release)..."
swift build -c release --product AgentGaugeApp
swift build -c release --product AgentGaugeCleanup

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="${BIN_DIR}/AgentGaugeApp"
CLEANUP_PATH="${BIN_DIR}/AgentGaugeCleanup"

if [ ! -f "${BIN_PATH}" ] || [ ! -f "${CLEANUP_PATH}" ]; then
  echo "Error: Build outputs missing in ${BIN_DIR}"
  exit 1
fi

pkill -f "/Applications/AgentGauge.app/Contents/MacOS/AgentGauge" || true
sleep 0.4
pkill -9 -f "/Applications/AgentGauge.app/Contents/MacOS/AgentGauge" || true
sleep 0.2

echo "Packaging ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${CLEANUP_PATH}" "${APP_BUNDLE}/Contents/MacOS/AgentGaugeCleanup"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/AgentGaugeCleanup"
if [ -f "${ROOT_DIR}/Resources/AppIcon.icns" ]; then
  cp "${ROOT_DIR}/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi
if [ -f "${ROOT_DIR}/Resources/AppIcon.svg" ]; then
  cp "${ROOT_DIR}/Resources/AppIcon.svg" "${APP_BUNDLE}/Contents/Resources/AppIcon.svg"
fi
if [ -d "${ROOT_DIR}/Resources/AgentIcons" ]; then
  cp -R "${ROOT_DIR}/Resources/AgentIcons" "${APP_BUNDLE}/Contents/Resources/AgentIcons"
fi

cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>AgentGauge</string>
    <key>CFBundleExecutable</key>
    <string>AgentGauge</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AgentGauge</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Prefer Apple Development cert so macOS TCC Accessibility permission persists across rebuilds
SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development:" | sed -E 's/.*"([^"]+)".*/\1/' || true)
if [ -n "${SIGN_ID}" ]; then
  echo "Signing with stable identity: ${SIGN_ID}"
  codesign --force --deep --sign "${SIGN_ID}" --identifier "${BUNDLE_ID}" "${APP_BUNDLE}"
else
  echo "No Apple Development identity found; using ad-hoc signature"
  codesign --force --deep --sign - --identifier "${BUNDLE_ID}" "${APP_BUNDLE}"
fi
touch "${APP_BUNDLE}"
codesign --verify --deep --strict "${APP_BUNDLE}"

echo "Installed and verified: ${APP_BUNDLE}"
