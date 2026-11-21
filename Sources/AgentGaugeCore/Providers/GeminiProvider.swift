import AppKit
import Foundation

/// Reads Google Gemini quota locally without requiring extra WebView login:
/// 1. Queries `~/.gemini/oauth_creds.json` against `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` when valid;
/// 2. Shares live Google AI Ultra / Pro Gemini model pool from local Google `language_server` when running!
public struct GeminiProvider: UsageProvider {
    public let agentID: AgentID = .gemini

    public init() {}

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isRunning = await MainActor.run {
            !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.GeminiMacOS").isEmpty
        }

        // 1. Reuse live Google AI Ultra / Pro Gemini pool & plan tier from Antigravity CLI/RPC cache when available!
        let agSnap = await AntigravityProvider().fetchSnapshot()
        if agSnap.remainingPercent != nil {
            let geminiWindows = agSnap.windows.filter {
                $0.label.localizedCaseInsensitiveContains("Gemini")
            }
            let limitingGemini = geminiWindows.min(by: { $0.remainingPercent < $1.remainingPercent })
            let primary = limitingGemini ?? geminiWindows.first ?? agSnap.windows.first
            if let rem = primary?.remainingPercent ?? agSnap.remainingPercent {
                return QuotaSnapshot(
                    agentID: .gemini,
                    remainingPercent: rem,
                    accountEmail: agSnap.accountEmail,
                    planTier: agSnap.planTier,
                    primaryLabel: primary?.label ?? "Gemini",
                    resetsAt: primary?.resetsAt ?? agSnap.resetsAt,
                    windows: geminiWindows.isEmpty ? agSnap.windows : geminiWindows,
                    subtitle: agSnap.subtitle,
                    isWorking: isRunning,
                    sourceDescription: "Google AI 账号同步"
                )
            }
        }

        // 2. Try local ~/.gemini/oauth_creds.json if unexpired
        if let cliSnap = await fetchFromGeminiCLIOAuth(isWorking: isRunning) {
            return cliSnap
        }

        // 3. Fallback to generic web dashboard if user explicitly logged in via WebView
        return await GenericWebUsageProvider(agentID: .gemini).fetchSnapshot()
    }

    private func fetchFromGeminiCLIOAuth(isWorking: Bool) async -> QuotaSnapshot? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let credsPath = "\(home)/.gemini/oauth_creds.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: credsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String, !token.isEmpty else {
            return nil
        }

        if let expiryMs = json["expiry_date"] as? Double {
            if Date().timeIntervalSince1970 * 1000.0 >= expiryMs - 30_000 {
                return nil
            }
        }

        guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota") else {
            return nil
        }
        var req = URLRequest(url: url, timeoutInterval: 5.0)
        req.httpMethod = "POST"
        req.httpBody = Data("{}".utf8)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (respData, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let root = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
                  let buckets = root["buckets"] as? [[String: Any]], !buckets.isEmpty else {
                return nil
            }

            let iso = ISO8601DateFormatter()
            var windows: [QuotaWindow] = []
            for (idx, b) in buckets.prefix(5).enumerated() {
                guard let frac = b["remainingFraction"] as? Double else { continue }
                let model = (b["modelId"] as? String) ?? "Gemini \(idx + 1)"
                let resetDate = (b["resetTime"] as? String).flatMap { iso.date(from: $0) }
                windows.append(QuotaWindow(
                    label: model,
                    remainingPercent: frac * 100.0,
                    resetsAt: resetDate,
                    isPrimary: idx == 0
                ))
            }
            guard let first = windows.first else { return nil }
            return QuotaSnapshot(
                agentID: .gemini,
                remainingPercent: first.remainingPercent,
                primaryLabel: "Gemini",
                resetsAt: first.resetsAt,
                windows: windows,
                isWorking: isWorking,
                sourceDescription: "Gemini CLI 本地凭证"
            )
        } catch {
            return nil
        }
    }
}
