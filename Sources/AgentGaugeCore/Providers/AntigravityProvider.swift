import AppKit
import Darwin
import Foundation

private final class AntigravityEndpointCache: @unchecked Sendable {
    static let shared = AntigravityEndpointCache()

    private let lock = NSLock()
    private var cachedPort: Int?
    private var cachedToken: String?
    private var cachedCLISnapshot: QuotaSnapshot?
    private var cachedCLIDate: Date = .distantPast
    private var cachedBannerPlanTier: String?

    func getBannerPlanTier(for email: String?) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let mem = cachedBannerPlanTier, !mem.isEmpty {
            return mem
        }
        if let em = email?.lowercased(), !em.isEmpty,
           let saved = UserDefaults.standard.string(forKey: "AgentGauge.agyPlanTier.\(em)"),
           let savedAt = UserDefaults.standard.object(forKey: "AgentGauge.agyPlanTierAt.\(em)") as? Date,
           Date().timeIntervalSince(savedAt) < 86_400,
           !saved.isEmpty {
            cachedBannerPlanTier = saved
            return saved
        }
        return nil
    }

    func setBannerPlanTier(_ tier: String, for email: String?) {
        lock.lock()
        cachedBannerPlanTier = tier
        lock.unlock()
        if let em = email?.lowercased(), !em.isEmpty {
            UserDefaults.standard.set(tier, forKey: "AgentGauge.agyPlanTier.\(em)")
            UserDefaults.standard.set(Date(), forKey: "AgentGauge.agyPlanTierAt.\(em)")
        }
    }
    func getRPC() -> (port: Int, token: String)? {
        lock.lock()
        defer { lock.unlock() }
        guard let p = cachedPort, let t = cachedToken else { return nil }
        return (p, t)
    }

    func setRPC(port: Int, token: String) {
        lock.lock()
        cachedPort = port
        cachedToken = token
        lock.unlock()
    }

    func clearRPC() {
        lock.lock()
        cachedPort = nil
        cachedToken = nil
        lock.unlock()
    }

    func getCLISnapshot(isAppRunning: Bool) -> QuotaSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let snap = cachedCLISnapshot else { return nil }
        // If reset timer has passed, force fresh sync to catch reset back to 100%!
        if let reset = snap.resetsAt, Date() >= reset {
            return nil
        }
        // Adaptive cadence: 175s when Antigravity.app is open, 900s (15 min) when closed to save background PTY spawns!
        let maxAge: TimeInterval = isAppRunning ? 175.0 : 900.0
        guard Date().timeIntervalSince(cachedCLIDate) <= maxAge else {
            return nil
        }
        return snap
    }

    func setCLISnapshot(_ snapshot: QuotaSnapshot) {
        lock.lock()
        cachedCLISnapshot = snapshot
        cachedCLIDate = Date()
        lock.unlock()
    }
}

