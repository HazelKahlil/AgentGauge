import AppKit
import Foundation

public enum AgentCategory: String, CaseIterable, Sendable {
    case codingAgent = "Coding Agent & AI IDE"
    case modelVendor = "自研大模型 · 官方套餐与 API"
}

public enum AgentID: String, CaseIterable, Codable, Sendable, Identifiable {
    // I · Official Coding Agents & AI IDEs with Subscription / Token Plans / Credits (17)
    case codex
    case antigravity
    case claude
    case cursor
    case grokbot
    case windsurf
    case workbuddy
    case trae
    case kiro
    case vscode
    case qoder
    case zed
    case warp
    case devin
    case intellij
    case pycharm
    case webstorm

    // II · First-Party Foundation Model Vendors & Official Token/Compute Plans (12)
    case gemini
    case grok
    case deepseek
    case kimi
    case chatglm
    case qwen
    case doubao
    case minimax
    case perplexity
    case lechat
    case manus
    case poe

    public var id: String { rawValue }

    public var category: AgentCategory {
        switch self {
        case .codex, .antigravity, .claude, .cursor, .grokbot, .windsurf, .workbuddy,
             .trae, .kiro, .vscode, .qoder, .zed, .warp, .devin, .intellij, .pycharm, .webstorm:
            return .codingAgent
        case .gemini, .grok, .deepseek, .kimi, .chatglm, .qwen, .doubao, .minimax,
             .perplexity, .lechat, .manus, .poe:
            return .modelVendor
        }
    }

    public var displayName: String {
        switch self {
        case .codex: return "ChatGPT / Codex"
        case .antigravity: return "Antigravity"
        case .claude: return "Claude"
        case .cursor: return "Cursor"
        case .grokbot: return "Grok Bot"
        case .windsurf: return "Windsurf"
        case .workbuddy: return "WorkBuddy"
        case .trae: return "Trae"
        case .kiro: return "Kiro"
        case .vscode: return "VS Code (Copilot)"
        case .qoder: return "Qoder"
        case .zed: return "Zed"
        case .warp: return "Warp"
        case .devin: return "Devin"
        case .intellij: return "IntelliJ IDEA"
        case .pycharm: return "PyCharm"
        case .webstorm: return "WebStorm"
        case .gemini: return "Gemini"
        case .grok: return "Grok"
        case .deepseek: return "DeepSeek"
        case .kimi: return "Kimi"
        case .chatglm: return "智谱 GLM"
        case .qwen: return "通义千问 Qwen"
        case .doubao: return "豆包 Doubao"
        case .minimax: return "MiniMax"
        case .perplexity: return "Perplexity"
        case .lechat: return "Le Chat (Mistral)"
        case .manus: return "Manus"
        case .poe: return "Poe"
        }
    }

    public var shortName: String {
        switch self {
        case .codex: return "Codex"
        case .antigravity: return "Antigravity"
        case .claude: return "Claude"
        case .cursor: return "Cursor"
        case .grokbot: return "Grok Bot"
        case .windsurf: return "Windsurf"
        case .workbuddy: return "WorkBuddy"
        case .trae: return "Trae"
        case .kiro: return "Kiro"
        case .vscode: return "Copilot"
        case .qoder: return "Qoder"
        case .zed: return "Zed"
        case .warp: return "Warp"
        case .devin: return "Devin"
        case .intellij: return "IDEA"
        case .pycharm: return "PyCharm"
        case .webstorm: return "WebStorm"
        case .gemini: return "Gemini"
        case .grok: return "Grok"
        case .deepseek: return "DeepSeek"
        case .kimi: return "Kimi"
        case .chatglm: return "智谱 GLM"
        case .qwen: return "千问 Qwen"
        case .doubao: return "豆包"
        case .minimax: return "MiniMax"
        case .perplexity: return "Perplexity"
        case .lechat: return "Le Chat"
        case .manus: return "Manus"
        case .poe: return "Poe"
        }
    }

