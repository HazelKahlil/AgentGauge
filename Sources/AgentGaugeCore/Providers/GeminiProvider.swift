import AppKit
import Foundation

enum GeminiSnapshotSource: Sendable, Equatable {
    case consumerWeb
    case developerCLI
}

final class GeminiSnapshotCache: @unchecked Sendable {
    static let shared = GeminiSnapshotCache()
    private let lock = NSLock()
    private var cached: QuotaSnapshot?
    private var cachedSource: GeminiSnapshotSource?
    private var cachedAt: Date = .distantPast

    func invalidate() {
        lock.lock()
        cached = nil
        cachedSource = nil
        cachedAt = .distantPast
        lock.unlock()
    }

    func get(maxAge: TimeInterval, isWorking: Bool, allowDeveloperCLI: Bool) -> QuotaSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let c = cached, Date().timeIntervalSince(cachedAt) <= maxAge else {
            return nil
        }
        // Strict product isolation on cache hit: once Gemini.app is installed, NEVER serve a previously cached Gemini CLI snapshot!
        if cachedSource == .developerCLI && !allowDeveloperCLI {
            cached = nil
            cachedSource = nil
            cachedAt = .distantPast
            return nil
        }
        return QuotaSnapshot(
            agentID: .gemini,
            remainingPercent: c.remainingPercent,
            accountEmail: c.accountEmail,
            planTier: c.planTier,
            primaryLabel: c.primaryLabel,
            resetsAt: c.resetsAt,
            resetText: c.resetText,
            windows: c.windows,
            subtitle: c.subtitle,
            isWorking: isWorking,
            sourceDescription: c.sourceDescription,
            updatedAt: c.updatedAt
        )
    }

    func set(_ snap: QuotaSnapshot, source: GeminiSnapshotSource) {
        lock.lock()
        cached = snap
        cachedSource = source
        cachedAt = Date()
        lock.unlock()
    }
}

/// Reads standalone Google Gemini (`Gemini.app` / `gemini.google.com/usage`) quota with strict product isolation:
/// - NEVER borrows from `Antigravity` (`Antigravity.app` has a completely separate developer quota pool & reset schedule!).
/// - Parses Consumer Gemini's official `用量限额 / Usage limits` (`当前用量` + `每周限额`) via `gemini.google.com/usage`.
/// - Only falls back to `Gemini CLI` (`cloudcode-pa.googleapis.com`) when `Gemini.app` is not installed on this Mac.
public struct GeminiProvider: UsageProvider {
    public let agentID: AgentID = .gemini

    public init() {}

    public static func invalidateCache() {
        GeminiSnapshotCache.shared.invalidate()
    }

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isRunning = await MainActor.run {
            !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.GeminiMacOS").isEmpty
        }
        let isDesktopInstalled = AgentID.gemini.isInstalledOnMac

        if let recent = GeminiSnapshotCache.shared.get(
            maxAge: 300.0,
            isWorking: isRunning,
            allowDeveloperCLI: !isDesktopInstalled
        ) {
            return recent
        }

        // 1. Consumer Gemini Web / Desktop Usage Limits (`https://gemini.google.com/usage`)
        let verifiedRaw = UserDefaults.standard.stringArray(forKey: "AgentGauge.webAuthVerified") ?? []
        if verifiedRaw.contains(AgentID.gemini.rawValue) || !isDesktopInstalled {
            if await WebUsageFetcher.shared.hasCookies(matchingDomainSuffixes: AgentID.gemini.cookieDomainSuffixes),
               let webSnap = await fetchFromGeminiUsagePage(isWorking: isRunning) {
                GeminiSnapshotCache.shared.set(webSnap, source: .consumerWeb)
                return webSnap
            }
        } else if await WebUsageFetcher.shared.hasCookies(matchingDomainSuffixes: ["gemini.google.com"]),
                  let webSnap = await fetchFromGeminiUsagePage(isWorking: isRunning) {
            GeminiSnapshotCache.shared.set(webSnap, source: .consumerWeb)
            return webSnap
        }

        // 2. Only if standalone `Gemini.app` is NOT installed, allow Gemini CLI (`~/.gemini/oauth_creds.json`)
        if !isDesktopInstalled, let cliSnap = await fetchFromGeminiCLIOAuth(isWorking: isRunning) {
            GeminiSnapshotCache.shared.set(cliSnap, source: .developerCLI)
            return cliSnap
        }

