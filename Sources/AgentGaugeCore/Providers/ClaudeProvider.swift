import Foundation

private final class ClaudeKeychainCache: @unchecked Sendable {
    static let shared = ClaudeKeychainCache()
    private let lock = NSLock()
    private var cachedOAuth: [String: Any]?
    private var lastRead: Date = .distantPast

    func readOAuthDict() -> [String: Any]? {
        let now = Date()
        lock.lock()
        if now.timeIntervalSince(lastRead) < 300.0 {
            let val = cachedOAuth
            lock.unlock()
            return val
        }
        lock.unlock()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice

        var parsed: [String: Any]? = nil
        do {
            try proc.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            if proc.terminationStatus == 0,
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                parsed = (root["claudeAiOauth"] as? [String: Any]) ?? root
            }
        } catch {}

        lock.lock()
        cachedOAuth = parsed
        lastRead = now
        lock.unlock()
        return parsed
    }
}

public struct ClaudeProvider: UsageProvider {
    public let agentID: AgentID = .claude

    public init() {}

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isWorking = Self.checkIsWorking()
        let localMeta = await Task.detached(priority: .utility) {
            Self.readLocalClaudeMetadata()
        }.value

        // 1. Primary local OAuth path (~/.claude/.credentials.json or macOS Keychain)
        if let token = localMeta.accessToken,
           let localOAuthSnap = await fetchFromLocalClaudeOAuth(
               accessToken: token,
               email: localMeta.email,
               planTier: localMeta.planTier,
               isWorking: isWorking
           ) {
            return localOAuthSnap
        }

        // 2. Web path: claude.ai/api/organizations/{uuid}/usage + bootstrap account/plan
        guard let url = agentID.webLoginURL else {
            return QuotaSnapshot(
                agentID: .claude,
                remainingPercent: nil,
                accountEmail: localMeta.email,
                planTier: localMeta.planTier,
                isWorking: isWorking,
                sourceDescription: "Claude"
            )
        }

        let script = """
        (async function() {
          const href = location.href || '';
          const text = document.body ? document.body.innerText : '';
          if (/\\/(login|signin|auth)/i.test(href)) {
            return JSON.stringify({ loggedIn: false, isLoginRedirect: true, href });
          }

          let email = null;
          let planRaw = null;
          let rateTier = null;

          try {
            const bootResp = await fetch('/api/bootstrap', { credentials: 'include' });
            if (bootResp.ok) {
              const boot = await bootResp.json();
              if (boot && boot.account) {
                email = boot.account.email_address || boot.account.email || null;
              }
            }
          } catch (e) {}

          try {
            const orgResp = await fetch('/api/organizations', { credentials: 'include' });
            if (orgResp.ok) {
              const orgs = await orgResp.json();
              const org = Array.isArray(orgs) && orgs.length > 0 ? orgs[0] : null;
              if (org && org.uuid) {
                rateTier = org.rate_limit_tier || null;
                const caps = Array.isArray(org.capabilities) ? org.capabilities.join(',') : '';
                if (/max/i.test(caps) || /max/i.test(rateTier || '')) planRaw = 'max';
                else if (/claude_pro|pro/i.test(caps)) planRaw = 'pro';
                else if (/team/i.test(caps)) planRaw = 'team';
                else if (/enterprise/i.test(caps)) planRaw = 'enterprise';

                const uResp = await fetch(`/api/organizations/${org.uuid}/usage`, { credentials: 'include' });
                if (uResp.ok) {
                  const u = await uResp.json();
                  const windows = [];
                  const pushWin = (key, label, isPrimary) => {
                    const obj = u[key];
                    if (obj && typeof obj.utilization === 'number') {
                      const pct = obj.utilization <= 1.0 ? obj.utilization * 100 : obj.utilization;
                      windows.push({
                        label,
                        remaining: Math.max(0, Math.min(100, 100 - pct)),
                        resetsAt: obj.resets_at || null,
                        isPrimary
                      });
                    }
                  };
                  pushWin('five_hour', '5h 会话额度', true);
                  pushWin('seven_day', '7d 周额度', false);
                  pushWin('seven_day_opus', 'Opus 周额度', false);
                  pushWin('seven_day_sonnet', 'Sonnet 周额度', false);
                  if (windows.length > 0) {
                    return JSON.stringify({ loggedIn: true, isLoginRedirect: false, windows, email, planRaw, rateTier, source: 'Claude API', href });
                  }
                }
              }
            }
          } catch (e) {}

          const windows = [];
          const usedMatches = [...text.matchAll(/(\\d+(?:\\.\\d+)?)%\\s*used/gi)];
          if (usedMatches.length > 0) {
            usedMatches.slice(0, 4).forEach((m, idx) => {
              const rem = Math.max(0, Math.min(100, 100 - parseFloat(m[1])));
              windows.push({
                label: idx === 0 ? '5h 当前窗口' : (idx === 1 ? '7d 周额度' : `窗口 ${idx + 1}`),
                remaining: rem,
                resetsAt: null,
                isPrimary: idx === 0
              });
            });
          }
          if (!email) {
            const em = text.match(/[\\w.+-]+@[\\w-]+\\.[\\w.-]+/);
            if (em) email = em[0];
          }
          if (!planRaw) {
            const pm = text.match(/\\b(Max\\s*20x|Max\\s*5x|Claude\\s*Max|Claude\\s*Pro|Team|Pro|Max)\\b/i);
            if (pm) planRaw = pm[1];
          }
          const resetMatch = text.match(/resets?\\s+(?:in\\s+)?([^\\n.]{2,32})/i);
          return JSON.stringify({
            loggedIn: windows.length > 0,
            isLoginRedirect: false,
            windows,
            email,
            planRaw,
            rateTier,
            resetText: resetMatch ? resetMatch[1].trim() : null,
            source: 'Claude Web',
            href
          });
        })()
        """

