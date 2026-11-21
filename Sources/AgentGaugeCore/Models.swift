import AppKit
import Foundation

public enum AgentCategory: String, CaseIterable, Sendable {
    case codingAgent = "Coding Agent & IDE"
    case devTools = "JetBrains & 终端"
    case aiAssistant = "AI 桌面客户端"
}

public enum AgentID: String, CaseIterable, Codable, Sendable, Identifiable {
    // Core Coding Agents & AI IDEs (18)
    case codex
    case antigravity
    case cursor
    case grokbot
    case muse
    case claude
    case workbuddy
    case multica
    case hermes
    case windsurf
    case trae
    case kiro
    case zed
    case vscode
    case warp
    case qoder
    case devin
    case xcode

    // JetBrains & Developer Tools (5)
    case intellij
    case pycharm
    case webstorm
    case androidstudio
    case opencode

    // Mainstream Desktop AI Assistants (9)
    case gemini
    case grok
    case deepseek
    case perplexity
    case doubao
    case kimi
    case qwen
    case cherrystudio
    case lmstudio

    // Local LLM, AI Agents & AI Browsers (18)
    case chatcut
    case manus
    case kaze
    case tabbit
    case quark
    case chatglm
    case ollama
    case raycast
    case jan
    case lechat
    case poe
    case chatbox
    case lobechat
    case anythingllm
    case nextchat
    case openwebui
    case gpt4all
    case comfyui

    public var id: String { rawValue }

    public var category: AgentCategory {
        switch self {
        case .codex, .antigravity, .cursor, .grokbot, .muse, .claude, .workbuddy,
             .multica, .hermes, .windsurf, .trae, .kiro, .zed, .vscode, .warp, .qoder, .devin, .xcode:
            return .codingAgent
        case .intellij, .pycharm, .webstorm, .androidstudio, .opencode:
            return .devTools
        case .gemini, .grok, .deepseek, .perplexity, .doubao, .kimi, .qwen, .cherrystudio, .lmstudio,
             .chatcut, .manus, .kaze, .tabbit, .quark, .chatglm, .ollama, .raycast, .jan, .lechat, .poe, .chatbox, .lobechat, .anythingllm, .nextchat, .openwebui, .gpt4all, .comfyui:
            return .aiAssistant
        }
    }

    public var displayName: String {
        switch self {
        case .codex: return "ChatGPT / Codex"
        case .antigravity: return "Antigravity"
        case .cursor: return "Cursor"
        case .grokbot: return "Grok Bot"
        case .muse: return "Muse"
        case .claude: return "Claude"
        case .workbuddy: return "WorkBuddy"
        case .multica: return "Multica"
        case .hermes: return "Hermes"
        case .windsurf: return "Windsurf"
        case .trae: return "Trae"
        case .kiro: return "Kiro"
        case .zed: return "Zed"
        case .vscode: return "VS Code (Copilot)"
        case .warp: return "Warp"
        case .qoder: return "Qoder"
        case .devin: return "Devin Desktop"
        case .xcode: return "Xcode"
        case .intellij: return "IntelliJ IDEA"
        case .pycharm: return "PyCharm"
        case .webstorm: return "WebStorm"
        case .androidstudio: return "Android Studio"
        case .opencode: return "OpenCode / 终端"
        case .gemini: return "Gemini"
        case .grok: return "Grok"
        case .deepseek: return "DeepSeek"
        case .perplexity: return "Perplexity"
        case .doubao: return "豆包 Doubao"
        case .kimi: return "Kimi"
        case .qwen: return "通义千问 Qwen"
        case .cherrystudio: return "Cherry Studio"
        case .lmstudio: return "LM Studio"
        case .chatcut: return "ChatCut"
        case .manus: return "Manus"
        case .kaze: return "Kaze 浏览器"
        case .tabbit: return "Tabbit"
        case .quark: return "夸克 Quark"
        case .chatglm: return "智谱清言"
        case .ollama: return "Ollama"
        case .raycast: return "Raycast AI"
        case .jan: return "Jan"
        case .lechat: return "Le Chat (Mistral)"
        case .poe: return "Poe"
        case .chatbox: return "Chatbox"
        case .lobechat: return "LobeChat"
        case .anythingllm: return "AnythingLLM"
        case .nextchat: return "NextChat"
        case .openwebui: return "Open WebUI"
        case .gpt4all: return "GPT4All"
        case .comfyui: return "ComfyUI Desktop"
        }
    }

