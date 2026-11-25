# Changelog / 更新日志

All notable changes to **AgentGauge** are documented here.  
**AgentGauge** 的所有重要版本变更均记录于此。

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases adhere to [Semantic Versioning](https://semver.org/).  
格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，版本号采用[语义化版本](https://semver.org/lang/zh-CN/)。

---

## [1.3.5] - 2026-11-25

### Fixed / 修复

- **Restored Anodized Mineral Plan Nameplate Contrast in Menu Bar Popover**: Replaced SwiftUI `Menu(.borderlessButton)` around `PlanTierBadgePill` (which stripped the dark smoked-mineral capsule background on macOS 26 Tahoe, leaving washed-out white text) with a native `.buttonStyle(.plain)` + AppKit `NSMenu` dropdown (`InteractivePlanBadgeButton`) so `Pro Lite · 5x` / `AI Ultra · 20x` nameplates render at full contrast while remaining 1-click switchable.  
  **修复菜单栏套餐铭牌透明看不清的问题**：移除会剥离胶囊深色矿石背景的 SwiftUI `Menu(.borderlessButton)`，改用原生 `.buttonStyle(.plain)` 保留完整深色阳极氧化矿石铭牌并在点击时直接弹出原生 `NSMenu`，兼顾高对比度与一键倍率切换。

---

## [1.3.4] - 2026-11-25

### Security & Reliability / 安全与可靠性加固

- **End-to-End Ed25519 Release Signing Across All OTA & Installer Paths (`UpdateManager`, `install.sh`)**: Removed unsigned GitHub Release fallback (`UpdateManager` now fetches and Ed25519-verifies GitHub's uploaded `latest.json` manifest and checks extracted bundle version/build/codesign & TeamIdentifier on disk hot-reloads); upgraded `Website/install.sh` with a zero-dependency Ed25519 verifier (fail-closed) and mandatory SHA-256 + `codesign` checks.  
  **全链路 Ed25519 强制验签（OTA + GitHub 回退 + 一行脚本安装器）**：消除未验签回退路径，GitHub Releases 回退源与 `Website/install.sh` 统一执行 Ed25519 签名 + SHA-256 + 解包后版本/代码签名校验（无验签能力或验签失败直接拦截）；磁盘替换自动热重启同步核验签名团队一致性。
- **Kernel-Atomic `renamex_np` Bundle Swap & Auto-Rollback**: Added `--atomic-swap` (`renamex_np(..., RENAME_SWAP)`) to `AgentGaugeCleanup`, staging updates on the target volume and verifying new process launch before deleting the previous app (automatically rolling back if launch fails) across OTA updates, `install.sh`, and DMG one-click upgraders.  
  **内核级 `renamex_np` 原子交换与启动失败自动回滚**：OTA 更新、终端一行安装器与 DMG 一键助手统一改为同卷暂存 + 内核原子交换，确认新版拉起存活后才清理旧包，启动异常自动无损回滚。

### Fixed / 修复

- **Concurrency, Mach Port & Subprocess Hardening**:
  - Fixed `WebUsageFetcher` FIFO ownership handoff gap and added per-request generation IDs + strict cancellation guards so concurrent web refreshes never orphan continuations or stall `refreshAll()`.
  - Fixed `TASK_BOOTSTRAP_PORT` Mach send-right leak (`mach_port_deallocate(bp)`) in `NativeDockTile.c`, moved Mach draw/release IPC onto an ordered off-main-thread `ipcQueue` with `<= 24ms` worst-case release budget, and tracked failed releases in `pendingReleases` so watchdog/main-process compensation never forgets an icon.
  - Guarded `ClaudeProvider` Keychain `/usr/bin/security` queries behind file-token fallback + `2.5s` hard timeout & reaping; guarded `UpdateManager.checkForUpdates` with generation checks so background checks never clobber `.downloading`/`.installing` progress.
  **并发、Mach 端口与子进程全量加固**：修复 `WebUsageFetcher` 队列所有权空档与回调串台导致的刷新卡死；修复 `NativeDockTile.c` 泄漏 `TASK_BOOTSTRAP_PORT` send right，将 Dock Mach 通信迁出主线程并增加 `pendingReleases` 补偿机制；为 `ClaudeProvider` Keychain 查询补齐 `2.5s` 硬超时与按需触发；为 `UpdateManager` 补齐代次守卫，防止后台检查覆盖下载/安装进度。
- **Account, Pool & Product Boundary Isolation**:
  - Hardened `Cursor` ↔ `Grok Bot` sharing behind a single strict predicate requiring exact identity + BOTH valid reset timestamps within `<= 300s`, and exact `sand.client.slice.account.<slot>.weekly-usage.cache` matching (never falling back to an old account blob).
  - Scoped `Cursor` & `Codex` caches/single-flight and `AgentGaugeStore` transient-error preservation strictly by account identity + request generation; prevented `AntigravityProvider` from borrowing the sibling pool when a fixed pool is missing; tagged `GeminiSnapshotCache` by source (`consumerWeb` vs `developerCLI`) so installing `Gemini.app` immediately rejects cached CLI quota.
  - Strictly scoped plan multipliers to `(agentID, confirmedEmail)` with a single application point in `AgentGaugeStore` (clean `5x -> 自动` recovery, zero cross-product leakage); unified `>= 2000-01-01` reset-date sanitization inside `QuotaSnapshot` / `QuotaWindow` across all providers; aligned Menu Bar login actions with each provider's actual auth mechanism (CLI/desktop vs WebKit).
  **账号、模型池与跨产品边界彻底隔离**：统一 `Cursor ↔ Grok Bot` 共享校验（严格精确槽位/邮箱 + 双有效重置时间 `<= 300s`），禁止新槽位回落旧账号缓存；`Cursor` / `Codex` 缓存与 Store 暂态报错保留严格按账号身份与代次隔离；修复 Antigravity 固定池缺数据时借用另一池的问题；`GeminiSnapshotCache` 按来源打标防安装桌面版后串读 CLI 缓存；套餐倍率收敛为单一生效点并严格按 `(应用, 确认邮箱)` 独立保存；全量 Provider 统一过滤 `1970` 哨兵时间戳，并按实际鉴权方式修正菜单栏登录引导。
- **Website Resilience & Fail-Closed Release Tooling**: Wrapped `localStorage` access in `Website/js/app.js` against storage-disabled browsers; made `Scripts/sync_version.sh` validate every file in memory before atomic writes (`--check` shared by `verify_release.sh`); and wired mandatory fail-closed release + delivered-ZIP inner-bundle verification directly into `Scripts/push_remote_update.sh --publish`.  
  **官网无痕模式容错与不可绕过发布门禁**：为官网 `localStorage` 读写补齐异常兜底；升级 `sync_version.sh` 先全量内存校验再原子落盘；`push_remote_update.sh --publish` 强制串联 `verify_release.sh` 并实际解包检验交付 ZIP 内 `.app` 的版本、构建号与代码签名。

---

## [1.3.3] - 2026-11-25

### Added / 新增

- **Engineering Guardrails, Single Version Source (`VERSION`) & Fast Offline `swift test` Suite**: Added repository-level `AGENTS.md` engineering invariants, single-source `VERSION` + `Scripts/sync_version.sh`, a 12-case `AgentGaugeCoreTests` offline unit test target (`<2s`), and `Scripts/verify_release.sh` pre-release automated gate verifying version parity, static invariants, unit tests, hysteresis, and Ed25519 OTA signatures before any release.  
  **沉淀项目工程规范（`AGENTS.md`）、单一版本源（`VERSION`）与 `swift test` 自动化发布门禁**：新增根级 `AGENTS.md` 硬约束规则、`Scripts/sync_version.sh` 单源版本号同步脚本、覆盖 12 项核心回归不变量的离线单元测试集 `AgentGaugeCoreTests`，以及发布前自动校验版本一致性、静态反回归规则、施密特防抖与 Ed25519 OTA 签名的 `Scripts/verify_release.sh` 门禁。

### Changed / 优化

- **Zero-IPC 60Hz/30Hz Dock Hover Loop & Activity-Aware CLI Caching**: Eliminated uncached `@MainActor` IPC calls in hot Dock hover/animation loops by caching `DockLocator.currentOrientation()` (`3s` TTL), reusing `NativeTileChannel` active tiles via `<1µs` `kill(pid, 0)` PID liveness checks, caching the `com.apple.dock.server` Mach port in `NativeDockTile.c` with a `16ms` send timeout (down from `100ms`), and gating `agy` / `codex app-server` subprocess launches behind local DB/history mtime activity caches (~65% fewer idle CLI spawns).  
  **零阻塞 60Hz/30Hz Dock 悬停性能优化与活动感知 CLI 缓存**：移除主线程高频循环中的未缓存跨进程 IPC（`DockLocator.currentOrientation()` 增加 `3s` 缓存、`NativeTileChannel` 通过 `kill(pid, 0)` `<1µs` 复用活跃图块、`NativeDockTile.c` 缓存 `com.apple.dock.server` Mach 端口并将发送超时由 `100ms` 压缩至 `16ms`），同时为 `Antigravity` / `Codex` 引入基于本地数据库/历史文件 mtime 的活动感知缓存，闲置期后台 CLI 唤醒次数降低约 `65%`。

### Fixed / 修复

- **Unified Cross-Platform `3x / 5x / 20x` Plan Multiplier Engine, `agy 1.5.16` `plan_tier` Sync & `tick()` Multi-Variant Tile Lock**: Unified subscription multiplier detection (`compactPlanBadge` never truncates `3x / 5x / 20x`) and per-`(agent, email)` overrides across **Antigravity / Gemini (`AI Ultra · 5x / 20x`)**, **ChatGPT / Codex (`Pro Lite · 5x` / `Pro · 20x`)**, **Claude (`Max · 5x / 20x`)**, **Cursor (`Pro+ · 3x` / `Ultra · 20x`)**, and **Grok Bot / Grok (`Heavy · 20x`)**; made the Menu Bar plan pill directly clickable to switch multipliers in `<1ms` when a vendor API omits the tier suffix; fixed the `agy 1.5.16` delayed `plan_tier` race & email-isolated cache; and closed the remaining `OverlayManager.tick()` multi-variant `preferredBundleID` omission.  
  **全平台统一 `3x / 5x / 20x` 套餐倍率引擎、`agy 1.5.16` 套餐异步补读与 `tick()` 多变体图块锁定**：统一适配 **Antigravity / Gemini（`AI Ultra · 5x / 20x`）**、**ChatGPT / Codex（`Pro Lite · 5x` / `Pro · 20x`）**、**Claude（`Max · 5x / 20x`）**、**Cursor（`Pro+ · 3x` / `Ultra · 20x`）** 与 **Grok Bot / Grok（`Heavy · 20x`）** 的倍数自动解析与防截断展示；在菜单栏顶部套餐徽章与设置详情均支持一键切换倍率并按「应用 + 邮箱」独立记忆；同步修复 `agy 1.5.16` 切换账号时 `plan_tier` 延迟写入竞态与 `OverlayManager.tick()` 遗漏 `preferredBundleID` 的多变体绘制边界。

---

## [1.3.2] - 2026-11-24

### Fixed / 修复

- **WYSIWYG Dock Water Color (No Forced Amber/Red Override on Dock Icons)**: Removed the hardcoded `<= 30%` amber and `<= 15%` red water-tint overrides inside `NativeIconRenderer` so Dock liquid water and icon badges always stay 100% faithful to your selected custom color or app brand theme color regardless of quota level, while keeping `<= 30%` amber and `<= 15%` red warning bars cleanly inside hover cards, menu bar rows, and Settings cards.  
  **修复低水位强制改变 Dock 水色的问题（颜色选择器 100% 所见即所得）**：移除 `NativeIconRenderer` 在剩余额度 `<= 30%` / `<= 15%` 时强制将整团水体和图标徽标覆盖为黄/红色的逻辑；现在无论余量高低，Dock 水波始终忠实呈现你选择的颜色或应用主题色，低额度变橙/变红预警统一保留在悬停卡片、菜单栏与设置进度条上。
- **Antigravity Real Model Pool Naming (`Claude / GPT`), `Google AI Ultra (5x / 20x)` Tier Badges & `1970-01-01` Epoch Sentinel Fix**: Renamed Antigravity's third-party model pool from the vendor name `"Anthropic"` to its actual model family **`Claude / GPT`** (`Claude / GPT · 周限额`, `Claude / GPT · 5h 限额`, switcher pill `Claude/GPT`), added full `Google AI Ultra (5x)` / `Google AI Ultra (20x)` compact badge (`AI Ultra · 5x` / `AI Ultra · 20x`) and Settings detail tier switcher support (matching `ChatGPT Pro Lite (5x)`), and filtered out Unix epoch `1970-01-01T00:00:00Z` sentinels emitted by `agy` on untouched `100%` weekly/5h pools so they honestly read `未消耗` instead of falsely displaying `即将重置` and bypassing cache.  
  **修正 Antigravity 模型池命名（`Claude / GPT`）、支持 `AI Ultra · 5x / 20x` 档位与 `1970` 时间戳修复**：将 Antigravity 第三方模型池由厂商名「Anthropic」更正为实际模型名 **`Claude / GPT`**；新增 `Google AI Ultra (5x / 20x)` 档位徽章（`AI Ultra · 5x` / `AI Ultra · 20x`）与邮箱副标题完整展示（与 ChatGPT 保持一致，并支持在详情弹窗一键切换 `自动 / 5x / 20x`）；同时过滤 `agy` 对未消耗 `100%` 池返回的 `1970-01-01` 哨兵重置时间，消除误标「即将重置」与重复穿透缓存的问题。

---

## [1.3.1] - 2026-11-23

### Fixed / 修复

- **Strict Product-Boundary Quota Isolation (`Gemini.app` vs `Antigravity`, `Grok.app` vs `Grok Bot`)**: Completely decoupled standalone consumer `Gemini.app` (`com.google.GeminiMacOS`) from `Antigravity.app` (`com.google.antigravity`) and `Gemini CLI` (`cloudcode-pa`), and decoupled consumer `Grok.app` (`com.grokapp.desktop`) from Anysphere's coding agent `Grok Bot.app` (`com.anysphere.sand`). Even under the same Google AI Ultra or xAI subscription, consumer chat apps and developer coding agents maintain separate billing buckets and reset epochs; `GeminiProvider` now parses `gemini.google.com/usage` (`当前用量 / Current usage` + `每周限额 / Weekly limit`) directly with `min(current, weekly)` bottleneck dominance, while `GrokBotProvider` ↔ `CursorProvider` additionally verifies `<= 300s` reset-epoch agreement before sharing unified quota readings.  
  **严格跨产品独立额度池硬隔离（`Gemini.app` vs `Antigravity`、`Grok.app` vs `Grok Bot`）**：彻底解耦消费级 `Gemini.app`（`com.google.GeminiMacOS`）与开发者 `Antigravity.app` / `Gemini CLI` 的算力池，并解耦消费级对话端 `Grok.app`（`com.grokapp.desktop`）与编程智能体 `Grok Bot.app`（`com.anysphere.sand`）的周限额池——即便同属一个 Google AI Ultra 或 xAI 账号，不同产品线亦拥有各自独立的计费桶与重置周期；`GeminiProvider` 现直连解析 `gemini.google.com/usage`（「当前用量」+「每周限额」取 `min` 瓶颈），`Grok Bot` ↔ `Cursor` 互通则额外增加重置时间戳一致性校验（偏差 `<= 5 分钟` 才视为同一合并池）。
- **Chat-Bubble False-Positive Prevention, Console Billing URLs & Multi-Variant Dock Tile Targeting**: `GenericWebUsageProvider` now strips user chat messages, `<pre>`/`<code>` blocks, and `.prose`/`.markdown-body` nodes before quota extraction so percentages discussed inside conversations are never mistaken for account quota, adds `360s` snapshot caching + trailing currency code parsing (`CNY`/`RMB`/`USD`/`元`), updates `Qwen` (`bailian.console.aliyun.com/#/efm/coding_plan`) and `MiniMax` (`platform.minimaxi.com/user-center/payment/balance`) billing URLs, and locks `NativeTileChannel.draw` strictly to the hovered Dock icon's exact `bundleID` when multi-variant apps (`Zed` vs `Zed Preview`, `WorkBuddy` vs `CodeBuddy`) coexist on the Dock.  
  **防对话文本误采、控制台账单直连校准与多变体 Dock 磁贴精准投递**：`GenericWebUsageProvider` 在提取网页额度前自动剥离聊天消息气泡、代码块与 Markdown 正文，杜绝对话中提及的百分比被误判为账户配额，补齐缓存与后置币种单位（`CNY`/`RMB`/`USD`/`元`）识别，校准千问百炼 Coding Plan 与 MiniMax 余额页直达地址；同时令 `NativeTileChannel` 严格锁定鼠标当前悬停的精确 `bundleID`，避免同系多变体应用（如 `Zed` 与 `Zed Preview`）并存时点亮相邻未悬停图标。

---

## [1.3.0] - 2026-11-22

### Added / 新增

- **Cryptographically Signed Remote Push Auto-Updater (`UpdateManager`)**: Added native in-app remote update notifications (menu bar indicator dot, one-click popover banner, and Settings version inspector) backed by Ed25519 digital signatures (`CryptoKit`) + SHA-256 verification over `usage.komorebi.date/updates/latest.json` with automatic GitHub Releases fallback, atomic `/Applications/AgentGauge.app` replacement without Gatekeeper re-quarantine, automatic takeover/cleanup of older `v1.1.0–v1.2.1` memory processes, on-disk bundle replacement hot-restart, evergreen CDN redirects (`_redirects`), and a one-line installer/upgrader (`curl -fsSL https://usage.komorebi.date/install.sh | bash`).  
  **新增 Ed25519 数字签名远程推送热更新系统（`UpdateManager`）**：支持在菜单栏角标、弹窗横幅与设置顶部接收远程版本推送，基于 `CryptoKit` Ed25519 签名 + SHA-256 双重校验静默下载更新包、原子覆盖 `/Applications/AgentGauge.app` 并自动重启（免重复触发 Gatekeeper 弹窗）；同时支持启动自动接管清理 `v1.1.0–v1.2.1` 旧版驻留进程、手动拖入覆盖自动热重启、历史旧链接自动 302 跳转至最新包，以及一行命令覆盖升级（`curl -fsSL https://usage.komorebi.date/install.sh | bash`）。

### Fixed / 修复

- **Antigravity `Gemini` vs `Anthropic` Dual-Pool Isolation & Real Desktop Model Tracking**: Fixed a major cross-pool masking issue where Antigravity's independent `Gemini` (`gemini-5h`, `gemini-weekly`) and `Anthropic` (`3p-5h`, `3p-weekly`) quota pools could hide one another because `agy` CLI reported its own CLI default model rather than the active model in Antigravity Desktop. `AntigravityProvider` now reads the active Desktop conversation model in `<0.5ms` upon Dock hover / Menu Bar wake, aligns `isPrimary` strictly with the limiting bucket, labels untouched rolling `5h` buckets honestly as `未消耗`, and exposes a 4-mode pool selector (`跟随模型` / `双池最低` / `Gemini` / `Anthropic`).  
  **修复 Antigravity 内 `Gemini` 与 `Anthropic` 双独立模型池隔离与真实活跃模型识别**：解决此前依赖 `agy` CLI 默认模型而忽略 Antigravity 桌面端当前实际使用模型（例如 Anthropic 周限仅剩 `2%` 却仍显示 Gemini 池 `63%`）的问题。现支持在鼠标靠近 Dock 或打开菜单栏时以 `<0.5ms` 实时识别桌面端当前对话模型池，严格对齐主读数与高亮行，将未消耗的 `5h` 滚动窗标为 `未消耗`，并在菜单栏与设置卡片提供四档主读数池切换（`跟随模型` / `双池最低` / `Gemini` / `Anthropic`）。
- **Anthropic `Claude` `0..100` Utilization Scaling & Series-Gate Bottleneck Law (`Claude` & `Codex`)**: Fixed a `100×` scaling bug in `ClaudeProvider` when `utilization <= 1.0%` (which previously misread `0.5%–1.0%` used as `50%–100%` used), and enforced `min(5h, 7d weekly)` bottleneck dominance across both `ClaudeProvider` and `CodexProvider` so an exhausted weekly cap is never masked as `100%` after a 5-hour session reset.  
  **修复 Claude 低消耗区间 `100×` 比例跳变及 Claude / Codex 多窗口木桶串联定律**：修复 `ClaudeProvider` 在 `utilization <= 1.0%` 时误按小数放大 100 倍导致刚用 `1%` 就掉成 `0%` 的计算缺陷；并在 `Claude` 与 `Codex` 中统一执行 `min(5h 会话窗口, 7d 周总额度)` 木桶串联规则，杜绝周限额见底但 5 小时窗口重置后假满血显示 `100%` 的误报。
- **Standalone `Gemini`, `Cursor` & `Grok Bot` Pool Isolation, `Dual-Track HUD` & Manual Refresh**: Isolated standalone `Gemini` from Antigravity's `Anthropic` pool, guarded `Grok Bot` ↔ `Cursor` live quota sharing behind strict account-slot verification with single-flight deduplication, fixed `Dual-Track HUD` (`#09`) duplicating the weekly bar instead of rendering `5h + Weekly` (or `Gemini + Anthropic` on Antigravity) with low-quota alert colors, restored the missing progress bar in `.primaryOnly` tooltip mode, added boundary-honest percentage rounding (`0.1%–0.9% → 1%`, `99.1%–99.9% → 99%`), and made Manual Refresh invalidate all in-memory provider caches immediately.  
  **修复独立 `Gemini` / `Cursor` / `Grok Bot` 账号池边界、双轨微仪表与手动刷新缓存穿透**：隔离独立 `Gemini` 应用与 Antigravity 的 Anthropic 池；为 `Grok Bot` 与 `Cursor` 增加严格同账号槽位校验与并发请求合并；修复 `双轨微仪表` 在周限成为瓶颈时双轨重复显示同一数值及低水位不变红的问题；补齐「仅主额度」悬停模式缺失的进度条；引入临界诚实取整（未耗尽不显示 `0%`、已消耗不显示 `100%`），并让手动点击「刷新」立即穿透全部内存缓存。

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
