# AgentGauge Engineering Rules & Release Invariants

This repository is a native macOS Swift 6 / Metal Dock & Menu Bar quota monitor (`com.kahlil.AgentGauge`).
Every change—especially across quota providers, Dock rendering/hover physics, and releases—MUST obey the five engineering invariants below. They exist because each one prevented real production regressions audited in the 2026-11 engineering retrospective.

---

## 1. Strict Domain, Product, Account & Coordinate Boundary Isolation

1. **Product Boundaries**: Never borrow, merge, or fall back across distinct commercial products even when signed into the same vendor account:
   - Consumer `Gemini.app` (`com.google.GeminiMacOS`) MUST NEVER read `Antigravity.app` (`com.google.antigravity`) or `Gemini CLI` developer pools; it parses `gemini.google.com/usage` directly.
   - Consumer `Grok.app` (`com.grokapp.desktop`) MUST NEVER read `Grok Bot.app` (`com.anysphere.sand`) coding pools.
   - `Cursor` ↔ `Grok Bot` sharing requires matching account email AND `<= 300s` reset-epoch agreement.
2. **Quota Pool & Model Naming**:
   - Keep Antigravity's `Gemini` pool and third-party `Claude / GPT` pool strictly separated.
   - User-facing Antigravity third-party pool labels MUST display real model families (`Claude / GPT`), NEVER the vendor name `"Anthropic"`.
3. **Per-Account Keying**:
   - Store user overrides and cached banners keyed by `(agentID, lowercasedEmail)` (e.g. `planMultipliersByAccount`, `cachedBannerPlanTiersByEmail`), NEVER globally per app. Switching accounts must never inherit the prior account's tier or multiplier.
4. **Bundle ID Fidelity on Multi-Variant Apps**:
   - Every `nativeChannel.draw(...)` call in `OverlayManager.swift` (both initial hover wake AND the 30fps `tick()` loop) MUST pass `preferredBundleID` so multi-variant apps (`Zed` / `Zed Preview`, `WorkBuddy` / `CodeBuddy`, `ChatGPT` / `Codex`) never paint the wrong sibling icon.
5. **WYSIWYG Dock Water Color**:
   - `NativeIconRenderer` MUST ALWAYS honor the user's chosen water color (or app brand theme color) regardless of quota level. NEVER reintroduce hardcoded `<= 30%` amber or `<= 15%` red water-tint overrides inside the Dock icon renderer; low-quota warning colors belong exclusively to hover cards, menu bar rows, and Settings progress bars.
6. **Single-Authority Dock Hover Coordinate Frame**:
   - Never blend live magnified `AXFrame` coordinates with unmagnified `cachedDockTiles` coordinates when deciding hover transitions. All Dock hover switches must flow through `DockAXHitOutcome` and `OverlayManager.shouldCommitNeighborSwitch(...)` Schmitt-trigger hysteresis.

---

## 2. External Data & CLI Contract Hygiene

1. **Zero Fake `100%`**: Unauthenticated, unreachable, or unparsable providers MUST return `remainingPercent = nil`. Never fabricate `100%`.
2. **Reject Unset Epoch Sentinels**: Any parsed reset timestamp earlier than `2000-01-01T00:00:00Z` (e.g. `1970-01-01T00:00:00Z` emitted by `agy` for untouched `100%` buckets) MUST be treated as `nil` (`未消耗`), NEVER as an expired date (`即将重置`), and MUST NOT bust caches.
3. **Exact Provider Units & Series-Gate Bottleneck Law**:
   - Anthropic `/api/oauth/usage` `utilization` is ALWAYS in `0...100` percentage points (never multiply values `<= 1.0` by `100`).
   - Multi-window account-wide caps (`Claude` and `Codex`) MUST enforce `effectiveRemaining = min(5h, 7d weekly)` so an exhausted weekly cap is never masked as `100%` after a 5h reset.
4. **Boundary-Honest Percentage Rounding**:
   - Always format display integers via `QuotaSnapshot.displayPercentInt(_:)` (`(0.05%, 1%) -> 1%`, `(99%, 99.95%) -> 99%`).