    public var shortName: String {
        switch self {
        case .codex: return "Codex"
        case .antigravity: return "Antigravity"
        case .cursor: return "Cursor"
        case .grokbot: return "Grok Bot"
        case .muse: return "Muse"
        case .claude: return "Claude"
        case .workbuddy: return "WorkBuddy"
        case .multica: return "Multica"
        case .hermes: return "Hermes"
        case .windsurf: return "Windsurf"
        case .trae: return "Trae"
        case .kiro: return "Kiro"
        case .zed: return "Zed"
        case .vscode: return "VS Code"
        case .warp: return "Warp"
        case .qoder: return "Qoder"
        case .devin: return "Devin"
        case .xcode: return "Xcode"
        case .intellij: return "IDEA"
        case .pycharm: return "PyCharm"
        case .webstorm: return "WebStorm"
        case .androidstudio: return "Android Studio"
        case .opencode: return "OpenCode"
        case .gemini: return "Gemini"
        case .grok: return "Grok"
        case .deepseek: return "DeepSeek"
        case .perplexity: return "Perplexity"
        case .doubao: return "豆包"
        case .kimi: return "Kimi"
        case .qwen: return "Qwen"
        case .cherrystudio: return "Cherry"
        case .lmstudio: return "LM Studio"
        case .chatcut: return "ChatCut"
        case .manus: return "Manus"
        case .kaze: return "Kaze"
        case .tabbit: return "Tabbit"
        case .quark: return "夸克"
        case .chatglm: return "智谱清言"
        case .ollama: return "Ollama"
        case .raycast: return "Raycast"
        case .jan: return "Jan"
        case .lechat: return "Le Chat"
        case .poe: return "Poe"
        case .chatbox: return "Chatbox"
        case .lobechat: return "LobeChat"
        case .anythingllm: return "AnythingLLM"
        case .nextchat: return "NextChat"
        case .openwebui: return "Open WebUI"
        case .gpt4all: return "GPT4All"
        case .comfyui: return "ComfyUI"
        }
    }

