import Foundation

public enum ProviderRegistry {
    public static func allProviders() -> [any UsageProvider] {
        AgentID.allCases.map { id in
            switch id {
            case .codex:
                return CodexProvider()
            case .antigravity:
                return AntigravityProvider()
            case .cursor:
                return CursorProvider()
            case .grokbot:
                return GrokBotProvider()
            case .muse:
                return MuseProvider()
            case .claude:
                return ClaudeProvider()
            case .workbuddy:
                return WorkBuddyProvider()
            case .gemini:
                return GeminiProvider()
            default:
                return GenericWebUsageProvider(agentID: id)
            }
        }
    }
}
