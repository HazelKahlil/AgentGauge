<div align="center">
  <img src="Website/assets/icons/agentgauge.png" width="116" height="116" alt="AgentGauge 图标" />
  <h1>AgentGauge</h1>
  <p>
    <strong>AI 额度，清澈如水。</strong><br />
    将 Mac Dock 里的每一款 AI 应用与编程智能体，变成一枚实时流动的原生 Metal 液态仪表——悬停即见分模型余量，顶部菜单栏全局一触即达。
  </p>

  <p>
    <a href="https://github.com/HazelKahlil/AgentGauge/releases/latest"><img src="https://img.shields.io/badge/版本-v1.1.0-141413?style=flat-square" alt="Release v1.1.0" /></a>
    <img src="https://img.shields.io/badge/系统-macOS%2026%20Tahoe%2B-3d3c39?style=flat-square&logo=apple&logoColor=white" alt="macOS 26 Tahoe+" />
    <img src="https://img.shields.io/badge/引擎-Swift%206%20%C2%B7%20Metal-587ba3?style=flat-square" alt="Swift 6 + Metal" />
    <img src="https://img.shields.io/badge/已支持-50%20款%20AI%20应用-478577?style=flat-square" alt="50 款 AI 应用" />
    <a href="./LICENSE"><img src="https://img.shields.io/badge/开源协议-MIT-77756f?style=flat-square" alt="MIT License" /></a>
  </p>

  <p>
    <a href="./README.md">English</a> · <strong>简体中文</strong> · <a href="https://usage.komorebi.date/?lang=zh">产品官网</a> · <a href="https://usage.komorebi.date/?lang=zh#lab">在线液态实验室</a> · <a href="https://github.com/HazelKahlil/AgentGauge/releases/latest">下载安装包</a>
  </p>

  <br />
  <a href="https://usage.komorebi.date/?lang=zh">
    <img src="docs/assets/hero-dock.jpg" width="100%" alt="AgentGauge 原生 macOS Dock 液态水位与悬停额度卡片" />
  </a>
</div>

<br />

## 为什么做 AgentGauge？

别再挨个点开五六个应用和网页后台，才在写代码写到一半时发现额度早已见底。**AgentGauge** 把所有 AI 工具的剩余配额，放在你目光本就停留的地方——**macOS 的 Dock 栏与顶部菜单栏**。

鼠标轻轻掠过 Dock 上的 AI 应用图标，16 位半精度 Metal 管线即刻唤醒双层液态水面：波浪随指针惯性轻晃，微泡在水下折射微光，百分比数字穿过水线时自动完成光学反相，上方液态玻璃卡片以 120Hz 丝滑跟随鼠标，一眼看清订阅套餐、5 小时/周限额、各模型独立进度与重置倒计时。移开鼠标，渲染即刻休眠，闲置占用严格归零。

---

## 核心体验一览

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/assets/hero-dock.jpg" width="100%" alt="120Hz 丝滑跟随悬停卡片" />
      <p><strong>120Hz 悬停卡片 · 分模型明细</strong><br />订阅等级徽章（AI Ultra / Pro Lite · 5x / Max 20x 等）、主窗口额度、周限额与各模型独立进度条收进同一张原生液态玻璃卡片。低于 <code>30%</code> 自动转琥珀色预警，低于 <code>15%</code> 亮红提醒。</p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/assets/menubar-dashboard.jpg" width="100%" alt="顶部菜单栏全局看板" />
      <p><strong>菜单栏里的全局看板</strong><br />点击系统顶部菜单栏的水位图标，左侧纵览全部已监控应用与活跃绿点，右侧实时联动多模型进度条，鼠标上下滑过即可丝滑切换，支持单应用独立暂停与一键刷新。</p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/assets/liquid-styles.jpg" width="100%" alt="11 种几何样式与低水位自动避让" />
      <p><strong>11 种几何样式 · 4 种色调 · 低水位避让</strong><br />每一枚徽标均严格贴合 macOS 图标圆角曲率裁切。余量低于 <code>30%</code> 时，同心 R 角徽标自动滑向顶部角落，绝不遮挡应用图标本体。</p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/assets/apps-matrix.jpg" width="100%" alt="支持 50 款主流 AI 应用" />
      <p><strong>50 款主流工具 · 一枚仪表统管</strong><br />覆盖编程智能体、主流 IDE、JetBrains 全家桶与桌面/本地大模型客户端，按 macOS Bundle ID 自动识别本机已登录状态。</p>
    </td>
  </tr>
</table>

---

## 下载与安装

### 方式一：直接下载安装包（`.dmg`）