    /// Primary + alternate macOS Bundle Identifiers supported for this agent.
    public var bundleIdentifiers: [String] {
        switch self {
        case .codex: return ["com.openai.codex", "com.openai.chat"]
        case .antigravity: return ["com.google.antigravity"]
        case .cursor: return ["com.todesktop.230313mzl4w4u92"]
        case .grokbot: return ["com.anysphere.sand"]
        case .muse: return ["com.meta.endo"]
        case .claude: return ["com.anthropic.claudefordesktop"]
        case .workbuddy: return ["com.tencent.workbuddy.mac", "com.tencent.codebuddy"]
        case .multica: return ["ai.multica.desktop"]
        case .hermes: return ["com.nousresearch.hermes.setup"]
        case .windsurf: return ["com.exafunction.windsurf"]
        case .trae: return ["com.trae.app", "com.bytedance.trae", "com.trae.cn"]
        case .kiro: return ["dev.kiro.desktop"]
        case .zed: return ["dev.zed.Zed", "dev.zed.Zed-Preview"]
        case .vscode: return ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]
        case .warp: return ["dev.warp.Warp-Stable", "dev.warp.Warp"]
        case .qoder: return ["com.qoder.ide", "com.alibaba.qoder"]
        case .devin: return ["ai.cognition.devin", "com.cognition.devin"]
        case .xcode: return ["com.apple.dt.Xcode"]
        case .intellij: return ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"]
        case .pycharm: return ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"]
        case .webstorm: return ["com.jetbrains.WebStorm"]
        case .androidstudio: return ["com.google.android.studio"]
        case .opencode: return ["ai.opencode.desktop", "com.mitchellh.ghostty", "com.googlecode.iterm2"]
        case .gemini: return ["com.google.GeminiMacOS"]
        case .grok: return ["com.grokapp.desktop", "ai.x.grok"]
        case .deepseek: return ["com.deepseek.dsh", "com.deepseek.chat"]
        case .perplexity: return ["ai.perplexity.mac"]
        case .doubao: return ["com.bytedance.doubao.desktop", "com.bot.doubao", "com.bot.neotix.doubao"]
        case .kimi: return ["com.moonshot.kimi", "cn.moonshot.kimi"]
        case .qwen: return ["com.alibaba.qwen", "com.aliyun.tongyi", "com.alibaba.tongyi"]
        case .cherrystudio: return ["com.kangfenmao.CherryStudio"]
        case .lmstudio: return ["ai.elementlabs.lmstudio"]
        case .chatcut: return ["io.chatcut.desktop"]
        case .manus: return ["ai.manus.agents", "im.manus.desktop"]
        case .kaze: return ["dev.kite.browser"]
        case .tabbit: return ["com.tabbit-ai.Tabbit"]
        case .quark: return ["com.quark.desktop"]
        case .chatglm: return ["com.zhipu.chatglm"]
        case .ollama: return ["com.electron.ollama", "com.ollama.ollama"]
        case .raycast: return ["com.raycast.macos"]
        case .jan: return ["jan.ai.app"]
        case .lechat: return ["ai.mistral.lechat", "ai.mistral.chat"]
        case .poe: return ["com.quora.poe.electron", "com.quora.poe"]
        case .chatbox: return ["xyz.chatboxapp.app"]
        case .lobechat: return ["com.lobehub.lobehub-desktop", "com.lobehub.desktop"]
        case .anythingllm: return ["com.anythingllm", "com.mintplexlabs.anythingllm"]
        case .nextchat: return ["com.yida.chatgpt.next.web"]
        case .openwebui: return ["com.openwebui.desktop", "com.open-webui.desktop"]
        case .gpt4all: return ["io.gpt4all.gpt4all", "ai.nomic.gpt4all"]
        case .comfyui: return ["com.comfyorg.comfyui-electron", "org.comfy.desktop"]
        }
    }

    public var bundleIdentifier: String {
        bundleIdentifiers.first ?? ""
    }

    public func matches(bundleIdentifier bid: String) -> Bool {
        bundleIdentifiers.contains(bid)
    }

    public var defaultAccentHex: String {
        switch self {
        // Calibrated macOS Tahoe Mineral & Titanium Tones (desaturated ~35% chroma for calm optical harmony)
        case .codex: return "#3E8C79"         // Alpine Sage
        case .antigravity: return "#5479B2"   // Sapphire Slate
        case .cursor: return "#7165AD"        // Prism Iris
        case .grokbot: return "#B37452"       // Terracotta Sandstone
        case .muse: return "#4E7CA8"          // Nordic Azure
        case .claude: return "#AD6E54"        // Anthropic Clay
        case .workbuddy: return "#498596"     // Fjord Teal
        case .multica: return "#7A67A6"       // Twilight Amethyst
        case .hermes: return "#A3687E"        // Dusty Rose
        case .windsurf: return "#428E85"      // Surf Mineral Teal
        case .trae: return "#4C9468"          // Moss Jade
        case .kiro: return "#7C62AD"          // Muted Violet
        case .zed: return "#4A6FA5"           // Deep Fjord Blue
        case .vscode: return "#4878A8"        // Steel Azure
        case .warp: return "#4A86A8"          // Mist Sky
        case .qoder: return "#6368A8"         // Slate Indigo
        case .devin: return "#458C86"         // Celadon Teal
        case .xcode: return "#4F7BB0"         // Dev Slate Blue
        case .intellij: return "#AD5F6E"      // Mineral Crimson
        case .pycharm: return "#4A9476"       // Botanical Green
        case .webstorm: return "#468996"      // Glacier Aqua
        case .androidstudio: return "#529672" // Sage Green
        case .opencode: return "#AD824C"      // Warm Ochre
        case .gemini: return "#597AB2"        // Starlight Slate
        case .grok: return "#788494"          // Titanium Silver
        case .deepseek: return "#536DA8"      // Mineral Cobalt
        case .perplexity: return "#3E7C87"    // Slate Teal
        case .doubao: return "#547EB0"        // Mist Blue
        case .kimi: return "#6B7685"          // Graphite Slate
        case .qwen: return "#6A64A8"          // Star Iris
        case .cherrystudio: return "#AD5E5E"  // Muted Garnet
        case .lmstudio: return "#755FA6"      // Mineral Purple
        case .chatcut: return "#7A6BA8"
        case .manus: return "#6B7685"
        case .kaze: return "#4E7FA6"
        case .tabbit: return "#5C7FAE"
        case .quark: return "#5470B0"
        case .chatglm: return "#4F6FB0"
        case .ollama: return "#6E7480"
        case .raycast: return "#B0605E"
        case .jan: return "#B08A4C"
        case .lechat: return "#B57A4E"
        case .poe: return "#7B66AD"
        case .chatbox: return "#B0905C"
        case .lobechat: return "#B07A5A"
        case .anythingllm: return "#727985"
        case .nextchat: return "#5272B0"
        case .openwebui: return "#6A6F78"
        case .gpt4all: return "#8E9A52"
        case .comfyui: return "#9EA24E"
        }
    }

    public var defaultAccentColor: NSColor {
        NSColor.fromHex(defaultAccentHex) ?? NSColor(srgbRed: 0.33, green: 0.48, blue: 0.68, alpha: 1.0)
    }
}

