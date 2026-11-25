#!/usr/bin/env bash
# Atomic single-source-of-truth version synchronizer & parity checker for AgentGauge.
# Validates ALL target files in memory before writing a single byte (and writes VERSION last!).
# Usage:
#   ./Scripts/sync_version.sh --check          # Read-only parity check against ./VERSION
#   ./Scripts/sync_version.sh                  # Sync all files to match ./VERSION
#   ./Scripts/sync_version.sh 1.3.4 134        # Validate all targets, write targets, then commit ./VERSION
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="${ROOT_DIR}/VERSION"

CHECK_ONLY=0
NEW_VER=""
NEW_BUILD=""

if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=1
elif [ "$#" -ge 2 ]; then
  NEW_VER="$1"
  NEW_BUILD="$2"
  if ! [[ "${NEW_VER}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || ! [[ "${NEW_BUILD}" =~ ^[0-9]+$ ]]; then
    echo "Error: Usage: $0 [--check | <X.Y.Z> <BUILD_INT>]" >&2
    exit 1
  fi
fi

if [ -n "${NEW_VER}" ]; then
  TARGET_VERSION="${NEW_VER}"
  TARGET_BUILD="${NEW_BUILD}"
else
  if [ ! -f "${VERSION_FILE}" ]; then
    echo "Error: Missing ${VERSION_FILE}" >&2
    exit 1
  fi
  # shellcheck source=../VERSION
  source "${VERSION_FILE}"
  TARGET_VERSION="${VERSION}"
  TARGET_BUILD="${BUILD}"
fi

ROOT_DIR="${ROOT_DIR}" \
TARGET_VERSION="${TARGET_VERSION}" \
TARGET_BUILD="${TARGET_BUILD}" \
CHECK_ONLY="${CHECK_ONLY}" \
UPDATE_VERSION_FILE="$( [ -n "${NEW_VER}" ] && echo 1 || echo 0 )" \
python3 - <<'PY'
import os
import re
from pathlib import Path

root = Path(os.environ["ROOT_DIR"])
ver = os.environ["TARGET_VERSION"]
build = os.environ["TARGET_BUILD"]
check_only = os.environ["CHECK_ONLY"] == "1"
update_version_file = os.environ["UPDATE_VERSION_FILE"] == "1"

# Each rule: (regex_pattern, replacement, expected_match_count)
RULES: list[tuple[str, list[tuple[str, str, int]]]] = [
    ("Website/index.html", [
        (r'(css/site\.css\?v=)[0-9]+\.[0-9]+\.[0-9]+', rf'\g<1>{ver}', 1),
        (r'(data-i18n="hero\.eyebrow"><b>v)[0-9]+\.[0-9]+\.[0-9]+(</b>)', rf'\g<1>{ver}\g<2>', 1),
        (r'(assets/shots/settings\.png\?v=)[0-9]+\.[0-9]+\.[0-9]+', rf'\g<1>{ver}', 1),
        (r'(alt="AgentGauge v)[0-9]+\.[0-9]+\.[0-9]+( settings window")', rf'\g<1>{ver}\g<2>', 1),
        (r'(fileName:\s*"AgentGauge-v)[0-9]+\.[0-9]+\.[0-9]+(-macOS\.dmg")', rf'\g<1>{ver}\g<2>', 1),
        (r'(version:\s*")[0-9]+\.[0-9]+\.[0-9]+(")', rf'\g<1>{ver}\g<2>', 1),
        (r'(js/(?:i18n|liquid|app)\.js\?v=)[0-9]+\.[0-9]+\.[0-9]+', rf'\g<1>{ver}', 3),
    ]),
    ("Website/js/i18n.js", [
        (r'("hero\.eyebrow":\s*"<b>v)[0-9]+\.[0-9]+\.[0-9]+(</b>)', rf'\g<1>{ver}\g<2>', 2),
        (r'("film\.eyebrow":\s*"(?:The film|宣传片) · v)[0-9]+\.[0-9]+\.[0-9]+(")', rf'\g<1>{ver}\g<2>', 2),
        (r'("cta\.btn":\s*"(?:Download for macOS|下载 macOS 版) · v)[0-9]+\.[0-9]+\.[0-9]+(")', rf'\g<1>{ver}\g<2>', 2),
    ]),
    ("README.md", [
        (r'(img\.shields\.io/badge/release-v)[0-9]+\.[0-9]+\.[0-9]+(-)', rf'\g<1>{ver}\g<2>', 1),
        (r'(alt="Release v)[0-9]+\.[0-9]+\.[0-9]+(")', rf'\g<1>{ver}\g<2>', 1),
        (r"(## What's New in v)[0-9]+\.[0-9]+\.[0-9]+", rf'\g<1>{ver}', 1),
        (r'(AgentGauge-macOS\.dmg\)\s*\(`v)[0-9]+\.[0-9]+\.[0-9]+(`)', rf'\g<1>{ver}\g<2>', 1),
    ]),
    ("README.zh-CN.md", [
        (r'(img\.shields\.io/badge/版本-v)[0-9]+\.[0-9]+\.[0-9]+(-)', rf'\g<1>{ver}\g<2>', 1),
        (r'(alt="Release v)[0-9]+\.[0-9]+\.[0-9]+(")', rf'\g<1>{ver}\g<2>', 1),
        (r'(## v)[0-9]+\.[0-9]+\.[0-9]+( 更新亮点)', rf'\g<1>{ver}\g<2>', 1),
        (r'(AgentGauge-macOS\.dmg\)\s*（`v)[0-9]+\.[0-9]+\.[0-9]+(`)', rf'\g<1>{ver}\g<2>', 1),
    ]),
    ("Sources/AgentGaugeCore/UpdateManager.swift", [
        (r'(\["CFBundleShortVersionString"\]\s+as\?\s+String\)\s*\?\?\s*")[0-9]+\.[0-9]+\.[0-9]+(")', rf'\g<1>{ver}\g<2>', 1),
        (r'(if let raw = Bundle\.main\.infoDictionary\?\["CFBundleVersion"\] as\? String, let n = Int\(raw\) \{\s*return n\s*\}\s*return\s+)[0-9]+', rf'\g<1>{build}', 1),
    ]),
]

# Phase 1: Pure in-memory validation across EVERY target file before touching disk!
planned: list[tuple[Path, str, str, str]] = []
errors: list[str] = []

for rel_path, replacements in RULES:
    p = root / rel_path
    if not p.exists():
        errors.append(f"Missing target file: {rel_path}")
        continue
    original = p.read_text(encoding="utf-8")
    updated = original
    for pattern, repl, expected_count in replacements:
        updated, count = re.subn(pattern, repl, updated)
        if count != expected_count:
            errors.append(
                f"Rule count mismatch in {rel_path}: matched {count}, expected {expected_count} for {pattern}"
            )
    planned.append((p, rel_path, original, updated))

if errors:
    for err in errors:
        print(f"[FAIL] {err}")
    raise SystemExit("Aborted before writing any files (working tree untouched).")

if check_only:
    drifted = [rel for _, rel, orig, upd in planned if orig != upd]
    if drifted:
        for rel in drifted:
            print(f"[FAIL] Version drift detected in {rel} (expected v{ver}, build {build})")
        raise SystemExit(1)
    print(f"[PASS] All versioned repository metadata matches VERSION (v{ver}, build {build})")
    raise SystemExit(0)

# Phase 2: Atomic write (targets first, VERSION committed LAST so an interrupted run never leaves VERSION ahead!)
print(f"Syncing AgentGauge repository metadata to v{ver} (build {build})...")
for p, rel_path, original, updated in planned:
    if updated != original:
        tmp = p.with_suffix(p.suffix + ".tmp")
        tmp.write_text(updated, encoding="utf-8")
        os.replace(tmp, p)
        print(f"  updated {rel_path}")
    else:
        print(f"  in-sync {rel_path}")

if update_version_file:
    vf = root / "VERSION"
    tmp_vf = root / "VERSION.tmp"
    tmp_vf.write_text(f"VERSION={ver}\nBUILD={build}\n", encoding="utf-8")
    os.replace(tmp_vf, vf)
    print(f"  updated VERSION -> v{ver} ({build})")

print(f"Done. Remember to add the v{ver} entry in CHANGELOG.md and Website/js/app.js if bumping to a new version.")
PY
