import AppKit
import Darwin
import Foundation
import SQLite3

public enum AntigravityModelPool: String, Sendable {
    case gemini
    case anthropic
    case other

    public var displayTitle: String {
        switch self {
        case .gemini:    return "Gemini"
        case .anthropic: return "Claude / GPT"
        case .other:     return "其他模型"
        }
    }
}

struct ParsedAGYBucket: Sendable {
    let key: String
    let pool: AntigravityModelPool
    let isWeekly: Bool
    let is5h: Bool
    let label: String
    let percent: Double
    let resetsAt: Date?
    let resetText: String?
}

struct CachedAGYPayload: Sendable {
    let email: String?
    let planTier: String?
    let cliFallbackPool: AntigravityModelPool
    let buckets: [ParsedAGYBucket]
    let fetchedAt: Date
}

private final class AntigravityEndpointCache: @unchecked Sendable {
    static let shared = AntigravityEndpointCache()

    private let lock = NSLock()
    private var cachedPayload: CachedAGYPayload?
    private var cachedBannerPlanTiersByEmail: [String: String] = [:]
    private var lastBannerProbeAtByEmail: [String: Date] = [:]

    func invalidate() {
        lock.lock()
        cachedPayload = nil
        lock.unlock()
    }

    func getBannerPlanTier(for email: String?) -> String? {
        guard let em = email?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !em.isEmpty else {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        if let mem = cachedBannerPlanTiersByEmail[em], !mem.isEmpty {
            return mem
        }
        if let saved = UserDefaults.standard.string(forKey: "AgentGauge.agyPlanTier.\(em)"),
           let savedAt = UserDefaults.standard.object(forKey: "AgentGauge.agyPlanTierAt.\(em)") as? Date,
           Date().timeIntervalSince(savedAt) < 86_400,
           !saved.isEmpty {
            cachedBannerPlanTiersByEmail[em] = saved
            return saved
        }
        return nil
    }

    func setBannerPlanTier(_ tier: String, for email: String?) {
        guard let em = email?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !em.isEmpty, !tier.isEmpty else {
            return
        }
        lock.lock()
        cachedBannerPlanTiersByEmail[em] = tier
        lastBannerProbeAtByEmail[em] = Date()
        lock.unlock()
        UserDefaults.standard.set(tier, forKey: "AgentGauge.agyPlanTier.\(em)")
        UserDefaults.standard.set(Date(), forKey: "AgentGauge.agyPlanTierAt.\(em)")
    }

    func shouldProbeBannerTier(for email: String?) -> Bool {
        if getBannerPlanTier(for: email) != nil {
            return false
        }
        lock.lock()
        defer { lock.unlock() }
        let key = (email?.lowercased().nilIfEmpty) ?? "_default"
        if let last = lastBannerProbeAtByEmail[key], Date().timeIntervalSince(last) < 3_600 {
            return false
        }
        lastBannerProbeAtByEmail[key] = Date()
        return true
    }

    func getPayload(isAppRunning: Bool, isWorking: Bool, latestActivityMtime: Date?) -> CachedAGYPayload? {
        lock.lock()
        defer { lock.unlock() }
        guard let payload = cachedPayload else { return nil }

        let now = Date()
        // Force fresh sync as soon as any real reset clock crosses zero!
        for b in payload.buckets {
            if let r = b.resetsAt, now >= r {
                return nil
            }
        }

        // Activity-aware invalidation: if Antigravity Desktop wrote new trajectory state after our last fetch
        // and at least 35s have elapsed, refresh promptly; if completely untouched while idle, extend TTL to 480s
        // to cut expensive `agy` Go language-server spawns by ~65% with zero staleness!
        let hasNewLocalActivity = latestActivityMtime.map { $0 > payload.fetchedAt } ?? false
        let maxAge: TimeInterval = if isWorking {
            75.0
        } else if hasNewLocalActivity {
            45.0
        } else if isAppRunning {
            480.0
        } else {
            900.0
        }
        guard now.timeIntervalSince(payload.fetchedAt) <= maxAge else {
            return nil
        }
        return payload
    }

    func peekUnexpiredPayload() -> CachedAGYPayload? {
        lock.lock()
        defer { lock.unlock() }
        return cachedPayload
    }

    func setPayload(_ payload: CachedAGYPayload) {
        lock.lock()
        cachedPayload = payload
        lock.unlock()
    }
}

private actor AntigravityCLISingleFlight {
    static let shared = AntigravityCLISingleFlight()
    private var inFlight: Task<CachedAGYPayload?, Never>?

    func fetch(operation: @Sendable @escaping () -> CachedAGYPayload?) async -> CachedAGYPayload? {
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

    public static func invalidateCache() {
        AntigravityEndpointCache.shared.invalidate()
    }

    public static func currentSavedPoolFocus() -> AntigravityPoolFocus {
        if let raw = UserDefaults.standard.string(forKey: "AgentGauge.antigravityPoolFocus"),
           let mode = AntigravityPoolFocus(rawValue: raw) {
            return mode
        }
        return .autoActiveModel
    }

    public static func currentSavedUltraMultiplier(forEmail email: String? = nil) -> AntigravityUltraMultiplier {
        let defaults = UserDefaults.standard
        if let em = email?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !em.isEmpty,
           let map = defaults.dictionary(forKey: "AgentGauge.antigravityUltraMultipliersByEmail") as? [String: String],
           let raw = map[em],
           let tier = AntigravityUltraMultiplier(rawValue: raw) {
            return tier
        }
        return .auto
    }

    public static func setSavedUltraMultiplier(_ tier: AntigravityUltraMultiplier, forEmail email: String?) {
        guard let em = email?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !em.isEmpty else {
            return
        }
        let defaults = UserDefaults.standard
        var map = (defaults.dictionary(forKey: "AgentGauge.antigravityUltraMultipliersByEmail") as? [String: String]) ?? [:]
        if tier == .auto {
            map.removeValue(forKey: em)
        } else {
            map[em] = tier.rawValue
        }
        defaults.set(map, forKey: "AgentGauge.antigravityUltraMultipliersByEmail")
    }

    /// Re-evaluates cached Antigravity dual-pool buckets in <0.5ms without spawning `agy` CLI.
    /// Used when user switches models in Antigravity Desktop or toggles pool/tier settings.
    public static func reevaluateFromCache(
        poolFocus: AntigravityPoolFocus? = nil,
        ultraMultiplier: AntigravityUltraMultiplier? = nil
    ) -> QuotaSnapshot? {
        guard let payload = AntigravityEndpointCache.shared.peekUnexpiredPayload() else { return nil }
        let focus = poolFocus ?? currentSavedPoolFocus()
        let mult = ultraMultiplier ?? currentSavedUltraMultiplier(forEmail: payload.email)
        let isWorking = checkIsWorking()
        let desktopPool = (focus == .autoActiveModel) ? detectActiveDesktopPool() : nil
        return buildSnapshot(
            from: payload,
            poolFocus: focus,
            ultraMultiplier: mult,
            detectedDesktopPool: desktopPool,
            isWorking: isWorking
        )
    }

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isWorking = Self.checkIsWorking()
        let isAppRunning = await MainActor.run {
            !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.antigravity").isEmpty
        }
        let focus = Self.currentSavedPoolFocus()
        let desktopPool = (focus == .autoActiveModel) ? Self.detectActiveDesktopPool() : nil

        let latestMtime = Self.latestLocalActivityMtime()
        if let recent = AntigravityEndpointCache.shared.getPayload(isAppRunning: isAppRunning, isWorking: isWorking, latestActivityMtime: latestMtime) {
            let mult = Self.currentSavedUltraMultiplier(forEmail: recent.email)
            if let snap = Self.buildSnapshot(from: recent, poolFocus: focus, ultraMultiplier: mult, detectedDesktopPool: desktopPool, isWorking: isWorking) {
                return snap
            }
        }

        if let freshPayload = await AntigravityCLISingleFlight.shared.fetch(operation: {
            Self.fetchViaDocumentedAGYStatusLine()
        }) {
            AntigravityEndpointCache.shared.setPayload(freshPayload)
            let refreshedDesktopPool = (focus == .autoActiveModel) ? Self.detectActiveDesktopPool() : nil
            let mult = Self.currentSavedUltraMultiplier(forEmail: freshPayload.email)
            if let snap = Self.buildSnapshot(from: freshPayload, poolFocus: focus, ultraMultiplier: mult, detectedDesktopPool: refreshedDesktopPool, isWorking: isWorking) {
                return snap
            }
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

    private static func fetchViaDocumentedAGYStatusLine() -> CachedAGYPayload? {
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
        var shouldWaitForPlanTier = false
        let deadline = launchDate.addingTimeInterval(11.5)

        while Date() < deadline {
            drainStdout()

            // Continuously re-read outFile until `plan_tier` arrives:
            // agy 1.5.16+ writes `quota` first (~3.8s) and populates `plan_tier` natively ~1.5s later without any modal input!
            if (parsedRoot == nil || detectedBannerTier == nil),
               let data = try? Data(contentsOf: outFile), data.count > 20,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let quotaDict = json["quota"] as? [String: Any], !quotaDict.isEmpty {
                parsedRoot = json
                if quotaDetectedAt == nil {
                    quotaDetectedAt = Date()
                }
                if let em = (json["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !em.isEmpty {
                    parsedEmail = em
                }
                if let jsonTier = (json["plan_tier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !jsonTier.isEmpty {
                    let norm = normalizeGooglePlanTier(jsonTier)
                    detectedBannerTier = norm
                    AntigravityEndpointCache.shared.setBannerPlanTier(norm, for: parsedEmail)
                } else if detectedBannerTier == nil {
                    if let cachedTier = AntigravityEndpointCache.shared.getBannerPlanTier(for: parsedEmail) {
                        detectedBannerTier = cachedTier
                    } else if !shouldWaitForPlanTier {
                        shouldWaitForPlanTier = AntigravityEndpointCache.shared.shouldProbeBannerTier(for: parsedEmail)
                    }
                }
            }

            if detectedBannerTier == nil && !bannerBytes.isEmpty {
                if let extracted = extractPlanTierFromAGYBanner(bannerBytes) {
                    detectedBannerTier = extracted
                    AntigravityEndpointCache.shared.setBannerPlanTier(extracted, for: parsedEmail)
                }
            }

            if parsedRoot != nil {
                // Fast exit when tier is already known or cached!
                if detectedBannerTier != nil || !shouldWaitForPlanTier {
                    break
                }
                // Wait cleanly up to 4.5s after quota arrives for agy's native `plan_tier` statusLine update (only once per 24h per email!)
                if Date().timeIntervalSince(quotaDetectedAt ?? launchDate) >= 4.5 {
                    break
                }
            }

            if !proc.isRunning {
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        drainStdout()
        if let data = try? Data(contentsOf: outFile), data.count > 20,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let quotaDict = json["quota"] as? [String: Any], !quotaDict.isEmpty {
            parsedRoot = json
            if let jsonTier = (json["plan_tier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !jsonTier.isEmpty {
                let norm = normalizeGooglePlanTier(jsonTier)
                detectedBannerTier = norm
                AntigravityEndpointCache.shared.setBannerPlanTier(norm, for: parsedEmail)
            }
        }
        if detectedBannerTier == nil && !bannerBytes.isEmpty {
            if let extracted = extractPlanTierFromAGYBanner(bannerBytes) {
                detectedBannerTier = extracted
                AntigravityEndpointCache.shared.setBannerPlanTier(extracted, for: parsedEmail)
            }
        }
        if let tier = detectedBannerTier, !tier.isEmpty {
            AntigravityEndpointCache.shared.setBannerPlanTier(tier, for: parsedEmail)
        }

        // Documented graceful exit (`ESC` + `Ctrl+D Ctrl+D`), then deterministically reap child PTY & script process
        writeStdin("\u{1B}\u{04}\u{04}")
        try? inPipe.fileHandleForWriting.close()
        Thread.sleep(forTimeInterval: 0.06)

        let scriptPID = proc.processIdentifier
        SubprocessReaper.terminateAndReap(proc, killChildrenOfScriptPID: scriptPID)
        try? outPipe.fileHandleForReading.close()

        if parsedRoot == nil,
           let data = try? Data(contentsOf: outFile), data.count > 20,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            parsedRoot = json
        }

        guard let root = parsedRoot else { return nil }
        return parseStatusLinePayload(root, bannerPlanTier: detectedBannerTier)
    }

    // MARK: - Dual-Pool Parsing & Snapshot Construction (`Gemini` vs `Anthropic`)

    private static func parseStatusLinePayload(_ root: [String: Any], bannerPlanTier: String?) -> CachedAGYPayload? {
        guard let quotaDict = root["quota"] as? [String: Any], !quotaDict.isEmpty else {
            return nil
        }

        let email = (root["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let rawTier = ((root["plan_tier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
            ?? bannerPlanTier
            ?? AntigravityEndpointCache.shared.getBannerPlanTier(for: email)
        let resolvedTier = rawTier.map(normalizeGooglePlanTier)

        let modelDict = root["model"] as? [String: Any]
        let cliModelStr = ((modelDict?["display_name"] as? String) ?? (modelDict?["id"] as? String))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cliFallbackPool = classifyModelString(cliModelStr) ?? .gemini

        let now = Date()
        var buckets: [ParsedAGYBucket] = []

        for (key, val) in quotaDict {
            guard let info = val as? [String: Any] else { continue }
            if (info["disabled"] as? Bool) == true { continue }

            let rawResetDate: Date? = {
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
            } else if rawResetDate != nil {
                fraction = 0.0
            } else {
                continue
            }

            let kLower = key.lowercased()
            let pool: AntigravityModelPool = if kLower.contains("gemini") {
                .gemini
            } else if kLower.contains("3p") || kLower.contains("claude") || kLower.contains("anthropic") || kLower.contains("gpt") {
                .anthropic
            } else {
                .other
            }

            let isWeekly = kLower.contains("week") || (rawResetDate.map { $0.timeIntervalSince(now) > 26 * 3600 } ?? false)
            let is5h = !isWeekly && (kLower.contains("5h") || kLower.contains("hour") || kLower.contains("session"))

            let groupName: String = switch pool {
            case .gemini:    "Gemini"
            case .anthropic: "Claude / GPT"
            case .other:     key
            }

            let windowKind: String = if isWeekly {
                "周限额"
            } else if is5h {
                "5h 限额"
            } else {
                "限额"
            }

            // Untouched window honesty:
            // - Rolling 5h window at 100% returns a perpetual `now + 5h` horizon;
            // - Untouched 3P weekly/5h windows return Unix epoch sentinel (`1970-01-01T00:00:00Z` -> `rawResetDate == nil`).
            // Never mislead with "4h 59m" or "即将重置" when 100% quota is untouched!
            let effectiveResetDate: Date?
            let effectiveResetText: String?
            if fraction >= 0.9995 && (is5h || rawResetDate == nil) {
                effectiveResetDate = nil
                effectiveResetText = "未消耗"
            } else {
                effectiveResetDate = rawResetDate
                effectiveResetText = nil
            }

            buckets.append(ParsedAGYBucket(
                key: key,
                pool: pool,
                isWeekly: isWeekly,
                is5h: is5h,
                label: "\(groupName) · \(windowKind)",
                percent: max(0, min(100, fraction * 100.0)),
                resetsAt: effectiveResetDate,
                resetText: effectiveResetText
            ))
        }

        guard !buckets.isEmpty else { return nil }
        return CachedAGYPayload(
            email: email,
            planTier: resolvedTier,
            cliFallbackPool: cliFallbackPool,
            buckets: buckets,
            fetchedAt: now
        )
    }

    static func buildSnapshot(
        from payload: CachedAGYPayload,
        poolFocus: AntigravityPoolFocus,
        ultraMultiplier: AntigravityUltraMultiplier = .auto,
        detectedDesktopPool: AntigravityModelPool?,
        isWorking: Bool
    ) -> QuotaSnapshot? {
        let buckets = payload.buckets
        guard !buckets.isEmpty else { return nil }

        let geminiBuckets = buckets.filter { $0.pool == .gemini }
        let anthropicBuckets = buckets.filter { $0.pool == .anthropic }
        let otherBuckets = buckets.filter { $0.pool == .other }

        let geminiLimiting = geminiBuckets.min(by: {
            ($0.percent, $0.isWeekly ? 0 : 1) < ($1.percent, $1.isWeekly ? 0 : 1)
        })
        let anthropicLimiting = anthropicBuckets.min(by: {
            ($0.percent, $0.isWeekly ? 0 : 1) < ($1.percent, $1.isWeekly ? 0 : 1)
        })

        let activePool: AntigravityModelPool = switch poolFocus {
        case .geminiOnly:
            .gemini
        case .anthropicOnly:
            .anthropic
        case .minBottleneck:
            if let g = geminiLimiting, let a = anthropicLimiting {
                (a.percent < g.percent) ? .anthropic : .gemini
            } else if anthropicLimiting != nil {
                .anthropic
            } else {
                .gemini
            }
        case .autoActiveModel:
            detectedDesktopPool ?? payload.cliFallbackPool
        }

        let targetPoolBuckets: [ParsedAGYBucket] = switch activePool {
        case .gemini:    geminiBuckets.isEmpty ? buckets : geminiBuckets
        case .anthropic: anthropicBuckets.isEmpty ? buckets : anthropicBuckets
        case .other:     buckets
        }

        let primaryBucket = targetPoolBuckets.min(by: {
            ($0.percent, $0.isWeekly ? 0 : 1) < ($1.percent, $1.isWeekly ? 0 : 1)
        }) ?? buckets[0]

        // Order windows deterministically so Row 0 (`isPrimary = true`) ALWAYS matches Hero % & countdown:
        // 1) Active pool limiting bucket (`isPrimary = true`)
        // 2) Active pool remaining window(s)
        // 3) Secondary pool limiting bucket + remaining window(s)
        var orderedBuckets: [ParsedAGYBucket] = [primaryBucket]
        for b in targetPoolBuckets.sorted(by: { ($0.isWeekly ? 1 : 0, $0.key) < ($1.isWeekly ? 1 : 0, $1.key) }) where b.key != primaryBucket.key {
            orderedBuckets.append(b)
        }

        let siblingPoolBuckets: [ParsedAGYBucket] = (activePool == .anthropic) ? geminiBuckets : anthropicBuckets
        if let sibLim = siblingPoolBuckets.min(by: { ($0.percent, $0.isWeekly ? 0 : 1) < ($1.percent, $1.isWeekly ? 0 : 1) }) {
            if !orderedBuckets.contains(where: { $0.key == sibLim.key }) {
                orderedBuckets.append(sibLim)
            }
            for b in siblingPoolBuckets.sorted(by: { ($0.isWeekly ? 1 : 0, $0.key) < ($1.isWeekly ? 1 : 0, $1.key) }) where !orderedBuckets.contains(where: { $0.key == b.key }) {
                orderedBuckets.append(b)
            }
        }

        for b in otherBuckets where !orderedBuckets.contains(where: { $0.key == b.key }) {
            orderedBuckets.append(b)
        }

        let windows: [QuotaWindow] = orderedBuckets.enumerated().map { idx, b in
            QuotaWindow(
                label: b.label,
                remainingPercent: b.percent,
                resetsAt: b.resetsAt,
                resetText: b.resetText,
                isPrimary: idx == 0
            )
        }

        let subtitle: String? = {
            if let g = geminiLimiting, let a = anthropicLimiting {
                let gInt = QuotaSnapshot.displayPercentInt(g.percent)
                let aInt = QuotaSnapshot.displayPercentInt(a.percent)
                let modePrefix: String = switch poolFocus {
                case .autoActiveModel: "跟随 \(activePool.displayTitle)"
                case .minBottleneck:   "双池最低"
                case .geminiOnly:      "固定 Gemini"
                case .anthropicOnly:   "固定 Claude / GPT"
                }
                return "\(modePrefix) · Gemini \(gInt)% / Claude·GPT \(aInt)%"
            }
            return nil
        }()

        let resolvedPlanTier = applyUltraMultiplier(payload.planTier, override: ultraMultiplier)

        return QuotaSnapshot(
            agentID: .antigravity,
            remainingPercent: primaryBucket.percent,
            accountEmail: payload.email,
            planTier: resolvedPlanTier,
            primaryLabel: primaryBucket.label,
            resetsAt: primaryBucket.resetsAt,
            resetText: primaryBucket.resetText,
            windows: windows,
            subtitle: subtitle,
            isWorking: isWorking,
            sourceDescription: "Antigravity CLI",
            updatedAt: payload.fetchedAt
        )
    }

    // MARK: - Real Antigravity Desktop Active Model Pool Reader (<0.5ms Tail Read)

    static func detectActiveDesktopPool() -> AntigravityModelPool? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let brainRoot = "\(home)/.gemini/antigravity/brain"
        let fm = FileManager.default
        guard let convDirs = try? fm.contentsOfDirectory(atPath: brainRoot) else {
            return nil
        }

        var newestPath: String?
        var newestMtime: Date = .distantPast
        let cutoff = Date().addingTimeInterval(-7 * 86_400)

        for dir in convDirs where !dir.hasPrefix(".") {
            let tp = "\(brainRoot)/\(dir)/.system_generated/logs/transcript.jsonl"
            guard let attrs = try? fm.attributesOfItem(atPath: tp),
                  let mtime = attrs[.modificationDate] as? Date,
                  mtime > cutoff,
                  mtime > newestMtime else {
                continue
            }
            newestMtime = mtime
            newestPath = tp
        }

        guard let targetPath = newestPath,
              let fh = FileHandle(forReadingAtPath: targetPath) else {
            return nil
        }
        defer { try? fh.close() }

        let fileSize = (try? fh.seekToEnd()) ?? 0
        guard fileSize > 0 else { return nil }
        let readLen: UInt64 = min(fileSize, 49_152)
        try? fh.seek(toOffset: fileSize - readLen)
        let tailData = (try? fh.readToEnd()) ?? Data()
        guard !tailData.isEmpty else { return nil }

        let tailText = String(decoding: tailData, as: UTF8.self)
        let lines = tailText.split(separator: "\n")

        for rawLine in lines.reversed() {
            guard let lineData = rawLine.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            // 1. Check explicit user model dropdown switch (`<USER_SETTINGS_CHANGE> ... Model Selection ... to ...`)
            if (obj["type"] as? String) == "USER_INPUT",
               let content = obj["content"] as? String,
               content.contains("Model Selection"),
               let toRange = content.range(of: " to ", options: .backwards) {
                let after = String(content[toRange.upperBound...]).prefix(64)
                if let pool = classifyModelString(String(after)) {
                    return pool
                }
            }

            // 2. Check most recent model response (`PLANNER_RESPONSE.model`)
            if let modelField = obj["model"] as? String,
               let pool = classifyModelString(modelField) {
                return pool
            }
        }

        return nil
    }

    static func classifyModelString(_ raw: String) -> AntigravityModelPool? {
        let lower = raw.lowercased()
        guard !lower.isEmpty else { return nil }
        if lower.contains("claude")
            || lower.contains("anthropic")
            || lower.contains("sonnet")
            || lower.contains("opus")
            || lower.contains("haiku")
            || lower.contains("gpt")
            || lower.contains("o1")
            || lower.contains("o3")
            || lower.contains("o4")
            || lower.contains("3p") {
            return .anthropic
        }
        if lower.contains("gemini")
            || lower.contains("gemma")
            || lower.contains("hydrogen")
            || lower.contains("helium")
            || lower.contains("lithium")
            || lower.contains("beryllium")
            || lower.contains("boron")
            || lower.contains("carbon")
            || lower.contains("nitrogen")
            || lower.contains("oxygen")
            || lower.contains("fluorine")
            || lower.contains("neon") {
            return .gemini
        }
        return nil
    }

    // MARK: - Helpers (ANSI Stripping, Tier Normalization, Working State)

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

    static func normalizeGooglePlanTier(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.contains("ultra") {
            if lower.contains("20x") { return "Google AI Ultra (20x)" }
            if lower.contains("5x")  { return "Google AI Ultra (5x)" }
            if lower == "ultra" || lower == "ai ultra" || lower == "google ai ultra" {
                return "Google AI Ultra"
            }
        }
        if lower == "pro" || lower == "ai pro" || lower == "google ai pro" {
            return "Google AI Pro"
        }
        return trimmed
    }

    private static func applyUltraMultiplier(_ tier: String?, override: AntigravityUltraMultiplier) -> String? {
        guard let tier, !tier.isEmpty else { return nil }
        let lower = tier.lowercased()
        guard lower.contains("google ai ultra") else { return tier }
        switch override {
        case .auto:
            return tier
        case .x3:
            return "Google AI Ultra (3x)"
        case .x5:
            return "Google AI Ultra (5x)"
        case .x20:
            return "Google AI Ultra (20x)"
        }
    }

    static func parseISODate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let minValidEpoch: TimeInterval = 946_684_800 // 2000-01-01T00:00:00Z; filters out 1970-01-01 unset sentinels!
        let fFrac = ISO8601DateFormatter()
        fFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fFrac.date(from: raw) {
            return d.timeIntervalSince1970 >= minValidEpoch ? d : nil
        }

        let fStd = ISO8601DateFormatter()
        fStd.formatOptions = [.withInternetDateTime]
        if let d = fStd.date(from: raw) {
            return d.timeIntervalSince1970 >= minValidEpoch ? d : nil
        }

        if let secs = Double(raw), secs >= minValidEpoch {
            return Date(timeIntervalSince1970: secs)
        }
        return nil
    }

    private static func latestLocalActivityMtime() -> Date? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "\(home)/.gemini/antigravity/conversation_summaries.db-wal",
            "\(home)/.gemini/antigravity/conversation_summaries.db",
            "\(home)/.gemini/antigravity/cli.log"
        ]
        var newest: Date?
        for p in paths {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: p),
               let m = attrs[.modificationDate] as? Date {
                if newest == nil || m > newest! { newest = m }
            }
        }
        return newest
    }

    private static func checkIsWorking() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let summaryDB = "\(home)/.gemini/antigravity/conversation_summaries.db"
        if FileManager.default.fileExists(atPath: summaryDB) {
            var db: OpaquePointer?
            if sqlite3_open_v2(summaryDB, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let db {
                sqlite3_busy_timeout(db, 400)
                defer { sqlite3_close(db) }
                var stmt: OpaquePointer?
                let sql = "SELECT 1 FROM conversation_summaries WHERE not_fully_idle = 1 AND killed = 0 LIMIT 1;"
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
                    defer { sqlite3_finalize(stmt) }
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        return true
                    }
                }
            }
        }

        let paths = [
            "\(home)/.gemini/antigravity/cli.log",
            summaryDB
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
