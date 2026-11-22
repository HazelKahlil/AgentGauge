import AppKit
import Foundation

/// Reads standalone Google Gemini quota with strict pool isolation:
/// 1. Dedicated Gemini CLI Cloud Code quota (`~/.gemini/oauth_creds.json` -> `retrieveUserQuota`) when active;
/// 2. Explicit `gemini.google.com` WebView session when connected by the user;
/// 3. Shared Google AI Pro / Ultra **Gemini-only** subscription pool (`AntigravityProvider.fetchGeminiPoolOnly`),
///    strictly isolated from Antigravity's Anthropic (3P) pool.
public struct GeminiProvider: UsageProvider {
    public let agentID: AgentID = .gemini

    public init() {}

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isRunning = await MainActor.run {
            !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.GeminiMacOS").isEmpty
        }

        // 1. Dedicated Gemini CLI OAuth quota if unexpired
        if let cliSnap = await fetchFromGeminiCLIOAuth(isWorking: isRunning) {
            return cliSnap
        }

        // 2. Explicit Gemini Web session if user signed into gemini.google.com via AgentGauge
        let verifiedRaw = UserDefaults.standard.stringArray(forKey: "AgentGauge.webAuthVerified") ?? []
        if verifiedRaw.contains(AgentID.gemini.rawValue),
           await WebUsageFetcher.shared.hasCookies(matchingDomainSuffixes: AgentID.gemini.cookieDomainSuffixes) {
            let webSnap = await GenericWebUsageProvider(agentID: .gemini).fetchSnapshot()
            if webSnap.remainingPercent != nil {
                return webSnap
            }
        }

        // 3. Shared Google AI Pro / Ultra Gemini-only subscription pool (never contaminated by Anthropic 3P!)
        if let sharedGemini = await AntigravityProvider.fetchGeminiPoolOnly(isGeminiAppRunning: isRunning) {
            return sharedGemini
        }

        // 4. Fallback to web dashboard prompt
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

        if let expiryMs = (json["expiry_date"] as? NSNumber)?.doubleValue {
            if Date().timeIntervalSince1970 * 1000.0 >= expiryMs - 30_000 {
                return nil
            }
        }

        var email: String? = nil
        if let idTok = json["id_token"] as? String,
           let claims = idTok.decodeJWTPayload() {
            email = (claims["email"] as? String)?.nilIfEmpty
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

            let isoFrac = ISO8601DateFormatter()
            isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoStd = ISO8601DateFormatter()

            struct ParsedCLIBucket {
                let label: String
                let remaining: Double
                let resetsAt: Date?
            }

            var parsed: [ParsedCLIBucket] = []
            var seenLabels = Set<String>()
            for (idx, b) in buckets.enumerated() {
                guard let frac = (b["remainingFraction"] as? NSNumber)?.doubleValue else { continue }
                let rawModel = (b["modelId"] as? String) ?? "Gemini \(idx + 1)"
                let cleanLabel = Self.cleanGeminiModelLabel(rawModel)
                guard !seenLabels.contains(cleanLabel) else { continue }
                seenLabels.insert(cleanLabel)
                let resetDate = (b["resetTime"] as? String).flatMap { isoFrac.date(from: $0) ?? isoStd.date(from: $0) }
                parsed.append(ParsedCLIBucket(
                    label: cleanLabel,
                    remaining: max(0, min(100, frac * 100.0)),
                    resetsAt: resetDate
                ))
                if parsed.count >= 6 { break }
            }
            guard !parsed.isEmpty else { return nil }

            let limiting = parsed.min(by: { $0.remaining < $1.remaining }) ?? parsed[0]
            let ordered = [limiting] + parsed.filter { $0.label != limiting.label }
            let windows: [QuotaWindow] = ordered.enumerated().map { idx, item in
                QuotaWindow(
                    label: item.label,
                    remainingPercent: item.remaining,
                    resetsAt: item.resetsAt,
                    isPrimary: idx == 0
                )
            }

            return QuotaSnapshot(
                agentID: .gemini,
                remainingPercent: limiting.remaining,
                accountEmail: email,
                primaryLabel: limiting.label,
                resetsAt: limiting.resetsAt,
                windows: windows,
                isWorking: isWorking,
                sourceDescription: "Gemini CLI 本地凭证"
            )
        } catch {
            return nil
        }
    }

    private static func cleanGeminiModelLabel(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("flash-lite") { return "Gemini Flash Lite" }
        if lower.contains("flash")      { return "Gemini Flash" }
        if lower.contains("pro")        { return "Gemini Pro" }
        return raw
    }
}
