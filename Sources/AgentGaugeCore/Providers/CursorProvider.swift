import Foundation
import SQLite3

public struct CursorLocalAuth: Sendable {
    public let accessToken: String?
    public let refreshToken: String?
    public let email: String?
    public let membershipType: String?
    public let signUpType: String?
    public let authId: String?
    public let displayName: String?
}

public struct CursorProvider: UsageProvider {
    public let agentID: AgentID = .cursor

    public init() {}

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isWorking = Self.checkIsWorking()
        let localAuth = Self.readLocalAuthState()

        // 1. Primary path: Direct Cursor Desktop API (zero WebView!)
        if let token = localAuth.accessToken {
            if let snapshot = await fetchFromDesktopAPI(auth: localAuth, accessToken: token, isWorking: isWorking) {
                return snapshot
            }
            // Attempt native refreshToken exchange if accessToken expired while Cursor.app was closed
            if let rt = localAuth.refreshToken,
               let refreshed = await Self.refreshCursorAccessToken(refreshToken: rt),
               let snapshot = await fetchFromDesktopAPI(auth: localAuth, accessToken: refreshed, isWorking: isWorking) {
                return snapshot
            }
            // Retry once after brief pause on transient network/SSL hiccup
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let snapshot = await fetchFromDesktopAPI(auth: localAuth, accessToken: token, isWorking: isWorking) {
                return snapshot
            }
            // Unified Anysphere/xAI offline cross-fallback when account is Grok-linked
            if localAuth.signUpType?.lowercased() == "grok",
               let sandCache = GrokBotProvider.readSandPersistenceUsage(matchingEmailFrom: localAuth) {
                return QuotaSnapshot(
                    agentID: .cursor,
                    remainingPercent: sandCache.remainingPercent,
                    accountEmail: localAuth.email ?? sandCache.email,
                    planTier: Self.formatCursorPlan(rawPlan: localAuth.membershipType, isMergedGrok: true) ?? sandCache.planTier,
                    primaryLabel: "Cursor",
                    resetsAt: sandCache.resetsAt,
                    windows: [
                        QuotaWindow(
                            label: "周期总额度 (xAI 互通缓存)",
                            remainingPercent: sandCache.remainingPercent,
                            resetsAt: sandCache.resetsAt,
                            isPrimary: true
                        )
                    ],
                    isWorking: isWorking,
                    sourceDescription: "Cursor 本地账号"
                )
            }
            // Local token exists -> transient network issue, NEVER set requiresWebLogin=true (preserves last valid quota!)
            return QuotaSnapshot(
                agentID: .cursor,
                remainingPercent: nil,
                accountEmail: localAuth.email,
                planTier: Self.formatCursorPlan(rawPlan: localAuth.membershipType, isMergedGrok: localAuth.signUpType?.lowercased() == "grok"),
                isWorking: isWorking,
                sourceDescription: "Cursor 本地账号",
                requiresWebLogin: false,
                errorMessage: "Cursor 接口网络波动（已保留上次额度）"
            )
        }

        // 2. Fallback path: WKWebView dashboard ONLY if no local Cursor desktop token exists
        guard let url = agentID.webLoginURL else {
            return QuotaSnapshot(agentID: .cursor, remainingPercent: nil, isWorking: isWorking, sourceDescription: "Cursor")
        }

