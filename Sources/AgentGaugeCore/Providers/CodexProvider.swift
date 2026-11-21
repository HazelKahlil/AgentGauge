import AppKit
import Foundation
import SQLite3

private final class CodexSnapshotCache: @unchecked Sendable {
    static let shared = CodexSnapshotCache()
    private let lock = NSLock()
    private var cached: QuotaSnapshot?
    private var cachedAt: Date = .distantPast

    func get(isAppRunning: Bool, isWorking: Bool) -> QuotaSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let snap = cached else { return nil }
        if let reset = snap.resetsAt, Date() >= reset {
            return nil
        }
        let maxAge: TimeInterval = (isAppRunning || isWorking) ? 85.0 : 300.0
        guard Date().timeIntervalSince(cachedAt) <= maxAge else {
            return nil
        }
        return snap
    }

    func set(_ snap: QuotaSnapshot) {
        lock.lock()
        cached = snap
        cachedAt = Date()
        lock.unlock()
    }
}

public struct CodexProvider: UsageProvider {
    public let agentID: AgentID = .codex

    public init() {}

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isWorking = Self.checkIsWorking()
        let isAppRunning = await MainActor.run {
            AgentID.codex.bundleIdentifiers.contains { bid in
                !NSRunningApplication.runningApplications(withBundleIdentifier: bid).isEmpty
            }
        }
        if let recent = CodexSnapshotCache.shared.get(isAppRunning: isAppRunning, isWorking: isWorking) {
            return QuotaSnapshot(
                agentID: .codex,
                remainingPercent: recent.remainingPercent,
                creditsRemaining: recent.creditsRemaining,
                creditsTotal: recent.creditsTotal,
                accountEmail: recent.accountEmail,
                planTier: recent.planTier,
                primaryLabel: recent.primaryLabel,
                resetsAt: recent.resetsAt,
                resetText: recent.resetText,
                windows: recent.windows,
                subtitle: recent.subtitle,
                isWorking: isWorking,
                sourceDescription: recent.sourceDescription,
                updatedAt: recent.updatedAt
            )
        }

        let localAuth = Self.readLocalAuthIdentity()

        guard let codexPath = Self.findCodexBinary() else {
            return QuotaSnapshot(
                agentID: .codex,
                remainingPercent: nil,
                accountEmail: localAuth.email,
                planTier: localAuth.planTier,
                isWorking: isWorking,
                sourceDescription: "Codex CLI 未找到",
                requiresWebLogin: localAuth.email == nil,
                errorMessage: "未找到 codex 可执行文件"
            )
        }

