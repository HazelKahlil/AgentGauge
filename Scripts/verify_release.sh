#!/usr/bin/env bash
# Automated fail-closed pre-release verification gate for AgentGauge.
# Usage:
#   ./Scripts/verify_release.sh               # Full gate: parity + invariants + swift test + probe + delivered ZIP inspection
#   ./Scripts/verify_release.sh --live        # Also runs live local quota smoke check (--verify-quotas)
#   ./Scripts/verify_release.sh --no-artifacts # Dev-only: skip OTA ZIP/DMG artifact checks
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT_DIR}"

LIVE_MODE=0
REQUIRE_ARTIFACTS=1
for arg in "$@"; do
  case "${arg}" in
    --live) LIVE_MODE=1 ;;
    --no-artifacts) REQUIRE_ARTIFACTS=0 ;;
    --require-artifacts) REQUIRE_ARTIFACTS=1 ;;
    *) echo "Unknown flag: ${arg}" >&2; exit 1 ;;
  esac
done

if [ ! -f "${ROOT_DIR}/VERSION" ]; then
  echo "[FAIL] Missing VERSION file at repository root" >&2
  exit 1
fi

# shellcheck source=../VERSION
source "${ROOT_DIR}/VERSION"
echo "=== AgentGauge Release Gate (v${VERSION}, build ${BUILD}) ==="

# 1. Single-source version parity via sync_version.sh --check
./Scripts/sync_version.sh --check

# 2. Changelog parity, AGENTS.md static anti-regression invariants & delivered ZIP interior verification
ROOT_DIR="${ROOT_DIR}" TARGET_VERSION="${VERSION}" TARGET_BUILD="${BUILD}" REQUIRE_ARTIFACTS="${REQUIRE_ARTIFACTS}" python3 - <<'PY'
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

root = Path(os.environ["ROOT_DIR"])
ver = os.environ["TARGET_VERSION"]
build = int(os.environ["TARGET_BUILD"])
require_artifacts = os.environ["REQUIRE_ARTIFACTS"] == "1"
failures: list[str] = []

def expect_contains(rel: str, needle: str, desc: str) -> None:
    text = (root / rel).read_text(encoding="utf-8")
    if needle not in text:
        failures.append(f"Release parity [{desc}] missing '{needle}' in {rel}")

expect_contains("CHANGELOG.md", f"## [{ver}]", "CHANGELOG heading")
expect_contains("Website/js/app.js", f'ver: "v{ver}"', "Website changelog entry")

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
if "mach_port_deallocate(mach_task_self(), bp)" not in dock_tile_c:
    failures.append("NativeDockTile.c leaks TASK_BOOTSTRAP_PORT send right (`bp` not deallocated)")
for m in re.finditer(r"MACH_SEND_TIMEOUT\s*,\s*sizeof\([^)]+\)\s*,\s*0\s*,\s*MACH_PORT_NULL\s*,\s*(\d+)", dock_tile_c):
    timeout_ms = int(m.group(1))
    if timeout_ms > 24:
        failures.append(f"NativeDockTile.c mach_msg timeout {timeout_ms}ms exceeds 24ms budget")
# Check release worst-case budget array sum <= 24ms
budget_match = re.search(r"budgets\[\d+\]\s*=\s*\{([^}]+)\}", dock_tile_c)
if not budget_match:
    failures.append("NativeDockTile.c release timeout budget array missing")
else:
    budget_vals = [int(x.strip()) for x in budget_match.group(1).split(",") if x.strip()]
    if sum(budget_vals) > 24:
        failures.append(f"NativeDockTile.c worst-case release timeout sum {sum(budget_vals)}ms exceeds 24ms budget")

tile_channel_src = (root / "Sources/AgentGaugeCore/Dock/NativeTileChannel.swift").read_text(encoding="utf-8")
if "ipcQueue" not in tile_channel_src or "pendingReleases" not in tile_channel_src:
    failures.append("NativeTileChannel.swift missing off-main-thread ipcQueue or pendingReleases compensation")

dock_locator_src = (root / "Sources/AgentGaugeCore/Dock/DockLocator.swift").read_text(encoding="utf-8")
if "cachedOrientation" not in dock_locator_src:
    failures.append("DockLocator.swift currentOrientation() appears uncached")

ag_src = (root / "Sources/AgentGaugeCore/Providers/AntigravityProvider.swift").read_text(encoding="utf-8")
if re.search(r'label:\s*"Anthropic', ag_src):
    failures.append('AntigravityProvider.swift uses vendor label "Anthropic" instead of real model family "Claude / GPT"')

updater_src = (root / "Sources/AgentGaugeCore/UpdateManager.swift").read_text(encoding="utf-8")
if "isFromSignedFeed: false" in updater_src:
    failures.append("UpdateManager.swift allows unsigned update fallback (`isFromSignedFeed: false`)")

