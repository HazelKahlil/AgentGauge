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

    /// Invalidates in-memory provider caches when the user explicitly clicks Manual Refresh.
    public static func invalidateCaches(for agentID: AgentID? = nil) {
        if let id = agentID {
            switch id {
            case .antigravity:
                AntigravityProvider.invalidateCache()
            case .gemini:
                GeminiProvider.invalidateCache()
            case .codex:
                CodexProvider.invalidateCache()
            case .claude:
                ClaudeProvider.invalidateCache()
            case .cursor, .grokbot:
                CursorProvider.invalidateCache()
            case .workbuddy:
                WorkBuddyProvider.invalidateCache()
            default:
                EcosystemCacheControl.invalidate(for: id)
                GenericWebUsageProvider.invalidateCache(for: id)
            }
        } else {
            AntigravityProvider.invalidateCache()
            GeminiProvider.invalidateCache()
            CodexProvider.invalidateCache()
            ClaudeProvider.invalidateCache()
            CursorProvider.invalidateCache()
            WorkBuddyProvider.invalidateCache()
            EcosystemCacheControl.invalidate(for: nil)
            GenericWebUsageProvider.invalidateCache(for: nil)
        }
    }
}
