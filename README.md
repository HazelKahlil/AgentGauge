# AgentGauge

**Your AI quota, as clear as water.** · **AI 额度，清澈如水。**

Website: [https://usage.komorebi.date](https://usage.komorebi.date) · Latest release: **v1.1.0** (macOS 26 Tahoe+)

AgentGauge turns every AI app and coding agent in your Mac's Dock into a living liquid gauge — powered by a 16-bit half-float Metal shader, native Liquid Glass hover cards, and a unified menu bar dashboard. Supporting **50** AI apps and IDEs locally on your Mac.

---

## Highlights · 核心特性

- **Living Liquid Dock Tiles · 原生 Dock 液态水位**：通过 Metal 半精度管线（单帧约 `1.7 ms`）实时渲染双层水波、光学折射、微泡、动态反相字与低水位自动避让同心 R 角徽标。
- **Zero Idle Cost · 离开即零占用**：仅在鼠标悬停 Dock 图标时唤醒渲染；移开视线即刻释放覆写并休眠，崩溃守护进程 `AgentGaugeCleanup` 确保退出后 100% 还原原生图标。
- **Hover Cards & Menu Bar Dashboard · 悬停分模型卡片与菜单栏看板**：一眼查看订阅套餐（`AI Ultra`、`Max 20x`、`Pro Lite · 5x`、`Ultra · 20x` 等）、各模型独立窗口进度与重置倒计时。
- **50 Supported Apps · 支持 50 款主流工具**：涵盖 Claude、ChatGPT / Codex、Cursor、Antigravity、Gemini、Grok、Windsurf、Trae、Kiro、Zed、VS Code、Xcode、JetBrains 全家桶、DeepSeek、Kimi、Qwen、Ollama、Raycast、ComfyUI 等。
- **Local by Design · 本地优先**：直接读取各应用在本机已有的登录态，无需注册 AgentGauge 账号，不做任何云端同步。

---

## Build & Package · 编译与打包

```bash
# Build & install /Applications/AgentGauge.app (Release)
./Scripts/build_app.sh

# Package distributable DMG installer
./Scripts/package_dmg.sh
```

## Project Layout · 目录结构

- `Sources/AgentGaugeCore` — Metal 液态着色器、Dock 定位与 Mach 图块通道、50 款应用配额 Provider 与状态存储
- `Sources/AgentGaugeApp` — macOS 26 Tahoe 原生菜单栏看板（`MenuBarPopoverView`）与设置工作台（`SettingsWindowView`）
- `Website/` — 中英双语产品官网（含 WebGL 实时液态着色器移植版，部署于 `usage.komorebi.date`）
- `Promo/` — Remotion 产品宣传片工程
- `Scripts/` — Release 应用构建与 DMG 打包脚本
