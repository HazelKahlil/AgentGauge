#!/usr/bin/env bash
# One-command build + sign + OTA manifest generator (+ optional remote publish)
# Usage:
#   ./Scripts/push_remote_update.sh                  # Build & sign local vX.Y.Z + latest.json
#   ./Scripts/push_remote_update.sh --publish        # Also upload GitHub Release assets & deploy Website CDN
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT_DIR}"

./Scripts/build_app.sh
./Scripts/package_dmg.sh

SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "/Applications/AgentGauge.app/Contents/Info.plist")
echo ""
echo "✅ 本地构建与 Ed25519 远程推送清单已就绪: v${SHORT_VERSION}"
echo "   • OTA 清单: Website/updates/latest.json"
echo "   • OTA 更新包: Website/downloads/AgentGauge-macOS.zip"
echo "   • 安装镜像: Website/downloads/AgentGauge-v${SHORT_VERSION}-macOS.dmg & AgentGauge-macOS.dmg"

if [[ "${1:-}" == "--publish" ]]; then
  echo "🛡️  正在执行发布前强制门禁（未通过将中止上传与部署）..."
  ./Scripts/verify_release.sh --require-artifacts

  TAG="v${SHORT_VERSION}"
  echo "🚀 正在发布 GitHub Release (${TAG})..."
  if gh release view "${TAG}" >/dev/null 2>&1; then
    gh release upload "${TAG}" \
      "Website/downloads/AgentGauge-v${SHORT_VERSION}-macOS.dmg" \
      "Website/downloads/AgentGauge-macOS.dmg" \
      "Website/downloads/AgentGauge-macOS.zip" \
      "Website/updates/latest.json" \
      --clobber
  else
    gh release create "${TAG}" \
      "Website/downloads/AgentGauge-v${SHORT_VERSION}-macOS.dmg" \
      "Website/downloads/AgentGauge-macOS.dmg" \
      "Website/downloads/AgentGauge-macOS.zip" \
      "Website/updates/latest.json" \
      --title "AgentGauge ${TAG}" \
      --notes "See CHANGELOG.md and https://usage.komorebi.date/#changelog"
  fi

  if command -v npx >/dev/null 2>&1; then
    echo "🌍 正在推送到 Cloudflare Pages (usage.komorebi.date)..."
    npx wrangler pages deploy Website --project-name=agentgauge --commit-dirty=true
  fi
  echo "🎉 远程更新 ${TAG} 已全网生效！所有客户端将在检查更新时收到一键升级提示。"
fi
