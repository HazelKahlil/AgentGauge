<div align="center">
  <img src="Website/assets/icons/agentgauge.png" width="116" height="116" alt="AgentGauge Icon" />
  <h1>AgentGauge</h1>
  <p>
    <strong>Your AI quota, as clear as water.</strong><br />
    Turns every AI app and coding agent in your Mac's Dock into a living Metal liquid gauge — with 120Hz hover cards and a unified menu bar dashboard.
  </p>

  <p>
    <a href="https://github.com/HazelKahlil/AgentGauge/releases/latest"><img src="https://img.shields.io/badge/release-v1.3.4-141413?style=flat-square" alt="Release v1.3.4" /></a>
    <img src="https://img.shields.io/badge/platform-macOS%2026%20Tahoe%2B-3d3c39?style=flat-square&logo=apple&logoColor=white" alt="macOS 26 Tahoe+" />
    <img src="https://img.shields.io/badge/engine-Swift%206%20%C2%B7%20Metal-587ba3?style=flat-square" alt="Swift 6 + Metal" />
    <img src="https://img.shields.io/badge/supported-30%2B%20AI%20Models%20%26%20Plans-478577?style=flat-square" alt="30+ AI Models & Plans" />
    <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-77756f?style=flat-square" alt="MIT License" /></a>
  </p>

  <p>
    <strong>English</strong> · <a href="./README.zh-CN.md">简体中文</a> · <a href="https://usage.komorebi.date">Official Website</a> · <a href="https://usage.komorebi.date/#changelog">Changelog</a> · <a href="https://github.com/HazelKahlil/AgentGauge/releases/latest">Releases</a>
  </p>

  <br />
  <a href="https://usage.komorebi.date">
    <img src="docs/assets/hero-dock.jpg" width="100%" alt="AgentGauge live Dock liquid gauge and gliding hover card on macOS" />
  </a>
</div>

<br />

## Why AgentGauge?

Stop opening five different apps and settings pages just to discover you are out of credits mid-session. **AgentGauge** places your remaining quota right where your eyes already rest — **the macOS Dock and the menu bar**.

Hover any AI app in your Dock and its icon comes alive as a 16-bit half-float Metal water surface: waves sway with cursor inertia, micro-bubbles refract underneath, the percentage badge cuts its own optical contrast across the waterline, and a native Liquid Glass card glides smoothly alongside your pointer with per-model windows, subscription tier, and reset countdowns. Move your cursor away, and AgentGauge goes completely still (`0%` idle CPU/GPU).

---

## Visual Overview

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/assets/hero-dock.jpg" width="100%" alt="120Hz Hover Quota Cards" />
      <p><strong>120Hz Gliding Hover Cards</strong><br />Plan tier badge, primary window, weekly quota, and per-model bars in one native Liquid Glass card. Progress bars automatically shift to amber below <code>30%</code> and red below <code>15%</code>.</p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/assets/menubar-dashboard.jpg" width="100%" alt="Unified Menu Bar Dashboard" />
      <p><strong>Unified Menu Bar Dashboard</strong><br />Click the wave icon in your menu bar to inspect every monitored app on the left and its full model breakdown on the right. Sweep vertically to switch apps instantaneously.</p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/assets/liquid-styles.jpg" width="100%" alt="11 Curated Optical Liquid Styles" />
      <p><strong>11 Curated Styles · Unified Optical Water</strong><br />Top-timer scrims, dynamic polarity-split numerals, camera aperture sweeps, pixel LED matrices, Braun arc needles, and low-water dodge — all sharing signature refracting bubble water.</p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/assets/apps-matrix.jpg" width="100%" alt="30+ Supported AI Models & Coding Plans" />
      <p><strong>30+ AI Models &amp; Plans · Continuously Growing</strong><br />Official Coding-Plan agents, AI IDEs, foundation-model subscriptions, and API currency balance pools — never fake <code>100%</code> placeholders on local wrappers.</p>
    </td>
  </tr>
</table>

---

## What's New in v1.3.4 (See [CHANGELOG.md](./CHANGELOG.md))

