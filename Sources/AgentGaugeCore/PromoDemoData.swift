import Foundation

/// Synthetic, privacy-safe quota data used only for promo captures (`--promo-demo-data`).
/// Never contains the user's real account emails.
public enum PromoDemoData {
    public static func snapshots(now: Date = Date()) -> [AgentID: QuotaSnapshot] {
        func t(_ d: Int, _ h: Int, _ m: Int) -> Date {
            now.addingTimeInterval(TimeInterval(d * 86400 + h * 3600 + m * 60 + 30))
        }
        return [
            .antigravity: QuotaSnapshot(
                agentID: .antigravity,
                remainingPercent: 64,
                accountEmail: "hello@agentgauge.app",
                planTier: "Google AI Ultra",
                resetsAt: t(4, 22, 0),
                windows: [
                    QuotaWindow(label: "Gemini 4 (当前)", remainingPercent: 72, resetsAt: t(0, 1, 41), isPrimary: true),
                    QuotaWindow(label: "Gemini · 周限额", remainingPercent: 64, resetsAt: t(4, 22, 0), isPrimary: true),
                    QuotaWindow(label: "Claude/GPT · 周限额", remainingPercent: 100, resetsAt: t(6, 23, 0), isPrimary: true),
                    QuotaWindow(label: "Orchestrator", remainingPercent: 72, resetsAt: t(0, 1, 41)),
                    QuotaWindow(label: "Gemini 3.8 Flash", remainingPercent: 86, resetsAt: t(0, 1, 41)),
                    QuotaWindow(label: "Claude Opus 5.5", remainingPercent: 41, resetsAt: t(0, 4, 55)),
                    QuotaWindow(label: "Claude Sonnet 5.5", remainingPercent: 93, resetsAt: t(0, 4, 55)),
                    QuotaWindow(label: "GPT-OSS 120B", remainingPercent: 100, resetsAt: t(0, 4, 55))
                ],
                subtitle: "可用积分 500",
                sourceDescription: "Antigravity 本地 RPC"
            ),
            .codex: QuotaSnapshot(
                agentID: .codex,
                remainingPercent: 82,
                accountEmail: "dev@agentgauge.app",
                planTier: "ChatGPT Pro Lite (5x)",
                resetsAt: t(0, 3, 12),
                windows: [
                    QuotaWindow(label: "5 小时窗口 (主)", remainingPercent: 82, resetsAt: t(0, 3, 12), isPrimary: true),
                    QuotaWindow(label: "周额度", remainingPercent: 91, resetsAt: t(5, 20, 0), isPrimary: true)
                ],
                subtitle: "Credits $128.90 · 满额重置券 ×2",
                isWorking: true,
                sourceDescription: "Codex 本地账号"
            ),
            .grokbot: QuotaSnapshot(
                agentID: .grokbot,
                remainingPercent: 69,
                accountEmail: "grok@agentgauge.app",
                planTier: "Premium",
                resetsAt: t(5, 4, 0),
                windows: [
                    QuotaWindow(label: "Grok 周额度 (主)", remainingPercent: 69, resetsAt: t(5, 4, 0), isPrimary: true),
                    QuotaWindow(label: "Auto / 主力模型", remainingPercent: 69, resetsAt: t(5, 4, 0))
                ],
                subtitle: "本周已使用 31% 的套餐额度",
                sourceDescription: "Grok Bot / xAI 账号"
            ),
            .cursor: QuotaSnapshot(
                agentID: .cursor,
                remainingPercent: 68,
                accountEmail: "code@agentgauge.app",
                planTier: "Ultra · 20x",
                resetsAt: t(5, 4, 0),
                windows: [
                    QuotaWindow(label: "Cursor 月度额度 (主)", remainingPercent: 68, resetsAt: t(5, 4, 0), isPrimary: true),
                    QuotaWindow(label: "Auto 模型", remainingPercent: 88, resetsAt: t(5, 4, 0)),
                    QuotaWindow(label: "Claude Opus 5.5", remainingPercent: 46, resetsAt: t(5, 4, 0)),
                    QuotaWindow(label: "GPT-5.5 Codex", remainingPercent: 74, resetsAt: t(5, 4, 0))
                ],
                subtitle: "按量计费 $0 / $200 上限",
                sourceDescription: "Cursor 本地账号"
            ),
            .claude: QuotaSnapshot(
                agentID: .claude,
                remainingPercent: 83,
                accountEmail: "claude@agentgauge.app",
                planTier: "Max 20x",
                resetsAt: t(0, 2, 18),
                windows: [
                    QuotaWindow(label: "5 小时会话 (主)", remainingPercent: 83, resetsAt: t(0, 2, 18), isPrimary: true),
                    QuotaWindow(label: "周额度 · Opus", remainingPercent: 57, resetsAt: t(3, 10, 0), isPrimary: true)
                ],
                sourceDescription: "Claude Code 凭证"
            ),
            .workbuddy: QuotaSnapshot(
                agentID: .workbuddy,
                remainingPercent: 52.4,
                creditsRemaining: 3177,
                creditsTotal: 6068,
                planTier: "体验版",
                resetsAt: t(10, 11, 0),
                sourceDescription: "CodeBuddy 积分"
            ),
            .multica: QuotaSnapshot(
                agentID: .multica,
                remainingPercent: 100,
                planTier: "本地应用",
                resetText: "运行中",
                windows: [QuotaWindow(label: "本地运行状态（无独立配额）", remainingPercent: 100, resetText: "在线", isPrimary: true)],
                subtitle: "本地编排 / 工具客户端（不设百分比限额）",
                isWorking: true,
                sourceDescription: "Multica 本地状态"
            ),
            .gemini: QuotaSnapshot(
                agentID: .gemini,
                remainingPercent: 77,
                accountEmail: "hello@agentgauge.app",
                planTier: "Google AI Ultra",
                resetsAt: t(0, 6, 10),
                windows: [QuotaWindow(label: "Gemini App 每日额度", remainingPercent: 77, resetsAt: t(0, 6, 10), isPrimary: true)],
                sourceDescription: "Gemini 本地账号"
            ),
            .muse: QuotaSnapshot(
                agentID: .muse,
                remainingPercent: 91,
                planTier: "Free",
                resetsAt: t(0, 9, 0),
                sourceDescription: "Meta AI"
            )
        ]
    }
}