    /// Primary + alternate macOS Bundle Identifiers supported for this vendor's official app.
    public var bundleIdentifiers: [String] {
        switch self {
        case .codex: return ["com.openai.codex", "com.openai.chat"]
        case .antigravity: return ["com.google.antigravity"]
        case .claude: return ["com.anthropic.claudefordesktop"]
        case .cursor: return ["com.todesktop.230313mzl4w4u92"]
        case .grokbot: return ["com.anysphere.sand"]
        case .windsurf: return ["com.exafunction.windsurf"]
        case .workbuddy: return ["com.tencent.workbuddy.mac", "com.tencent.codebuddy"]
        case .trae: return ["com.trae.app", "com.bytedance.trae", "com.trae.cn"]
        case .kiro: return ["dev.kiro.desktop"]
        case .vscode: return ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]
        case .qoder: return ["com.qoder.ide", "com.alibaba.qoder"]
        case .zed: return ["dev.zed.Zed", "dev.zed.Zed-Preview"]
        case .warp: return ["dev.warp.Warp-Stable", "dev.warp.Warp"]
        case .devin: return ["ai.cognition.devin", "com.cognition.devin"]
        case .intellij: return ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"]
        case .pycharm: return ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"]
        case .webstorm: return ["com.jetbrains.WebStorm"]
        case .gemini: return ["com.google.GeminiMacOS"]
        case .grok: return ["com.grokapp.desktop", "ai.x.grok"]
        case .deepseek: return ["com.deepseek.dsh", "com.deepseek.chat"]
        case .kimi: return ["com.moonshot.kimi", "cn.moonshot.kimi"]
        case .chatglm: return ["com.zhipu.chatglm", "cn.zhipuai.chatglm"]
        case .qwen: return ["com.alibaba.qwen", "com.aliyun.tongyi", "com.alibaba.tongyi"]
        case .doubao: return ["com.bytedance.doubao.desktop", "com.bot.doubao", "com.bot.neotix.doubao"]
        case .minimax: return ["com.minimaxi.hailuo", "io.minimax.desktop"]
        case .perplexity: return ["ai.perplexity.mac"]
        case .lechat: return ["ai.mistral.lechat", "ai.mistral.chat"]
        case .manus: return ["ai.manus.agents", "im.manus.desktop"]
        case .poe: return ["com.quora.poe.electron", "com.quora.poe"]
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
        case .claude: return "#AD6E54"        // Anthropic Clay
        case .cursor: return "#7165AD"        // Prism Iris
        case .grokbot: return "#B37452"       // Terracotta Sandstone
        case .windsurf: return "#428E85"      // Surf Mineral Teal
        case .workbuddy: return "#498596"     // Fjord Teal
        case .trae: return "#4C9468"          // Moss Jade
        case .kiro: return "#7C62AD"          // Muted Violet
        case .vscode: return "#4878A8"        // Steel Azure
        case .qoder: return "#6368A8"         // Slate Indigo
        case .zed: return "#4A6FA5"           // Deep Fjord Blue
        case .warp: return "#4A86A8"          // Mist Sky
        case .devin: return "#458C86"         // Celadon Teal
        case .intellij: return "#AD5F6E"      // Mineral Crimson
        case .pycharm: return "#4A9476"       // Botanical Green
        case .webstorm: return "#468996"      // Glacier Aqua
        case .gemini: return "#597AB2"        // Starlight Slate
        case .grok: return "#788494"          // Titanium Silver
        case .deepseek: return "#536DA8"      // Mineral Cobalt
        case .kimi: return "#6B7685"          // Graphite Slate
        case .chatglm: return "#4F6FB0"       // Zhipu Indigo
        case .qwen: return "#6A64A8"          // Star Iris
        case .doubao: return "#547EB0"        // Mist Blue
        case .minimax: return "#A8667A"       // Coral Rose
        case .perplexity: return "#3E7C87"    // Slate Teal
        case .lechat: return "#B57A4E"        // Mistral Amber
        case .manus: return "#6B7685"         // Slate
        case .poe: return "#7B66AD"           // Twilight Iris
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
        case .claude: return "Claude 陶土橙"
        case .cursor: return "Cursor 棱镜紫"
        case .grokbot: return "Grok Bot 曜橙"
        case .windsurf: return "Windsurf 浪潮青"
        case .workbuddy: return "腾讯云青蓝"
        case .trae: return "Trae 极光绿"
        case .kiro: return "Kiro 幻紫"
        case .vscode: return "Copilot 钢蓝"
        case .qoder: return "Qoder 靛蓝"
        case .zed: return "Zed 深海蓝"
        case .warp: return "Warp 霓虹蓝"
        case .devin: return "Devin 碧青"
        case .intellij: return "JetBrains 绯红"
        case .pycharm: return "PyCharm 翠绿"
        case .webstorm: return "WebStorm 湖青"
        case .gemini: return "Gemini 星辉蓝"
        case .grok: return "Grok 钛银"
        case .deepseek: return "DeepSeek 深蓝"
        case .kimi: return "Kimi 曜石灰"
        case .chatglm: return "智谱 靛蓝"
        case .qwen: return "通义 星紫"
        case .doubao: return "豆包 晴蓝"
        case .minimax: return "MiniMax 珊瑚粉"
        case .perplexity: return "Perplexity 墨青"
        case .lechat: return "Mistral 橙金"
        case .manus: return "Manus 石墨灰"
        case .poe: return "Poe 暮紫"
        }
    }

    public var webLoginURL: URL? {
        switch self {
        case .codex: return URL(string: "https://chatgpt.com/codex/settings/usage")
        case .antigravity: return nil
        case .claude: return URL(string: "https://claude.ai/settings/usage")
        case .cursor: return URL(string: "https://cursor.com/dashboard/spending")
        case .grokbot: return URL(string: "https://cursor.com/dashboard/spending")
        case .windsurf: return URL(string: "https://windsurf.com/subscription/usage")
        case .workbuddy: return URL(string: "https://www.codebuddy.cn/profile/plan")
        case .trae: return URL(string: "https://www.trae.ai/account-setting")
        case .kiro: return URL(string: "https://app.kiro.dev")
        case .vscode: return URL(string: "https://github.com/settings/copilot")
        case .qoder: return URL(string: "https://qoder.com/account")
        case .zed: return URL(string: "https://zed.dev/account")
        case .warp: return URL(string: "https://app.warp.dev/billing")
        case .devin: return URL(string: "https://app.devin.ai/settings/billing")
        case .intellij, .pycharm, .webstorm: return URL(string: "https://account.jetbrains.com")
        case .gemini: return URL(string: "https://gemini.google.com/usage")
        case .grok: return URL(string: "https://grok.com")
        case .deepseek: return URL(string: "https://platform.deepseek.com/usage")
        case .kimi: return URL(string: "https://www.kimi.com/code")
        case .chatglm: return URL(string: "https://open.bigmodel.cn/usercenter/proj-mgmt/rate-limits")
        case .qwen: return URL(string: "https://bailian.console.aliyun.com/#/efm/coding_plan")
        case .doubao: return URL(string: "https://console.volcengine.com/ark")
        case .minimax: return URL(string: "https://platform.minimaxi.com/user-center/payment/balance")
        case .perplexity: return URL(string: "https://www.perplexity.ai/settings/account")
        case .lechat: return URL(string: "https://chat.mistral.ai")
        case .manus: return URL(string: "https://manus.im")
        case .poe: return URL(string: "https://poe.com/settings")
        }
    }

    public var cookieDomainSuffixes: [String] {
        switch self {
        case .codex: return ["chatgpt.com", "openai.com"]
        case .antigravity: return []
        case .claude: return ["claude.ai", "anthropic.com"]
        case .cursor, .grokbot: return ["cursor.com", "grok.com", "x.ai"]
        case .windsurf: return ["windsurf.com", "codeium.com"]
        case .workbuddy: return ["codebuddy.cn", "tencent.com", "workbuddy.cn"]
        case .trae: return ["trae.ai", "trae.cn"]
        case .kiro: return ["kiro.dev"]
        case .vscode: return ["github.com"]
        case .qoder: return ["qoder.com"]
        case .zed: return ["zed.dev"]
        case .warp: return ["warp.dev"]
        case .devin: return ["devin.ai"]
        case .intellij, .pycharm, .webstorm: return ["jetbrains.com"]
        case .gemini: return ["google.com"]
        case .grok: return ["grok.com", "x.ai"]
        case .deepseek: return ["deepseek.com"]
        case .kimi: return ["kimi.com", "moonshot.cn"]
        case .chatglm: return ["bigmodel.cn", "chatglm.cn", "z.ai"]
        case .qwen: return ["aliyun.com", "qwen.ai"]
        case .doubao: return ["volcengine.com", "doubao.com"]
        case .minimax: return ["minimaxi.com", "hailuoai.com", "minimax.io"]
        case .perplexity: return ["perplexity.ai"]
        case .lechat: return ["mistral.ai"]
        case .manus: return ["manus.im"]
        case .poe: return ["poe.com"]
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

    static let defaultCoreSet: [AgentID] = [.antigravity, .cursor, .grokbot, .codex, .claude, .workbuddy]
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
    public let remainingPercent: Double? // nil = unauthenticated or unavailable (NEVER fabricated as 100%!)
    public let creditsRemaining: Int?    // non-nil for Credits-based agents (e.g. WorkBuddy / Windsurf 积分)
    public let creditsTotal: Int?
    public let balanceDisplay: String?   // non-nil for API currency balance pools (e.g. DeepSeek / Kimi "¥11.28")
    public let dockBalanceShort: String? // compact currency label for 144x144 Dock icon (e.g. "¥11")
    public let accountEmail: String?     // Logged-in account email / handle
    public let planTier: String?         // Subscription plan & multiplier (e.g. Google AI Ultra, Pro Lite (5x), Max 20x)
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
        balanceDisplay: String? = nil,
        dockBalanceShort: String? = nil,
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
        self.balanceDisplay = balanceDisplay?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.dockBalanceShort = dockBalanceShort?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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
        creditsRemaining != nil || balanceDisplay != nil
    }

    /// Boundary-honest integer percentage:
    /// - `<= 0.05%` -> `0` (truly exhausted / rate-limited)
    /// - `(0.05%, 1.0%)` -> `1` (sliver of quota remains; never falsely reports hard `0%`)
    /// - `(99.0%, 99.95%)` -> `99` (already consumed tokens; never falsely reports untouched `100%`)
    public static func displayPercentInt(_ pct: Double) -> Int {
        let clamped = max(0, min(100, pct))
        if clamped <= 0.05 { return 0 }
        if clamped < 1.0 { return 1 }
        if clamped > 99.0 && clamped < 99.95 { return 99 }
        return Int(round(clamped))
    }

    /// True when quota/credits/balance/tier/pool/windows/error meaningfully changed (prevents repetitive 120s log spam).
    public func hasMeaningfulChange(from previous: QuotaSnapshot?) -> Bool {
        guard let prev = previous else { return true }
        let curPct = remainingPercent.map(Self.displayPercentInt)
        let prevPct = prev.remainingPercent.map(Self.displayPercentInt)
        let curWins = windows.map { "\($0.label):\(Self.displayPercentInt($0.remainingPercent))" }
        let prevWins = prev.windows.map { "\($0.label):\(Self.displayPercentInt($0.remainingPercent))" }
        return curPct != prevPct
            || curWins != prevWins
            || primaryLabel != prev.primaryLabel
            || creditsRemaining != prev.creditsRemaining
            || balanceDisplay != prev.balanceDisplay
            || planTier != prev.planTier
            || requiresWebLogin != prev.requiresWebLogin
            || errorMessage != prev.errorMessage
    }

    /// Compact pill badge for tight card headers (e.g. "AI Ultra", "Pro Lite · 5x", "Pro · 20x", "Max 20x", "Plus").
    public var compactPlanBadge: String? {
        guard let raw = planTier, !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if lower.contains("google ai ultra") {
            if lower.contains("20x") { return "AI Ultra · 20x" }
            if lower.contains("5x")  { return "AI Ultra · 5x" }
            return "AI Ultra"
        }
        if lower.contains("google ai pro")   { return "AI Pro" }
        if lower.contains("pro lite") && lower.contains("5x") { return "Pro Lite · 5x" }
        if lower.contains("chatgpt pro") && lower.contains("20x") { return "Pro · 20x" }
        if lower.contains("chatgpt plus")    { return "Plus" }
        if lower.contains("chatgpt team")    { return "Team" }
        if lower.contains("chatgpt go")      { return "Go" }
        if lower == "claude max"             { return "Max" }
        if lower == "claude pro"             { return "Pro" }
        if lower.contains("copilot pro+")    { return "Pro+" }
        if lower.contains("copilot pro")     { return "Copilot Pro" }
        if lower.contains("copilot free")    { return "Free" }
        if lower.contains("copilot business") { return "Business" }
        if lower.contains("deepseek api")    { return "API 余额" }
        if lower.contains("kimi api")        { return "API 余额" }
        if lower.contains("coding plan")     { return "Coding Plan" }
        if lower.contains("token plan")      { return "Token Plan" }
        if lower.hasPrefix("premium")        { return "Premium" }
        if lower.contains("supergrok heavy") { return "Heavy · 20x" }
        if lower.contains("supergrok")       { return "SuperGrok" }
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

    /// Formatted value for Settings Bento Card (e.g. "¥11.28", "500 积分", or "85%").
    public func formattedCardValue(showPercentageSign: Bool) -> String {
        if let bal = balanceDisplay {
            return bal
        }
        if let credits = creditsRemaining {
            return "\(credits) 积分"
        }
        guard let rem = remainingPercent else { return "—" }
        return "\(Self.displayPercentInt(rem))\(showPercentageSign ? "%" : "")"
    }

    /// Compact formatted value for the 144x144 Dock Icon (never appends % for Credits or Currency Balance!).
    public func formattedDockIconValue(showPercentageSign: Bool) -> String {
        if let shortBal = dockBalanceShort {
            return shortBal
        }
        if let bal = balanceDisplay {
            return bal
        }
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
        return "\(Self.displayPercentInt(rem))\(showPercentageSign ? "%" : "")"
    }

    /// Formatted summary for Hover Tooltip & Menu Bar (e.g. "余额 ¥11.28", "剩 500/500 积分", or "剩 85%").
    public func formattedTooltipValue(showPercentageSign: Bool) -> String {
        if let bal = balanceDisplay {
            return "余额 \(bal)"
        }
        if let credits = creditsRemaining {
            if let total = creditsTotal, total > 0 {
                return "剩 \(credits)/\(total) 积分"
            }
            return "剩 \(credits) 积分"
        }
        guard let rem = remainingPercent else { return "—" }
        return "剩 \(Self.displayPercentInt(rem))\(showPercentageSign ? "%" : "")"
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

/// Controls which isolated quota pool drives Antigravity's primary Dock water level & hero percentage.
/// Antigravity enforces separate 5h + Weekly pools for Google Gemini models vs 3P (Claude / GPT) models.
public enum AntigravityPoolFocus: String, CaseIterable, Codable, Sendable, Identifiable {
    case autoActiveModel = "autoActiveModel"
    case minBottleneck = "minBottleneck"
    case geminiOnly = "geminiOnly"
    case anthropicOnly = "anthropicOnly"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .autoActiveModel: return "跟随模型"
        case .minBottleneck:   return "双池最低"
        case .geminiOnly:      return "Gemini"
        case .anthropicOnly:   return "Claude/GPT"
        }
    }

    public var helpDescription: String {
        switch self {
        case .autoActiveModel:
            return "自动识别 Antigravity 最近一次对话所用的模型池（Gemini 或 Claude / GPT），切换模型即刻同步水位"
        case .minBottleneck:
            return "始终显示 Gemini 池与 Claude / GPT 池中余量最低的木桶瓶颈，任一池见底立即预警"
        case .geminiOnly:
            return "固定在 Dock 图标主读数展示 Gemini 模型池余量"
        case .anthropicOnly:
            return "固定在 Dock 图标主读数展示 Claude / GPT 模型池余量"
        }
    }
}

/// Optional multiplier suffix (`5x` / `20x`) for Google AI Ultra accounts when `agy` CLI reports generic `"Google AI Ultra"`.
public enum AntigravityUltraMultiplier: String, CaseIterable, Codable, Sendable, Identifiable {
    case auto = "auto"
    case x5 = "5x"
    case x20 = "20x"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .auto: return "自动"
        case .x5:   return "5x"
        case .x20:  return "20x"
        }
    }
}