// MARK: - Curated macOS Tahoe Mineral & Titanium Theme Presets (Low Saturation, High Legibility)

public struct MineralColorPreset: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let hex: String

    public init(id: String, name: String, hex: String) {
        self.id = id
        self.name = name
        self.hex = hex
    }

    public var nsColor: NSColor {
        NSColor.fromHex(hex) ?? NSColor(srgbRed: 0.35, green: 0.48, blue: 0.64, alpha: 1.0)
    }

    public static let defaultUIAccentHex = "#587BA3"

    public static let curated: [MineralColorPreset] = [
        MineralColorPreset(id: "mist_blue",   name: "钛雾蓝", hex: "#587BA3"),
        MineralColorPreset(id: "alpine_sage", name: "松石青", hex: "#478577"),
        MineralColorPreset(id: "iris_slate",  name: "暮云紫", hex: "#7268A6"),
        MineralColorPreset(id: "terracotta",  name: "陶土棕", hex: "#B07354"),
        MineralColorPreset(id: "fjord_teal",  name: "冰川青", hex: "#4B8494"),
        MineralColorPreset(id: "dusty_rose",  name: "烟灰粉", hex: "#A36A7B"),
        MineralColorPreset(id: "titanium",    name: "香槟钛", hex: "#8E7F6B")
    ]
}

extension AgentID {

    public var themeColorName: String {
        switch self {
        case .codex: return "OpenAI 翡翠绿"
        case .antigravity: return "Gemini 宝石蓝"
        case .cursor: return "Cursor 棱镜紫"
        case .grokbot: return "Grok Bot 曜橙"
        case .muse: return "Muse 灵眸蓝"
        case .claude: return "Claude 陶土橙"
        case .workbuddy: return "腾讯云青蓝"
        case .multica: return "Multica 矩阵紫"
        case .hermes: return "Hermes 星云粉"
        case .windsurf: return "Windsurf 浪潮青"
        case .trae: return "Trae 极光绿"
        case .kiro: return "Kiro 幻紫"
        case .zed: return "Zed 深海蓝"
        case .vscode: return "VS Code 经典蓝"
        case .warp: return "Warp 霓虹蓝"
        case .qoder: return "Qoder 靛蓝"
        case .devin: return "Devin 碧青"
        case .xcode: return "Xcode 研发蓝"
        case .intellij: return "JetBrains 绯红"
        case .pycharm: return "PyCharm 翠绿"
        case .webstorm: return "WebStorm 湖青"
        case .androidstudio: return "Android 霓绿"
        case .opencode: return "OpenCode 琥珀"
        case .gemini: return "Gemini 星辉蓝"
        case .grok: return "Grok 钛银"
        case .deepseek: return "DeepSeek 深蓝"
        case .perplexity: return "Perplexity 墨青"
        case .doubao: return "豆包晴蓝"
        case .kimi: return "Kimi 曜石灰"
        case .qwen: return "通义星紫"
        case .cherrystudio: return "Cherry 樱桃红"
        case .lmstudio: return "LM Studio 电紫"
        case .chatcut: return "ChatCut 剪影紫"
        case .manus: return "Manus 石墨灰"
        case .kaze: return "Kaze 晴岚蓝"
        case .tabbit: return "Tabbit 雾蓝"
        case .quark: return "夸克 星蓝"
        case .chatglm: return "智谱 深蓝"
        case .ollama: return "Ollama 羊驼灰"
        case .raycast: return "Raycast 珊瑚红"
        case .jan: return "Jan 暖金"
        case .lechat: return "Mistral 橙金"
        case .poe: return "Poe 暮紫"
        case .chatbox: return "Chatbox 杏色"
        case .lobechat: return "Lobe 暖橙"
        case .anythingllm: return "AnythingLLM 钛灰"
        case .nextchat: return "NextChat 宝蓝"
        case .openwebui: return "Open WebUI 墨灰"
        case .gpt4all: return "GPT4All 苔绿"
        case .comfyui: return "Comfy 柠绿"
        }
    }

