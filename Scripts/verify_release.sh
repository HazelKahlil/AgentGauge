#!/usr/bin/env bash
# Automated pre-release verification gate for AgentGauge.
# Usage:
#   ./Scripts/verify_release.sh          # Version parity + static invariants + swift test + probe (hysteresis & updater)
#   ./Scripts/verify_release.sh --live   # Also runs live local quota checks (--verify-quotas)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT_DIR}"

LIVE_MODE=0
if [[ "${1:-}" == "--live" ]]; then
  LIVE_MODE=1
fi

if [ ! -f "${ROOT_DIR}/VERSION" ]; then
  echo "[FAIL] Missing VERSION file at repository root" >&2
  exit 1
fi

# shellcheck source=../VERSION
source "${ROOT_DIR}/VERSION"
echo "=== AgentGauge Release Gate (v${VERSION}, build ${BUILD}) ==="

# 1. Cross-file Version Parity & Static Anti-Regression Invariants
ROOT_DIR="${ROOT_DIR}" TARGET_VERSION="${VERSION}" TARGET_BUILD="${BUILD}" python3 - <<'PY'
import json
import os
import re
import subprocess
from pathlib import Path

root = Path(os.environ["ROOT_DIR"])
ver = os.environ["TARGET_VERSION"]
build = int(os.environ["TARGET_BUILD"])
failures: list[str] = []

def expect_contains(rel: str, needle: str, desc: str) -> None:
    text = (root / rel).read_text(encoding="utf-8")
    if needle not in text:
        failures.append(f"Version parity [{desc}] missing '{needle}' in {rel}")

# Version parity checks
expect_contains("Website/index.html", f'version: "{ver}"', "Website AG_CONFIG.version")
expect_contains("Website/index.html", f'AgentGauge-v{ver}-macOS.dmg', "Website AG_CONFIG.fileName")
expect_contains("Website/js/i18n.js", f'<b>v{ver}</b>', "i18n hero eyebrow")
expect_contains("Website/js/i18n.js", f'Download for macOS · v{ver}', "i18n EN CTA")
expect_contains("Website/js/i18n.js", f'下载 macOS 版 · v{ver}', "i18n ZH CTA")
expect_contains("README.md", f'release-v{ver}-', "README badge")
expect_contains("README.md", f"## What's New in v{ver}", "README heading")
expect_contains("README.zh-CN.md", f'版本-v{ver}-', "README.zh-CN badge")
expect_contains("README.zh-CN.md", f'## v{ver} 更新亮点', "README.zh-CN heading")
expect_contains("CHANGELOG.md", f'## [{ver}]', "CHANGELOG heading")
expect_contains("Website/js/app.js", f'ver: "v{ver}"', "Website changelog entry")
expect_contains("Sources/AgentGaugeCore/UpdateManager.swift", f'?? "{ver}"', "UpdateManager fallback version")

latest_json = root / "Website/updates/latest.json"
if latest_json.exists():
    manifest = json.loads(latest_json.read_text(encoding="utf-8"))
    if manifest.get("version") != ver or manifest.get("build") != build:
        failures.append(
            f"Website/updates/latest.json mismatch: got v{manifest.get('version')} ({manifest.get('build')}), expected v{ver} ({build})"
        )

app_plist = Path("/Applications/AgentGauge.app/Contents/Info.plist")
if app_plist.exists():
    plist_ver = subprocess.check_output(
        ["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleShortVersionString", str(app_plist)],
        text=True,
    ).strip()
    plist_build = subprocess.check_output(
        ["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleVersion", str(app_plist)],
        text=True,
    ).strip()
    if plist_ver != ver or int(plist_build) != build:
        failures.append(
            f"/Applications/AgentGauge.app Info.plist mismatch: got v{plist_ver} ({plist_build}), expected v{ver} ({build})"
        )

