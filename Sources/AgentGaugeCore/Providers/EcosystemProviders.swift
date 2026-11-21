import AppKit
import Darwin
import Foundation

// MARK: - Deterministic Subprocess Reaper (Zero Zombie / Orphan Leak Guarantee for 24/7 Uptime)

public enum SubprocessReaper {
    public static func terminateAndReap(_ proc: Process, killChildrenOfScriptPID: pid_t? = nil) {
        let pid = proc.processIdentifier
        if let spid = killChildrenOfScriptPID, spid > 0 {
            killChildProcesses(parentPID: spid, sig: SIGTERM)
        }
        if proc.isRunning {
            proc.terminate()
            let deadline = Date().addingTimeInterval(0.14)
            while proc.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if proc.isRunning && pid > 0 {
                if let spid = killChildrenOfScriptPID, spid > 0 {
                    killChildProcesses(parentPID: spid, sig: SIGKILL)
                }
                _ = Darwin.kill(pid, SIGKILL)
            }
        }
        if pid > 0 {
            proc.waitUntilExit()
        }
    }

    private static func killChildProcesses(parentPID: pid_t, sig: Int32) {
        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killer.arguments = ["-\(sig)", "-P", "\(parentPID)"]
        killer.standardOutput = FileHandle.nullDevice
        killer.standardError = FileHandle.nullDevice
        try? killer.run()
        killer.waitUntilExit()
    }
}

// MARK: - Shared Ecosystem Cache

private final class EcosystemSnapshotCache: @unchecked Sendable {
    static let shared = EcosystemSnapshotCache()
    private let lock = NSLock()
    private var snapshots: [AgentID: (snap: QuotaSnapshot, at: Date)] = [:]
    private var ghToken: String?
    private var ghTokenAt: Date = .distantPast

    func snapshot(for id: AgentID, maxAge: TimeInterval) -> QuotaSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = snapshots[id], Date().timeIntervalSince(entry.at) <= maxAge else {
            return nil
        }
        return entry.snap
    }

    func setSnapshot(_ snap: QuotaSnapshot, for id: AgentID) {
        lock.lock()
        snapshots[id] = (snap, Date())
        lock.unlock()
    }

    func cachedGitHubToken(maxAge: TimeInterval = 600.0) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let tok = ghToken, Date().timeIntervalSince(ghTokenAt) <= maxAge else {
            return nil
        }
        return tok
    }

    func setGitHubToken(_ tok: String?) {
        lock.lock()
        ghToken = tok
        ghTokenAt = Date()
        lock.unlock()
    }
}

// MARK: - 1. GitHub Copilot / VS Code Native Provider (`api.github.com/copilot_internal/user`)

public struct CopilotProvider: UsageProvider {
    public let agentID: AgentID = .vscode

    public init() {}

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isRunning = await Self.isAppRunning(.vscode)
        let ttl: TimeInterval = isRunning ? 90.0 : 360.0
        if let cached = EcosystemSnapshotCache.shared.snapshot(for: .vscode, maxAge: ttl) {
            return Self.withWorking(cached, isWorking: isRunning)
        }

        let token = await Task.detached(priority: .utility) {
            Self.resolveGitHubToken()
        }.value

        if let token, let snap = await Self.fetchCopilotInternalQuota(token: token, isWorking: isRunning) {
            EcosystemSnapshotCache.shared.setSnapshot(snap, for: .vscode)
            return snap
        }