        let script = """
        (function() {
          const text = document.body ? document.body.innerText : '';
          const href = location.href || '';
          const isLogin = href.includes('authenticator') || href.includes('login') || href.includes('sign-in');
          if (isLogin) return JSON.stringify({ loggedIn: false, isLoginRedirect: true, href });

          const windows = [];
          const patterns = [
            { label: 'Cursor Models', re: /Cursor Models[\\s\\S]{0,120}?(\\d+(?:\\.\\d+)?)%\\s*used/i },
            { label: 'Other Models', re: /Other Models[\\s\\S]{0,120}?(\\d+(?:\\.\\d+)?)%\\s*used/i },
            { label: 'Weekly usage', re: /Weekly usage\\s+(\\d+(?:\\.\\d+)?)%\\s*used/i }
          ];
          for (const p of patterns) {
            const m = text.match(p.re);
            if (m) {
              windows.push({ label: p.label, remaining: Math.max(0, Math.min(100, 100 - parseFloat(m[1]))) });
            }
          }
          if (windows.length === 0) {
            const generic = text.match(/(\\d+(?:\\.\\d+)?)%\\s*used/i);
            if (generic) {
              windows.push({ label: 'Plan usage', remaining: Math.max(0, Math.min(100, 100 - parseFloat(generic[1]))) });
            }
          }
          const emailMatch = text.match(/[\\w.+-]+@[\\w-]+\\.[\\w.-]+/);
          const planMatch = text.match(/\\b(Ultra|Pro\\+|Pro Plus|Super|Premium|Pro|Business)\\b/i);
          const resetMatch = text.match(/resets?\\s+(?:in\\s+)?([^\\n.]{2,28})/i);
          return JSON.stringify({
            loggedIn: windows.length > 0,
            isLoginRedirect: false,
            windows,
            email: emailMatch ? emailMatch[0] : null,
            plan: planMatch ? planMatch[1] : null,
            resetText: resetMatch ? resetMatch[1].trim() : null,
            href
          });
        })()
        """