# Static anti-regression invariants (AGENTS.md)
overlay_src = (root / "Sources/AgentGaugeCore/Dock/OverlayManager.swift").read_text(encoding="utf-8")
draw_calls = list(re.finditer(r"nativeChannel\.draw\((.*?)\)", overlay_src, flags=re.S))
if not draw_calls:
    failures.append("No nativeChannel.draw calls found in OverlayManager.swift")
for idx, m in enumerate(draw_calls, 1):
    if "preferredBundleID:" not in m.group(1):
        failures.append(f"OverlayManager.swift nativeChannel.draw call #{idx} omits preferredBundleID:")

renderer_src = (root / "Sources/AgentGaugeCore/Rendering/NativeIconRenderer.swift").read_text(encoding="utf-8")
if re.search(r"effectiveLevel\s*<=\s*0\.30|effectiveLevel\s*<=\s*0\.15", renderer_src):
    failures.append("NativeIconRenderer.swift reintroduces low-quota water tint override (violates WYSIWYG color rule)")

dock_tile_c = (root / "Sources/CNativeDockTile/NativeDockTile.c").read_text(encoding="utf-8")
if "acquire_dock_server_port" not in dock_tile_c:
    failures.append("NativeDockTile.c missing cached Mach server port helper")
for m in re.finditer(r"MACH_SEND_TIMEOUT\s*,\s*sizeof\([^)]+\)\s*,\s*0\s*,\s*MACH_PORT_NULL\s*,\s*(\d+)", dock_tile_c):
    timeout_ms = int(m.group(1))
    if timeout_ms > 24:
        failures.append(f"NativeDockTile.c mach_msg timeout {timeout_ms}ms exceeds 24ms budget")

dock_locator_src = (root / "Sources/AgentGaugeCore/Dock/DockLocator.swift").read_text(encoding="utf-8")
if "orientationCache" not in dock_locator_src and "cachedOrientation" not in dock_locator_src:
    failures.append("DockLocator.swift currentOrientation() appears uncached")

ag_src = (root / "Sources/AgentGaugeCore/Providers/AntigravityProvider.swift").read_text(encoding="utf-8")
if re.search(r'label:\s*"Anthropic', ag_src):
    failures.append('AntigravityProvider.swift uses vendor label "Anthropic" instead of real model family "Claude / GPT"')

tracked_files = subprocess.check_output(["git", "ls-files"], cwd=root, text=True).splitlines()
for tf in tracked_files:
    if tf.endswith(".key") or tf.endswith(".dmg") or tf.endswith(".zip"):
        failures.append(f"Forbidden binary or private key tracked in git: {tf}")

if failures:
    for f in failures:
        print(f"[FAIL] {f}")
    raise SystemExit(1)
print("[PASS] Version parity & all AGENTS.md static invariants verified")
PY

# 2. Fast Offline Swift Unit Tests
echo "--- Running swift test ---"
swift test

# 3. Compiled Probe Checks (Schmitt-trigger hysteresis + Ed25519/SHA-256 OTA verification)
echo "--- Running AgentGaugeProbe --verify-hysteresis ---"
swift run AgentGaugeProbe --verify-hysteresis

if [ -f "${ROOT_DIR}/Website/updates/latest.json" ] && [ -f "${ROOT_DIR}/Website/downloads/AgentGauge-macOS.zip" ]; then
  echo "--- Running AgentGaugeProbe --verify-updater ---"
  swift run AgentGaugeProbe --verify-updater
else
  echo "[WARN] Skipped --verify-updater (run ./Scripts/push_remote_update.sh to generate signed OTA archive first)"
fi

# 4. Optional Live Local Quota Smoke Verification
if [ "${LIVE_MODE}" -eq 1 ]; then
  echo "--- Running AgentGaugeProbe --verify-quotas (live) ---"
  swift run AgentGaugeProbe --verify-quotas
fi

echo "=== ALL RELEASE GATES PASSED (v${VERSION}, build ${BUILD}) ==="