        return await VendorTokenPlanProvider(agentID: .vscode).fetchSnapshot()
    }

    private static func resolveGitHubToken() -> String? {
        if let cached = EcosystemSnapshotCache.shared.cachedGitHubToken() {
            return cached
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for fn in ["apps.json", "hosts.json"] {
            let path = "\(home)/.config/github-copilot/\(fn)"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (_, val) in root {
                    if let dict = val as? [String: Any],
                       let oauth = (dict["oauth_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !oauth.isEmpty {
                        EcosystemSnapshotCache.shared.setGitHubToken(oauth)
                        return oauth
                    }
                }
            }
        }

        let ghCandidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "\(home)/.local/bin/gh",
            "/usr/bin/gh"
        ]
        for gh in ghCandidates where FileManager.default.isExecutableFile(atPath: gh) {
            if let out = EcosystemExec.run(gh, args: ["auth", "token"], timeout: 2.5)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !out.isEmpty, !out.contains(" ") {
                EcosystemSnapshotCache.shared.setGitHubToken(out)
                return out
            }
        }
        return nil
    }

    private static func fetchCopilotInternalQuota(token: String, isWorking: Bool) async -> QuotaSnapshot? {
        guard let url = URL(string: "https://api.github.com/copilot_internal/user") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 6.0)
        req.httpMethod = "GET"
        req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("vscode/1.96.0", forHTTPHeaderField: "Editor-Version")
        req.setValue("copilot-chat/0.24.0", forHTTPHeaderField: "Editor-Plugin-Version")
        req.setValue("GitHubCopilotChat/0.24.0", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let rawPlan = (root["copilot_plan"] as? String)?.lowercased() ?? ""
        let sku = (root["access_type_sku"] as? String)?.lowercased() ?? ""
        let loginHandle = (root["login"] as? String).map { "@\($0)" }

        let planTier: String = {
            if sku.contains("free") || rawPlan.contains("free") { return "Copilot Free" }
            if sku.contains("pro_plus") || rawPlan.contains("pro_plus") { return "Copilot Pro+" }
            if rawPlan.contains("enterprise") || sku.contains("enterprise") { return "Copilot Enterprise" }
            if rawPlan.contains("business") || sku.contains("business") { return "Copilot Business" }
            if rawPlan == "individual" || sku.contains("individual") || rawPlan.contains("pro") { return "Copilot Pro" }
            return rawPlan.isEmpty ? "GitHub Copilot" : "Copilot \(rawPlan.capitalized)"
        }()

        let resetDate = EcosystemExec.parseISODate(root["quota_reset_date_utc"] as? String)
            ?? EcosystemExec.parseISODate(root["quota_reset_date"] as? String)

        guard let snaps = root["quota_snapshots"] as? [String: Any] else {
            return nil
        }

        var windows: [QuotaWindow] = []
        var subtitleParts: [String] = []

        let defs: [(String, String)] = [
            ("premium_interactions", "Premium 高级请求"),
            ("chat", "Copilot Chat 对话"),
            ("completions", "代码补全额度")
        ]

        for (key, title) in defs {
            guard let item = snaps[key] as? [String: Any] else { continue }
            let unlimited = (item["unlimited"] as? Bool) ?? false
            let hasQuota = (item["has_quota"] as? Bool) ?? unlimited
            guard hasQuota else { continue }

            let pct: Double
            if unlimited {
                pct = 100.0
            } else if let p = (item["percent_remaining"] as? NSNumber)?.doubleValue {
                pct = max(0, min(100, p))
            } else if let rem = (item["remaining"] as? NSNumber)?.doubleValue,
                      let ent = (item["entitlement"] as? NSNumber)?.doubleValue, ent > 0 {
                pct = max(0, min(100, (rem / ent) * 100.0))
            } else {
                continue
            }

            windows.append(QuotaWindow(
                label: unlimited ? "\(title) (不限)" : title,
                remainingPercent: pct,
                resetsAt: resetDate,
                isPrimary: windows.isEmpty
            ))

            if !unlimited,
               let rem = (item["remaining"] as? NSNumber)?.intValue,
               let ent = (item["entitlement"] as? NSNumber)?.intValue, ent > 0,
               subtitleParts.count < 2 {
                let shortName = (key == "premium_interactions") ? "Premium" : (key == "chat" ? "Chat" : "补全")
                subtitleParts.append("\(shortName) 剩 \(rem)/\(ent)")
            }
        }

        guard let primary = windows.first else { return nil }
        return QuotaSnapshot(
            agentID: .vscode,
            remainingPercent: primary.remainingPercent,
            accountEmail: loginHandle,
            planTier: planTier,
            primaryLabel: primary.label,
            resetsAt: resetDate,
            windows: windows,
            subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · "),
            isWorking: isWorking,
            sourceDescription: "GitHub Copilot API"
        )
    }

    fileprivate static func isAppRunning(_ id: AgentID) async -> Bool {
        await MainActor.run {
            id.bundleIdentifiers.contains { bid in
                !NSRunningApplication.runningApplications(withBundleIdentifier: bid).isEmpty
            }
        }
    }

    fileprivate static func withWorking(_ snap: QuotaSnapshot, isWorking: Bool) -> QuotaSnapshot {
        QuotaSnapshot(
            agentID: snap.agentID,
            remainingPercent: snap.remainingPercent,
            creditsRemaining: snap.creditsRemaining,
            creditsTotal: snap.creditsTotal,
            balanceDisplay: snap.balanceDisplay,
            dockBalanceShort: snap.dockBalanceShort,
            accountEmail: snap.accountEmail,
            planTier: snap.planTier,
            primaryLabel: snap.primaryLabel,
            resetsAt: snap.resetsAt,
            resetText: snap.resetText,
            windows: snap.windows,
            subtitle: snap.subtitle,
            isWorking: isWorking,
            sourceDescription: snap.sourceDescription,
            updatedAt: snap.updatedAt,
            requiresWebLogin: snap.requiresWebLogin,
            errorMessage: snap.errorMessage
        )
    }
}