- **官网全球 / 国内高速直链（Cloudflare CDN 推荐）**：[**AgentGauge-v1.1.0-macOS.dmg**](https://usage.komorebi.date/downloads/AgentGauge-v1.1.0-macOS.dmg)（`3.0 MB`）
- **GitHub Releases 下载**：[**AgentGauge-v1.1.0-macOS.dmg**](https://github.com/HazelKahlil/AgentGauge/releases/latest/download/AgentGauge-v1.1.0-macOS.dmg)

1. 打开 `AgentGauge-v1.1.0-macOS.dmg`，将 **AgentGauge** 拖入 `/Applications`（应用程序）文件夹。
2. 首次启动时按系统提示授予一次 **辅助功能（Accessibility）** 权限（仅用于判断鼠标当前悬停在哪个 Dock 图标上）。
3. *(可选)* 若首次打开时遇到 macOS Gatekeeper 开发者验证提示，可在「系统设置 → 隐私与安全性」中点击**仍要打开**，或在终端执行：
   ```bash
   xattr -cr /Applications/AgentGauge.app
   ```

### 方式二：从源码编译

环境要求：**macOS 26 Tahoe 或更新版本**，已安装 **Swift 6.0 / Xcode Command Line Tools**：

```bash
git clone https://github.com/HazelKahlil/AgentGauge.git
cd AgentGauge

# 编译 Release 版本并安装至 /Applications/AgentGauge.app
./Scripts/build_app.sh

# 打包可分发的 DMG 安装镜像（输出至 Website/downloads/）
./Scripts/package_dmg.sh
```

---

## 已支持的 50 款应用

| 类别 | 支持列表 |
| :--- | :--- |
| **编程智能体与 IDE（18）** | Claude, ChatGPT / Codex, Cursor, Antigravity, Grok Bot, Muse, WorkBuddy, Multica, Hermes, Windsurf, Trae, Kiro, Zed, VS Code, Warp, Qoder, Devin, Xcode |
| **JetBrains 与终端（5）** | IntelliJ IDEA, PyCharm, WebStorm, Android Studio, OpenCode |
| **AI 桌面助手与本地运行时（27）** | Gemini, Grok, DeepSeek, Perplexity, 豆包 (Doubao), Kimi, 通义千问 (Qwen), Cherry Studio, LM Studio, ChatCut, Manus, Kaze, Tabbit, 夸克 (Quark), 智谱清言 (ChatGLM), Ollama, Raycast AI, Jan, Le Chat, Poe, Chatbox, LobeChat, AnythingLLM, NextChat, Open WebUI, GPT4All, ComfyUI |

---

## 隐私边界与架构审计

AgentGauge 从底层设计上坚持 **100% 本地运行、源码完全可审计**：

| 安全关切 | AgentGauge 的实现边界 | 对应源码路径 |
| :--- | :--- | :--- |
| **零云端同步 · 零遥测上报** | 无需注册 AgentGauge 账号，不接入任何第三方统计 SDK，不向任何外部服务器上传配额或凭证。 | `Sources/AgentGaugeCore/Providers/` |
| **为什么需要辅助功能权限？** | 仅通过 `AXUIElement` 检测鼠标当前悬停在哪个 Dock 图标上；绝不读取屏幕画面、键盘输入或其他窗口内容。 | `Sources/AgentGaugeCore/AgentGaugeStore.swift` |
| **绝不永久修改应用图标** | 液态水位为实时 GPU 图块叠加层（Metal 单帧约 `1.7 ms`），不改动原 `.app` 包内资源；退出即刻复原，并内置 `AgentGaugeCleanup` 守护进程防止异常退出残留。 | `Sources/CNativeDockTile/` · `Sources/AgentGaugeCleanup/` |
| **离开视线即零占用** | 仅在指针悬停 Dock 时运行渲染循环；鼠标移开后立即挂起休眠。 | `Sources/AgentGaugeCore/` |

---

## 目录结构

```text
AgentGauge/
├── Sources/
│   ├── CNativeDockTile/      # macOS 原生 Dock 图块底层桥接
│   ├── AgentGaugeCore/       # 16-bit 半精度 Metal 液态着色器、状态存储与 50 款应用 Provider
│   ├── AgentGaugeApp/        # 菜单栏全局看板 (MenuBarPopoverView)、悬停卡片与设置工作台
│   ├── AgentGaugeCleanup/    # 崩溃安全的原生 Dock 图标自动还原守护进程
│   └── AgentGaugeProbe/      # 命令行诊断与图块渲染校验工具
├── Website/                  # 中英双语产品官网与 WebGL 实时液态着色器移植版 (usage.komorebi.date)
├── Promo/                    # Remotion 62 秒 1080p 产品宣传片工程
└── Scripts/                  # Release 构建脚本 (build_app.sh) 与 DMG 打包脚本 (package_dmg.sh)
```

---

## 开源协议

本项目基于 [MIT License](./LICENSE) 开源发布。  
文中提及的所有第三方产品名称、商标与应用图标均归其各自所有者所有。