5. **Preserve Tier Multipliers**:
   - `QuotaSnapshot.compactPlanBadge` MUST extract and preserve explicit `2x / 3x / 5x / 10x / 20x` tokens before any length truncation.
6. **Anti-Noise DOM Scraping & Non-Destructive CLI Probes**:
   - `GenericWebUsageProvider` MUST strip chat messages, `<pre>`/`<code>`, and markdown prose nodes before scanning percentages.
   - Never send modal-opening commands (e.g. `/credits`) to `agy` while waiting for async `plan_tier` emission.

---

## 3. MainActor Zero-IPC & Subprocess Performance Budget

1. **Zero Uncached IPC in Render / Hover Loops**:
   - Hot loops (`OverlayManager.tick` at 30Hz, Dock hover poll at 60Hz, tooltip spring at 120Hz) MUST NOT perform uncached `UserDefaults(suiteName:)`, `NSRunningApplication.runningApplications`, `NSWorkspace`, or `bootstrap_look_up` IPC on `@MainActor`.
   - `DockLocator.currentOrientation()` MUST stay cached (`>= 2s` TTL).
   - `NativeTileChannel` MUST reuse active tile PIDs via `kill(pid, 0) == 0` fast-path, dispatch Dock Mach draw/release IPC off `@MainActor` onto a dedicated serial `ipcQueue`, retain failed releases in `pendingReleases` until confirmed released or target exited, and cache the `com.apple.dock.server` Mach send right in `NativeDockTile.c` while ALWAYS deallocating the copied `TASK_BOOTSTRAP_PORT` send right (`mach_port_deallocate(mach_task_self(), bp)`).
   - `mach_msg` worst-case total send/release timeout in `NativeDockTile.c` MUST remain `<= 24ms` (16ms draw; 16ms + at most one 8ms stale-port retry on release).
   - `WebUsageFetcher` MUST transfer evaluation-slot ownership atomically without clearing `isEvaluating` before waking the next FIFO waiter, and MUST guard every async callback with a monotonic request ID.
2. **Activity-Aware CLI Caching, Keychain Timeouts & Deterministic Reaping**:
   - Expensive CLI probes (`agy`, `codex app-server`) and `/usr/bin/security` Keychain reads MUST use bounded timeouts, activity-aware caching, and deterministic `SIGTERM -> SIGKILL -> waitUntilExit` reaping.
3. **Fail-Closed Cryptographic OTA & Atomic Rollback**:
   - Every update source (primary CDN, GitHub Releases fallback, `Website/install.sh`) MUST verify Ed25519 release signatures + SHA-256 + inner bundle version/build/codesign (zero unsigned fallbacks).
   - Upgrades MUST stage on the target volume, swap atomically (`renamex_np`), verify launch liveness, and roll back automatically on launch failure.
   - `Scripts/push_remote_update.sh --publish` MUST invoke `Scripts/verify_release.sh --require-artifacts` before any upload or CDN deploy.

---

## 4. Single Source of Truth for Versioning & Secrets

1. **Single Version Source (`VERSION`)**:
   - `VERSION` at repo root (`VERSION=X.Y.Z`, `BUILD=BBB`) is the sole canonical version source.
   - To bump a release version, run `./Scripts/sync_version.sh <X.Y.Z> <BBB>` instead of hand-editing HTML, JS, READMEs, and build scripts.
   - Read runtime app version from `Bundle.main.infoDictionary?["CFBundleShortVersionString"]` rather than hardcoding literals in Swift providers or logs.
2. **Secret Hygiene**:
   - Never commit `~/.config/agentgauge/release_ed25519.key`, `.dmg`, `.zip`, or personal account email addresses/tokens into git or tests.

---

## 5. Mandatory Pre-Release Verification Gate

Before committing a release, creating a GitHub Release, or deploying Cloudflare Pages OTA updates:

1. Run offline unit tests (`< 2s`):
   ```bash
   swift test
   ```
2. Build & sign the release bundle + OTA manifest:
   ```bash
   ./Scripts/push_remote_update.sh
   ```
3. Pass the full automated release gate (must exit `0` with zero failures):
   ```bash
   ./Scripts/verify_release.sh
   ```
   (Add `--live` when validating live local provider readings on the development machine.)