popover_src = (root / "Sources/AgentGaugeApp/MenuBarPopoverView.swift").read_text(encoding="utf-8")
if ".menuStyle(.borderlessButton)" in popover_src:
    failures.append("MenuBarPopoverView.swift uses .menuStyle(.borderlessButton) which strips PlanTierBadgePill dark mineral background on macOS")

tracked_files = subprocess.check_output(["git", "ls-files"], cwd=root, text=True).splitlines()
for tf in tracked_files:
    if tf.endswith(".key") or tf.endswith(".dmg") or tf.endswith(".zip"):
        failures.append(f"Forbidden binary or private key tracked in git: {tf}")

# Fail-closed verification of actual delivered release artifacts (manifest + DMG + ZIP interior .app!)
if require_artifacts:
    required_paths = [
        root / "Website/updates/latest.json",
        root / "Website/downloads/AgentGauge-macOS.zip",
        root / "Website/downloads/AgentGauge-macOS.dmg",
        root / f"Website/downloads/AgentGauge-v{ver}-macOS.dmg",
    ]
    for rp in required_paths:
        if not rp.is_file():
            failures.append(f"Required release artifact missing: {rp.relative_to(root)}")

    latest_json = root / "Website/updates/latest.json"
    ota_zip = root / "Website/downloads/AgentGauge-macOS.zip"
    if latest_json.is_file() and ota_zip.is_file():
        manifest = json.loads(latest_json.read_text(encoding="utf-8"))
        if manifest.get("version") != ver or manifest.get("build") != build:
            failures.append(
                f"Website/updates/latest.json mismatch: got v{manifest.get('version')} ({manifest.get('build')}), expected v{ver} ({build})"
            )

        # Extract the ACTUAL delivered ZIP archive and verify its inner AgentGauge.app bundle ID, version, build, executables & codesign!
        with tempfile.TemporaryDirectory(prefix="ag-verify-zip-") as tmpd:
            rc = subprocess.run(["/usr/bin/ditto", "-x", "-k", str(ota_zip), tmpd], capture_output=True)
            if rc.returncode != 0:
                failures.append("Failed to extract Website/downloads/AgentGauge-macOS.zip")
            else:
                inner_app = Path(tmpd) / "AgentGauge.app"
                inner_plist = inner_app / "Contents/Info.plist"
                if not inner_plist.is_file():
                    failures.append("Delivered OTA ZIP does not contain AgentGauge.app/Contents/Info.plist")
                else:
                    def pb(key: str) -> str:
                        return subprocess.check_output(
                            ["/usr/libexec/PlistBuddy", "-c", f"Print :{key}", str(inner_plist)],
                            text=True,
                        ).strip()
                    bid = pb("CFBundleIdentifier")
                    iver = pb("CFBundleShortVersionString")
                    ibuild = int(pb("CFBundleVersion"))
                    if bid != "com.kahlil.AgentGauge":
                        failures.append(f"Delivered ZIP bundle ID mismatch: {bid}")
                    if iver != ver or ibuild != build:
                        failures.append(f"Delivered ZIP app version mismatch: v{iver} ({ibuild}) != v{ver} ({build})")
                    for exe in ("Contents/MacOS/AgentGauge", "Contents/MacOS/AgentGaugeCleanup"):
                        if not os.access(inner_app / exe, os.X_OK):
                            failures.append(f"Delivered ZIP missing executable: {exe}")
                    cs = subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(inner_app)], capture_output=True, text=True)
                    if cs.returncode != 0:
                        failures.append(f"Delivered ZIP codesign verification failed: {cs.stderr.strip()}")

if failures:
    for f in failures:
        print(f"[FAIL] {f}")
    raise SystemExit(1)
print("[PASS] AGENTS.md static invariants & delivered OTA ZIP bundle integrity verified")
PY

# 3. Fast Offline Swift Unit Tests
echo "--- Running swift test ---"
swift test

# 4. Compiled Probe Checks (Schmitt-trigger hysteresis + Ed25519/SHA-256 OTA verification)
echo "--- Running AgentGaugeProbe --verify-hysteresis ---"
swift run AgentGaugeProbe --verify-hysteresis

if [ "${REQUIRE_ARTIFACTS}" -eq 1 ]; then
  echo "--- Running AgentGaugeProbe --verify-updater ---"
  swift run AgentGaugeProbe --verify-updater
fi

# 5. Optional Live Local Quota Smoke Verification
if [ "${LIVE_MODE}" -eq 1 ]; then
  echo "--- Running AgentGaugeProbe --verify-quotas (live) ---"
  swift run AgentGaugeProbe --verify-quotas
fi

echo "=== ALL RELEASE GATES PASSED (v${VERSION}, build ${BUILD}) ==="
