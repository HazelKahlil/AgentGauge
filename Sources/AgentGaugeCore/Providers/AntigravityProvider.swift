import Foundation

private final class AntigravityEndpointCache: @unchecked Sendable {
    static let shared = AntigravityEndpointCache()
    private let lock = NSLock()
    private var cachedPort: Int?
    private var cachedToken: String?

    func get() -> (port: Int, token: String)? {
        lock.lock()
        defer { lock.unlock() }
        guard let p = cachedPort, let t = cachedToken else { return nil }
        return (p, t)
    }

    func set(port: Int, token: String) {
        lock.lock()
        cachedPort = port
        cachedToken = token
        lock.unlock()
    }

    func clear() {
        lock.lock()
        cachedPort = nil
        cachedToken = nil
        lock.unlock()
    }
}

public struct AntigravityProvider: UsageProvider {
    public let agentID: AgentID = .antigravity

    public init() {}

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isWorking = Self.checkIsWorking()

        // Fast path (~3ms, zero subprocesses): try cached port + token first
        if let cached = AntigravityEndpointCache.shared.get() {
            if let snapshot = await Self.queryCombinedQuota(port: cached.port, csrfToken: cached.token, isWorking: isWorking) {
                return snapshot
            }
            AntigravityEndpointCache.shared.clear()
        }

        // Slow path: discover local Antigravity language_server off-main-thread
        let discovered = await Task.detached(priority: .utility) {
            Self.discoverLanguageServer()
        }.value

        guard let server = discovered else {
            return QuotaSnapshot(
                agentID: .antigravity,
                remainingPercent: nil,
                isWorking: isWorking,
                sourceDescription: "Antigravity 未运行",
                errorMessage: "未检测到运行中的 Antigravity language_server"
            )
        }

        for port in server.ports {
            if let snapshot = await Self.queryCombinedQuota(port: port, csrfToken: server.csrfToken, isWorking: isWorking) {
                AntigravityEndpointCache.shared.set(port: port, token: server.csrfToken)
                return snapshot
            }
        }