// MARK: - 2. Codeium Windsurf Native Provider (Local Language Server RPC + Web Token Plan)

public struct WindsurfProvider: UsageProvider {
    public let agentID: AgentID = .windsurf

    public init() {}

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isRunning = await CopilotProvider.isAppRunning(.windsurf)
        if isRunning,
           let server = await Task.detached(priority: .utility, operation: { Self.discoverWindsurfServer() }).value {
            for port in server.ports {
                if let snap = await Self.queryWindsurfStatus(port: port, csrfToken: server.csrfToken, isWorking: isRunning) {
                    EcosystemSnapshotCache.shared.setSnapshot(snap, for: .windsurf)
                    return snap
                }
            }
        } else if let cached = EcosystemSnapshotCache.shared.snapshot(for: .windsurf, maxAge: 900.0) {
            return CopilotProvider.withWorking(cached, isWorking: false)
        }
        return await VendorTokenPlanProvider(agentID: .windsurf).fetchSnapshot()
    }

    private struct ServerEndpoint {
        let csrfToken: String
        let ports: [Int]
    }

    private static func discoverWindsurfServer() -> ServerEndpoint? {
        guard let psOut = EcosystemExec.run("/bin/ps", args: ["-axww", "-o", "pid=,command="], timeout: 2.0) else {
            return nil
        }
        var targetPID: Int32?
        var token: String?

        for line in psOut.split(separator: "\n") {
            let s = String(line)
            let lower = s.lowercased()
            guard lower.contains("language_server"),
                  lower.contains("windsurf"),
                  !lower.contains("--override_ide_name antigravity") else { continue }
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
            if let r = s.range(of: "--csrf_token ") {
                let after = s[r.upperBound...]
                if let tok = after.split(separator: " ").first.map(String.init), !tok.isEmpty {
                    targetPID = pid
                    token = tok
                    break
                }
            }
        }

        guard let pid = targetPID, let csrf = token,
              let lsofOut = EcosystemExec.run("/usr/sbin/lsof", args: ["-Pan", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN"], timeout: 2.0) else {
            return nil
        }
        var ports: [Int] = []
        for line in lsofOut.split(separator: "\n") {
            let s = String(line)
            if let r = s.range(of: "127.0.0.1:") {
                let pStr = s[r.upperBound...].prefix(while: \.isNumber)
                if let p = Int(pStr), !ports.contains(p) {
                    ports.append(p)
                }
            }
        }
        return ports.isEmpty ? nil : ServerEndpoint(csrfToken: csrf, ports: ports)
    }

    private static func queryWindsurfStatus(port: Int, csrfToken: String, isWorking: Bool) async -> QuotaSnapshot? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus") else {
            return nil
        }
        var req = URLRequest(url: url, timeoutInterval: 2.5)
        req.httpMethod = "POST"
        req.httpBody = Data("{\"metadata\":{\"ideName\":\"windsurf\"}}".utf8)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        req.setValue(csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userStatus = root["userStatus"] as? [String: Any] else {
            return nil
        }

        let email = userStatus["email"] as? String
        let planStatus = userStatus["planStatus"] as? [String: Any]
        let planInfo = planStatus?["planInfo"] as? [String: Any]
        let planName = (planInfo?["planName"] as? String) ?? (userStatus["userTier"] as? [String: Any])?["name"] as? String
        let resetDate = EcosystemExec.parseISODate(planStatus?["planEnd"] as? String)

        var windows: [QuotaWindow] = []
        var creditsRem: Int?
        var creditsTot: Int?

        if let availPrompt = (planStatus?["availablePromptCredits"] as? NSNumber)?.doubleValue,
           let totalPrompt = (planInfo?["monthlyPromptCredits"] as? NSNumber)?.doubleValue, totalPrompt > 0 {
            let pct = max(0, min(100, (availPrompt / totalPrompt) * 100.0))
            creditsRem = Int(round(availPrompt))
            creditsTot = Int(round(totalPrompt))
            windows.append(QuotaWindow(label: "Prompt 积分", remainingPercent: pct, resetsAt: resetDate, isPrimary: true))
        }
        if let availFlow = (planStatus?["availableFlowCredits"] as? NSNumber)?.doubleValue,
           let totalFlow = (planInfo?["monthlyFlowCredits"] as? NSNumber)?.doubleValue, totalFlow > 0 {
            let pct = max(0, min(100, (availFlow / totalFlow) * 100.0))
            windows.append(QuotaWindow(label: "Flow 动作积分", remainingPercent: pct, resetsAt: resetDate, isPrimary: windows.isEmpty))
        }

        guard let first = windows.first else { return nil }
        return QuotaSnapshot(
            agentID: .windsurf,
            remainingPercent: first.remainingPercent,
            creditsRemaining: creditsRem,
            creditsTotal: creditsTot,
            accountEmail: email,
            planTier: planName.map { "Windsurf \($0)" } ?? "Windsurf Pro",
            primaryLabel: first.label,
            resetsAt: resetDate,
            windows: windows,
            isWorking: isWorking,
            sourceDescription: "Windsurf 本地服务"
        )
    }
}

