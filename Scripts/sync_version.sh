#!/usr/bin/env bash
# Single-source-of-truth version synchronizer for AgentGauge.
# Usage:
#   ./Scripts/sync_version.sh               # Sync all files to match ./VERSION
#   ./Scripts/sync_version.sh 1.3.4 134     # Update ./VERSION and sync all files
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="${ROOT_DIR}/VERSION"

if [ "$#" -ge 2 ]; then
  NEW_VER="$1"
  NEW_BUILD="$2"
  if ! [[ "${NEW_VER}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || ! [[ "${NEW_BUILD}" =~ ^[0-9]+$ ]]; then
    echo "Error: Usage: $0 <X.Y.Z> <BUILD_INT>" >&2
    exit 1
  fi
  cat > "${VERSION_FILE}" <<EOF
VERSION=${NEW_VER}
BUILD=${NEW_BUILD}
EOF
fi

if [ ! -f "${VERSION_FILE}" ]; then
  echo "Error: Missing ${VERSION_FILE}" >&2
  exit 1
fi

# shellcheck source=../VERSION
source "${VERSION_FILE}"
echo "Syncing AgentGauge repository metadata to v${VERSION} (build ${BUILD})..."

ROOT_DIR="${ROOT_DIR}" TARGET_VERSION="${VERSION}" TARGET_BUILD="${BUILD}" python3 - <<'PY'
import os
import re
from pathlib import Path

root = Path(os.environ["ROOT_DIR"])
ver = os.environ["TARGET_VERSION"]
build = os.environ["TARGET_BUILD"]

def patch_file(rel_path: str, replacements: list[tuple[str, str]]) -> None:
    p = root / rel_path
    text = p.read_text(encoding="utf-8")
    updated = text
    for pattern, repl in replacements:
        updated, count = re.subn(pattern, repl, updated)
        if count == 0:
            raise SystemExit(f"[FAIL] Pattern not matched in {rel_path}: {pattern}")
    if updated != text:
        p.write_text(updated, encoding="utf-8")
        print(f"  updated {rel_path}")
    else:
        print(f"  in-sync {rel_path}")

patch_file("Website/index.html", [
    (r'(css/site\.css\?v=)[0-9]+\.[0-9]+\.[0-9]+', rf'\g<1>{ver}'),
    (r'(data-i18n="hero\.eyebrow"><b>v)[0-9]+\.[0-9]+\.[0-9]+(</b>)', rf'\g<1>{ver}\g<2>'),
    (r'(assets/shots/settings\.png\?v=)[0-9]+\.[0-9]+\.[0-9]+', rf'\g<1>{ver}'),
    (r'(alt="AgentGauge v)[0-9]+\.[0-9]+\.[0-9]+( settings window")', rf'\g<1>{ver}\g<2>'),
    (r'(fileName:\s*"AgentGauge-v)[0-9]+\.[0-9]+\.[0-9]+(-macOS\.dmg")', rf'\g<1>{ver}\g<2>'),
    (r'(version:\s*")[0-9]+\.[0-9]+\.[0-9]+(")', rf'\g<1>{ver}\g<2>'),
    (r'(js/(?:i18n|liquid|app)\.js\?v=)[0-9]+\.[0-9]+\.[0-9]+', rf'\g<1>{ver}'),
])

patch_file("Website/js/i18n.js", [
    (r'("hero\.eyebrow":\s*"<b>v)[0-9]+\.[0-9]+\.[0-9]+(</b>)', rf'\g<1>{ver}\g<2>'),
    (r'("film\.eyebrow":\s*"(?:The film|宣传片) · v)[0-9]+\.[0-9]+\.[0-9]+(")', rf'\g<1>{ver}\g<2>'),
    (r'("cta\.btn":\s*"(?:Download for macOS|下载 macOS 版) · v)[0-9]+\.[0-9]+\.[0-9]+(")', rf'\g<1>{ver}\g<2>'),
])

patch_file("README.md", [
    (r'(img\.shields\.io/badge/release-v)[0-9]+\.[0-9]+\.[0-9]+(-)', rf'\g<1>{ver}\g<2>'),
    (r'(alt="Release v)[0-9]+\.[0-9]+\.[0-9]+(")', rf'\g<1>{ver}\g<2>'),
    (r'(## What\'s New in v)[0-9]+\.[0-9]+\.[0-9]+', rf'\g<1>{ver}'),
    (r'(AgentGauge-macOS\.dmg\)\s*\(`v)[0-9]+\.[0-9]+\.[0-9]+(`)', rf'\g<1>{ver}\g<2>'),
])

patch_file("README.zh-CN.md", [
    (r'(img\.shields\.io/badge/版本-v)[0-9]+\.[0-9]+\.[0-9]+(-)', rf'\g<1>{ver}\g<2>'),
    (r'(alt="Release v)[0-9]+\.[0-9]+\.[0-9]+(")', rf'\g<1>{ver}\g<2>'),
    (r'(## v)[0-9]+\.[0-9]+\.[0-9]+( 更新亮点)', rf'\g<1>{ver}\g<2>'),
    (r'(AgentGauge-macOS\.dmg\)\s*（`v)[0-9]+\.[0-9]+\.[0-9]+(`)', rf'\g<1>{ver}\g<2>'),
])

patch_file("Sources/AgentGaugeCore/UpdateManager.swift", [
    (r'(\["CFBundleShortVersionString"\]\s+as\?\s+String\)\s*\?\?\s*")[0-9]+\.[0-9]+\.[0-9]+(")', rf'\g<1>{ver}\g<2>'),
    (r'(if let raw = Bundle\.main\.infoDictionary\?\["CFBundleVersion"\] as\? String, let n = Int\(raw\) \{\s*return n\s*\}\s*return\s+)[0-9]+', rf'\g<1>{build}'),
])

print(f"Done. Remember to add the v{ver} entry in CHANGELOG.md and Website/js/app.js if bumping to a new version.")
PY
