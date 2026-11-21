import Foundation

public enum ProviderRegistry {
    public static func allProviders() -> [any UsageProvider] {
        AgentID.allCases.map { id in
            switch id {
            case .codex:
                return CodexProvider()
            case .antigravity:
                return AntigravityProvider()
            case .claude:
                return ClaudeProvider()
            case .cursor:
                return CursorProvider()
            case .grokbot:
                return GrokBotProvider()
            case .windsurf:
                return WindsurfProvider()
            case .workbuddy:
                return WorkBuddyProvider()
            case .vscode:
                return CopilotProvider()
            case .gemini:
                return GeminiProvider()
            case .grok:
                return GrokDesktopProvider()
            case .deepseek:
                return DeepSeekProvider()
            case .kimi:
                return KimiProvider()
            default:
                return VendorTokenPlanProvider(agentID: id)
            }
        }
    }
}
