#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../VERSION
source "${ROOT_DIR}/VERSION"
APP_PATH="/Applications/AgentGauge.app"
OUT_DIR="${ROOT_DIR}/Website/downloads"
UPDATES_DIR="${ROOT_DIR}/Website/updates"

if [ ! -d "${APP_PATH}" ]; then
  echo "Error: ${APP_PATH} not found. Run Scripts/build_app.sh first." >&2
  exit 1
fi

SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "${VERSION}")
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "${BUILD}")
DMG_NAME="AgentGauge-v${SHORT_VERSION}-macOS.dmg"
DMG_PATH="${OUT_DIR}/${DMG_NAME}"
EVERGREEN_DMG_PATH="${OUT_DIR}/AgentGauge-macOS.dmg"
OTA_ZIP_PATH="${OUT_DIR}/AgentGauge-macOS.zip"
VOL_NAME="AgentGauge v${SHORT_VERSION}"

echo "Packaging ${APP_PATH} (version=${SHORT_VERSION}, build=${BUILD_VERSION})..."
codesign --verify --deep --strict "${APP_PATH}"

STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agentgauge-dmg-stage.XXXXXX")"
cleanup() {
  rm -rf "${STAGE_DIR}"
}
trap cleanup EXIT

cp -R "${APP_PATH}" "${STAGE_DIR}/AgentGauge.app"
ln -s /Applications "${STAGE_DIR}/Applications"

# One-click helper inside DMG so legacy v1.1.0–v1.2.1 users can cleanly quit old memory process & overwrite in 1 second
cat > "${STAGE_DIR}/双击一键覆盖旧版.command" <<'HELPER'
#!/usr/bin/env bash
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "正在关闭旧版 AgentGauge 进程并覆盖安装最新版本..."
pkill -f "/Applications/AgentGauge.app/Contents/MacOS/AgentGauge" 2>/dev/null || true
sleep 0.4
rm -rf "/Applications/AgentGauge.app"
cp -R "${SRC_DIR}/AgentGauge.app" "/Applications/AgentGauge.app"
/usr/bin/xattr -cr "/Applications/AgentGauge.app" 2>/dev/null || true
open -a "/Applications/AgentGauge.app"
echo "✅ 已成功升级并启动新版 AgentGauge！（后续版本均支持应用内一键远程推送更新）"
sleep 1.2
HELPER
chmod +x "${STAGE_DIR}/双击一键覆盖旧版.command"

mkdir -p "${OUT_DIR}" "${UPDATES_DIR}"
hdiutil detach "/Volumes/${VOL_NAME}" -force >/dev/null 2>&1 || true

# Remove stale versioned DMGs so repo/CDN stays lean while _redirects routes legacy filenames to AgentGauge-macOS.dmg
find "${OUT_DIR}" -maxdepth 1 -name "AgentGauge-v*-macOS.dmg" ! -name "${DMG_NAME}" -delete 2>/dev/null || true
rm -f "${DMG_PATH}" "${EVERGREEN_DMG_PATH}" "${OTA_ZIP_PATH}"

# 1. Build verified UDZO Installer DMG + Evergreen alias copy
hdiutil create \
  -volname "${VOL_NAME}" \
  -srcfolder "${STAGE_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

hdiutil verify "${DMG_PATH}"
cp -f "${DMG_PATH}" "${EVERGREEN_DMG_PATH}"

# 2. Build OTA Auto-Update Archive (.zip preserving macOS symlinks & code signature)
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${OTA_ZIP_PATH}"
ZIP_SHA256=$(shasum -a 256 "${OTA_ZIP_PATH}" | awk '{print $1}')

# 3. Cryptographically sign OTA Manifest (`Website/updates/latest.json`) with Ed25519 Private Key
RELEASE_TITLE="${RELEASE_TITLE:-v${SHORT_VERSION} · 全平台 3x/5x/20x 倍率引擎与零阻塞 Dock 悬停性能优化}"
SHORT_VERSION="${SHORT_VERSION}" \
BUILD_VERSION="${BUILD_VERSION}" \
ZIP_SHA256="${ZIP_SHA256}" \
RELEASE_TITLE="${RELEASE_TITLE}" \
MANIFEST_OUT="${UPDATES_DIR}/latest.json" \
swift - <<'SWIFT'
import CryptoKit
import Foundation

let env = ProcessInfo.processInfo.environment
let version = env["SHORT_VERSION"]!
let build = Int(env["BUILD_VERSION"]!)!
let sha256 = (env["ZIP_SHA256"] ?? "").lowercased()
let title = env["RELEASE_TITLE"] ?? "v\(version)"
let outPath = env["MANIFEST_OUT"]!

let home = FileManager.default.homeDirectoryForCurrentUser.path
let keyPath = "\(home)/.config/agentgauge/release_ed25519.key"
guard let keyB64 = try? String(contentsOfFile: keyPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
      let keyData = Data(base64Encoded: keyB64),
      let privKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else {
    fputs("Error: Missing Ed25519 signing key at \(keyPath)\n", stderr)
    exit(1)
}

let canonical = Data("AgentGauge-Update-v1|\(version)|\(build)|\(sha256)".utf8)
let sigData = try privKey.signature(for: canonical)
let sigB64 = sigData.base64EncodedString()

let iso = ISO8601DateFormatter()
let manifest: [String: Any] = [
    "version": version,
    "build": build,
    "publishedAt": iso.string(from: Date()),
    "urgency": "recommended",
    "title": title,
    "notes": [
        "全平台统一 3x / 5x / 20x 套餐倍率引擎：覆盖 Antigravity / Gemini AI Ultra、ChatGPT Pro (5x/20x)、Claude Max (5x/20x)、Cursor (Pro+ 3x / Ultra 20x) 与 SuperGrok Heavy (20x)，菜单栏套餐徽章支持一键切换并按「应用 + 邮箱」独立记忆",
        "消除 Dock 60Hz/30Hz 主线程高频同步 IPC（缓存 Dock 方位与 com.apple.dock.server Mach 端口、PID 零开销复用、发送超时压缩至 16ms），悬停滑行彻底零卡顿",
        "引入 Antigravity / Codex 活动感知本地缓存，闲置期后台 CLI 唤醒次数降低约 65%；同步修复 agy 1.5.16 异步 plan_tier 竞态与多变体应用 tick() 图标锁定"
    ],
    "zipUrl": "https://usage.komorebi.date/downloads/AgentGauge-macOS.zip",
    "fallbackZipUrl": "https://github.com/HazelKahlil/AgentGauge/releases/latest/download/AgentGauge-macOS.zip",
    "dmgUrl": "https://usage.komorebi.date/downloads/AgentGauge-macOS.dmg",
    "sha256": sha256,
    "signature": sigB64
]

let jsonData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try jsonData.write(to: URL(fileURLWithPath: outPath), options: .atomic)
print("Signed OTA manifest written to \(outPath) (sha256=\(sha256.prefix(16))...)")
SWIFT

ls -lh "${DMG_PATH}" "${EVERGREEN_DMG_PATH}" "${OTA_ZIP_PATH}" "${UPDATES_DIR}/latest.json"
