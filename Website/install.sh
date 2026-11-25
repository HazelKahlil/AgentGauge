#!/usr/bin/env bash
# AgentGauge One-Line Install & Atomic Verified Upgrader
# Usage: curl -fsSL https://usage.komorebi.date/install.sh | bash
set -euo pipefail

RELEASE_PUBKEY_B64="5OsV5hFo010d6lSMn3XGJRQOAznpoZ7SFXINupTk+GA="
MANIFEST_URL="https://usage.komorebi.date/updates/latest.json"
FALLBACK_MANIFEST_URL="https://github.com/HazelKahlil/AgentGauge/releases/latest/download/latest.json"
ZIP_URL="https://usage.komorebi.date/downloads/AgentGauge-macOS.zip"
FALLBACK_ZIP_URL="https://github.com/HazelKahlil/AgentGauge/releases/latest/download/AgentGauge-macOS.zip"
TARGET_APP="/Applications/AgentGauge.app"
SAME_VOL_STAGE="/Applications/.AgentGauge.install-stage.$$.app"

STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agentgauge-install.XXXXXX")"
cleanup() {
  rm -rf "${STAGE_DIR}" "${SAME_VOL_STAGE}" 2>/dev/null || true
}
trap cleanup EXIT

echo "⬇️  正在获取并验签最新版 AgentGauge 清单..."
MANIFEST_FILE="${STAGE_DIR}/latest.json"
if ! curl -fsSL --max-time 15 "${MANIFEST_URL}" -o "${MANIFEST_FILE}"; then
  echo "主清单源暂不可用，切换至 GitHub Releases 已签名清单..."
  if ! curl -fsSL --max-time 20 "${FALLBACK_MANIFEST_URL}" -o "${MANIFEST_FILE}"; then
    echo "❌ 无法下载已签名发布清单，已中止安装！" >&2
    exit 1
  fi
fi