        return QuotaSnapshot(
            agentID: .gemini,
            remainingPercent: nil,
            isWorking: isRunning,
            sourceDescription: "Gemini 未连接",
            requiresWebLogin: true,
            errorMessage: "点击「登录」同步 Gemini 独立用量限额（与 Antigravity 独立计费）"
        )
    }

    private func fetchFromGeminiUsagePage(isWorking: Bool) async -> QuotaSnapshot? {
        guard let url = AgentID.gemini.webLoginURL else { return nil }

        let script = """
        (async function() {
          const href = location.href || '';
          if (/accounts\\.google\\.com\\/(?:v3\\/)?signin|ServiceLogin/i.test(href)) {
            return JSON.stringify({ loggedIn: false, isLoginRedirect: true, href });
          }

          const readText = () => (document.body ? document.body.innerText : '');
          let text = readText();

          // If `/usage` landed on the main Gemini shell without opening the Usage Limits view yet, try clicking Settings -> Usage limits
          if (!/(?:当前用量|每周限额|Current\\s*usage|Weekly\\s*limit)/i.test(text)) {
            const clickByText = (re) => {
              const els = document.querySelectorAll('button, a, [role="menuitem"], [role="tab"], mat-list-item');
              for (const el of els) {
                const t = (el.innerText || el.getAttribute('aria-label') || '').trim();
                if (re.test(t)) { el.click(); return true; }
              }
              return false;
            };
            if (!clickByText(/(?:用量限额|Usage\\s*limits)/i)) {
              if (clickByText(/(?:设置和帮助|设置|Settings)/i)) {
                await new Promise(r => setTimeout(r, 450));
                clickByText(/(?:用量限额|Usage\\s*limits)/i);
              }
            }
            await new Promise(r => setTimeout(r, 650));
            text = readText();
          }

          const windows = [];

          // 1. Match "当前用量 / Current usage ... 已使用 X% / X% used ... 重置时间：..."
          const curBlock = text.match(/(?:当前用量|Current\\s*usage)[\\s\\S]{0,160}?(?:(?:已使用|已用)\\s*(\\d+(?:\\.\\d+)?)\\s*%|(\\d+(?:\\.\\d+)?)\\s*%\\s*used)(?:[\\s\\S]{0,90}?(?:重置时间|Resets?\\s*(?:at|in|on)?)[：:\\s]*([^\\n]+))?/i);
          if (curBlock) {
            const used = parseFloat(curBlock[1] ?? curBlock[2]);
            if (!isNaN(used)) {
              windows.push({
                key: 'current',
                label: '当前用量窗口',
                remaining: Math.max(0, Math.min(100, 100 - used)),
                resetText: curBlock[3] ? curBlock[3].trim() : null
              });
            }
          }

          // 2. Match "每周限额 / Weekly limit ... 已使用 Y% / Y% used ... 重置时间：..."
          const wkBlock = text.match(/(?:每周限额|Weekly\\s*limit)[\\s\\S]{0,160}?(?:(?:已使用|已用)\\s*(\\d+(?:\\.\\d+)?)\\s*%|(\\d+(?:\\.\\d+)?)\\s*%\\s*used)(?:[\\s\\S]{0,90}?(?:重置时间|Resets?\\s*(?:at|in|on)?)[：:\\s]*([^\\n]+))?/i);
          if (wkBlock) {
            const used = parseFloat(wkBlock[1] ?? wkBlock[2]);
            if (!isNaN(used)) {
              // Note: in Gemini UI, reset line can appear right BEFORE "已使用 0%" inside the Weekly row!
              let rText = wkBlock[3] ? wkBlock[3].trim() : null;
              if (!rText) {
                const preReset = wkBlock[0].match(/(?:重置时间|Resets?\\s*(?:at|in|on)?)[：:\\s]*([^\\n]+?)(?:\\s*(?:已使用|已用|\\d+%))/i);
                if (preReset) rText = preReset[1].trim();
              }
              windows.push({
                key: 'weekly',
                label: '每周限额',
                remaining: Math.max(0, Math.min(100, 100 - used)),
                resetText: rText
              });
            }
          }

          let email = null;
          const em = text.match(/[\\w.+-]+@[\\w-]+\\.[\\w.-]+/);
          if (em) email = em[0];

          let planTier = null;
          if (/\\bGoogle\\s*AI\\s*Ultra\\b|\\bUltra\\b/i.test(text)) {
            if (/\\b20x\\b/i.test(text)) planTier = 'Google AI Ultra (20x)';
            else if (/\\b5x\\b/i.test(text)) planTier = 'Google AI Ultra (5x)';
            else planTier = 'Google AI Ultra';
          } else if (/\\bGoogle\\s*AI\\s*Pro\\b|\\bAdvanced\\b|\\bPro\\b/i.test(text)) {
            planTier = 'Google AI Pro';
          }

          return JSON.stringify({
            loggedIn: windows.length > 0,
            isLoginRedirect: false,
            windows,
            email,
            planTier,
            href
          });
        })()
        """

        let outcome = await WebUsageFetcher.shared.evaluatePageOutcome(
            url: url,
            script: script,
            requireExistingCookiesFor: AgentID.gemini.cookieDomainSuffixes
        )
        guard case let .payload(data) = outcome,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["loggedIn"] as? Bool) == true,
              let rawWins = json["windows"] as? [[String: Any]],
              !rawWins.isEmpty else {
            return nil
        }

        struct ParsedGemWin {
            let key: String
            let label: String
            let remaining: Double
            let resetText: String?
        }

        let parsed: [ParsedGemWin] = rawWins.compactMap { item in
            guard let label = item["label"] as? String,
                  let rem = (item["remaining"] as? NSNumber)?.doubleValue else { return nil }
            let key = (item["key"] as? String) ?? label
            let rText = (item["resetText"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            return ParsedGemWin(key: key, label: label, remaining: rem, resetText: rText)
        }
        guard !parsed.isEmpty else { return nil }

        let limiting = parsed.min(by: { $0.remaining < $1.remaining }) ?? parsed[0]
        let ordered = [limiting] + parsed.filter { $0.key != limiting.key }
        let windows = ordered.enumerated().map { idx, w in
            QuotaWindow(
                label: w.label,
                remainingPercent: w.remaining,
                resetText: w.resetText,
                isPrimary: idx == 0
            )
        }

        let resolvedEmail = (json["email"] as? String)?.nilIfEmpty
        let resolvedPlan = (json["planTier"] as? String)?.nilIfEmpty

        return QuotaSnapshot(
            agentID: .gemini,
            remainingPercent: limiting.remaining,
            accountEmail: resolvedEmail,
            planTier: resolvedPlan,
            primaryLabel: limiting.label,
            resetText: limiting.resetText,
            windows: windows,
            isWorking: isWorking,
            sourceDescription: "Gemini 用量限额"
        )
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
                let resetDate = QuotaSnapshot.parseValidResetDate(from: b["resetTime"])
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