        do {
            let rpc = try await Self.queryAccountAndRateLimits(codexPath: codexPath)
            let acctDict = rpc.account?["account"] as? [String: Any]
            let rpcEmail = acctDict?["email"] as? String
            let workspaceName = acctDict?["workspaceName"] as? String
            let rawPlan = (acctDict?["planType"] as? String)
                ?? ((rpc.rateLimits?["rateLimits"] as? [String: Any])?["planType"] as? String)
                ?? localAuth.rawPlan

            let resolvedEmail = rpcEmail?.nilIfEmpty ?? localAuth.email
            let resolvedPlan = Self.formatOpenAIPlan(rawPlan: rawPlan, workspaceName: workspaceName) ?? localAuth.planTier

            guard let rateLimits = rpc.rateLimits?["rateLimits"] as? [String: Any] else {
                return QuotaSnapshot(
                    agentID: .codex,
                    remainingPercent: nil,
                    accountEmail: resolvedEmail,
                    planTier: resolvedPlan,
                    isWorking: isWorking,
                    sourceDescription: "Codex app-server",
                    requiresWebLogin: resolvedEmail == nil,
                    errorMessage: "未返回 rateLimits（请在终端登录 codex）"
                )
            }

            var windows: [QuotaWindow] = []
            var primaryRemaining: Double?
            var primaryReset: Date?

            if let primary = rateLimits["primary"] as? [String: Any],
               let used = Self.doubleValue(primary["usedPercent"]) {
                let remaining = max(0, min(100, 100.0 - used))
                let resetDate = Self.dateValue(primary["resetsAt"])
                let mins = primary["windowDurationMins"] as? Int
                let label = Self.windowLabel(mins: mins, fallback: "周额度")
                primaryRemaining = remaining
                primaryReset = resetDate
                windows.append(QuotaWindow(label: label, remainingPercent: remaining, resetsAt: resetDate, isPrimary: true))
            }

            if let secondary = rateLimits["secondary"] as? [String: Any],
               let used = Self.doubleValue(secondary["usedPercent"]) {
                let remaining = max(0, min(100, 100.0 - used))
                let resetDate = Self.dateValue(secondary["resetsAt"])
                let mins = secondary["windowDurationMins"] as? Int
                let label = Self.windowLabel(mins: mins, fallback: "5h 窗口")
                windows.append(QuotaWindow(label: label, remainingPercent: remaining, resetsAt: resetDate, isPrimary: primaryRemaining == nil))
                if primaryRemaining == nil {
                    primaryRemaining = remaining
                    primaryReset = resetDate
                }
            }

            var subtitleParts: [String] = []
            if let credits = rateLimits["credits"] as? [String: Any],
               let balanceStr = credits["balance"] as? String,
               let bal = Double(balanceStr), bal > 0.005 {
                subtitleParts.append(String(format: "Credits $%.2f", bal))
            }
            if let resetCredits = rpc.rateLimits?["rateLimitResetCredits"] as? [String: Any],
               let avail = resetCredits["availableCount"] as? Int, avail > 0 {
                subtitleParts.append("满额重置券 ×\(avail)")
            }

            let snap = QuotaSnapshot(
                agentID: .codex,
                remainingPercent: primaryRemaining,
                accountEmail: resolvedEmail,
                planTier: resolvedPlan,
                primaryLabel: windows.first(where: { $0.isPrimary })?.label ?? "周额度",
                resetsAt: primaryReset,
                windows: windows,
                subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · "),
                isWorking: isWorking,
                sourceDescription: "Codex 本地账号"
            )
            if primaryRemaining != nil {
                CodexSnapshotCache.shared.set(snap)
            }
            return snap
        } catch {
            return QuotaSnapshot(
                agentID: .codex,
                remainingPercent: nil,
                accountEmail: localAuth.email,
                planTier: localAuth.planTier,
                isWorking: isWorking,
                sourceDescription: "Codex CLI",
                requiresWebLogin: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    private struct LocalAuthInfo {
        let email: String?
        let rawPlan: String?
        let planTier: String?
    }

    private static func readLocalAuthIdentity() -> LocalAuthInfo {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let authPath = "\(home)/.codex/auth.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: authPath)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any] else {
            return LocalAuthInfo(email: nil, rawPlan: nil, planTier: nil)
        }

        var email: String?
        var rawPlan: String?

        for key in ["id_token", "access_token"] {
            guard let jwt = tokens[key] as? String,
                  let claims = jwt.decodeJWTPayload() else { continue }
            if email == nil {
                email = (claims["email"] as? String)
                    ?? ((claims["https://api.openai.com/profile"] as? [String: Any])?["email"] as? String)
            }
            if rawPlan == nil {
                rawPlan = (claims["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_plan_type"] as? String
            }
        }
        return LocalAuthInfo(
            email: email,
            rawPlan: rawPlan,
            planTier: formatOpenAIPlan(rawPlan: rawPlan, workspaceName: nil)
        )
    }

    public static func formatOpenAIPlan(rawPlan: String?, workspaceName: String?) -> String? {
        guard let raw = rawPlan?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return nil
        }
        switch raw {
        case "pro":
            return "ChatGPT Pro (20x)"
        case "prolite", "pro_lite", "pro-lite":
            return "ChatGPT Pro Lite (5x)"
        case "plus":
            return "ChatGPT Plus"
        case "team", "business":
            if let ws = workspaceName?.nilIfEmpty {
                return "Team (\(ws))"
            }
            return "ChatGPT Team"
        case "enterprise":
            return "Enterprise"
        case "edu":
            return "ChatGPT Edu"
        case "go":
            return "ChatGPT Go"
        case "free":
            return "Free"
        default:
            return raw.capitalized
        }
    }

    private static func findCodexBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/app/bin/codex"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private struct RPCBundle: @unchecked Sendable {
        let account: [String: Any]?
        let rateLimits: [String: Any]?
    }

