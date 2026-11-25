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

# One-click atomic helper inside DMG so legacy v1.1.0–v1.2.1 users can safely upgrade with rollback protection
cat > "${STAGE_DIR}/双击一键覆盖旧版.command" <<'HELPER'
#!/usr/bin/env bash
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_APP="/Applications/AgentGauge.app"
STAGE_APP="/Applications/.AgentGauge.dmg-stage.$$.app"
cleanup() { rm -rf "${STAGE_APP}" 2>/dev/null || true; }
trap cleanup EXIT

echo "正在准备并校验新版 AgentGauge..."
rm -rf "${STAGE_APP}" 2>/dev/null || true
cp -R "${SRC_DIR}/AgentGauge.app" "${STAGE_APP}"
/usr/bin/xattr -cr "${STAGE_APP}" 2>/dev/null || true
codesign --verify --deep --strict "${STAGE_APP}"

echo "正在关闭旧版进程并原子替换安装..."
pkill -f "/Applications/AgentGauge.app/Contents/MacOS/AgentGauge" 2>/dev/null || true
sleep 0.4

SWAPPED=0
SWAP_HELPER="${STAGE_APP}/Contents/MacOS/AgentGaugeCleanup"
INSTALLED_HELPER="${TARGET_APP}/Contents/MacOS/AgentGaugeCleanup"
if [ -d "${TARGET_APP}" ]; then
  if [ -x "${SWAP_HELPER}" ] && "${SWAP_HELPER}" --atomic-swap "${STAGE_APP}" "${TARGET_APP}"; then
    SWAPPED=1
  else
    BACKUP_APP="/Applications/.AgentGauge.backup.$$.app"
    rm -rf "${BACKUP_APP}" 2>/dev/null || true
    if mv "${TARGET_APP}" "${BACKUP_APP}" && mv "${STAGE_APP}" "${TARGET_APP}"; then
      STAGE_APP="${BACKUP_APP}"
      SWAPPED=1
    else
      [ -d "${BACKUP_APP}" ] && [ ! -d "${TARGET_APP}" ] && mv "${BACKUP_APP}" "${TARGET_APP}" 2>/dev/null || true
      echo "❌ 替换安装失败，已保留原版本" >&2
      exit 1
    fi
  fi
else
  mv "${STAGE_APP}" "${TARGET_APP}"
fi

LAUNCH_OK=0
if /usr/bin/open -n "${TARGET_APP}"; then
  for _ in $(seq 1 25); do
    sleep 0.15
    if pgrep -f "${TARGET_APP}/Contents/MacOS/AgentGauge" >/dev/null 2>&1; then
      LAUNCH_OK=1
      break
    fi
  done
fi

if [ "${LAUNCH_OK}" -eq 1 ]; then
  rm -rf "${STAGE_APP}" 2>/dev/null || true
  echo "✅ 已成功升级并启动新版 AgentGauge！（后续版本均支持应用内一键远程推送更新）"
  sleep 1.2
  exit 0
fi

echo "⚠️ 新版启动检测失败，正在自动回滚至原版本..." >&2
if [ "${SWAPPED}" -eq 1 ] && [ -d "${STAGE_APP}" ]; then
  if [ -x "${INSTALLED_HELPER}" ] && "${INSTALLED_HELPER}" --atomic-swap "${STAGE_APP}" "${TARGET_APP}"; then
    rm -rf "${STAGE_APP}" 2>/dev/null || true
  else
    FAILED_APP="/Applications/.AgentGauge.failed.$$.app"
    mv "${TARGET_APP}" "${FAILED_APP}" 2>/dev/null || true
    mv "${STAGE_APP}" "${TARGET_APP}" 2>/dev/null || true
    rm -rf "${FAILED_APP}" 2>/dev/null || true
  fi
  /usr/bin/open -n "${TARGET_APP}" 2>/dev/null || true
fi
exit 1
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
RELEASE_TITLE="${RELEASE_TITLE:-v${SHORT_VERSION} · 全链路 Ed25519 验签原子回滚与多账号隔离加固}"
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
        "全链路强制 Ed25519 数字签名与 SHA-256 验签（覆盖 CDN、GitHub 回退源与一行安装脚本），并升级为内核级 renamex_np 原子交换 + 启动失败自动回滚",
        "修复并发网页刷新队列竞态、Dock bootstrap 端口泄漏及 Claude Keychain 阻塞风险，将 Dock Mach 通信迁出主线程并补齐失败补偿释放",
        "严格加固多账号、单模型池与跨产品隔离（Cursor ↔ Grok Bot 精确槽位与双有效重置时间校验、Antigravity 缺池不串池、Gemini 桌面版隔离 CLI 缓存、全量过滤 1970 哨兵时间）"
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