public enum DockBadgeStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    // I · Liquid Water Styles (4: #01 Screenshot Replica, 2 Kept Pure-Text Styles, #19 Concentric Auto-Dodge)
    case refTopTimerScrim = "refTopTimerScrim"
    case pureSplitText = "pureSplitText"
    case haloText = "haloText"
    case concentricAutoDodge = "concentricAutoDodge"

    // II · Precision Optical & Hardware Instrument Styles (4: #07, #08, #09, #11)
    case apertureSweep = "apertureSweep"
    case retroLEDMatrix = "retroLEDMatrix"
    case dualTrackHUD = "dualTrackHUD"
    case braunAnalogNeedle = "braunAnalogNeedle"

    // III · Luminous Micro-Cells & Floating Dynamic Pods (3: #15, #20, #23)
    case bottomPrismCells = "bottomPrismCells"
    case topDynamicIsland = "topDynamicIsland"
    case topEnergyBrow = "topEnergyBrow"

    public var id: String { rawValue }

    public var usesLiquidWater: Bool {
        true
    }

    public var title: String {
        switch self {
        case .refTopTimerScrim:    return "截图原版 · 顶栏时间 + 微阴白字"
        case .pureSplitText:       return "纯数字 · 随水波动态反相"
        case .haloText:            return "纯数字 · 微晶护边描边字"
        case .concentricAutoDodge: return "同心 R角磨砂章 · 低水自动避让"
        case .apertureSweep:       return "相机光学光圈扇叶扫描"
        case .retroLEDMatrix:      return "复古像素 LED 辉光点阵带"
        case .dualTrackHUD:        return "底部 5h/周限双轨微仪表 HUD"
        case .braunAnalogNeedle:   return "博朗极简圆弧刻度 + 橙红指针"
        case .bottomPrismCells:    return "底部 5 颗辉光小方块 + 双读数"
        case .topDynamicIsland:    return "顶部居中毛玻璃灵动微岛"
        case .topEnergyBrow:       return "顶部内弧发光能量眉"
        }
    }

    public var shortTitle: String {
        switch self {
        case .refTopTimerScrim:    return "截图顶栏时间"
        case .pureSplitText:       return "动态反相字"
        case .haloText:            return "微晶描边字"
        case .concentricAutoDodge: return "同心R角(避让)"
        case .apertureSweep:       return "光圈扇叶扫描"
        case .retroLEDMatrix:      return "像素LED点阵"
        case .dualTrackHUD:        return "双轨微仪表"
        case .braunAnalogNeedle:   return "博朗圆弧指针"
        case .bottomPrismCells:    return "底部5格晶块"
        case .topDynamicIsland:    return "顶部灵动微岛"
        case .topEnergyBrow:       return "顶部弧形光眉"
        }
    }

    public var symbolName: String {
        switch self {
        case .refTopTimerScrim:    return "inset.filled.topthird.square"
        case .pureSplitText:       return "circle.lefthalf.striped.horizontal.inverse"
        case .haloText:            return "textformat.123"
        case .concentricAutoDodge: return "inset.filled.bottomleft.rectangle"
        case .apertureSweep:       return "camera.aperture"
        case .retroLEDMatrix:      return "circle.grid.3x3.fill"
        case .dualTrackHUD:        return "chart.bar.xaxis"
        case .braunAnalogNeedle:   return "gauge.with.needle"
        case .bottomPrismCells:    return "square.grid.4x3.fill"
        case .topDynamicIsland:    return "capsule.inset.filled"
        case .topEnergyBrow:       return "弧"
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
