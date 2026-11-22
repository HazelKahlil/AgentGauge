#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="/Applications/AgentGauge.app"
OUT_DIR="${ROOT_DIR}/Website/downloads"
UPDATES_DIR="${ROOT_DIR}/Website/updates"

if [ ! -d "${APP_PATH}" ]; then
  echo "Error: ${APP_PATH} not found. Run Scripts/build_app.sh first." >&2
  exit 1
fi

SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "1.3.0")
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "130")
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
RELEASE_TITLE="${RELEASE_TITLE:-v${SHORT_VERSION} · 远程推送热更新与第一性原理双算力池引擎}"
SHORT_VERSION="${SHORT_VERSION}" \
BUILD_VERSION="${BUILD_VERSION}" \
ZIP_SHA256="${ZIP_SHA256}" \
RELEASE_TITLE="${RELEASE_TITLE}" \
MANIFEST_OUT="${UPDATES_DIR}/latest.json" \
swift - <<'SWIFT'
import CryptoKit
import Foundation

let env = ProcessInfo.processInfo.environment
let version = env["SHORT_VERSION"] ?? "1.3.0"
let build = Int(env["BUILD_VERSION"] ?? "130") ?? 130
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
        "支持远程更新推送：菜单栏与设置页一键静默下载、Ed25519 签名校验、原子覆盖并自动重启",
        "Antigravity 独立分离 Gemini 与 Anthropic 模型限额池，<0.5ms 追踪当前对话模型并支持四档池切换",
        "修复 Claude 低用量比例缩放，Claude 与 Codex 统一执行 min(5h, 周限) 木桶串联规则",
        "升级双轨微仪表双池低水位变红预警，手动刷新立即穿透全部缓存"
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