- **Security, Concurrency & Account-Isolation Audit Hardening (`v1.3.4`)**: Enforced fail-closed Ed25519 + SHA-256 verification across all OTA paths (including GitHub fallback & `install.sh`) with kernel-atomic `renamex_np` swaps and auto-rollback; eliminated `WebUsageFetcher` FIFO continuation races, `NativeDockTile.c` bootstrap port leaks, and main-thread Dock IPC blocking; tightened `Cursor` ↔ `Grok Bot`, Antigravity single-pool, `Gemini.app` CLI cache, and per-account multiplier isolation; and wired mandatory delivered-ZIP verification directly into `push_remote_update.sh --publish`.
- **Unified `3x / 5x / 20x` Multipliers, Zero-IPC Dock Optimization & Release Guardrails (`v1.3.3`)**: Unified `3x / 5x / 20x` plan badges and per-`(app, email)` 1-click Menu Bar switching across Antigravity/Gemini (`AI Ultra · 5x / 20x`), ChatGPT/Codex (`Pro Lite · 5x` / `Pro · 20x`), Claude (`Max · 5x / 20x`), Cursor (`Pro+ · 3x` / `Ultra · 20x`), and Grok (`Heavy · 20x`); fixed `agy 1.5.16` delayed `plan_tier` sync; eliminated 60Hz/30Hz main-thread Dock IPC stalls (cached orientation & Mach port, `16ms` send timeout, `<1µs` PID reuse) plus activity-aware CLI caching (~65% fewer idle spawns); and added `AGENTS.md`, single-source `VERSION`, offline `swift test`, and `Scripts/verify_release.sh`.
- **WYSIWYG Water Colors, `Claude / GPT` Model Naming & `AI Ultra · 5x / 20x` Tiers (`v1.3.2`)**: Dock water and icon badges now stay 100% faithful to your selected custom or brand color at every level (keeping `<= 30%` amber / `<= 15%` red warnings cleanly on card progress bars), Antigravity's third-party pool displays real model names **`Claude / GPT`** instead of vendor name `Anthropic`, `Google AI Ultra (5x / 20x)` badges match ChatGPT's multiplier display, and `1970-01-01` sentinel reset timestamps on untouched `100%` pools are properly filtered to `未消耗`.
- **Strict Cross-Product Quota Isolation (`v1.3.1`)**: Completely decoupled standalone consumer `Gemini.app` (`gemini.google.com/usage` current + weekly limits) from `Antigravity` developer pools and decoupled consumer `Grok.app` from `Grok Bot` coding pools, added reset-epoch agreement verification for `Cursor` ↔ `Grok Bot`, stripped chat bubbles/code blocks during web quota scraping to prevent conversational false positives, and locked multi-variant Dock tiles (`Zed` / `Zed Preview`, `WorkBuddy` / `CodeBuddy`) strictly to the hovered bundle ID.
- **Ed25519 Signed Remote Push Auto-Updater (`v1.3.0`)**: Native in-app remote update notifications, one-click verified download (`CryptoKit` Ed25519 + SHA-256), atomic `/Applications/AgentGauge.app` overwrite & seamless restart without Gatekeeper prompts, plus automatic cleanup of older running instances.
- **First-Principles Multi-Pool Quota Engine (`v1.3.0`)**: Separated Antigravity's independent `Gemini` and `Anthropic` quota pools with `<0.5ms` Desktop active-model tracking and 4-mode pool switching (`Auto`, `Min Bottleneck`, `Gemini`, `Anthropic`), fixed Anthropic `0..100` utilization scaling, enforced `min(5h, 7d weekly)` bottleneck dominance across `Claude` & `Codex`, upgraded `Dual-Track HUD` (`#09`), and added full cache invalidation on manual refresh.
- **Zero-Flicker Schmitt-Trigger Dock Handoff (`v1.2.1`)**: Eliminated hover oscillation (`A ↔ B` / `On ↔ Off`) when parking the pointer on the boundary or empty gap between adjacent magnified Dock icons via a single-authority 60Hz `DockAXHitOutcome` state machine with `~17pt` bidirectional hysteresis and inter-icon seam hold.
- **11 Curated Optical-Water Styles**: Pure-icon indicator suite (`Top Timer Scrim`, `Dynamic Split`, `Micro-Halo Text`, `Concentric R-Corner Dodge`, `Aperture Sweep`, `Pixel LED Matrix`, `Dual-Track HUD`, `Braun Arc Needle`, `5-Cell Prism Bar`, `Dynamic Micro-Island`, `Top Energy Brow`) unified onto the signature optical bubble-refraction Metal shader.
- **Gravity-Stabilized 120Hz Physics & Rail Centering**: Critically damped wave equilibrium (`0` async jitter) and constant horizontal hover rail without vertical bounce.
- **Authentic 30+ Model & Coding-Plan Purification + API Balances**: Focused on real metered models & plans; added direct currency balance rendering (`DeepSeek` / `Kimi` `¥` / `$` API balances), GitHub Copilot (`gh api /copilot_internal/user`), Windsurf local Protobuf state, and cached Antigravity `AI Ultra` plan tier detection.
- **Zero-Power Sleep & Self-Healing IPC**: Automatic `NSWorkspace` sleep/screen-lock suspension, 5s Mach Dock-tile circuit breaker, and deterministic subprocess reaping.