        let outcome = await WebUsageFetcher.shared.evaluatePageOutcome(
            url: url,
            script: script,
            requireExistingCookiesFor: ["cursor.com"]
        )
        switch outcome {
        case .missingCookies:
            return QuotaSnapshot(
                agentID: .cursor,
                remainingPercent: nil,
                accountEmail: localAuth.email,
                isWorking: isWorking,
                sourceDescription: "Cursor 未登录",
                requiresWebLogin: true,
                errorMessage: "请在 Cursor 客户端或点击「登录」连接账号"
            )
        case .transientFailure:
            return QuotaSnapshot(
                agentID: .cursor,
                remainingPercent: nil,
                accountEmail: localAuth.email,
                isWorking: isWorking,
                sourceDescription: "Cursor Dashboard",
                requiresWebLogin: false,
                errorMessage: "网页响应超时（已保留上次状态）"
            )
        case .payload(let resultData):
            guard let result = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
                  (result["loggedIn"] as? Bool) == true,
                  let rawWindows = result["windows"] as? [[String: Any]], !rawWindows.isEmpty else {
                let redirected = ((try? JSONSerialization.jsonObject(with: resultData) as? [String: Any])?["isLoginRedirect"] as? Bool) ?? false
                return QuotaSnapshot(
                    agentID: .cursor,
                    remainingPercent: nil,
                    accountEmail: localAuth.email,
                    isWorking: isWorking,
                    sourceDescription: "Cursor 未登录",
                    requiresWebLogin: redirected,
                    errorMessage: "请打开 Cursor 或点击登录"
                )
            }

            let resetText = result["resetText"] as? String
            let email = (result["email"] as? String) ?? localAuth.email
            let plan = Self.formatCursorPlan(rawPlan: result["plan"] as? String, isMergedGrok: false)
            let windows: [QuotaWindow] = rawWindows.compactMap { item in
                guard let label = item["label"] as? String,
                      let rem = item["remaining"] as? Double else { return nil }
                return QuotaWindow(label: label, remainingPercent: rem, resetText: resetText)
            }

            let primary = windows.first
            return QuotaSnapshot(
                agentID: .cursor,
                remainingPercent: primary?.remainingPercent,
                accountEmail: email,
                planTier: plan,
                resetText: resetText,
                windows: windows,
                isWorking: isWorking,
                sourceDescription: "Cursor Dashboard"
            )
        }
    }

    // MARK: - Direct Cursor Desktop API (api2.cursor.sh)

    private func fetchFromDesktopAPI(auth: CursorLocalAuth, accessToken: String, isWorking: Bool) async -> QuotaSnapshot? {
        async let usageResp = Self.postCursorRPC(endpoint: "aiserver.v1.DashboardService/GetCurrentPeriodUsage", accessToken: accessToken)
        async let planResp = Self.postCursorRPC(endpoint: "aiserver.v1.DashboardService/GetPlanInfo", accessToken: accessToken)

        let (jsonOpt, planRoot) = await (usageResp, planResp)
        guard let json = jsonOpt,
              let planUsage = json["planUsage"] as? [String: Any] else {
            return nil
        }

        let totalUsed = Self.parseDouble(planUsage["totalPercentUsed"])
            ?? Self.parseDouble(planUsage["autoPercentUsed"])
        guard let usedPct = totalUsed else { return nil }
        let remaining = max(0, min(100, 100.0 - usedPct))

        var resetsAt: Date? = nil
        if let endMs = Self.parseDouble(json["billingCycleEnd"]), endMs > 1_000_000_000_000 {
            resetsAt = Date(timeIntervalSince1970: endMs / 1000.0)
        } else if let endSec = Self.parseDouble(json["billingCycleEnd"]), endSec > 1_000_000_000 {
            resetsAt = Date(timeIntervalSince1970: endSec)
        }

        var windows: [QuotaWindow] = []
        windows.append(QuotaWindow(
            label: "周期总额度 (主)",
            remainingPercent: remaining,
            resetsAt: resetsAt,
            isPrimary: true
        ))
        if let autoUsed = Self.parseDouble(planUsage["autoPercentUsed"]) {
            windows.append(QuotaWindow(
                label: "Auto / 主力模型",
                remainingPercent: max(0, min(100, 100.0 - autoUsed)),
                resetsAt: resetsAt
            ))
        }
        if let apiUsed = Self.parseDouble(planUsage["apiPercentUsed"]) {
            windows.append(QuotaWindow(
                label: "API / 独立模型池",
                remainingPercent: max(0, min(100, 100.0 - apiUsed)),
                resetsAt: resetsAt
            ))
        }

        let planInfoDict = planRoot?["planInfo"] as? [String: Any]
        let apiPlanName = planInfoDict?["planName"] as? String
        let isMerged = (planRoot?["isMerged"] as? Bool) ?? (auth.signUpType?.lowercased() == "grok")
        let resolvedPlan = Self.formatCursorPlan(rawPlan: apiPlanName ?? auth.membershipType, isMergedGrok: isMerged)

        var subtitleParts: [String] = []
        if let msg = (json["displayMessage"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !msg.isEmpty {
            subtitleParts.append(msg)
        }
        if let spend = json["spendLimitUsage"] as? [String: Any] {
            let usedCents = Self.parseDouble(spend["individualUsed"]) ?? Self.parseDouble(spend["pooledUsed"])
            let limitCents = Self.parseDouble(spend["individualLimit"]) ?? Self.parseDouble(spend["pooledLimit"])
            if let u = usedCents, let l = limitCents, l > 0 {
                subtitleParts.append(String(format: "按量支出 $%.2f / $%.0f", u / 100.0, l / 100.0))
            }
        }
        if let bonus = Self.parseDouble(planUsage["remainingBonus"]), bonus > 0.5 {
            subtitleParts.append(String(format: "赠送额度剩 %.0f", bonus))
        }

        return QuotaSnapshot(
            agentID: .cursor,
            remainingPercent: remaining,
            accountEmail: auth.email,
            planTier: resolvedPlan,
            primaryLabel: "Cursor",
            resetsAt: resetsAt,
            windows: windows,
            subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · "),
            isWorking: isWorking,
            sourceDescription: "Cursor 本地账号"
        )
    }

    private static func refreshCursorAccessToken(refreshToken: String) async -> String? {
        guard let url = URL(string: "https://api2.cursor.sh/aiserver.v1.AuthService/RefreshToken") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 5.5)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refreshToken": refreshToken])

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = (json["accessToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    private static func postCursorRPC(endpoint: String, accessToken: String) async -> [String: Any]? {
        guard let url = URL(string: "https://api2.cursor.sh/\(endpoint)") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 6.5)
        req.httpMethod = "POST"
        req.httpBody = Data("{}".utf8)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    public static func formatCursorPlan(rawPlan: String?, isMergedGrok: Bool) -> String? {
        guard let raw = rawPlan?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let lower = raw.lowercased()
        if lower.contains("ultra") {
            return "Ultra · 20x"
        }
        if lower == "pro_plus" || lower == "pro+" || lower == "proplus" || lower == "pro plus" {
            return "Pro+ · 3x"
        }
        if lower == "super" {
            return "Super"
        }
        if lower == "premium" {
            return isMergedGrok ? "Premium (xAI 互通)" : "Premium"
        }
        if lower == "pro" {
            return "Pro"
        }
        if lower.contains("business") || lower.contains("team") {
            return "Business"
        }
        if lower.contains("trial") {
            return "Pro Trial"
        }
        if lower == "free" || lower == "hobby" {
            return "Free"
        }
        return raw
    }

    private static func parseDouble(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    public static func readLocalAuthState() -> CursorLocalAuth {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dbPath = "\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        let empty = CursorLocalAuth(accessToken: nil, refreshToken: nil, email: nil, membershipType: nil, signUpType: nil, authId: nil, displayName: nil)
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return empty
        }

        let sql = """
        SELECT key, value FROM ItemTable WHERE key IN (
            'cursorAuth/accessToken',
            'cursorAuth/refreshToken',
            'cursorAuth/cachedEmail',
            'cursorAuth/stripeMembershipType',
            'cursorAuth/cachedSignUpType',
            'cursorAuth/stripeMembershipAuthId',
            'cursorAuth/cachedScopedProfile'
        );
        """

        // Standard read-only open first; fallback to immutable URI if Cursor closed leaving an unindexed -wal file!
        let map = querySQLiteKeyValues(dbPath: dbPath, sql: sql, immutable: false)
            ?? querySQLiteKeyValues(dbPath: dbPath, sql: sql, immutable: true)
        guard let map else {
            return empty
        }

        var displayName: String? = nil
        var profileAuthId: String? = nil
        if let profStr = map["cursorAuth/cachedScopedProfile"],
           let profData = profStr.data(using: .utf8),
           let profJson = try? JSONSerialization.jsonObject(with: profData) as? [String: Any] {
            displayName = profJson["displayName"] as? String
            profileAuthId = profJson["authId"] as? String
        }

        return CursorLocalAuth(
            accessToken: map["cursorAuth/accessToken"]?.nilIfEmpty,
            refreshToken: map["cursorAuth/refreshToken"]?.nilIfEmpty,
            email: map["cursorAuth/cachedEmail"]?.nilIfEmpty,
            membershipType: map["cursorAuth/stripeMembershipType"]?.nilIfEmpty,
            signUpType: map["cursorAuth/cachedSignUpType"]?.nilIfEmpty,
            authId: map["cursorAuth/stripeMembershipAuthId"]?.nilIfEmpty ?? profileAuthId,
            displayName: displayName?.nilIfEmpty
        )
    }

    static func querySQLiteKeyValues(dbPath: String, sql: String, immutable: Bool) -> [String: String]? {
        var db: OpaquePointer?
        let openRC: Int32
        if immutable {
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove(charactersIn: "?#")
            guard let encoded = dbPath.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
            let uri = "file:\(encoded)?immutable=1"
            openRC = sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX, nil)
        } else {
            openRC = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        }
        guard openRC == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        sqlite3_busy_timeout(db, 1500)
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        var map: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let kPtr = sqlite3_column_text(stmt, 0),
               let vPtr = sqlite3_column_text(stmt, 1) {
                map[String(cString: kPtr)] = String(cString: vPtr).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return map
    }

    private static func checkIsWorking() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dbPath = "\(home)/Library/Application Support/Cursor/User/globalStorage/conversation-search.db"
        if let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath),
           let mtime = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(mtime) < 8.0 {
            return true
        }
        return false
    }
}