    public var webLoginURL: URL? {
        switch self {
        case .codex: return URL(string: "https://chatgpt.com/codex/settings/usage")
        case .antigravity: return nil
        case .cursor: return URL(string: "https://cursor.com/dashboard/spending")
        case .grokbot: return URL(string: "https://cursor.com/dashboard/spending")
        case .muse: return URL(string: "https://www.meta.ai")
        case .claude: return URL(string: "https://claude.ai/settings/usage")
        case .workbuddy: return URL(string: "https://www.codebuddy.cn/profile/plan")
        case .multica, .hermes: return nil
        case .windsurf: return URL(string: "https://windsurf.com/subscription/usage")
        case .trae: return URL(string: "https://www.trae.ai/account-setting")
        case .kiro: return URL(string: "https://app.kiro.dev")
        case .zed: return URL(string: "https://zed.dev/account")
        case .vscode: return URL(string: "https://github.com/settings/copilot")
        case .warp: return URL(string: "https://app.warp.dev/billing")
        case .qoder: return URL(string: "https://qoder.com/account")
        case .devin: return URL(string: "https://app.devin.ai/settings/billing")
        case .xcode: return nil
        case .intellij, .pycharm, .webstorm: return URL(string: "https://account.jetbrains.com")
        case .androidstudio: return URL(string: "https://gemini.google.com")
        case .opencode: return nil
        case .gemini: return URL(string: "https://gemini.google.com")
        case .grok: return URL(string: "https://grok.com")
        case .deepseek: return URL(string: "https://platform.deepseek.com/usage")
        case .perplexity: return URL(string: "https://www.perplexity.ai/settings/account")
        case .doubao: return URL(string: "https://www.doubao.com")
        case .kimi: return URL(string: "https://kimi.moonshot.cn")
        case .qwen: return URL(string: "https://chat.qwen.ai")
        case .cherrystudio, .lmstudio: return nil
        case .chatcut: return URL(string: "https://chatcut.io")
        case .manus: return URL(string: "https://manus.im")
        case .kaze: return nil
        case .tabbit: return nil
        case .quark: return URL(string: "https://www.quark.cn")
        case .chatglm: return URL(string: "https://chatglm.cn")
        case .ollama: return nil
        case .raycast: return URL(string: "https://www.raycast.com/pro")
        case .jan: return nil
        case .lechat: return URL(string: "https://chat.mistral.ai")
        case .poe: return URL(string: "https://poe.com")
        case .chatbox: return nil
        case .lobechat: return nil
        case .anythingllm: return nil
        case .nextchat: return nil
        case .openwebui: return nil
        case .gpt4all: return nil
        case .comfyui: return nil
        }
    }

    public var cookieDomainSuffixes: [String] {
        switch self {
        case .codex: return ["chatgpt.com", "openai.com"]
        case .cursor, .grokbot: return ["cursor.com", "grok.com", "x.ai"]
        case .muse: return ["meta.ai", "meta.com"]
        case .claude: return ["claude.ai", "anthropic.com"]
        case .workbuddy: return ["codebuddy.cn", "tencent.com", "workbuddy.cn"]
        case .windsurf: return ["windsurf.com", "codeium.com"]
        case .trae: return ["trae.ai", "trae.cn"]
        case .kiro: return ["kiro.dev"]
        case .zed: return ["zed.dev"]
        case .vscode: return ["github.com"]
        case .warp: return ["warp.dev"]
        case .qoder: return ["qoder.com"]
        case .devin: return ["devin.ai"]
        case .intellij, .pycharm, .webstorm: return ["jetbrains.com"]
        case .androidstudio, .gemini: return ["google.com"]
        case .grok: return ["grok.com", "x.ai"]
        case .deepseek: return ["deepseek.com"]
        case .perplexity: return ["perplexity.ai"]
        case .doubao: return ["doubao.com"]
        case .kimi: return ["moonshot.cn", "kimi.com"]
        case .qwen: return ["qwen.ai", "aliyun.com"]
        default: return []
        }
    }
}

private final class InstalledAppLookupCache: @unchecked Sendable {
    static let shared = InstalledAppLookupCache()
    private let lock = NSLock()
    private var cache: [AgentID: URL?] = [:]
    private var lastScan: Date = .distantPast

    func url(for agentID: AgentID) -> URL? {
        let now = Date()
        lock.lock()
        if now.timeIntervalSince(lastScan) < 45.0, let entry = cache[agentID] {
            lock.unlock()
            return entry
        }
        if now.timeIntervalSince(lastScan) >= 45.0 {
            cache.removeAll(keepingCapacity: true)
            lastScan = now
        }
        lock.unlock()

        var resolved: URL? = nil
        for bid in agentID.bundleIdentifiers {
            if let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                resolved = found
                break
            }
        }

        lock.lock()
        cache[agentID] = resolved
        lock.unlock()
        return resolved
    }
}

public extension AgentID {
    var installedAppURL: URL? {
        InstalledAppLookupCache.shared.url(for: self)
    }