# Cryptographically verify Ed25519 signature over `AgentGauge-Update-v1|<version>|<build>|<sha256>` (fail closed!)
verify_manifest_ed25519() {
  if command -v python3 >/dev/null 2>&1; then
    MANIFEST_FILE="${MANIFEST_FILE}" PUBKEY_B64="${RELEASE_PUBKEY_B64}" python3 - <<'PY'
import base64, hashlib, json, os, sys

# Pure-stdlib RFC 8032 Ed25519 signature verifier (zero external dependencies)
p = 2**255 - 19
l = 2**252 + 27742317777372353535851937790883648493
d = (-121665 * pow(121666, p - 2, p)) % p
I = pow(2, (p - 1) // 4, p)

def xrecover(y):
    xx = (y * y - 1) * pow(d * y * y + 1, p - 2, p) % p
    x = pow(xx, (p + 3) // 8, p)
    if (x * x - xx) % p != 0:
        x = (x * I) % p
    if x % 2 != 0:
        x = p - x
    return x

By = 4 * pow(5, p - 2, p) % p
Bx = xrecover(By)
B = (Bx, By, 1, (Bx * By) % p)

def edwards_add(P, Q):
    X1, Y1, Z1, T1 = P
    X2, Y2, Z2, T2 = Q
    A = ((Y1 - X1) * (Y2 - X2)) % p
    B_ = ((Y1 + X1) * (Y2 + X2)) % p
    C = (2 * d * T1 * T2) % p
    D = (2 * Z1 * Z2) % p
    E, F, G, H = (B_ - A) % p, (D - C) % p, (D + C) % p, (B_ + A) % p
    return ((E * F) % p, (G * H) % p, (F * G) % p, (E * H) % p)

def scalarmult(P, e):
    Q = (0, 1, 1, 0)
    while e > 0:
        if e & 1:
            Q = edwards_add(Q, P)
        P = edwards_add(P, P)
        e >>= 1
    return Q

def decodepoint(s):
    y = int.from_bytes(s, "little") & ((1 << 255) - 1)
    if y >= p:
        raise ValueError("invalid y")
    x = xrecover(y)
    if (x & 1) != (s[31] >> 7):
        x = p - x
    if (-x * x + y * y - 1 - d * x * x * y * y) % p != 0:
        raise ValueError("point not on curve")
    return (x, y, 1, (x * y) % p)

def point_eq(P, Q):
    return (P[0] * Q[2] - Q[0] * P[2]) % p == 0 and (P[1] * Q[2] - Q[1] * P[2]) % p == 0

with open(os.environ["MANIFEST_FILE"], "r", encoding="utf-8") as fh:
    m = json.load(fh)

ver = str(m.get("version", "")).strip().lstrip("v")
build = int(m.get("build", 0))
sha = str(m.get("sha256", "")).strip().lower()
sig_b64 = str(m.get("signature", "")).strip()
if not ver or build <= 0 or len(sha) != 64 or not sig_b64:
    raise SystemExit("invalid manifest fields")

pk = base64.b64decode(os.environ["PUBKEY_B64"])
sig = base64.b64decode(sig_b64)
if len(pk) != 32 or len(sig) != 64:
    raise SystemExit("invalid key/signature length")

R = decodepoint(sig[:32])
A = decodepoint(pk)
S = int.from_bytes(sig[32:], "little")
if S >= l:
    raise SystemExit("invalid S scalar")

msg = f"AgentGauge-Update-v1|{ver}|{build}|{sha}".encode("utf-8")
k = int.from_bytes(hashlib.sha512(sig[:32] + pk + msg).digest(), "little") % l
if not point_eq(scalarmult(B, S), edwards_add(R, scalarmult(A, k))):
    raise SystemExit("Ed25519 signature verification failed")

print(f"{ver}|{build}|{sha}")
PY
    return $?
  fi

  if command -v swift >/dev/null 2>&1; then
    MANIFEST_FILE="${MANIFEST_FILE}" PUBKEY_B64="${RELEASE_PUBKEY_B64}" swift - <<'SWIFT'
import CryptoKit
import Foundation

let env = ProcessInfo.processInfo.environment
guard let data = try? Data(contentsOf: URL(fileURLWithPath: env["MANIFEST_FILE"]!)),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let rawVer = (json["version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
      let build = json["build"] as? Int, build > 0,
      let sha = (json["sha256"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), sha.count == 64,
      let sigB64 = (json["signature"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
      let pubData = Data(base64Encoded: env["PUBKEY_B64"]!),
      let sigData = Data(base64Encoded: sigB64),
      let pubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData) else {
    exit(1)
}
let ver = rawVer.hasPrefix("v") ? String(rawVer.dropFirst()) : rawVer
let canonical = Data("AgentGauge-Update-v1|\(ver)|\(build)|\(sha)".utf8)
guard pubKey.isValidSignature(sigData, for: canonical) else { exit(1) }
print("\(ver)|\(build)|\(sha)")
SWIFT
    return $?
  fi

  echo "❌ 本机缺少 python3 / swift，无法验证 Ed25519 发布签名，拒绝安装未验签软件包！" >&2
  return 1
}

VERIFIED_META="$(verify_manifest_ed25519)" || {
  echo "❌ 清单 Ed25519 数字签名校验失败，已拦截安装！" >&2
  exit 1
}

LATEST_VER="${VERIFIED_META%%|*}"
REST_META="${VERIFIED_META#*|}"
EXPECTED_BUILD="${REST_META%%|*}"
EXPECTED_SHA="${REST_META#*|}"
echo "✅ 清单 Ed25519 签名验证通过：v${LATEST_VER} (build ${EXPECTED_BUILD})"

ZIP_FILE="${STAGE_DIR}/AgentGauge.zip"
if ! curl -fL --progress-bar "${ZIP_URL}" -o "${ZIP_FILE}"; then
  echo "切换至 GitHub Releases 备用源..."
  curl -fL --progress-bar "${FALLBACK_ZIP_URL}" -o "${ZIP_FILE}"
fi

ACTUAL_SHA=$(shasum -a 256 "${ZIP_FILE}" | awk '{print $1}')
if [ "${ACTUAL_SHA}" != "${EXPECTED_SHA}" ]; then
  echo "❌ SHA-256 校验失败（期望 ${EXPECTED_SHA}，实际 ${ACTUAL_SHA}），已中止安装！" >&2
  exit 1
fi
echo "✅ 更新包 SHA-256 完整性校验通过"

ditto -x -k "${ZIP_FILE}" "${STAGE_DIR}/extracted"
CANDIDATE_APP="${STAGE_DIR}/extracted/AgentGauge.app"
if [ ! -d "${CANDIDATE_APP}" ]; then
  echo "❌ 安装包结构异常" >&2
  exit 1
fi

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${CANDIDATE_APP}/Contents/Info.plist" 2>/dev/null || true)
APP_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${CANDIDATE_APP}/Contents/Info.plist" 2>/dev/null || true)
APP_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${CANDIDATE_APP}/Contents/Info.plist" 2>/dev/null || true)
if [ "${BUNDLE_ID}" != "com.kahlil.AgentGauge" ] || [ "${APP_VER}" != "${LATEST_VER}" ] || [ "${APP_BUILD}" != "${EXPECTED_BUILD}" ]; then
  echo "❌ 应用元数据与已签名清单不匹配，已中止安装！" >&2
  exit 1
fi

/usr/bin/xattr -cr "${CANDIDATE_APP}" 2>/dev/null || true
if ! codesign --verify --deep --strict "${CANDIDATE_APP}"; then
  echo "❌ 应用代码签名校验失败，已中止安装！" >&2
  exit 1
fi

# Stage on target volume before atomic swap so TARGET_APP is never deleted prior to verified replacement & launch!
rm -rf "${SAME_VOL_STAGE}" 2>/dev/null || true
mv "${CANDIDATE_APP}" "${SAME_VOL_STAGE}"

echo "🔄 正在关闭旧版进程并原子替换安装 v${LATEST_VER}..."
pkill -f "/Applications/AgentGauge.app/Contents/MacOS/AgentGauge" 2>/dev/null || true
sleep 0.4

SWAPPED=0
SWAP_HELPER="${SAME_VOL_STAGE}/Contents/MacOS/AgentGaugeCleanup"
INSTALLED_HELPER="${TARGET_APP}/Contents/MacOS/AgentGaugeCleanup"
if [ -d "${TARGET_APP}" ]; then
  if [ -x "${SWAP_HELPER}" ] && "${SWAP_HELPER}" --atomic-swap "${SAME_VOL_STAGE}" "${TARGET_APP}"; then
    SWAPPED=1
  else
    BACKUP_APP="/Applications/.AgentGauge.backup.$$.app"
    rm -rf "${BACKUP_APP}" 2>/dev/null || true
    if mv "${TARGET_APP}" "${BACKUP_APP}" && mv "${SAME_VOL_STAGE}" "${TARGET_APP}"; then
      SAME_VOL_STAGE="${BACKUP_APP}"
      SWAPPED=1
    else
      [ -d "${BACKUP_APP}" ] && [ ! -d "${TARGET_APP}" ] && mv "${BACKUP_APP}" "${TARGET_APP}" 2>/dev/null || true
      echo "❌ 替换安装失败，已保留原安装" >&2
      exit 1
    fi
  fi
else
  mv "${SAME_VOL_STAGE}" "${TARGET_APP}"
fi

/usr/bin/xattr -cr "${TARGET_APP}" 2>/dev/null || true
touch "${TARGET_APP}" 2>/dev/null || true

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
  rm -rf "${SAME_VOL_STAGE}" 2>/dev/null || true
  echo "✅ AgentGauge v${LATEST_VER} 已验签安装并启动！（后续更新可在菜单栏一键完成）"
  exit 0
fi

# Launch failed -> atomically roll back to previous working installation
echo "⚠️ 新版启动检测失败，正在自动回滚至原版本..." >&2
if [ "${SWAPPED}" -eq 1 ] && [ -d "${SAME_VOL_STAGE}" ]; then
  if [ -x "${INSTALLED_HELPER}" ] && "${INSTALLED_HELPER}" --atomic-swap "${SAME_VOL_STAGE}" "${TARGET_APP}"; then
    rm -rf "${SAME_VOL_STAGE}" 2>/dev/null || true
  else
    FAILED_APP="/Applications/.AgentGauge.failed.$$.app"
    mv "${TARGET_APP}" "${FAILED_APP}" 2>/dev/null || true
    mv "${SAME_VOL_STAGE}" "${TARGET_APP}" 2>/dev/null || true
    rm -rf "${FAILED_APP}" 2>/dev/null || true
  fi
  /usr/bin/open -n "${TARGET_APP}" 2>/dev/null || true
fi
exit 1
