import AppKit
import Foundation

/// Native provider for Grok Bot (`com.anysphere.sand`):
/// 1. Reads Grok Bot's own persisted `weekly-usage.cache` & `account-slot` in `~/Library/Application Support/Grok Bot/sand-client-persistence/` (matched strictly to active account slot);
/// 2. Cross-checks live Anysphere/xAI unified quota API ONLY when Cursor & Grok Bot share the same linked xAI/Anysphere account.
public struct GrokBotProvider: UsageProvider {
    public let agentID: AgentID = .grokbot

    public init() {}

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isWorking = Self.checkIsWorking()
        let cursorAuth = CursorProvider.readLocalAuthState()
        let localCache = Self.readSandPersistenceUsage(matchingEmailFrom: cursorAuth)

        // 1. Only share live Cursor/Anysphere API when verified as the SAME xAI-linked account!
        let isSameUnifiedAccount: Bool = {
            if let slot = localCache?.activeSlot, let cAuthId = cursorAuth.authId, !slot.isEmpty, slot == cAuthId {
                return true
            }
            if cursorAuth.signUpType?.lowercased() == "grok" {
                return localCache == nil || localCache?.activeSlot?.lowercased().hasPrefix("grok|") == true
            }
            return false
        }()

        if isSameUnifiedAccount, cursorAuth.accessToken != nil {
            let liveCursor = await CursorProvider().fetchSnapshot()
            // Double-verify reset epoch agreement: if both timestamps exist and differ by >5 min, they are separate billing buckets!
            let epochsAgree: Bool = {
                if let r1 = localCache?.resetsAt, let r2 = liveCursor.resetsAt {
                    return abs(r1.timeIntervalSince(r2)) <= 300.0
                }
                return true
            }()
            if epochsAgree, let liveRem = liveCursor.remainingPercent {
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
                let planLabel = localCache?.planTier ?? liveCursor.planTier
                let email = localCache?.email ?? liveCursor.accountEmail
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

        // 2. Instant local Grok Bot sand-client-persistence reading for Grok Bot's own active slot
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
            accountEmail: isSameUnifiedAccount ? cursorAuth.email : nil,
            isWorking: isWorking,
            sourceDescription: "Grok Bot 未登录",
            requiresWebLogin: true,
            errorMessage: "请打开 Grok Bot 登录账号"
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
        var usageCandidates: [(slotKey: String, readAtMs: Double, usage: [String: Any])] = []

        for fn in files where fn.hasSuffix(".blob") {
            let rawDecoded = decodeBase32Filename(String(fn.dropLast(5)))
            let decodedKey = rawDecoded.removingPercentEncoding ?? rawDecoded
            let fullPath = (dirPath as NSString).appendingPathComponent(fn)

            if decodedKey == "sand.client.slice.client-meta.account-slot" {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let val = obj["value"] as? String {
                    activeSlot = val.removingPercentEncoding ?? val
                }
            } else if decodedKey.hasSuffix(".weekly-usage.cache") {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let val = obj["value"] as? [String: Any],
                   let reading = val["reading"] as? [String: Any],
                   let usage = reading["usage"] as? [String: Any] {
                    let readAt = (reading["readAtMs"] as? NSNumber)?.doubleValue ?? 0
                    usageCandidates.append((slotKey: decodedKey, readAtMs: readAt, usage: usage))
                }
            }
        }

        // Match exact active account slot first; fall back to most recently read usage blob
        let matchedUsage: [String: Any]? = {
            if let slot = activeSlot, !slot.isEmpty {
                if let exact = usageCandidates.first(where: { $0.slotKey.contains(slot) }) {
                    return exact.usage
                }
            }
            return usageCandidates.max(by: { $0.readAtMs < $1.readAtMs })?.usage
        }()

        guard let usage = matchedUsage else { return nil }
        let used: Double
        if let n = usage["percentUsed"] as? NSNumber {
            used = n.doubleValue
        } else {
            return nil
        }

        var resetsAt: Date? = nil
        if let ms = (usage["nextResetMs"] as? NSNumber)?.doubleValue, ms > 1_000_000_000_000 {
            resetsAt = Date(timeIntervalSince1970: ms / 1000.0)
        }

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

        var resolvedEmail: String? = nil
        if let slot = activeSlot, let cAuthId = cursorAuth.authId, slot == cAuthId {
            resolvedEmail = cursorAuth.email
        } else if cursorAuth.signUpType?.lowercased() == "grok",
                  (activeSlot == nil || activeSlot?.lowercased().hasPrefix("grok|") == true) {
            resolvedEmail = cursorAuth.email
        }

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