    var isInstalledOnMac: Bool {
        installedAppURL != nil
    }

    static let defaultCoreSet: [AgentID] = [.antigravity, .cursor, .grokbot, .muse, .codex, .claude, .workbuddy]
}

public struct QuotaWindow: Sendable, Equatable {
    public let label: String
    public let remainingPercent: Double // 0...100
    public let resetsAt: Date?
    public let resetText: String?
    public let isPrimary: Bool

    public init(
        label: String,
        remainingPercent: Double,
        resetsAt: Date? = nil,
        resetText: String? = nil,
        isPrimary: Bool = false
    ) {
        self.label = label
        self.remainingPercent = max(0, min(100, remainingPercent))
        self.resetsAt = resetsAt
        self.resetText = resetText
        self.isPrimary = isPrimary
    }

    public func formattedCountdown(now: Date = Date()) -> String {
        if let resetsAt {
            let diff = Int(resetsAt.timeIntervalSince(now))
            if diff <= 0 { return "即将重置" }
            let days = diff / 86400
            let hours = (diff % 86400) / 3600
            let mins = (diff % 3600) / 60
            if days > 0 {
                return "\(days)d \(hours)h"
            } else if hours > 0 {
                return "\(hours)h \(mins)m"
            } else {
                return "\(max(1, mins))m"
            }
        }
        if let resetText, !resetText.isEmpty {
            return resetText
        }
        return "—"
    }
}

public struct QuotaSnapshot: Sendable, Equatable {
    public let agentID: AgentID
    public let remainingPercent: Double? // nil = unauthenticated or unavailable (0...100 drives water level)
    public let creditsRemaining: Int?    // non-nil for Credits-based agents (e.g. WorkBuddy 积分)
    public let creditsTotal: Int?
    public let accountEmail: String?     // Logged-in account email / handle (e.g. hello@example.com)
    public let planTier: String?         // Subscription plan & multiplier (e.g. Google AI Ultra, Pro Lite (5x), Max 20x, Plus)
    public let primaryLabel: String?
    public let resetsAt: Date?
    public let resetText: String?
    public let windows: [QuotaWindow]
    public let subtitle: String?
    public let isWorking: Bool
    public let sourceDescription: String
    public let updatedAt: Date
    public let requiresWebLogin: Bool
    public let errorMessage: String?

    public init(
        agentID: AgentID,
        remainingPercent: Double?,
        creditsRemaining: Int? = nil,
        creditsTotal: Int? = nil,
        accountEmail: String? = nil,
        planTier: String? = nil,
        primaryLabel: String? = nil,
        resetsAt: Date? = nil,
        resetText: String? = nil,
        windows: [QuotaWindow] = [],
        subtitle: String? = nil,
        isWorking: Bool = false,
        sourceDescription: String,
        updatedAt: Date = Date(),
        requiresWebLogin: Bool = false,
        errorMessage: String? = nil
    ) {
        self.agentID = agentID
        self.remainingPercent = remainingPercent.map { max(0, min(100, $0)) }
        self.creditsRemaining = creditsRemaining
        self.creditsTotal = creditsTotal
        self.accountEmail = accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.planTier = planTier?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.primaryLabel = primaryLabel
        self.resetsAt = resetsAt
        self.resetText = resetText
        self.windows = windows
        self.subtitle = subtitle
        self.isWorking = isWorking
        self.sourceDescription = sourceDescription
        self.updatedAt = updatedAt
        self.requiresWebLogin = requiresWebLogin
        self.errorMessage = errorMessage
    }

    public var isCreditsBased: Bool {
        creditsRemaining != nil
    }

    /// Compact pill badge for tight card headers (e.g. "AI Ultra", "Pro Lite · 5x", "Pro · 20x", "Max 20x", "Plus").
    public var compactPlanBadge: String? {
        guard let raw = planTier, !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if lower.contains("google ai ultra") { return "AI Ultra" }
        if lower.contains("google ai pro")   { return "AI Pro" }
        if lower.contains("pro lite") && lower.contains("5x") { return "Pro Lite · 5x" }
        if lower.contains("chatgpt pro") && lower.contains("20x") { return "Pro · 20x" }
        if lower.contains("chatgpt plus")    { return "Plus" }
        if lower.contains("chatgpt team")    { return "Team" }
        if lower.contains("chatgpt go")      { return "Go" }
        if lower.hasPrefix("premium")        { return "Premium" }
        if lower.contains("supergrok heavy") { return "Heavy · 20x" }
        if lower.contains("套餐")            { return raw.replacingOccurrences(of: "套餐", with: "").trimmingCharacters(in: .whitespaces) }
        if raw.count > 12 {
            return String(raw.prefix(11)) + "…"
        }
        return raw
    }