        let outcome = await WebUsageFetcher.shared.evaluatePageOutcome(
            url: url,
            script: script,
            requireExistingCookiesFor: agentID.cookieDomainSuffixes
        )
        switch outcome {
        case .missingCookies:
            return QuotaSnapshot(
                agentID: .claude,
                remainingPercent: nil,
                accountEmail: localMeta.email,
                planTier: localMeta.planTier,
                isWorking: isWorking,
                sourceDescription: "Claude 未连接",
                requiresWebLogin: true,
                errorMessage: localMeta.planTier != nil
                    ? "检测到 \(localMeta.planTier!) · 登录凭证已过期，请点击「登录」"
                    : "可在终端运行 claude login 或点击「登录」"
            )
        case .transientFailure:
            return QuotaSnapshot(
                agentID: .claude,
                remainingPercent: nil,
                accountEmail: localMeta.email,
                planTier: localMeta.planTier,
                isWorking: isWorking,
                sourceDescription: "Claude",
                requiresWebLogin: false,
                errorMessage: "Claude 网页响应超时（已保留上次状态）"
            )
        case .payload(let resultData):
            guard let result = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
                  (result["loggedIn"] as? Bool) == true,
                  let rawWindows = result["windows"] as? [[String: Any]], !rawWindows.isEmpty else {
                let redirected = ((try? JSONSerialization.jsonObject(with: resultData) as? [String: Any])?["isLoginRedirect"] as? Bool) ?? true
                return QuotaSnapshot(
                    agentID: .claude,
                    remainingPercent: nil,
                    accountEmail: localMeta.email,
                    planTier: localMeta.planTier,
                    isWorking: isWorking,
                    sourceDescription: "Claude 未连接",
                    requiresWebLogin: redirected,
                    errorMessage: "请点击「登录」同步 Claude 用量"
                )
            }

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoFallback = ISO8601DateFormatter()
            let resetText = result["resetText"] as? String

            let windows: [QuotaWindow] = rawWindows.compactMap { item in
                guard let label = item["label"] as? String,
                      let rem = item["remaining"] as? Double else { return nil }
                var resetDate: Date? = nil
                if let iso = item["resetsAt"] as? String {
                    resetDate = isoFormatter.date(from: iso) ?? isoFallback.date(from: iso)
                }
                let isPrimary = (item["isPrimary"] as? Bool) ?? false
                return QuotaWindow(
                    label: label,
                    remainingPercent: rem,
                    resetsAt: resetDate,
                    resetText: resetDate == nil ? resetText : nil,
                    isPrimary: isPrimary
                )
            }

            let resolvedEmail = (result["email"] as? String)?.nilIfEmpty ?? localMeta.email
            let resolvedPlan = Self.formatClaudePlan(
                subscriptionType: result["planRaw"] as? String,
                rateLimitTier: result["rateTier"] as? String
            ) ?? localMeta.planTier

            let primary = windows.first(where: { $0.isPrimary }) ?? windows.first
            let source = (result["source"] as? String) ?? "Claude"
            return QuotaSnapshot(
                agentID: .claude,
                remainingPercent: primary?.remainingPercent,
                accountEmail: resolvedEmail,
                planTier: resolvedPlan,
                primaryLabel: "Claude",
                resetsAt: primary?.resetsAt,
                resetText: primary?.resetText ?? resetText,
                windows: windows,
                isWorking: isWorking,
                sourceDescription: source
            )
        }
    }

    private struct LocalClaudeMeta: Sendable {
        let accessToken: String?
        let email: String?
        let planTier: String?
    }

    private static func readLocalClaudeMetadata() -> LocalClaudeMeta {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var accessToken: String?
        var subType: String?
        var rateTier: String?
        var email: String?

        // 1. ~/.claude/.credentials.json
        for path in ["\(home)/.claude/.credentials.json", "\(home)/.claude/credentials.json"] {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let oauth = (json["claudeAiOauth"] as? [String: Any]) ?? json
                if let tok = (oauth["accessToken"] as? String)?.nilIfEmpty {
                    accessToken = tok
                }
                subType = subType ?? (oauth["subscriptionType"] as? String)
                rateTier = rateTier ?? (oauth["rateLimitTier"] as? String)
            }
        }

        // 2. macOS Keychain "Claude Code-credentials"
        if let kc = ClaudeKeychainCache.shared.readOAuthDict() {
            if accessToken == nil, let tok = (kc["accessToken"] as? String)?.nilIfEmpty {
                let expMs = (kc["expiresAt"] as? Double) ?? 0
                if expMs <= 0 || expMs > Date().timeIntervalSince1970 * 1000.0 {
                    accessToken = tok
                }
            }
            subType = subType ?? (kc["subscriptionType"] as? String)
            rateTier = rateTier ?? (kc["rateLimitTier"] as? String)
        }

        // 3. ~/.claude.json oauthAccount email & billing
        if let data = try? Data(contentsOf: URL(fileURLWithPath: "\(home)/.claude.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let acct = json["oauthAccount"] as? [String: Any] {
            email = (acct["emailAddress"] as? String)?.nilIfEmpty ?? (acct["email"] as? String)?.nilIfEmpty
            subType = subType ?? (acct["billingType"] as? String)
        }

        return LocalClaudeMeta(
            accessToken: accessToken,
            email: email,
            planTier: formatClaudePlan(subscriptionType: subType, rateLimitTier: rateTier)
        )
    }

    public static func formatClaudePlan(subscriptionType: String?, rateLimitTier: String?) -> String? {
        let combined = "\(subscriptionType ?? "") \(rateLimitTier ?? "")".lowercased()
        if combined.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        if combined.contains("20x") { return "Max 20x" }
        if combined.contains("5x")  { return "Max 5x" }
        if combined.contains("max") { return "Claude Max" }
        if combined.contains("enterprise") { return "Enterprise" }
        if combined.contains("team") { return "Team" }
        if combined.contains("pro") { return "Pro" }
        if combined.contains("free") { return "Free" }
        return subscriptionType?.capitalized
    }

    private func fetchFromLocalClaudeOAuth(
        accessToken: String,
        email: String?,
        planTier: String?,
        isWorking: Bool
    ) async -> QuotaSnapshot? {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            return nil
        }

        var req = URLRequest(url: url, timeoutInterval: 6.0)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-code/2.1.100", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            let isoFrac = ISO8601DateFormatter()
            isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoStd = ISO8601DateFormatter()

            let bucketDefs: [(String, String, Bool)] = [
                ("five_hour", "5h 会话额度", true),
                ("seven_day", "7d 周额度", false),
                ("seven_day_opus", "Opus 周额度", false),
                ("seven_day_sonnet", "Sonnet 周额度", false)
            ]
            var windows: [QuotaWindow] = []
            for (key, label, isPrim) in bucketDefs {
                guard let obj = root[key] as? [String: Any],
                      let util = obj["utilization"] as? Double else { continue }
                let usedPct = util <= 1.0 ? util * 100.0 : util
                let rem = max(0, min(100, 100.0 - usedPct))
                let resetStr = obj["resets_at"] as? String
                let resetDate = resetStr.flatMap { isoFrac.date(from: $0) ?? isoStd.date(from: $0) }
                windows.append(QuotaWindow(label: label, remainingPercent: rem, resetsAt: resetDate, isPrimary: isPrim))
            }
            guard let primary = windows.first else { return nil }

            var subtitle: String?
            if let extra = root["extra_usage"] as? [String: Any],
               (extra["is_enabled"] as? Bool) == true {
                let usedRaw = (extra["used_credits"] as? NSNumber)?.doubleValue ?? 0
                let limitRaw = (extra["monthly_limit"] as? NSNumber)?.doubleValue ?? 0
                // Anthropic returns credits in cents when >= 100 on standard $ limits, or direct dollars
                if limitRaw > 0 {
                    let divisor = (limitRaw >= 500 && limitRaw.truncatingRemainder(dividingBy: 100) == 0) ? 100.0 : 1.0
                    subtitle = String(format: "额外用量 $%.2f / $%.0f", usedRaw / divisor, limitRaw / divisor)
                }
            }

            return QuotaSnapshot(
                agentID: .claude,
                remainingPercent: primary.remainingPercent,
                accountEmail: email,
                planTier: planTier,
                primaryLabel: "Claude",
                resetsAt: primary.resetsAt,
                windows: windows,
                subtitle: subtitle,
                isWorking: isWorking,
                sourceDescription: "Claude 本地凭证"
            )
        } catch {
            return nil
        }
    }

    private static func checkIsWorking() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "\(home)/.claude/history.jsonl",
            "\(home)/.claude/debug",
            "\(home)/.claude/projects",
            "\(home)/Library/Application Support/Claude/IndexedDB"
        ]
        let now = Date()
        for path in paths {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let mtime = attrs[.modificationDate] as? Date,
               now.timeIntervalSince(mtime) < 8.0 {
                return true
            }
        }
        return false
    }
}