---

## Installation

### Download Installer (`.dmg`)

- **GitHub Releases (Primary)**: [**AgentGauge-macOS.dmg**](https://github.com/HazelKahlil/AgentGauge/releases/latest/download/AgentGauge-macOS.dmg) (`v1.3.4`, `2.9 MB`, Apple Silicon / macOS 26+)
- **Official Website Mirror (Fast Global / China CDN)**: [**usage.komorebi.date/downloads/AgentGauge-macOS.dmg**](https://usage.komorebi.date/downloads/AgentGauge-macOS.dmg)
- **One-Line Install / Overwrite Upgrade from Terminal**:
  ```bash
  curl -fsSL https://usage.komorebi.date/install.sh | bash
  ```

1. Open `AgentGauge-macOS.dmg` and drag **AgentGauge** into `/Applications` (or double-click `双击一键覆盖旧版.command` when upgrading from `v1.1–v1.2.1`; `v1.3.0+` supports one-click in-app OTA updates).
2. Launch **AgentGauge** and grant **Accessibility** permission when macOS prompts once (used solely to detect which Dock icon sits under your cursor).
3. *(Optional)* If macOS Gatekeeper displays an unverified developer prompt on first launch, run the following command in Terminal or click **Open Anyway** in **System Settings → Privacy & Security**:
   ```bash
   xattr -cr /Applications/AgentGauge.app
   ```

### Build from Source

Requires **macOS 26 Tahoe+** (SDK 14+ compatible build target) and **Swift 6.0 / Xcode Command Line Tools**:

```bash
git clone https://github.com/HazelKahlil/AgentGauge.git
cd AgentGauge

# Build Release binary & install to /Applications/AgentGauge.app
./Scripts/build_app.sh

# Package a distributable DMG in Website/downloads/
./Scripts/package_dmg.sh
```

---

## Supported Models & Coding Plans (30+ & Growing)

| Category | Vendors & Official Desktop Apps |
| :--- | :--- |
| **Coding Agents & AI IDEs** | ChatGPT / Codex, Antigravity, Claude, Cursor, Grok Bot, Windsurf, WorkBuddy, Trae, Kiro, VS Code (Copilot), Qoder, Zed, Warp, Devin, IntelliJ IDEA, PyCharm, WebStorm |
| **Foundation Models & Token/API Plans** | Gemini, Grok, DeepSeek, Kimi, GLM (ChatGLM), Qwen, Doubao, MiniMax, Perplexity, Le Chat (Mistral), Manus, Poe — *with more providers continuously added* |

---

## Privacy, Permissions & Architecture

AgentGauge is architected to be **100% local and auditable**:

| Concern | How AgentGauge Handles It | Source Reference |
| :--- | :--- | :--- |
| **No Cloud Sync or Telemetry** | Zero AgentGauge accounts, zero analytics SDKs, and zero remote servers. Quota data stays on your Mac. | `Sources/AgentGaugeCore/Providers/` |
| **Why Accessibility Permission?** | Used exclusively via `AXUIElement` hit-testing to identify which Dock icon your cursor hovers over. Never reads screen contents, keystrokes, or other app windows. | `Sources/AgentGaugeCore/AgentGaugeStore.swift` |
| **Non-Destructive Dock Overlays** | Liquid frames are live GPU overlays (`~1.7 ms`/frame on Metal), never permanent edits to `.app` bundles. Quit AgentGauge and every icon restores immediately; `AgentGaugeCleanup` guards against unexpected termination. | `Sources/CNativeDockTile/` · `Sources/AgentGaugeCleanup/` |
| **Zero Cost at Rest** | Rendering runs strictly while hovering the Dock. Move your pointer away and the render loop suspends completely. | `Sources/AgentGaugeCore/` |

---

## Repository Structure

```text
AgentGauge/
├── Sources/
│   ├── CNativeDockTile/      # Low-level macOS Dock tile bridge
│   ├── AgentGaugeCore/       # 16-bit half-float Metal shader, store & 30+ vendor providers
│   ├── AgentGaugeApp/        # MenuBarPopoverView, HoverTooltipPanel & Settings workbench
│   ├── AgentGaugeCleanup/    # Crash-safe Dock icon restoration daemon
│   └── AgentGaugeProbe/      # CLI diagnostics & tile verification tool
├── Website/                  # Bilingual product site & WebGL shader port (usage.komorebi.date)
├── Promo/                    # Remotion 62s 1080p product film project
└── Scripts/                  # Release app bundler (build_app.sh) & DMG packager (package_dmg.sh)
```

---

## License

Released under the [MIT License](./LICENSE).  
All third-party product names, logos, and trademarks belong to their respective owners.
