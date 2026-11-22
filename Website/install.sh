#!/usr/bin/env bash
# AgentGauge One-Line Install & Legacy Overwrite Upgrader
# Usage: curl -fsSL https://usage.komorebi.date/install.sh | bash
set -euo pipefail

MANIFEST_URL="https://usage.komorebi.date/updates/latest.json"
ZIP_URL="https://usage.komorebi.date/downloads/AgentGauge-macOS.zip"
FALLBACK_ZIP_URL="https://github.com/HazelKahlil/AgentGauge/releases/latest/download/AgentGauge-macOS.zip"
TARGET_APP="/Applications/AgentGauge.app"

STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agentgauge-install.XXXXXX")"
cleanup() { rm -rf "${STAGE_DIR}"; }
trap cleanup EXIT

echo "⬇️  正在获取最新版 AgentGauge..."
MANIFEST_JSON="$(curl -fsSL "${MANIFEST_URL}" || true)"
EXPECTED_SHA=""
LATEST_VER="latest"
if [ -n "${MANIFEST_JSON}" ]; then
  EXPECTED_SHA=$(printf '%s' "${MANIFEST_JSON}" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("sha256",""))' 2>/dev/null || true)
  LATEST_VER=$(printf '%s' "${MANIFEST_JSON}" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("version","latest"))' 2>/dev/null || echo "latest")
fi

ZIP_FILE="${STAGE_DIR}/AgentGauge.zip"
if ! curl -fL --progress-bar "${ZIP_URL}" -o "${ZIP_FILE}"; then
  echo "切换至 GitHub Releases 备用源..."
  curl -fL --progress-bar "${FALLBACK_ZIP_URL}" -o "${ZIP_FILE}"
fi

if [ -n "${EXPECTED_SHA}" ]; then
  ACTUAL_SHA=$(shasum -a 256 "${ZIP_FILE}" | awk '{print $1}')
  if [ "${ACTUAL_SHA}" != "${EXPECTED_SHA}" ]; then
    echo "❌ SHA-256 校验失败，已中止安装！" >&2
    exit 1
  fi
fi

ditto -x -k "${ZIP_FILE}" "${STAGE_DIR}/extracted"
if [ ! -d "${STAGE_DIR}/extracted/AgentGauge.app" ]; then
  echo "❌ 安装包结构异常" >&2
  exit 1
fi

echo "🔄 正在关闭旧版进程并覆盖安装 v${LATEST_VER}..."
pkill -f "/Applications/AgentGauge.app/Contents/MacOS/AgentGauge" 2>/dev/null || true
sleep 0.4
rm -rf "${TARGET_APP}"
mv "${STAGE_DIR}/extracted/AgentGauge.app" "${TARGET_APP}"
/usr/bin/xattr -cr "${TARGET_APP}" 2>/dev/null || true
open -a "${TARGET_APP}"
echo "✅ AgentGauge v${LATEST_VER} 已安装并启动！（后续更新可在菜单栏一键完成）"
