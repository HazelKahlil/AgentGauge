import AppKit
import Foundation

/// Native provider for Grok Bot (`com.anysphere.sand`):
/// 1. Reads Grok Bot's own persisted `weekly-usage.cache` & `account-slot` in `~/Library/Application Support/Grok Bot/sand-client-persistence/` (matched strictly to the exact active account slot);
/// 2. Cross-checks live Anysphere/xAI unified quota API ONLY when strict identity AND reset-epoch agreement (`<= 300s` with BOTH valid timestamps present) are proven.
public struct GrokBotProvider: UsageProvider {
    public let agentID: AgentID = .grokbot

    public init() {}

    /// Single shared cross-product sharing predicate for `Grok Bot` <-> `Cursor`:
    /// - Identity: if both sides resolved emails, normalized emails MUST match; otherwise requires exact non-empty `grokAccountSlot == cursorAuthId` (NEVER `grok|` prefix heuristics!).
    /// - Reset epochs: BOTH `grokResetsAt` and `cursorResetsAt` MUST exist, be valid (`>= 2000-01-01`), and differ by `<= 300s`.
    public static func canShareCrossProductQuota(
        grokAccountSlot: String?,
        cursorAuthId: String?,
        grokEmail: String?,
        cursorEmail: String?,
        grokResetsAt: Date?,
        cursorResetsAt: Date?
    ) -> Bool {
        let gEmail = grokEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().nilIfEmpty
        let cEmail = cursorEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().nilIfEmpty
        let gSlot = grokAccountSlot?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let cAuth = cursorAuthId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let identityMatches: Bool
        if let gEmail, let cEmail {
            guard gEmail == cEmail else { return false }
            if let gSlot, let cAuth, gSlot != cAuth {
                return false
            }
            identityMatches = true
        } else if let gSlot, let cAuth, gSlot == cAuth {
            identityMatches = true
        } else {
            identityMatches = false
        }
        guard identityMatches else { return false }

        guard let r1 = QuotaSnapshot.sanitizedResetDate(grokResetsAt),
              let r2 = QuotaSnapshot.sanitizedResetDate(cursorResetsAt) else {
            return false
        }
        return abs(r1.timeIntervalSince(r2)) <= 300.0
    }

    /// Extracts the exact account slot identifier from `sand.client.slice.account.<slot>.weekly-usage.cache`.
    static func extractSlot(fromWeeklyCacheKey decodedKey: String) -> String? {
        let prefix = "sand.client.slice.account."
        let suffix = ".weekly-usage.cache"
        guard decodedKey.hasPrefix(prefix), decodedKey.hasSuffix(suffix) else { return nil }
        let start = decodedKey.index(decodedKey.startIndex, offsetBy: prefix.count)
        let end = decodedKey.index(decodedKey.endIndex, offsetBy: -suffix.count)
        guard start < end else { return nil }
        let rawSlot = String(decodedKey[start..<end])
        return (rawSlot.removingPercentEncoding ?? rawSlot).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    /// Pure slot selector: if `activeSlot` is present, ONLY an exact slot match is accepted (never falls back to another account's older blob!).
    static func selectUsageCandidate<T>(
        activeSlot: String?,
        candidates: [(slot: String, readAtMs: Double, payload: T)]
    ) -> T? {
        if let active = activeSlot?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return candidates
                .filter { $0.slot == active }
                .max(by: { $0.readAtMs < $1.readAtMs })?
                .payload
        }
        // Only fall back when no active-slot marker exists AND there is a single unambiguous blob
        if candidates.count == 1 {
            return candidates[0].payload
        }
        return nil
    }

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isWorking = Self.checkIsWorking()
        let cursorAuth = CursorProvider.readLocalAuthState()
        let localCache = Self.readSandPersistenceUsage(matchingEmailFrom: cursorAuth)

        // 1. Only share live Cursor/Anysphere API when Grok Bot's own active-slot cache exists AND exact account slot matches Cursor's authId!
        let exactSlotMatched: Bool = {
            guard let slot = localCache?.activeSlot?.nilIfEmpty,
                  let cAuthId = cursorAuth.authId?.nilIfEmpty else {
                return false
            }
            return slot == cAuthId
        }()