    /// Combined single-line account + subscription summary.
    public var formattedIdentityLine: String? {
        var parts: [String] = []
        if let tier = planTier, !tier.isEmpty {
            parts.append(tier)
        }
        if let acct = accountEmail, !acct.isEmpty {
            parts.append(acct)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Formatted value for Settings Bento Card (e.g. "500 积分" or "85%").
    public func formattedCardValue(showPercentageSign: Bool) -> String {
        if let credits = creditsRemaining {
            return "\(credits) 积分"
        }
        guard let rem = remainingPercent else { return "—" }
        return "\(Int(round(rem)))\(showPercentageSign ? "%" : "")"
    }

    /// Compact formatted value for the 144x144 Dock Icon (never appends % for Credits!).
    public func formattedDockIconValue(showPercentageSign: Bool) -> String {
        if let credits = creditsRemaining {
            if credits >= 10_000 {
                return String(format: "%.0fk", Double(credits) / 1000.0)
            } else if credits >= 1_000 {
                let k = Double(credits) / 1000.0
                return k.truncatingRemainder(dividingBy: 1.0) < 0.05
                    ? String(format: "%.0fk", k)
                    : String(format: "%.1fk", k)
            }
            return "\(credits)"
        }
        guard let rem = remainingPercent else { return "" }
        return "\(Int(round(rem)))\(showPercentageSign ? "%" : "")"
    }

    /// Formatted summary for Hover Tooltip & Menu Bar (e.g. "剩 500/500 积分" or "剩 85%").
    public func formattedTooltipValue(showPercentageSign: Bool) -> String {
        if let credits = creditsRemaining {
            if let total = creditsTotal, total > 0 {
                return "剩 \(credits)/\(total) 积分"
            }
            return "剩 \(credits) 积分"
        }
        guard let rem = remainingPercent else { return "—" }
        return "剩 \(Int(round(rem)))\(showPercentageSign ? "%" : "")"
    }

    public func formattedCountdown(now: Date = Date()) -> String {
        if let resetsAt {
            let diff = Int(resetsAt.timeIntervalSince(now))
            if diff <= 0 { return "即将重置" }
            let days = diff / 86400
            let hours = (diff % 86400) / 3600
            let mins = (diff % 3600) / 60
            if days > 0 {
                return "\(days)d \(hours)h"
            } else if hours > 0 {
                return "\(hours)h \(mins)m"
            } else {
                return "\(max(1, mins))m"
            }
        }
        if let resetText, !resetText.isEmpty {
            return resetText
        }
        return "—"
    }
}

public protocol UsageProvider: Sendable {
    var agentID: AgentID { get }
    func fetchSnapshot() async -> QuotaSnapshot
}

public enum AnimationIntensity: String, CaseIterable, Codable, Sendable, Identifiable {
    case interactive = "interactive"
    case always = "always"
    case reduced = "reduced"

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .interactive: return "跟随交互 / 工作中动画"
        case .always: return "始终保持微动画"
        case .reduced: return "静止（无动画）"
        }
    }
}

public enum TooltipDetailMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case multiModel = "multiModel"
    case primaryOnly = "primaryOnly"
    case off = "off"

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .multiModel: return "多模型 / 多窗口明细"
        case .primaryOnly: return "仅显示主/周额度"
        case .off: return "关闭上方悬停详情"
        }
    }
}