        return QuotaSnapshot(
            agentID: .antigravity,
            remainingPercent: nil,
            isWorking: isWorking,
            sourceDescription: "Antigravity 本地 RPC",
            errorMessage: "无法连接本地 language_server (\(server.ports.count) 个端口)"
        )
    }

    private struct ServerInfo {
        let pid: Int32
        let csrfToken: String
        let ports: [Int]
    }

    private static func discoverLanguageServer() -> ServerInfo? {
        let psOut = runCapture("/bin/ps", args: ["-ax", "-o", "pid=,command="])
        var targetPID: Int32?
        var csrfToken: String?

        for line in psOut.split(separator: "\n") {
            let str = String(line)
            guard str.contains("language_server"), str.contains("--override_ide_name antigravity") else { continue }
            let trimmed = str.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
            if let range = str.range(of: "--csrf_token ") {
                let after = str[range.upperBound...]
                let token = after.split(separator: " ").first.map(String.init)
                if let token, !token.isEmpty {
                    targetPID = pid
                    csrfToken = token
                    break
                }
            }
        }

        guard let pid = targetPID, let token = csrfToken else { return nil }

        let lsofOut = runCapture("/usr/sbin/lsof", args: ["-Pan", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN"])
        var ports: [Int] = []
        for line in lsofOut.split(separator: "\n") {
            let s = String(line)
            if let colonRange = s.range(of: "127.0.0.1:") {
                let after = s[colonRange.upperBound...]
                let portStr = after.prefix(while: { $0.isNumber })
                if let p = Int(portStr), !ports.contains(p) {
                    ports.append(p)
                }
            }
        }

        return ports.isEmpty ? nil : ServerInfo(pid: pid, csrfToken: token, ports: ports)
    }

    private static func parseISODate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fFrac = ISO8601DateFormatter()
        fFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fFrac.date(from: raw) { return d }

        let fStd = ISO8601DateFormatter()
        fStd.formatOptions = [.withInternetDateTime]
        if let d = fStd.date(from: raw) { return d }

        if let secs = Double(raw) {
            return Date(timeIntervalSince1970: secs)
        }
        return nil
    }

    private static func postLocalRPC(
        port: Int,
        csrfToken: String,
        method: String,
        bodyJSON: String
    ) async -> [String: Any]? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/\(method)") else {
            return nil
        }
        var request = URLRequest(url: url, timeoutInterval: 2.5)
        request.httpMethod = "POST"
        request.httpBody = Data(bodyJSON.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private struct ParsedSummaryBucket {
        let groupTitle: String
        let bucketTitle: String
        let isWeekly: Bool
        let remainingPercent: Double
        let resetsAt: Date?
        let resetText: String?
    }

    private static func extractSummaryBuckets(from root: [String: Any]) -> [ParsedSummaryBucket] {
        let payload: [String: Any]
        if let resp = root["response"] as? [String: Any], resp["groups"] != nil {
            payload = resp
        } else if let sum = root["summary"] as? [String: Any], sum["groups"] != nil {
            payload = sum
        } else {
            payload = root
        }

        guard let groups = payload["groups"] as? [[String: Any]], !groups.isEmpty else {
            return []
        }

        var result: [ParsedSummaryBucket] = []
        let now = Date()

        for group in groups {
            let rawGroup = ((group["displayName"] as? String) ?? (group["name"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let groupTitle: String
            let lowerG = rawGroup.lowercased()
            if lowerG.contains("gemini") && !rawGroup.contains(where: \.isNumber) {
                groupTitle = "Gemini"
            } else if lowerG.contains("claude") || lowerG.contains("gpt") {
                groupTitle = "Claude/GPT"
            } else {
                groupTitle = rawGroup.isEmpty ? "总额度" : rawGroup
            }

            let buckets = group["buckets"] as? [[String: Any]] ?? []
            for bucket in buckets {
                if (bucket["disabled"] as? Bool) == true { continue }

                let bucketId = ((bucket["bucketId"] as? String) ?? (bucket["id"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let rawDisplay = ((bucket["displayName"] as? String) ?? (bucket["name"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let rawWindow = ((bucket["window"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let resetDate = parseISODate(bucket["resetTime"] as? String)
                let desc = bucket["description"] as? String

                // Extract remainingFraction (handles Protobuf v3 omitted 0.0 when resetTime is active)
                var fraction: Double? = bucket["remainingFraction"] as? Double
                if fraction == nil, let remObj = bucket["remaining"] as? [String: Any] {
                    fraction = (remObj["remainingFraction"] as? Double) ?? (remObj["value"] as? Double)
                }
                if fraction == nil && resetDate != nil {
                    fraction = 0.0
                }
                guard let validFraction = fraction else { continue }

                let combined = "\(bucketId) \(rawDisplay) \(rawWindow)".lowercased()
                let isWeeklyByName = combined.contains("week") || combined.contains("7d") || combined.contains("168h") || combined.contains("周")
                let isWeeklyByDate = resetDate.map { $0.timeIntervalSince(now) > 26 * 3600 } ?? false
                let isWeekly = isWeeklyByName || isWeeklyByDate

                let isSession = combined.contains("5h") || combined.contains("5-hour") || combined.contains("5_hour") || combined.contains("session") || combined.contains("hour")

                let localizedKind: String
                if isWeekly {
                    localizedKind = "周限额"
                } else if isSession {
                    localizedKind = "5h 限额"
                } else {
                    localizedKind = rawDisplay.isEmpty ? bucketId : rawDisplay
                }

                result.append(ParsedSummaryBucket(
                    groupTitle: groupTitle,
                    bucketTitle: "\(groupTitle) · \(localizedKind)",
                    isWeekly: isWeekly,
                    remainingPercent: max(0, min(100, validFraction * 100.0)),
                    resetsAt: resetDate,
                    resetText: desc
                ))
            }
        }
        return result
    }

    private static func queryCombinedQuota(port: Int, csrfToken: String, isWorking: Bool) async -> QuotaSnapshot? {
        async let summaryTask = postLocalRPC(
            port: port,
            csrfToken: csrfToken,
            method: "RetrieveUserQuotaSummary",
            bodyJSON: #"{"forceRefresh":true}"#
        )
        async let statusTask = postLocalRPC(
            port: port,
            csrfToken: csrfToken,
            method: "GetUserStatus",
            bodyJSON: #"{"metadata":{"ideName":"antigravity","extensionName":"antigravity","ideVersion":"unknown","locale":"en"}}"#
        )

        let (summaryRoot, statusRoot) = await (summaryTask, statusTask)
        guard summaryRoot != nil || statusRoot != nil else {
            return nil
        }

        let summaryBuckets = summaryRoot.map { extractSummaryBuckets(from: $0) } ?? []

        // Parse identity, tier, credits & per-model configs from GetUserStatus
        let userStatus = statusRoot?["userStatus"] as? [String: Any]
        let accountEmail = (userStatus?["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let planStatus = userStatus?["planStatus"] as? [String: Any]
        let userTierDict = userStatus?["userTier"] as? [String: Any]
        let tierID = (userTierDict?["id"] as? String)?.lowercased() ?? ""
        let tierName = userTierDict?["name"] as? String
        let legacyPlanName = (planStatus?["planInfo"] as? [String: Any])?["planName"] as? String
        let resolvedPlanName: String? = {
            if let tn = tierName, !tn.isEmpty {
                return tn
            }
            if tierID.contains("ultra") { return "Google AI Ultra" }
            if tierID.contains("pro")   { return "Google AI Pro" }
            return legacyPlanName
        }()
        let promptCredits = planStatus?["availablePromptCredits"] as? Int

        let cascadeData = userStatus?["cascadeModelConfigData"] as? [String: Any]
        let models = cascadeData?["clientModelConfigs"] as? [[String: Any]] ?? []
        let defaultModelID = ((cascadeData?["defaultOverrideModelConfig"] as? [String: Any])?["modelOrAlias"] as? [String: Any])?["model"] as? String

        var modelWindows: [QuotaWindow] = []
        var seenFamilies = Set<String>()
        var primaryWindow: QuotaWindow?
        let now = Date()

        for model in models {
            guard let label = model["label"] as? String,
                  let quotaInfo = model["quotaInfo"] as? [String: Any] else {
                continue
            }

            let resetDate = parseISODate(quotaInfo["resetTime"] as? String)
            // Protobuf v3 omits remainingFraction when exactly 0.0; if resetTime is present, treat as 0%
            let fraction: Double
            if let f = quotaInfo["remainingFraction"] as? Double {
                fraction = f
            } else if resetDate != nil {
                fraction = 0.0
            } else {
                continue
            }

            let modelID = (model["modelOrAlias"] as? [String: Any])?["model"] as? String
            let isSelected = (defaultModelID != nil && modelID == defaultModelID)
            let family = Self.familyLabel(from: label)

            // Detect if this model's active limiting window is already a multi-day weekly cap (>26h)
            let isMultiDayCap = resetDate.map { $0.timeIntervalSince(now) > 26 * 3600 } ?? false
            let displayFamily = isMultiDayCap ? "\(family) · 周限" : family

            if isSelected {
                let w = QuotaWindow(
                    label: "\(displayFamily) (当前)",
                    remainingPercent: fraction * 100.0,
                    resetsAt: resetDate,
                    isPrimary: true
                )
                primaryWindow = w
                if !seenFamilies.contains(family) {
                    seenFamilies.insert(family)
                    modelWindows.insert(w, at: 0)
                }
                continue
            }

            if seenFamilies.contains(family) { continue }
            seenFamilies.insert(family)

            modelWindows.append(QuotaWindow(
                label: displayFamily,
                remainingPercent: fraction * 100.0,
                resetsAt: resetDate,
                isPrimary: false
            ))
        }

        // Merge Weekly buckets from RetrieveUserQuotaSummary prominently so Weekly Quota is ALWAYS visible!
        var finalWindows: [QuotaWindow] = []
        let weeklyBuckets = summaryBuckets.filter { $0.isWeekly }

        if !modelWindows.isEmpty {
            // Put primary active model first, followed immediately by Weekly Quotas (周限额), then remaining models!
            if let first = modelWindows.first {
                finalWindows.append(first)
            }
            for wb in weeklyBuckets {
                finalWindows.append(QuotaWindow(
                    label: wb.bucketTitle,
                    remainingPercent: wb.remainingPercent,
                    resetsAt: wb.resetsAt,
                    resetText: wb.resetText,
                    isPrimary: false
                ))
            }
            if modelWindows.count > 1 {
                finalWindows.append(contentsOf: modelWindows.dropFirst())
            }
        } else if !summaryBuckets.isEmpty {
            // If GetUserStatus had no model rows, build directly from RetrieveUserQuotaSummary (5h + Weekly)
            for (idx, sb) in summaryBuckets.enumerated() {
                let w = QuotaWindow(
                    label: sb.bucketTitle,
                    remainingPercent: sb.remainingPercent,
                    resetsAt: sb.resetsAt,
                    resetText: sb.resetText,
                    isPrimary: idx == 0
                )
                if idx == 0 { primaryWindow = w }
                finalWindows.append(w)
            }
        }

        if primaryWindow == nil, let first = finalWindows.first {
            let promoted = QuotaWindow(
                label: first.label,
                remainingPercent: first.remainingPercent,
                resetsAt: first.resetsAt,
                resetText: first.resetText,
                isPrimary: true
            )
            primaryWindow = promoted
            finalWindows[0] = promoted
        }

        guard let activePrimary = primaryWindow else {
            return nil
        }

        // If a matching Weekly bucket is tighter than the 5h window, reflect the tighter effective remaining %
        var effectiveRemaining = activePrimary.remainingPercent
        var effectiveReset = activePrimary.resetsAt
        let activeLower = activePrimary.label.lowercased()
        for wb in weeklyBuckets {
            let groupMatch = (activeLower.contains("gemini") && wb.groupTitle == "Gemini")
                || ((activeLower.contains("claude") || activeLower.contains("gpt")) && wb.groupTitle == "Claude/GPT")
            if groupMatch && wb.remainingPercent < effectiveRemaining {
                effectiveRemaining = wb.remainingPercent
                effectiveReset = wb.resetsAt ?? effectiveReset
            }
        }

        var subtitleParts: [String] = []
        if let promptCredits { subtitleParts.append("可用积分 \(promptCredits)") }

        return QuotaSnapshot(
            agentID: .antigravity,
            remainingPercent: effectiveRemaining,
            accountEmail: accountEmail,
            planTier: resolvedPlanName,
            primaryLabel: activePrimary.label,
            resetsAt: effectiveReset,
            windows: finalWindows,
            subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · "),
            isWorking: isWorking,
            sourceDescription: "Antigravity 本地 RPC (:\(port))"
        )
    }

    private static func familyLabel(from rawLabel: String) -> String {
        let base = rawLabel.components(separatedBy: " (").first ?? rawLabel
        if base.hasPrefix("Gemini 4 ") {
            return "Gemini 4"
        }
        if base.hasPrefix("Orchestrator") {
            return "Orchestrator"
        }
        return base
    }

    private static func checkIsWorking() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "\(home)/.gemini/antigravity/cli.log",
            "\(home)/.gemini/antigravity/conversation_summaries.db"
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

    private static func runCapture(_ launchPath: String, args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