        if exactSlotMatched,
           let cache = localCache,
           cursorAuth.accessToken != nil {
            let liveCursor = await CursorProvider().fetchSnapshot()
            if Self.canShareCrossProductQuota(
                grokAccountSlot: cache.activeSlot,
                cursorAuthId: cursorAuth.authId,
                grokEmail: cache.email,
                cursorEmail: liveCursor.accountEmail ?? cursorAuth.email,
                grokResetsAt: cache.resetsAt,
                cursorResetsAt: liveCursor.resetsAt
            ), let liveRem = liveCursor.remainingPercent {
                let grokWindows = liveCursor.windows.map { win in
                    QuotaWindow(
                        label: win.label
                            .replacingOccurrences(of: "Cursor", with: "Grok")
                            .replacingOccurrences(of: "周总额度", with: "Grok 周总额度")
                            .replacingOccurrences(of: "周期总额度", with: "Grok 周总额度"),
                        remainingPercent: win.remainingPercent,
                        resetsAt: win.resetsAt,
                        resetText: win.resetText,
                        isPrimary: win.isPrimary
                    )
                }
                let planLabel = cache.planTier ?? liveCursor.planTier
                let email = cache.email ?? liveCursor.accountEmail
                return QuotaSnapshot(
                    agentID: .grokbot,
                    remainingPercent: liveRem,
                    accountEmail: email,
                    planTier: planLabel,
                    primaryLabel: "Grok 周总额度",
                    resetsAt: liveCursor.resetsAt,
                    windows: grokWindows,
                    subtitle: liveCursor.subtitle,
                    isWorking: isWorking,
                    sourceDescription: "Grok Bot / xAI 账号"
                )
            }
        }

        // 2. Instant local Grok Bot sand-client-persistence reading strictly for Grok Bot's own active slot
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
            accountEmail: nil,
            isWorking: isWorking,
            sourceDescription: "Grok Bot 未登录",
            requiresWebLogin: false,
            errorMessage: "请打开 Grok Bot 桌面端登录账号"
        )
    }

    struct SandCachedUsage: Sendable {
        let activeSlot: String?
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
        var usageCandidates: [(slot: String, readAtMs: Double, payload: [String: Any])] = []

        for fn in files where fn.hasSuffix(".blob") {
            let rawDecoded = decodeBase32Filename(String(fn.dropLast(5)))
            let decodedKey = rawDecoded.removingPercentEncoding ?? rawDecoded
            let fullPath = (dirPath as NSString).appendingPathComponent(fn)

            if decodedKey == "sand.client.slice.client-meta.account-slot" {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let val = obj["value"] as? String {
                    activeSlot = (val.removingPercentEncoding ?? val).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                }
            } else if let slot = extractSlot(fromWeeklyCacheKey: decodedKey) {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let val = obj["value"] as? [String: Any],
                   let reading = val["reading"] as? [String: Any],
                   let usage = reading["usage"] as? [String: Any] {
                    let readAt = (reading["readAtMs"] as? NSNumber)?.doubleValue ?? 0
                    usageCandidates.append((slot: slot, readAtMs: readAt, payload: usage))
                }
            }
        }

        guard let usage = selectUsageCandidate(activeSlot: activeSlot, candidates: usageCandidates) else {
            return nil
        }

        let used: Double
        if let n = usage["percentUsed"] as? NSNumber {
            used = n.doubleValue
        } else {
            return nil
        }

        let resetsAt = QuotaSnapshot.parseValidResetDate(from: usage["nextResetMs"])

        let isTrial = (usage["isSandTrial"] as? Bool) ?? false
        let isTeam = (usage["isTeamSeat"] as? Bool) ?? false
        let unifiedPlan = (usage["unifiedPlanName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let grokLabel = (usage["grokPlanLabel"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let planTier: String? = {
            if isTrial { return "Trial" }
            let combined = "\(unifiedPlan ?? "") \(grokLabel ?? "")".lowercased()
            if combined.contains("heavy") || combined.contains("ultra") || combined.contains("20x") {
                return "SuperGrok Heavy · 20x"
            }
            if combined.contains("5x") {
                return "SuperGrok · 5x"
            }
            if let up = unifiedPlan?.lowercased() {
                if up.contains("super") { return "SuperGrok" }
                if up == "premium" { return isTeam ? "Premium Team" : "Premium" }
                if up == "pro" { return "Pro" }
            }
            return unifiedPlan?.nilIfEmpty ?? grokLabel?.nilIfEmpty
        }()

        // Only attach Cursor's email when exact `activeSlot == cursorAuth.authId` proves the exact same user account!
        let resolvedEmail: String? = {
            if let direct = (usage["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                return direct
            }
            if let slot = activeSlot, let cAuthId = cursorAuth.authId, !slot.isEmpty, slot == cAuthId {
                return cursorAuth.email
            }
            return nil
        }()

        return SandCachedUsage(
            activeSlot: activeSlot,
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