// MARK: - 3. DeepSeek Official Balance API & Platform Provider

public struct DeepSeekProvider: UsageProvider {
    public let agentID: AgentID = .deepseek

    public init() {}

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isRunning = await CopilotProvider.isAppRunning(.deepseek)
        let isWorking = Self.checkDeepSeekWorking()

        if let apiKey = Self.resolveDeepSeekAPIKey(),
           let apiSnap = await Self.fetchDeepSeekBalance(apiKey: apiKey, isWorking: isWorking) {
            return apiSnap
        }

        if isRunning, let cached = EcosystemSnapshotCache.shared.snapshot(for: .deepseek, maxAge: 600.0) {
            return CopilotProvider.withWorking(cached, isWorking: isWorking)
        }

        return await VendorTokenPlanProvider(agentID: .deepseek).fetchSnapshot()
    }

    private static func resolveDeepSeekAPIKey() -> String? {
        if let envKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envKey.isEmpty {
            return envKey
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "\(home)/.deepseek/config.json",
            "\(home)/.config/deepseek/config.json",
            "\(home)/.deepseek-harness/config.json"
        ]
        for path in paths {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for k in ["apiKey", "api_key", "DEEPSEEK_API_KEY"] {
                    if let v = (json[k] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                        return v
                    }
                }
            }
        }
        return nil
    }

    private static func fetchDeepSeekBalance(apiKey: String, isWorking: Bool) async -> QuotaSnapshot? {
        guard let url = URL(string: "https://api.deepseek.com/user/balance") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 5.5)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let infos = root["balance_infos"] as? [[String: Any]],
              let first = infos.first else {
            return nil
        }

        let currency = (first["currency"] as? String) ?? "CNY"
        let isUSD = currency.uppercased() == "USD"
        let symbol = isUSD ? "$" : "¥"
        let total = Double((first["total_balance"] as? String) ?? "0") ?? 0
        let granted = Double((first["granted_balance"] as? String) ?? "0") ?? 0
        let isAvail = (root["is_available"] as? Bool) ?? (total > 0)

        return CurrencyBalanceGauge.makeSnapshot(
            agentID: .deepseek,
            planTier: "DeepSeek API",
            windowLabel: "DeepSeek API 可用余额",
            symbol: symbol,
            totalBalance: total,
            grantedBalance: granted,
            halfScale: isUSD ? 3.0 : 15.0,
            isAvailable: isAvail,
            isWorking: isWorking,
            sourceDescription: "DeepSeek Balance API"
        )
    }

    private static func checkDeepSeekWorking() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "\(home)/.deepseek-harness",
            "\(home)/Library/Application Support/@deepseek-ai/dsh-desktop"
        ]
        let now = Date()
        for p in paths {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: p),
               let mtime = attrs[.modificationDate] as? Date,
               now.timeIntervalSince(mtime) < 8.0 {
                return true
            }
        }
        return false
    }
}