    private static func queryAccountAndRateLimits(codexPath: String) async throws -> RPCBundle {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: codexPath)
                process.arguments = ["app-server"]

                var env = ProcessInfo.processInfo.environment
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let extraPath = "\(home)/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                env["PATH"] = extraPath + ":" + (env["PATH"] ?? "")
                process.environment = env

                let stdinPipe = Pipe()
                let stdoutPipe = Pipe()
                process.standardInput = stdinPipe
                process.standardOutput = stdoutPipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let requests: [[String: Any]] = [
                    ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["clientInfo": ["name": "AgentGauge", "version": "1.2.0"]]],
                    ["jsonrpc": "2.0", "method": "initialized", "params": [:]],
                    ["jsonrpc": "2.0", "id": 2, "method": "account/read", "params": [:]],
                    ["jsonrpc": "2.0", "id": 3, "method": "account/rateLimits/read", "params": [:]]
                ]
                for req in requests {
                    if let data = try? JSONSerialization.data(withJSONObject: req) {
                        stdinPipe.fileHandleForWriting.write(data)
                        stdinPipe.fileHandleForWriting.write(Data("\n".utf8))
                    }
                }

                let deadline = Date().addingTimeInterval(8.0)
                var buffer = Data()
                var acctResult: [String: Any]?
                var rateResult: [String: Any]?

                let fd = stdoutPipe.fileHandleForReading.fileDescriptor
                while Date() < deadline {
                    var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                    let rc = poll(&pfd, 1, 200)
                    if rc > 0 && (pfd.revents & Int16(POLLIN)) != 0 {
                        let chunk = stdoutPipe.fileHandleForReading.availableData
                        if chunk.isEmpty { break }
                        buffer.append(chunk)
                        if let text = String(data: buffer, encoding: .utf8) {
                            for line in text.split(separator: "\n") {
                                guard let lineData = line.data(using: .utf8),
                                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                                      let id = obj["id"] as? Int,
                                      let result = obj["result"] as? [String: Any] else {
                                    continue
                                }
                                if id == 2 { acctResult = result }
                                if id == 3 { rateResult = result }
                            }
                        }
                        if rateResult != nil && acctResult != nil { break }
                    } else if rc == 0 && !process.isRunning {
                        break
                    }
                }

                try? stdinPipe.fileHandleForWriting.close()
                SubprocessReaper.terminateAndReap(process)
                try? stdoutPipe.fileHandleForReading.close()

                if rateResult != nil {
                    continuation.resume(returning: RPCBundle(account: acctResult, rateLimits: rateResult))
                } else {
                    continuation.resume(throwing: NSError(domain: "CodexProvider", code: -1, userInfo: [NSLocalizedDescriptionKey: "Codex app-server 响应较慢（已保留上次状态）"]))
                }
            }
        }
    }

    private static func checkIsWorking() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dbPath = "\(home)/.codex/thread_history_1.sqlite"
        guard FileManager.default.fileExists(atPath: dbPath) else { return false }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return false
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT status FROM thread_turns ORDER BY rollout_ordinal DESC LIMIT 5;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cStr = sqlite3_column_text(stmt, 0) {
                let status = String(cString: cStr).lowercased()
                if status == "in_progress" || status == "running" || status == "pending" || status == "streaming" {
                    return true
                }
            }
        }
        return false
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static func dateValue(_ any: Any?) -> Date? {
        if let ts = any as? TimeInterval { return Date(timeIntervalSince1970: ts) }
        if let i = any as? Int { return Date(timeIntervalSince1970: TimeInterval(i)) }
        return nil
    }

    private static func windowLabel(mins: Int?, fallback: String) -> String {
        guard let mins else { return fallback }
        if mins >= 10080 { return "周额度" }
        if mins >= 1440 { return "\(mins / 1440)天额度" }
        if mins >= 60 { return "\(mins / 60)小时额度" }
        return "\(mins)分钟额度"
    }
}
