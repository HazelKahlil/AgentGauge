# Changelog / 更新日志

All notable changes to **AgentGauge** are documented here.  
**AgentGauge** 的所有重要版本变更均记录于此。

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases adhere to [Semantic Versioning](https://semver.org/).  
格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，版本号采用[语义化版本](https://semver.org/lang/zh-CN/)。

---

## [1.2.1] - 2026-11-22

### Fixed / 修复

- **Dock icon boundary & inter-icon seam no longer oscillate or blink (`A ↔ B` / `On ↔ Off`)**: Parking the pointer on the midpoint or empty glass gap between two adjacent Dock icons while macOS Dock Magnification is enabled no longer flickers between neighbors. `OverlayManager` previously blended 30Hz live magnified `AXFrame` coordinates with 60Hz unmagnified baseline `cachedDockTiles`, allowing the two coordinate frames to disagree along icon edges. `DockLocator` now classifies all five `AXUIElementCopyElementAtPosition` outcomes (`.matched`, `.dockGap`, `.untrackedItem`, `.outsideDock`, `.openMenu`) under a single-authority 60Hz state machine with a `3.8–5.5pt` Schmitt-trigger interior penetration threshold (`~17pt` total bidirectional deadband) and inter-icon seam hold.  
  **修复 Dock 相邻图标交界与中间缝隙处的来回闪烁跳变问题**：开启 macOS Dock 放大特效时，将鼠标停在两枚相邻图标中间或缝隙处不再发生 `A ↔ B` 反复切换或悬停卡片闪烁。此前 `OverlayManager` 同时混用了 30Hz 实时放大态 `AXFrame` 与 60Hz 未放大基线缓存 `cachedDockTiles`，两套坐标系在图标边缘产生竞争。现重构 `DockLocator` 五态分类状态机（命中受控图标、图标间空隙、非受控图标、离开 Dock、右键菜单），由单一 60Hz 权威状态机配合 `3.8–5.5pt` 施密特触发器（双向约 `17pt` 迟滞死区）与缝隙保持带彻底消除临界震荡。

### Added / 新增

- **Official Website Changelog (`#changelog`) & Repository `CHANGELOG.md`**: Added an interactive bilingual release timeline on [usage.komorebi.date/#changelog](https://usage.komorebi.date/#changelog) and a canonical Keep-a-Changelog file in the repository root.  
  **新增官网更新日志板块（`#changelog`）与仓库 `CHANGELOG.md`**：在产品官网上线中英双语版本演进时间轴，并在仓库根目录维护标准更新日志。

### Changed / 优化

- **Multi-Style Opening in the 62s Product Film & `30+` Ecosystem Framing**: Re-rendered the opening scenes, live Dock demo, and 2×2 draining quartet of the 1080p Remotion film so 6 distinct optical-water indicator styles appear side-by-side right from the start, paired with `30+` continuously expanding AI model & Coding-Plan framing.  
  **升级 62 秒产品宣传片多样式片头与 `30+` 持续扩展矩阵**：重制片头特写、实景 Dock 6 图标同屏混搭与 2×2 四宫格同步放水演示，开篇即呈现顶栏倒计时、像素 LED 点阵、博朗圆弧指针、双轨微仪表、动态反相字与同心 R 角胶囊的自由组合，并将厂商矩阵统一升级为 `30+` 持续接入表述。

---

## [1.2.0] - 2026-11-22

### Added / 新增

- **11 Curated Optical-Water Dock Styles**: Replaced experimental geometric semicircles with 11 pure-icon indicator designs — `Top Timer Scrim` (`截图顶栏时间`), `Dynamic Split` (`动态反相字`), `Micro-Halo Text` (`微晶描边字`), `Concentric R-Corner Dodge` (`同心 R 角避让`), `Aperture Sweep` (`光圈扇叶扫描`), `Pixel LED Matrix` (`像素 LED 点阵`), `Dual-Track HUD` (`双轨微仪表`), `Braun Arc Needle` (`博朗圆弧指针`), `5-Cell Prism Bar` (`底部 5 格晶块`), `Dynamic Micro-Island` (`顶部灵动微岛`), and `Top Energy Brow` (`顶部弧形光眉`) — all sharing the signature 16-bit half-float Metal bubble-refraction water shader (`waterMode = 1.0`).  
  **新增 11 款纯图标精选光学水波样式**：移除早期实验性几何半圆与外白圈边框，定制「截图顶栏时间、动态反相字、微晶描边字、同心 R 角（避让）、光圈扇叶扫描、像素 LED 点阵、双轨微仪表、博朗圆弧指针、底部 5 格晶块、顶部灵动微岛、顶部弧形光眉」11 款纯图标样式，全系共享招牌双层折射气泡水波。
- **First-Class API Currency Balances & Expanded Native Providers**: Added `balanceDisplay` and `dockBalanceShort` to `QuotaSnapshot` for currency-denominated API balance pools (`DeepSeek` and `Kimi` `¥` / `$` balances, e.g. `¥28.50` in cards and `¥29` on Dock tiles), local `GitHub Copilot` quota via `gh api /copilot_internal/user`, `Windsurf` local `state.vscdb` Protobuf parsing, `MiniMax` Coding Plan support, and complete `256×256` bundled fallback icons.  
  **新增官方 API 货币余额一等公民展示与多家原生 Provider**：支持 DeepSeek / Kimi 官方货币余额池（悬停卡片显示精确 `¥28.50`、Dock 图标显示紧凑 `¥29`），新增 VS Code (Copilot) 本地 `gh` 配额读取、Windsurf 本地 Protobuf 状态解析、MiniMax 接入，并内置全量 `256×256` 高清离线兜底图标。

### Changed / 优化

- **First-Principles Metering Catalog Purification (Zero Fake `100%`)**: Audited the entire app catalog and purged non-metered local browsers, orchestrators, and BYOK/offline shells (`Kaze`, `Multica`, `Muse`, `ChatCut`, `Ollama`, `LM Studio`, etc.). Unauthenticated providers strictly return `remainingPercent = nil` rather than fabricating `100%`.  
  **第一性原理配额目录提纯与「零假 100%」铁律**：全面核查并剔除本地浏览器、编排器与无计费体系的 BYOK 空壳客户端，严格聚焦拥有真实订阅配额、Coding Plan 积分与官方 API 余额的模型厂商；未登录或无凭证时绝不伪造 `100%`。
- **Gravity-Stabilized Liquid Physics & Adaptive Low-Water Contrast**: Removed async `AX` writes to `lastCursorX`/`tiltVel`, locked gravity equilibrium `targetTilt = 0`, tuned near-critical spring damping (`stiffness = 20, damping = 8.4`, wave speed `1.12×`), and boosted scrim contrast on white/light icons (`ChatGPT`, `Antigravity`) at low water (`14%–24%`).  
  **重力稳态液面物理与浅色图标低水位对比度增强**：消除异步坐标回写引发的水面抖动，锁定水平重力平衡态与近临界阻尼弹簧，并为纯白/浅色图标在 `14%–24%` 低水位区间自动加深底衬可读性。
- **Zero-Power Sleep & Self-Healing Mach IPC**: Added `NSWorkspace` sleep/screen-lock suspension, a 5-second `NativeTileChannel` Mach IPC circuit breaker (`3` consecutive `kern_return_t` errors), strict DNS label-boundary cookie matching in `WebUsageFetcher`, and deterministic `SIGTERM → SIGKILL → waitUntilExit` subprocess reaping.  
  **合盖休眠零功耗与底层自愈防护**：新增系统睡眠/锁屏自动挂起唤醒、Dock 图块 Mach 通道 5 秒断路自愈、严格 DNS 域名边界 Cookie 匹配及子进程确定性回收。

### Fixed / 修复

- **Restored Antigravity & Gemini `AI Ultra` Plan Tier Detection**: Replaced raw `openpty` (which lacked a controlling TTY for Ink's TUI) with unbuffered `/usr/bin/script -q -F /dev/null` + `/credits` header redraw, pure-Swift scalar ANSI stripping, `AntigravityCLISingleFlight` actor deduplication, and a 24h per-account `UserDefaults` tier cache.  
  **修复 Antigravity 与 Gemini `AI Ultra` 订阅套餐等级识别**：采用无缓冲 `script -q -F` 伪终端配合纯 Swift 标量状态机剥离 ANSI 控制序列，并引入 `AntigravityCLISingleFlight` 并发合并与 24 小时账号级缓存。
- **Eliminated ChatGPT White-Squircle Seam**: Resolved a horizontal optical discontinuity across bright white app icons in `NativeIconRenderer`.  
  **修复 ChatGPT 纯白图标断层问题**：消除亮白底色图标在水线过渡处的断层伪影。

---

## [1.1.2] - 2026-11-21

### Changed / 优化

- **120Hz Critically-Damped Horizontal Hover Rail & Per-App Anchor Lock**: Decoupled `NSHostingView` intrinsic content sizing from `NSPanel` frame origin calculation so `bottomY` stays locked to a single horizontal rail across the Dock (eliminating vertical jumps when switching between `Grok Bot` and `WorkBuddy`), and locked `centerX` per hovered app once AX-confirmed so Dock magnification breathing never wobbles the card.  
  **120Hz 悬停卡片水平导轨锁定与放大防抖**：将 SwiftUI 自适应尺寸测量与 `NSPanel` 锚点定位彻底解耦，左右切换不同高度卡片时底边严格锁定同一水平导轨；并在单应用 AX 确认后锁定水平中心，彻底消除 Dock 放大微呼吸导致的卡片晃动。
- **Unified Website Utility Capsule & Open-Source Documentation**: Unified the GitHub + Language switcher capsule in the navbar, added asset cache-busting, published bilingual `README.md` / `README.zh-CN.md`, and licensed under MIT.  
  **官网导航胶囊整合与开源双语文档**：统一顶部导航栏 GitHub 与语言切换胶囊组件，补充中英双语 README 图文架构说明与 MIT 开源协议。

---

## [1.1.0] - 2026-11-20

### Added / 新增

- **Native macOS 26 Tahoe Release & 16-Bit Half-Float Metal Dock Shader**: Real-time dual-wave optical liquid rendering (`~1.7 ms`/frame), 24 refracting micro-bubbles, low-water auto-dodge, `0%` CPU/GPU cost when away from the Dock, and crash-safe `AgentGaugeCleanup` icon restoration daemon.  
  **macOS 26 Tahoe 原生首发与 16-bit 半精度 Metal 液态着色器**：单帧约 `1.7 ms` 实时双层波浪与微泡色散折射渲染、低水位自动避让、离开 Dock 即刻零占用休眠，以及 `AgentGaugeCleanup` 异常退出自动还原守护进程。
- **Unified Menu Bar Dashboard, Settings Workbench & Interactive Website**: Single-piece Liquid Glass menu bar popover (`MenuBarPopoverView`), live badge customization studio, WebGL shader port (`Liquid Lab`), and 62-second 1080p Remotion product film at [usage.komorebi.date](https://usage.komorebi.date).  
  **菜单栏全局看板、原生设置工作台与交互式官网**：一体成型液态玻璃菜单栏弹窗、实时水位样式工作台，以及搭载浏览器实时 WebGL 液态实验室的产品官网。