// MARK: - 4. Moonshot Kimi Provider (`api.moonshot.cn` Balance + Kimi Code Token Plan)

public struct KimiProvider: UsageProvider {
    public let agentID: AgentID = .kimi

    public init() {}

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isRunning = await CopilotProvider.isAppRunning(.kimi)
        if let apiKey = Self.resolveMoonshotAPIKey(),
           let snap = await Self.fetchMoonshotBalance(apiKey: apiKey, isWorking: isRunning) {
            return snap
        }
        return await VendorTokenPlanProvider(agentID: .kimi).fetchSnapshot()
    }

    private static func resolveMoonshotAPIKey() -> String? {
        if let envKey = ProcessInfo.processInfo.environment["MOONSHOT_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envKey.isEmpty {
            return envKey
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for path in ["\(home)/.kimi/config.json", "\(home)/.config/kimi/config.json"] {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for k in ["apiKey", "api_key", "MOONSHOT_API_KEY"] {
                    if let v = (json[k] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                        return v
                    }
                }
            }
        }
        return nil
    }

    private static func fetchMoonshotBalance(apiKey: String, isWorking: Bool) async -> QuotaSnapshot? {
        guard let url = URL(string: "https://api.moonshot.cn/v1/users/me/balance") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 5.5)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = root["data"] as? [String: Any],
              let total = (dataObj["available_balance"] as? NSNumber)?.doubleValue else {
            return nil
        }
        let voucher = (dataObj["voucher_balance"] as? NSNumber)?.doubleValue ?? 0
        return CurrencyBalanceGauge.makeSnapshot(
            agentID: .kimi,
            planTier: "Kimi API",
            windowLabel: "Moonshot API 可用余额",
            symbol: "¥",
            totalBalance: total,
            grantedBalance: voucher,
            halfScale: 15.0,
            isAvailable: total > 0,
            isWorking: isWorking,
            sourceDescription: "Moonshot Balance API"
        )
    }
}

// MARK: - 5. Grok Desktop (`com.grokapp.desktop`) Native Provider

public struct GrokDesktopProvider: UsageProvider {
    public let agentID: AgentID = .grok

    public init() {}

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isRunning = await CopilotProvider.isAppRunning(.grok)