public enum DockBadgeStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case concentricAutoDodge = "concentricAutoDodge"
    case cornerQuarterTopLeft = "cornerQuarterTopLeft"
    case cornerQuarterBottomLeft = "cornerQuarterBottomLeft"
    case semiLeft = "semiLeft"
    case semiRight = "semiRight"
    case semiTop = "semiTop"
    case semiBottom = "semiBottom"
    case concentricTopLeft = "concentricTopLeft"
    case concentricCircle = "concentricCircle"
    case haloText = "haloText"
    case pureSplitText = "pureSplitText"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .concentricAutoDodge:     return "同心 R角 · 智能避让"
        case .cornerQuarterTopLeft:    return "左上 R角 · 扇形圆"
        case .cornerQuarterBottomLeft: return "左下 R角 · 扇形圆"
        case .semiLeft:                return "正左边缘 · 半圆"
        case .semiRight:               return "正右边缘 · 半圆"
        case .semiTop:                 return "正上边缘 · 半圆"
        case .semiBottom:              return "正下边缘 · 半圆"
        case .concentricTopLeft:       return "左上 · 同心 R角"
        case .concentricCircle:        return "车辆提示 · 正圆"
        case .haloText:                return "纯数字 · 微晶描边"
        case .pureSplitText:           return "纯数字 · 动态反相"
        }
    }

    public var shortTitle: String {
        switch self {
        case .concentricAutoDodge:     return "同心R角(避让)"
        case .cornerQuarterTopLeft:    return "左上扇圆"
        case .cornerQuarterBottomLeft: return "左下扇圆"
        case .semiLeft:                return "正左半圆"
        case .semiRight:               return "正右半圆"
        case .semiTop:                 return "正上半圆"
        case .semiBottom:              return "正下半圆"
        case .concentricTopLeft:       return "左上同心R角"
        case .concentricCircle:        return "同心正圆"
        case .haloText:                return "微晶描边字"
        case .pureSplitText:           return "动态反相字"
        }
    }

    public var symbolName: String {
        switch self {
        case .concentricAutoDodge:     return "inset.filled.bottomleft.rectangle"
        case .cornerQuarterTopLeft:    return "circle.tophalf.filled"
        case .cornerQuarterBottomLeft: return "circle.bottomhalf.filled"
        case .semiLeft:                return "circle.lefthalf.filled"
        case .semiRight:               return "circle.righthalf.filled"
        case .semiTop:                 return "inset.filled.topthird.square"
        case .semiBottom:              return "inset.filled.bottomthird.square"
        case .concentricTopLeft:       return "inset.filled.topleft.rectangle"
        case .concentricCircle:        return "smallcircle.filled.circle"
        case .haloText:                return "textformat.123"
        case .pureSplitText:           return "circle.lefthalf.striped.horizontal.inverse"
        }
    }
}

public enum NumberColorMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case smartInvert = "smartInvert"
    case smokeGray = "smokeGray"
    case obsidianBlack = "obsidianBlack"
    case adaptiveInk = "adaptiveInk"
    case white = "white"

    public static var studioCases: [NumberColorMode] {
        [.smartInvert, .smokeGray, .obsidianBlack, .adaptiveInk]
    }

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .smartInvert:   return "智能反转"
        case .smokeGray:     return "高级烟灰"
        case .obsidianBlack: return "深黑曜石"
        case .adaptiveInk:   return "主题水色"
        case .white:         return "纯白"
        }
    }
}

public extension NSColor {
    static func fromHex(_ hex: String) -> NSColor? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let val = UInt64(cleaned, radix: 16) else {
            return nil
        }
        let r = CGFloat((val >> 16) & 0xFF) / 255.0
        let g = CGFloat((val >> 8) & 0xFF) / 255.0
        let b = CGFloat(val & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    var srgbHexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Int(round(max(0, min(1, c.redComponent)) * 255.0))
        let g = Int(round(max(0, min(1, c.greenComponent)) * 255.0))
        let b = Int(round(max(0, min(1, c.blueComponent)) * 255.0))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// APCA / Apple Liquid Glass HIG Adaptive Tonal Ink:
    /// Achieves 11:1–16:1 luminance contrast without hue clashing or muddy shadows.
    /// - Light icons (e.g. Antigravity / ChatGPT): ultra-deep same-hue editorial ink (Midnight Navy, Deep Forest, etc.)
    /// - Dark icons (e.g. Cursor): crisp luminous ice-tinted white in the same tonal family.
    func adaptiveDigitColor(isDarkIcon: Bool) -> NSColor {
        let srgb = usingColorSpace(.sRGB) ?? self
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        if isDarkIcon {
            // Crisp luminous ice-tinted white — 15:1+ contrast on dark icons, harmonious with theme hue
            let tintS: CGFloat = min(0.14, s * 0.18)
            return NSColor(hue: h, saturation: tintS, brightness: 1.0, alpha: 1.0)
        } else {
            // Ultra-deep same-hue editorial ink — 11:1–15:1 contrast over translucent water AND bare white, zero hue clash!
            let inkS: CGFloat = s < 0.08 ? 0.08 : min(0.88, max(0.68, s))
            let inkB: CGFloat = 0.24
            return NSColor(hue: h, saturation: inkS, brightness: inkB, alpha: 1.0)
        }
    }
}

public extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func decodeJWTPayload() -> [String: Any]? {
        let segments = split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = base64.count % 4
        if rem > 0 {
            base64 += String(repeating: "=", count: 4 - rem)
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}