private actor AntigravityCLISingleFlight {
    static let shared = AntigravityCLISingleFlight()
    private var inFlight: Task<QuotaSnapshot?, Never>?

    func fetch(operation: @Sendable @escaping () -> QuotaSnapshot?) async -> QuotaSnapshot? {
        if let existing = inFlight {
            return await existing.value
        }
        let task = Task.detached(priority: .utility) {
            operation()
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }
}

public struct AntigravityProvider: UsageProvider {
    public let agentID: AgentID = .antigravity

    public init() {}

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isWorking = Self.checkIsWorking()

        // 1. Legacy Antigravity IDE 1.x fast path (only when explicit --override_ide_name antigravity & --csrf_token exist)
        if let cached = AntigravityEndpointCache.shared.getRPC() {
            if let snapshot = await Self.queryLegacyCombinedQuota(port: cached.port, csrfToken: cached.token, isWorking: isWorking) {
                return snapshot
            }
            AntigravityEndpointCache.shared.clearRPC()
        }

        let legacyServer = await Task.detached(priority: .utility) {
            Self.discoverLegacyLanguageServer()
        }.value

        if let server = legacyServer {
            for port in server.ports {
                if let snapshot = await Self.queryLegacyCombinedQuota(port: port, csrfToken: server.csrfToken, isWorking: isWorking) {
                    AntigravityEndpointCache.shared.setRPC(port: port, token: server.csrfToken)
                    return snapshot
                }
            }
        }

        let isAppRunning = await MainActor.run {
            !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.antigravity").isEmpty
        }

        // 2. Antigravity 2.0 & CLI official documented path (`agy --settings` statusLine JSON payload)
        if let recent = AntigravityEndpointCache.shared.getCLISnapshot(isAppRunning: isAppRunning) {
            return QuotaSnapshot(
                agentID: .antigravity,
                remainingPercent: recent.remainingPercent,
                creditsRemaining: recent.creditsRemaining,
                creditsTotal: recent.creditsTotal,
                balanceDisplay: recent.balanceDisplay,
                dockBalanceShort: recent.dockBalanceShort,
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

        if let cliSnapshot = await AntigravityCLISingleFlight.shared.fetch(operation: {
            Self.fetchViaDocumentedAGYStatusLine(isWorking: isWorking)
        }) {
            AntigravityEndpointCache.shared.setCLISnapshot(cliSnapshot)
            return QuotaSnapshot(
                agentID: .antigravity,
                remainingPercent: cliSnapshot.remainingPercent,
                creditsRemaining: cliSnapshot.creditsRemaining,
                creditsTotal: cliSnapshot.creditsTotal,
                accountEmail: cliSnapshot.accountEmail,
                planTier: cliSnapshot.planTier,
                primaryLabel: cliSnapshot.primaryLabel,
                resetsAt: cliSnapshot.resetsAt,
                resetText: cliSnapshot.resetText,
                windows: cliSnapshot.windows,
                subtitle: cliSnapshot.subtitle,
                isWorking: isWorking,
                sourceDescription: cliSnapshot.sourceDescription,
                updatedAt: cliSnapshot.updatedAt
            )
        }

        return QuotaSnapshot(
            agentID: .antigravity,
            remainingPercent: nil,
            isWorking: isWorking,
            sourceDescription: "Antigravity 未就绪",
            errorMessage: "请先在终端运行 `agy` 登录或在 Antigravity 中完成认证"
        )
    }

    // MARK: - Antigravity 2.0 Official Documented `agy` StatusLine JSON Reader

    private static func resolveAGYBinaryPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/agy",
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
            "/Applications/Antigravity.app/Contents/Resources/bin/agy",
            "/Applications/Antigravity.app/Contents/Resources/app/bin/agy"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let whichOut = runCapture("/usr/bin/which", args: ["agy"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !whichOut.isEmpty && FileManager.default.isExecutableFile(atPath: whichOut) {
            return whichOut
        }
        return nil
    }

    private static func fetchViaDocumentedAGYStatusLine(isWorking: Bool) -> QuotaSnapshot? {
        guard let agyPath = resolveAGYBinaryPath() else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
        let uid = UUID().uuidString
        let outFile = tempDir.appendingPathComponent("agentgauge-agy-status-\(uid).json")
        let logFile = tempDir.appendingPathComponent("agentgauge-agy-log-\(uid).log")
        defer {
            try? FileManager.default.removeItem(at: outFile)
            try? FileManager.default.removeItem(at: logFile)
        }

        let settingsObj: [String: Any] = [
            "statusLine": [
                "type": "command",
                "command": "cat > '\(outFile.path)'"
            ]
        ]
        guard let settingsData = try? JSONSerialization.data(withJSONObject: settingsObj),
              let settingsJSON = String(data: settingsData, encoding: .utf8) else {
            return nil
        }

        let inPipe = Pipe()
        let outPipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        proc.arguments = ["-q", "-F", "/dev/null", agyPath, "--settings", settingsJSON, "--log-file", logFile.path]
        proc.currentDirectoryURL = tempDir
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice

        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["HOME"] = home
        env["TERM"] = "xterm-256color"
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        proc.environment = env

        do {
            try proc.run()
        } catch {
            return nil
        }

        let outFD = outPipe.fileHandleForReading.fileDescriptor
        let curFlags = fcntl(outFD, F_GETFL)
        if curFlags >= 0 {
            _ = fcntl(outFD, F_SETFL, curFlags | O_NONBLOCK)
        }

        var bannerBytes = Data()
        func drainStdout() {
            var buf = [UInt8](repeating: 0, count: 8192)
            while bannerBytes.count < 262_144 {
                let n = Darwin.read(outFD, &buf, buf.count)
                if n > 0 {
                    bannerBytes.append(buf, count: n)
                } else {
                    break
                }
            }
        }

        func writeStdin(_ str: String) {
            if let data = str.data(using: .utf8) {
                try? inPipe.fileHandleForWriting.write(contentsOf: data)
            }
        }

        let launchDate = Date()
        var parsedRoot: [String: Any]?
        var quotaDetectedAt: Date?
        var parsedEmail: String?
        var detectedBannerTier: String?
        var tierProbeStage = 0 // 0 = waiting for prompt+quota, 1 = sent /credits, 2 = sent ESC
        var stageTimestamp = Date()
        let deadline = launchDate.addingTimeInterval(8.5)

        while Date() < deadline {
            drainStdout()

            if parsedRoot == nil,
               let data = try? Data(contentsOf: outFile), data.count > 20,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let quotaDict = json["quota"] as? [String: Any], !quotaDict.isEmpty {
                parsedRoot = json
                quotaDetectedAt = Date()
                parsedEmail = (json["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let jsonTier = (json["plan_tier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !jsonTier.isEmpty {
                    detectedBannerTier = normalizeGooglePlanTier(jsonTier)
                } else {
                    detectedBannerTier = AntigravityEndpointCache.shared.getBannerPlanTier(for: parsedEmail)
                }
            }

            if detectedBannerTier == nil && !bannerBytes.isEmpty {
                detectedBannerTier = extractPlanTierFromAGYBanner(bannerBytes)
            }

            if parsedRoot != nil {
                if detectedBannerTier != nil {
                    break
                }
                let cleaned = cleanANSIText(bannerBytes)
                let headerMounted: Bool = {
                    if let em = parsedEmail, !em.isEmpty, cleaned.contains(em) {
                        return Date().timeIntervalSince(quotaDetectedAt ?? launchDate) >= 0.45
                    }
                    return Date().timeIntervalSince(quotaDetectedAt ?? launchDate) >= 1.10
                }()

                if tierProbeStage == 0 && headerMounted {
                    writeStdin("/credits\r")
                    tierProbeStage = 1
                    stageTimestamp = Date()
                } else if tierProbeStage == 1 {
                    if cleaned.contains("Antigravity CLI credits") || Date().timeIntervalSince(stageTimestamp) >= 1.15 {
                        Thread.sleep(forTimeInterval: 0.10)
                        writeStdin("\u{1B}")
                        tierProbeStage = 2
                        stageTimestamp = Date()
                    }
                } else if tierProbeStage == 2 && Date().timeIntervalSince(stageTimestamp) >= 0.95 {
                    break
                }
            }

            if !proc.isRunning {
                break
            }
            Thread.sleep(forTimeInterval: 0.06)
        }

        drainStdout()
        if detectedBannerTier == nil && !bannerBytes.isEmpty {
            detectedBannerTier = extractPlanTierFromAGYBanner(bannerBytes)
        }
        if let tier = detectedBannerTier, !tier.isEmpty {
            AntigravityEndpointCache.shared.setBannerPlanTier(tier, for: parsedEmail)
        }

        // Documented graceful exit (`ESC` + `Ctrl+D Ctrl+D`), then deterministically reap child PTY & script process
        writeStdin("\u{1B}\u{04}\u{04}")
        try? inPipe.fileHandleForWriting.close()
        Thread.sleep(forTimeInterval: 0.08)

        let scriptPID = proc.processIdentifier
        SubprocessReaper.terminateAndReap(proc, killChildrenOfScriptPID: scriptPID)
        try? outPipe.fileHandleForReading.close()

        if parsedRoot == nil,
           let data = try? Data(contentsOf: outFile), data.count > 20,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            parsedRoot = json
        }

        guard let root = parsedRoot else { return nil }
        return parseStatusLinePayload(root, bannerPlanTier: detectedBannerTier, isWorking: isWorking)
    }

    private static func cleanANSIText(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        let raw = String(decoding: data, as: UTF8.self)
        var out = String()
        out.reserveCapacity(raw.count)

        enum State { case normal, esc, csi, osc, oscEsc }
        var state: State = .normal
        var lastWasSpace = false

        for scalar in raw.unicodeScalars {
            let v = scalar.value
            switch state {
            case .normal:
                if v == 0x1B {
                    state = .esc
                } else if v < 0x20 || v == 0x7F {
                    if !lastWasSpace {
                        out.append(" ")
                        lastWasSpace = true
                    }
                } else {
                    if scalar == " " {
                        if !lastWasSpace {
                            out.append(" ")
                            lastWasSpace = true
                        }
                    } else {
                        out.unicodeScalars.append(scalar)
                        lastWasSpace = false
                    }
                }
            case .esc:
                if scalar == "[" {
                    state = .csi
                } else if scalar == "]" {
                    state = .osc
                } else {
                    state = .normal
                }
            case .csi:
                if v >= 0x40 && v <= 0x7E {
                    state = .normal
                    if !lastWasSpace {
                        out.append(" ")
                        lastWasSpace = true
                    }
                }
            case .osc:
                if v == 0x07 {
                    state = .normal
                } else if v == 0x1B {
                    state = .oscEsc
                }
            case .oscEsc:
                state = .normal
            }
        }
        return out
    }

    private static func extractPlanTierFromAGYBanner(_ data: Data) -> String? {
        let text = cleanANSIText(data)
        guard !text.isEmpty else { return nil }

        // 1. Authoritative match: `<email> (<Plan Tier>)` in Antigravity CLI banner
        if let emailTierRe = try? NSRegularExpression(pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\s*\\(([^)]{2,42})\\)") {
            let matches = emailTierRe.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches.reversed() {
                if let r = Range(m.range(at: 1), in: text) {
                    let candidate = text[r].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty {
                        return normalizeGooglePlanTier(candidate)
                    }
                }
            }
        }

        // 2. Explicit named Google AI / Workspace tier fallback
        if let namedRe = try? NSRegularExpression(pattern: "\\((Google AI [A-Za-z0-9 +._-]+|AI Ultra|AI Pro|Workspace [A-Za-z0-9 +._-]+|Enterprise)\\)", options: [.caseInsensitive]),
           let m = namedRe.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(m.range(at: 1), in: text) {
            let candidate = text[r].trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                return normalizeGooglePlanTier(candidate)
            }
        }

        return nil
    }

    private static func normalizeGooglePlanTier(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower == "ultra" || lower == "ai ultra" || lower == "google ai ultra" {
            return "Google AI Ultra"
        }
        if lower == "pro" || lower == "ai pro" || lower == "google ai pro" {
            return "Google AI Pro"
        }
        return trimmed
    }

    private static func parseStatusLinePayload(_ root: [String: Any], bannerPlanTier: String?, isWorking: Bool) -> QuotaSnapshot? {
        guard let quotaDict = root["quota"] as? [String: Any], !quotaDict.isEmpty else {
            return nil
        }

        let email = (root["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTier = ((root["plan_tier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
            ?? bannerPlanTier
        let resolvedTier = rawTier.map(normalizeGooglePlanTier)

        let modelDict = root["model"] as? [String: Any]
        let modelDisplay = ((modelDict?["display_name"] as? String) ?? (modelDict?["id"] as? String))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let activeLower = (modelDisplay ?? "").lowercased()
        let isThirdPartyActive = activeLower.contains("claude")
            || activeLower.contains("gpt")
            || activeLower.contains("sonnet")
            || activeLower.contains("opus")
            || activeLower.contains("o1")
            || activeLower.contains("o3")

        struct RawBucket {
            let key: String
            let isGemini: Bool
            let isThirdParty: Bool
            let isWeekly: Bool
            let label: String
            let percent: Double
            let resetsAt: Date?
            let sortOrder: Int
        }

        let now = Date()
        var buckets: [RawBucket] = []

        for (key, val) in quotaDict {
            guard let info = val as? [String: Any] else { continue }
            if (info["disabled"] as? Bool) == true { continue }

            let resetDate: Date? = {
                if let d = parseISODate(info["reset_time"] as? String) {
                    return d
                }
                if let secs = (info["reset_in_seconds"] as? NSNumber)?.doubleValue, secs > 0 {
                    return now.addingTimeInterval(secs)
                }
                return nil
            }()

            let fraction: Double
            if let f = (info["remaining_fraction"] as? NSNumber)?.doubleValue {
                fraction = f
            } else if resetDate != nil {
                fraction = 0.0
            } else {
                continue
            }

            let kLower = key.lowercased()
            let isGemini = kLower.contains("gemini")
            let isThirdParty = kLower.contains("3p") || kLower.contains("claude") || kLower.contains("gpt")
            let isWeekly = kLower.contains("week") || (resetDate.map { $0.timeIntervalSince(now) > 26 * 3600 } ?? false)
            let is5h = kLower.contains("5h") || kLower.contains("hour") || kLower.contains("session")

            let groupName: String = if isGemini {
                "Gemini"
            } else if isThirdParty {
                "Claude/GPT"
            } else {
                key
            }

            let windowKind: String = if isWeekly {
                "周限额"
            } else if is5h {
                "5h 限额"
            } else {
                "限额"
            }

            let activePoolMatch = (isThirdPartyActive && isThirdParty) || (!isThirdPartyActive && isGemini)
            let order: Int = switch (activePoolMatch, isWeekly) {
            case (true, false): 0
            case (true, true):  1
            case (false, false): 2
            case (false, true):  3
            }

            buckets.append(RawBucket(
                key: key,
                isGemini: isGemini,
                isThirdParty: isThirdParty,
                isWeekly: isWeekly,
                label: "\(groupName) · \(windowKind)",
                percent: max(0, min(100, fraction * 100.0)),
                resetsAt: resetDate,
                sortOrder: order
            ))
        }

        guard !buckets.isEmpty else { return nil }
        buckets.sort { ($0.sortOrder, $0.key) < ($1.sortOrder, $1.key) }

        let activePoolBuckets = buckets.filter {
            (isThirdPartyActive && $0.isThirdParty) || (!isThirdPartyActive && $0.isGemini)
        }
        let limitingBucket = (activePoolBuckets.isEmpty ? buckets : activePoolBuckets)
            .min(by: { $0.percent < $1.percent }) ?? buckets[0]

        let windows: [QuotaWindow] = buckets.enumerated().map { idx, b in
            QuotaWindow(
                label: b.label,
                remainingPercent: b.percent,
                resetsAt: b.resetsAt,
                isPrimary: idx == 0
            )
        }

        let subtitle: String? = if let m = modelDisplay, !m.isEmpty {
            "当前模型 · \(m)"
        } else {
            nil
        }

        return QuotaSnapshot(
            agentID: .antigravity,
            remainingPercent: limitingBucket.percent,
            accountEmail: (email?.isEmpty == false) ? email : nil,
            planTier: resolvedTier,
            primaryLabel: limitingBucket.label,
            resetsAt: limitingBucket.resetsAt,
            windows: windows,
            subtitle: subtitle,
            isWorking: isWorking,
            sourceDescription: "Antigravity CLI"
        )
    }

    // MARK: - Legacy Antigravity 1.x Local RPC (`--override_ide_name antigravity`)

    private struct ServerInfo {
        let pid: Int32
        let csrfToken: String
        let ports: [Int]
    }

    private static func discoverLegacyLanguageServer() -> ServerInfo? {
        let psOut = runCapture("/bin/ps", args: ["-axww", "-o", "pid=,command="])
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

                var fraction: Double? = (bucket["remainingFraction"] as? NSNumber)?.doubleValue
                if fraction == nil, let remObj = bucket["remaining"] as? [String: Any] {
                    fraction = (remObj["remainingFraction"] as? NSNumber)?.doubleValue
                        ?? (remObj["value"] as? NSNumber)?.doubleValue
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

    private static func queryLegacyCombinedQuota(port: Int, csrfToken: String, isWorking: Bool) async -> QuotaSnapshot? {
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
        let userStatus = statusRoot?["userStatus"] as? [String: Any]
        let accountEmail = (userStatus?["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let planStatus = userStatus?["planStatus"] as? [String: Any]
        let userTierDict = userStatus?["userTier"] as? [String: Any]
        let tierID = (userTierDict?["id"] as? String)?.lowercased() ?? ""
        let tierName = userTierDict?["name"] as? String
        let legacyPlanName = (planStatus?["planInfo"] as? [String: Any])?["planName"] as? String
        let resolvedPlanName: String? = {
            if let tn = tierName, !tn.isEmpty { return tn }
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
            let fraction: Double
            if let f = (quotaInfo["remainingFraction"] as? NSNumber)?.doubleValue {
                fraction = f
            } else if resetDate != nil {
                fraction = 0.0
            } else {
                continue
            }

            let modelID = (model["modelOrAlias"] as? [String: Any])?["model"] as? String
            let isSelected = (defaultModelID != nil && modelID == defaultModelID)
            let family = Self.familyLabel(from: label)
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

        var finalWindows: [QuotaWindow] = []
        let weeklyBuckets = summaryBuckets.filter { $0.isWeekly }

        if !modelWindows.isEmpty {
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

        guard let activePrimary = primaryWindow else { return nil }

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
        if base.hasPrefix("Gemini 4 ") { return "Gemini 4" }
        if base.hasPrefix("Orchestrator") { return "Orchestrator" }
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