        // 1. Check explicit grok.com WebView cookies if user connected Grok Web
        if await WebUsageFetcher.shared.hasCookies(matchingDomainSuffixes: AgentID.grok.cookieDomainSuffixes) {
            let webSnap = await GenericWebUsageProvider(agentID: .grok).fetchSnapshot()
            if webSnap.remainingPercent != nil {
                return CopilotProvider.withWorking(webSnap, isWorking: isRunning)
            }
        }

        // 2. Share real xAI SuperGrok / Premium quota from local Grok Bot / Anysphere xAI-linked account on the same Mac
        let cursorAuth = CursorProvider.readLocalAuthState()
        if let sand = GrokBotProvider.readSandPersistenceUsage(matchingEmailFrom: cursorAuth) {
            return QuotaSnapshot(
                agentID: .grok,
                remainingPercent: sand.remainingPercent,
                accountEmail: sand.email,
                planTier: sand.planTier,
                primaryLabel: "Grok 额度",
                resetsAt: sand.resetsAt,
                windows: [
                    QuotaWindow(
                        label: "xAI / SuperGrok 周期额度",
                        remainingPercent: sand.remainingPercent,
                        resetsAt: sand.resetsAt,
                        isPrimary: true
                    )
                ],
                subtitle: String(format: "本机 xAI 账号同步 · 已用 %.1f%%", sand.usedPercent),
                isWorking: isRunning,
                sourceDescription: "本机 xAI 账号同步"
            )
        }

        // Strict Telemetry Honesty: never fabricate 100% when no xAI quota source is authenticated!
        return QuotaSnapshot(
            agentID: .grok,
            remainingPercent: nil,
            isWorking: isRunning,
            sourceDescription: "Grok 未连接",
            requiresWebLogin: true,
            errorMessage: "点击「登录」连接 SuperGrok 账号同步额度"
        )
    }
}

// MARK: - 6. Authentic Vendor Token-Plan Provider (Zero Fake 100% Fallbacks!)

public struct VendorTokenPlanProvider: UsageProvider {
    public let agentID: AgentID

    public init(agentID: AgentID) {
        self.agentID = agentID
    }

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isRunning = await CopilotProvider.isAppRunning(agentID)

        // 1. If user has WebView session cookies for this vendor, fetch real Web Token Plan / Quota
        if !agentID.cookieDomainSuffixes.isEmpty,
           await WebUsageFetcher.shared.hasCookies(matchingDomainSuffixes: agentID.cookieDomainSuffixes) {
            let webSnap = await GenericWebUsageProvider(agentID: agentID).fetchSnapshot()
            if webSnap.remainingPercent != nil {
                return CopilotProvider.withWorking(webSnap, isWorking: isRunning)
            }
        }

        // 2. Read non-sensitive cached email from local IDE SQLite if present (for honest Settings display, remainingPercent stays nil!)
        let localIdentity = await Task.detached(priority: .utility) {
            Self.readLocalIDEAccountHint(for: agentID)
        }.value

        return QuotaSnapshot(
            agentID: agentID,
            remainingPercent: nil,
            accountEmail: localIdentity.email,
            planTier: localIdentity.planTier,
            isWorking: isRunning,
            sourceDescription: "\(agentID.shortName) 未连接",
            requiresWebLogin: agentID.webLoginURL != nil,
            errorMessage: "点击「登录」同步 \(agentID.shortName) 套餐余量"
        )
    }

    private static func readLocalIDEAccountHint(for id: AgentID) -> (email: String?, planTier: String?) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let vscdbDir: String? = switch id {
        case .windsurf: "Windsurf"
        case .trae:     "Trae"
        case .kiro:     "Kiro"
        case .qoder:    "Qoder"
        case .vscode:   "Code"
        default:        nil
        }

        if let folder = vscdbDir {
            let dbPath = "\(home)/Library/Application Support/\(folder)/User/globalStorage/state.vscdb"
            if FileManager.default.fileExists(atPath: dbPath) {
                let sql = "SELECT key, value FROM ItemTable WHERE key LIKE '%Auth%' OR key LIKE '%account%' LIMIT 20;"
                if let map = CursorProvider.querySQLiteKeyValues(dbPath: dbPath, sql: sql, immutable: false)
                    ?? CursorProvider.querySQLiteKeyValues(dbPath: dbPath, sql: sql, immutable: true) {
                    for (_, v) in map {
                        if v.contains("@"), v.count < 80, !v.contains("{") {
                            return (v, nil)
                        }
                    }
                }
            }
        }
        return (nil, nil)
    }
}

