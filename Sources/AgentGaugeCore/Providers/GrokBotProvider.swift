import AppKit
import Foundation

/// Native provider for Grok Bot (`com.anysphere.sand`):
/// 1. Reads Grok Bot's own persisted `weekly-usage.cache` & `account-slot` in `~/Library/Application Support/Grok Bot/sand-client-persistence/` (0ms, zero network flakiness, never fabricates fake 100%!);
/// 2. Cross-checks live Anysphere/xAI unified quota API when shared account token is available.
public struct GrokBotProvider: UsageProvider {
    public let agentID: AgentID = .grokbot

    public init() {}

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isWorking = Self.checkIsWorking()
        let cursorAuth = CursorProvider.readLocalAuthState()
        let localCache = Self.readSandPersistenceUsage(matchingEmailFrom: cursorAuth)

        // 1. If shared Anysphere/xAI token is present, try live API first for up-to-the-second precision
        if cursorAuth.accessToken != nil {
            let liveCursor = await CursorProvider().fetchSnapshot()
            if let liveRem = liveCursor.remainingPercent {
                let grokWindows = liveCursor.windows.map { win in
                    QuotaWindow(
                        label: win.label
                            .replacingOccurrences(of: "Cursor", with: "Grok")
                            .replacingOccurrences(of: "周期总额度 (主)", with: "Grok 周额度 (主)"),
                        remainingPercent: win.remainingPercent,
                        resetsAt: win.resetsAt,
                        resetText: win.resetText,
                        isPrimary: win.isPrimary
                    )
                }
                let planLabel = localCache?.planTier ?? liveCursor.planTier
                let email = localCache?.email ?? liveCursor.accountEmail
                return QuotaSnapshot(
                    agentID: .grokbot,
                    remainingPercent: liveRem,
                    accountEmail: email,
                    planTier: planLabel,
                    primaryLabel: "Grok 周额度",
                    resetsAt: liveCursor.resetsAt,
                    windows: grokWindows,
                    subtitle: liveCursor.subtitle,
                    isWorking: isWorking,
                    sourceDescription: "Grok Bot / xAI 账号"
                )
            }
        }

        // 2. Instant local Grok Bot sand-client-persistence reading (eliminates intermittent 100% jump on network hiccup!)
        if let cache = localCache {
            return QuotaSnapshot(
                agentID: .grokbot,
                remainingPercent: cache.remainingPercent,
                accountEmail: cache.email,
                planTier: cache.planTier,
                primaryLabel: "Grok 周额度",
                resetsAt: cache.resetsAt,
                windows: [
                    QuotaWindow(
                        label: "Grok Bot 周额度",
                        remainingPercent: cache.remainingPercent,
                        resetsAt: cache.resetsAt,
                        isPrimary: true
                    )
                ],
                subtitle: String(format: "本周已用 %.1f%%", cache.usedPercent),
                isWorking: isWorking,
                sourceDescription: "Grok Bot 本地缓存"
            )
        }

        return QuotaSnapshot(
            agentID: .grokbot,
            remainingPercent: nil,
            accountEmail: cursorAuth.email,
            isWorking: isWorking,
            sourceDescription: "Grok Bot 未登录",
            requiresWebLogin: true,
            errorMessage: "请打开 Grok Bot 登录账号"
        )
    }

    struct SandCachedUsage: Sendable {
        let remainingPercent: Double
        let usedPercent: Double
        let resetsAt: Date?
        let planTier: String?
        let email: String?
    }

    static func readSandPersistenceUsage(matchingEmailFrom cursorAuth: CursorLocalAuth) -> SandCachedUsage? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirPath = "\(home)/Library/Application Support/Grok Bot/sand-client-persistence"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dirPath) else {
            return nil
        }

        var activeSlot: String? = nil
        var usageDict: [String: Any]? = nil

        for fn in files where fn.hasSuffix(".blob") {
            let decodedKey = decodeBase32Filename(String(fn.dropLast(5)))
            if decodedKey == "sand.client.slice.client-meta.account-slot" {
                let fullPath = (dirPath as NSString).appendingPathComponent(fn)
                if let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let val = obj["value"] as? String {
                    activeSlot = val
                }
            } else if decodedKey.hasSuffix(".weekly-usage.cache") {
                let fullPath = (dirPath as NSString).appendingPathComponent(fn)
                if let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let val = obj["value"] as? [String: Any],
                   let reading = val["reading"] as? [String: Any],
                   let usage = reading["usage"] as? [String: Any] {
                    usageDict = usage
                }
            }
        }

        guard let usage = usageDict else { return nil }
        let used: Double
        if let d = usage["percentUsed"] as? Double {
            used = d
        } else if let i = usage["percentUsed"] as? Int {
            used = Double(i)
        } else {
            return nil
        }

        var resetsAt: Date? = nil
        if let ms = usage["nextResetMs"] as? Double, ms > 1_000_000_000_000 {
            resetsAt = Date(timeIntervalSince1970: ms / 1000.0)
        } else if let msInt = usage["nextResetMs"] as? Int, msInt > 1_000_000_000_000 {
            resetsAt = Date(timeIntervalSince1970: Double(msInt) / 1000.0)
        }

        let isTrial = (usage["isSandTrial"] as? Bool) ?? false
        let isTeam = (usage["isTeamSeat"] as? Bool) ?? false
        let unifiedPlan = (usage["unifiedPlanName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let grokLabel = (usage["grokPlanLabel"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let planTier: String? = {
            if isTrial { return "Trial" }
            if let up = unifiedPlan?.lowercased() {
                if up.contains("ultra") || up.contains("heavy") { return "SuperGrok Heavy · 20x" }
                if up.contains("super") { return "SuperGrok" }
                if up == "premium" { return isTeam ? "Premium Team" : "Premium" }
                if up == "pro" { return "Pro" }
            }
            return unifiedPlan?.nilIfEmpty ?? grokLabel?.nilIfEmpty
        }()

        var resolvedEmail: String? = nil
        if let slot = activeSlot, let cAuthId = cursorAuth.authId, slot == cAuthId {
            resolvedEmail = cursorAuth.email
        } else if cursorAuth.signUpType?.lowercased() == "grok" {
            resolvedEmail = cursorAuth.email
        }

        return SandCachedUsage(
            remainingPercent: max(0, min(100, 100.0 - used)),
            usedPercent: used,
            resetsAt: resetsAt,
            planTier: planTier,
            email: resolvedEmail
        )
    }

    private static func decodeBase32Filename(_ raw: String) -> String {
        let chars = Array(raw.uppercased())
        var buffer: UInt64 = 0
        var bitsLeft: Int = 0
        var out: [UInt8] = []
        out.reserveCapacity((chars.count * 5) / 8)

        for ch in chars {
            let val: UInt64
            if ch >= "A" && ch <= "Z" {
                val = UInt64(ch.asciiValue! - Character("A").asciiValue!)
            } else if ch >= "2" && ch <= "7" {
                val = UInt64(ch.asciiValue! - Character("2").asciiValue!) + 26
            } else {
                continue
            }
            buffer = (buffer << 5) | val
            bitsLeft += 5
            if bitsLeft >= 8 {
                bitsLeft -= 8
                out.append(UInt8((buffer >> bitsLeft) & 0xFF))
            }
        }
        return String(bytes: out, encoding: .utf8) ?? ""
    }

    private static func checkIsWorking() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "\(home)/Library/Application Support/Grok Bot/DIPS-wal",
            "\(home)/.grok/sessions"
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