// MARK: - Shared Honest Currency-Balance Gauge Builder (Never Pretends Dollars/Yuan Are Percentages!)

enum CurrencyBalanceGauge {
    static func makeSnapshot(
        agentID: AgentID,
        planTier: String,
        windowLabel: String,
        symbol: String,
        totalBalance: Double,
        grantedBalance: Double,
        halfScale: Double,
        isAvailable: Bool,
        isWorking: Bool,
        sourceDescription: String
    ) -> QuotaSnapshot {
        // Smooth asymptotic curve `100 * bal / (bal + halfScale)`:
        // - ¥11.28 (~5.6M tokens) -> ~43% calm cobalt water (never triggers false <15% red panic!)
        // - < ¥2.5 / $0.50 -> <15% genuine low-balance red alert
        let waterGaugePct: Double = if !isAvailable || totalBalance <= 0.001 {
            0.0
        } else {
            max(4.0, min(98.0, (totalBalance / (totalBalance + halfScale)) * 100.0))
        }

        let cardBal = String(format: "%@%.2f", symbol, totalBalance)
        let dockBal: String = if totalBalance >= 100.0 {
            String(format: "%@%.0f", symbol, totalBalance)
        } else if totalBalance >= 10.0 {
            String(format: "%@%.0f", symbol, floor(totalBalance + 0.5))
        } else {
            String(format: "%@%.1f", symbol, totalBalance)
        }

        var sub = "按量计费 · 可用余额 \(cardBal)"
        if grantedBalance > 0.01 {
            sub += String(format: "（含赠金 %@%.2f）", symbol, grantedBalance)
        }

        return QuotaSnapshot(
            agentID: agentID,
            remainingPercent: waterGaugePct,
            balanceDisplay: cardBal,
            dockBalanceShort: dockBal,
            planTier: planTier,
            primaryLabel: windowLabel,
            resetText: "按量计费",
            windows: [
                QuotaWindow(
                    label: windowLabel,
                    remainingPercent: waterGaugePct,
                    resetText: cardBal,
                    isPrimary: true
                )
            ],
            subtitle: sub,
            isWorking: isWorking,
            sourceDescription: sourceDescription
        )
    }
}

// MARK: - Subprocess & ISO8601 Helper

private enum EcosystemExec {
    static func run(_ executable: String, args: [String], timeout: TimeInterval) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice

        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["HOME"] = home
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        proc.environment = env

        do {
            try proc.run()
        } catch {
            return nil
        }

        let fd = outPipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            while data.count < 262_144 {
                let n = Darwin.read(fd, &buf, buf.count)
                if n > 0 { data.append(buf, count: n) } else { break }
            }
            if !proc.isRunning {
                while data.count < 262_144 {
                    let n = Darwin.read(fd, &buf, buf.count)
                    if n > 0 { data.append(buf, count: n) } else { break }
                }
                break
            }
            Thread.sleep(forTimeInterval: 0.04)
        }

        SubprocessReaper.terminateAndReap(proc)
        try? outPipe.fileHandleForReading.close()
        return data.isEmpty ? nil : String(decoding: data, as: UTF8.self)
    }

    static func parseISODate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fFrac = ISO8601DateFormatter()
        fFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fFrac.date(from: raw) { return d }

        let fStd = ISO8601DateFormatter()
        fStd.formatOptions = [.withInternetDateTime]
        return fStd.date(from: raw)
    }
}
