import CryptoKit
import CoreGraphics
import Foundation
import XCTest
@testable import AgentGaugeCore

final class AgentGaugeCoreTests: XCTestCase {

    // MARK: - 1. Boundary-Honest Percentage Rounding

    func testBoundaryHonestPercentRounding() {
        XCTAssertEqual(QuotaSnapshot.displayPercentInt(-5.0), 0)
        XCTAssertEqual(QuotaSnapshot.displayPercentInt(0.0), 0)
        XCTAssertEqual(QuotaSnapshot.displayPercentInt(0.05), 0)
        XCTAssertEqual(QuotaSnapshot.displayPercentInt(0.06), 1)
        XCTAssertEqual(QuotaSnapshot.displayPercentInt(0.35), 1, "Sliver remaining must never display as 0%")
        XCTAssertEqual(QuotaSnapshot.displayPercentInt(0.99), 1)
        XCTAssertEqual(QuotaSnapshot.displayPercentInt(1.988), 2)
        XCTAssertEqual(QuotaSnapshot.displayPercentInt(50.4), 50)
        XCTAssertEqual(QuotaSnapshot.displayPercentInt(99.01), 99)
        XCTAssertEqual(QuotaSnapshot.displayPercentInt(99.6), 99, "Consumed pool must never display as untouched 100%")
        XCTAssertEqual(QuotaSnapshot.displayPercentInt(99.94), 99)
        XCTAssertEqual(QuotaSnapshot.displayPercentInt(99.95), 100)
        XCTAssertEqual(QuotaSnapshot.displayPercentInt(100.0), 100)
        XCTAssertEqual(QuotaSnapshot.displayPercentInt(125.0), 100)
    }

    // MARK: - 2. Cross-Platform 3x / 5x / 20x Plan Multiplier Engine

    func testCrossPlatformPlanMultiplierBadgesAndOverrides() {
        let cases: [(AgentID, String?, PlanMultiplierChoice, String)] = [
            (.antigravity, "Google AI Ultra", .x5, "AI Ultra · 5x"),
            (.antigravity, "Google AI Ultra", .x20, "AI Ultra · 20x"),
            (.antigravity, "Google AI Ultra (5x)", .x20, "AI Ultra · 20x"),
            (.antigravity, nil, .x20, "AI Ultra · 20x"),
            (.gemini, "Google AI Ultra", .x20, "AI Ultra · 20x"),
            (.codex, "ChatGPT Pro (20x)", .auto, "Pro · 20x"),
            (.codex, "ChatGPT Pro (20x)", .x5, "Pro Lite · 5x"),
            (.codex, "ChatGPT Pro Lite (5x)", .x20, "Pro · 20x"),
            (.claude, "Claude Max (20x)", .auto, "Max · 20x"),
            (.claude, "Claude Max", .x5, "Max · 5x"),
            (.claude, "Claude Pro", .x20, "Max · 20x"),
            (.cursor, "Pro+ · 3x", .auto, "Pro+ · 3x"),
            (.cursor, "Ultra · 20x", .auto, "Ultra · 20x"),
            (.cursor, "Pro", .x3, "Pro · 3x"),
            (.grokbot, "SuperGrok Heavy · 20x", .auto, "Heavy · 20x"),
            (.grok, nil, .x20, "Heavy · 20x"),
            // Long custom tier name must NEVER truncate its explicit 20x multiplier
            (.antigravity, "Enterprise SuperLongWorkspaceTier (20x)", .auto, "Enterpris… · 20x")
        ]

        for (agentID, rawTier, choice, expected) in cases {
            let snap = QuotaSnapshot(
                agentID: agentID,
                remainingPercent: 72,
                planTier: rawTier,
                sourceDescription: "unit-test"
            ).applyingPlanMultiplier(choice)
            XCTAssertEqual(
                snap.compactPlanBadge,
                expected,
                "Failed for \(agentID.rawValue) raw='\(rawTier ?? "nil")' choice=\(choice.rawValue)"
            )
        }

        XCTAssertEqual(QuotaSnapshot.stripMultiplierSuffix(from: "Google AI Ultra (20x)"), "Google AI Ultra")
        XCTAssertEqual(QuotaSnapshot.stripMultiplierSuffix(from: "Ultra · 20x"), "Ultra")
        XCTAssertEqual(QuotaSnapshot.stripMultiplierSuffix(from: "Claude Max 5x"), "Claude Max")
    }

    // MARK: - 3. Provider Plan Formatters

    func testProviderPlanFormatters() {
        XCTAssertEqual(CodexProvider.formatOpenAIPlan(rawPlan: "pro", workspaceName: nil), "ChatGPT Pro (20x)")
        XCTAssertEqual(CodexProvider.formatOpenAIPlan(rawPlan: "pro_lite", workspaceName: nil), "ChatGPT Pro Lite (5x)")
        XCTAssertEqual(CodexProvider.formatOpenAIPlan(rawPlan: "plus", workspaceName: nil), "ChatGPT Plus")
        XCTAssertEqual(CodexProvider.formatOpenAIPlan(rawPlan: "team", workspaceName: "Studio"), "Team (Studio)")

        XCTAssertEqual(ClaudeProvider.formatClaudePlan(subscriptionType: "max", rateLimitTier: "default_claude_max_20x"), "Claude Max (20x)")
        XCTAssertEqual(ClaudeProvider.formatClaudePlan(subscriptionType: "max", rateLimitTier: "default_claude_max_5x"), "Claude Max (5x)")
        XCTAssertEqual(ClaudeProvider.formatClaudePlan(subscriptionType: "pro", rateLimitTier: nil), "Claude Pro")

        XCTAssertEqual(CursorProvider.formatCursorPlan(rawPlan: "ultra", isMergedGrok: false), "Ultra · 20x")
        XCTAssertEqual(CursorProvider.formatCursorPlan(rawPlan: "pro_plus", isMergedGrok: false), "Pro+ · 3x")
        XCTAssertEqual(CursorProvider.formatCursorPlan(rawPlan: "premium", isMergedGrok: true), "Premium (xAI 互通)")

        XCTAssertEqual(AntigravityProvider.normalizeGooglePlanTier("AI Ultra"), "Google AI Ultra")
        XCTAssertEqual(AntigravityProvider.normalizeGooglePlanTier("Google AI Ultra 20x"), "Google AI Ultra (20x)")
        XCTAssertEqual(AntigravityProvider.normalizeGooglePlanTier("Google AI Ultra 5x"), "Google AI Ultra (5x)")
        XCTAssertEqual(AntigravityProvider.normalizeGooglePlanTier("ai pro"), "Google AI Pro")
    }

    // MARK: - 4. Unset 1970 Epoch Sentinel Rejection

    func testEpochSentinelFiltering() {
        XCTAssertNil(AntigravityProvider.parseISODate(nil))
        XCTAssertNil(AntigravityProvider.parseISODate(""))
        XCTAssertNil(AntigravityProvider.parseISODate("1970-01-01T00:00:00Z"))
        XCTAssertNil(AntigravityProvider.parseISODate("1970-01-01T00:00:00.000Z"))
        XCTAssertNil(AntigravityProvider.parseISODate("0"))
        XCTAssertNil(AntigravityProvider.parseISODate("1999-12-31T23:59:59Z"))

        let validStd = AntigravityProvider.parseISODate("2026-11-26T12:00:00Z")
        XCTAssertNotNil(validStd)
        let validFrac = AntigravityProvider.parseISODate("2026-11-26T12:00:00.250Z")
        XCTAssertNotNil(validFrac)
        let validEpoch = AntigravityProvider.parseISODate("1795608000")
        XCTAssertNotNil(validEpoch)
    }

    // MARK: - 5. Antigravity Model Pool Classification

    func testAntigravityModelClassification() {
        XCTAssertEqual(AntigravityProvider.classifyModelString("claude-sonnet-4-6"), .anthropic)
        XCTAssertEqual(AntigravityProvider.classifyModelString("claude-opus-4-6"), .anthropic)
        XCTAssertEqual(AntigravityProvider.classifyModelString("gpt-oss-120b"), .anthropic)
        XCTAssertEqual(AntigravityProvider.classifyModelString("3p-weekly"), .anthropic)
        XCTAssertEqual(AntigravityProvider.classifyModelString("gemini-3.1-pro"), .gemini)
        XCTAssertEqual(AntigravityProvider.classifyModelString("gemma-3-27b"), .gemini)
        XCTAssertNil(AntigravityProvider.classifyModelString(""))
        XCTAssertNil(AntigravityProvider.classifyModelString("unknown-local-model"))
    }

    // MARK: - 6. Claude 0..100 Utilization Scaling (No 100x Jump at <= 1.0%)

    func testClaudeUtilizationScalingNeverMultipliesSmallPercentBy100() {
        XCTAssertEqual(ClaudeProvider.remainingPercent(fromAnthropicUtilization: 0.0), 100.0, accuracy: 0.0001)
        XCTAssertEqual(ClaudeProvider.remainingPercent(fromAnthropicUtilization: 0.5), 99.5, accuracy: 0.0001)
        XCTAssertEqual(ClaudeProvider.remainingPercent(fromAnthropicUtilization: 1.0), 99.0, accuracy: 0.0001)
        XCTAssertEqual(ClaudeProvider.remainingPercent(fromAnthropicUtilization: 42.5), 57.5, accuracy: 0.0001)
        XCTAssertEqual(ClaudeProvider.remainingPercent(fromAnthropicUtilization: 100.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(ClaudeProvider.remainingPercent(fromAnthropicUtilization: 120.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(ClaudeProvider.remainingPercent(fromAnthropicUtilization: -3.0), 100.0, accuracy: 0.0001)
    }

    // MARK: - 7. Dock Hover Schmitt-Trigger Hysteresis

    @MainActor
    func testSchmittTriggerDockHysteresis() {
        let rectA = CGRect(x: 100, y: 1000, width: 68, height: 68)
        let rectB = CGRect(x: 176, y: 1000, width: 68, height: 68)
        var current = "A"
        var switches = 0

        for i in 0..<200 {
            let pt = CGPoint(x: 176.0 + CGFloat(i.isMultiple(of: 2) ? 2.5 : -2.5), y: 1034)
            if rectB.contains(pt), current != "B",
               OverlayManager.shouldCommitNeighborSwitch(cursor: pt, candidateAXFrame: rectB, orientation: .bottom) {
                current = "B"
                switches += 1
            } else if rectA.contains(pt), current != "A",
                      OverlayManager.shouldCommitNeighborSwitch(cursor: pt, candidateAXFrame: rectA, orientation: .bottom) {
                current = "A"
                switches += 1
            }
        }
        XCTAssertEqual(switches, 0, "Seam micro-jitter must produce zero switches")

        for x in stride(from: 120.0, through: 200.0, by: 1.0) {
            let pt = CGPoint(x: x, y: 1034)
            if rectB.contains(pt), current != "B",
               OverlayManager.shouldCommitNeighborSwitch(cursor: pt, candidateAXFrame: rectB, orientation: .bottom) {
                current = "B"
                switches += 1
            }
        }
        for x in stride(from: 200.0, through: 120.0, by: -1.0) {
            let pt = CGPoint(x: x, y: 1034)
            if rectA.contains(pt), current != "A",
               OverlayManager.shouldCommitNeighborSwitch(cursor: pt, candidateAXFrame: rectA, orientation: .bottom) {
                current = "A"
                switches += 1
            }
        }
        XCTAssertEqual(switches, 2)
        XCTAssertEqual(current, "A")

        // Left-dock vertical axis check
        let leftRect = CGRect(x: 4, y: 200, width: 64, height: 64)
        XCTAssertFalse(OverlayManager.shouldCommitNeighborSwitch(cursor: CGPoint(x: 36, y: 202), candidateAXFrame: leftRect, orientation: .left))
        XCTAssertTrue(OverlayManager.shouldCommitNeighborSwitch(cursor: CGPoint(x: 36, y: 210), candidateAXFrame: leftRect, orientation: .left))
    }

    // MARK: - 8. UpdateManager SemVer & Ed25519 Cryptographic Integrity

    func testUpdateManagerSemVerAndEd25519Signature() throws {
        XCTAssertTrue(UpdateManager.isRemoteNewer(remoteVersion: "1.3.3", remoteBuild: 133, currentVersion: "1.3.2", currentBuild: 132))
        XCTAssertTrue(UpdateManager.isRemoteNewer(remoteVersion: "1.10.0", remoteBuild: 1100, currentVersion: "1.3.3", currentBuild: 133))
        XCTAssertTrue(UpdateManager.isRemoteNewer(remoteVersion: "1.3.3", remoteBuild: 134, currentVersion: "1.3.3", currentBuild: 133))
        XCTAssertFalse(UpdateManager.isRemoteNewer(remoteVersion: "1.3.3", remoteBuild: 133, currentVersion: "1.3.3", currentBuild: 133))
        XCTAssertFalse(UpdateManager.isRemoteNewer(remoteVersion: "1.3.2", remoteBuild: 132, currentVersion: "1.3.3", currentBuild: 133))

        // Ephemeral Ed25519 keypair + archive verification
        let priv = Curve25519.Signing.PrivateKey()
        let pubB64 = priv.publicKey.rawRepresentation.base64EncodedString()
        let payloadBytes = Data("synthetic-agentgauge-ota-archive-bytes".utf8)
        let shaHex = SHA256.hash(data: payloadBytes).map { String(format: "%02x", $0) }.joined()
        let canonical = UpdateManager.canonicalSignedPayload(version: "1.3.3", build: 133, sha256: shaHex)
        let sigB64 = try priv.signature(for: canonical).base64EncodedString()

        XCTAssertTrue(UpdateManager.verifyManifestSignature(version: "1.3.3", build: 133, sha256: shaHex, signatureBase64: sigB64, publicKeyBase64: pubB64))
        XCTAssertFalse(UpdateManager.verifyManifestSignature(version: "9.9.9", build: 133, sha256: shaHex, signatureBase64: sigB64, publicKeyBase64: pubB64))
        XCTAssertFalse(UpdateManager.verifyManifestSignature(version: "1.3.3", build: 134, sha256: shaHex, signatureBase64: sigB64, publicKeyBase64: pubB64))

        let tmpArchive = FileManager.default.temporaryDirectory.appendingPathComponent("ag-test-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: tmpArchive) }
        try payloadBytes.write(to: tmpArchive)

        let manifest = ReleaseManifest(
            version: "1.3.3",
            build: 133,
            zipUrl: "https://usage.komorebi.date/downloads/AgentGauge-macOS.zip",
            sha256: shaHex,
            signature: sigB64,
            isFromSignedFeed: true
        )
        XCTAssertNoThrow(try UpdateManager.verifyArchiveCryptographically(at: tmpArchive, manifest: manifest, publicKeyBase64: pubB64))

        var tampered = payloadBytes
        tampered[0] ^= 0xFF
        try tampered.write(to: tmpArchive)
        XCTAssertThrowsError(try UpdateManager.verifyArchiveCryptographically(at: tmpArchive, manifest: manifest, publicKeyBase64: pubB64))
    }

    // MARK: - 9. Currency / Credits / Nil Formatting (Zero Fake 100%)

    func testCurrencyCreditsAndUnauthenticatedFormatting() {
        let deepSeek = QuotaSnapshot(
            agentID: .deepseek,
            remainingPercent: 48,
            balanceDisplay: "¥28.50",
            dockBalanceShort: "¥29",
            sourceDescription: "api"
        )
        XCTAssertEqual(deepSeek.formattedCardValue(showPercentageSign: true), "¥28.50")
        XCTAssertEqual(deepSeek.formattedDockIconValue(showPercentageSign: true), "¥29")
        XCTAssertEqual(deepSeek.formattedTooltipValue(showPercentageSign: true), "余额 ¥28.50")

        let credits3k = QuotaSnapshot(agentID: .workbuddy, remainingPercent: 52, creditsRemaining: 3177, creditsTotal: 6068, sourceDescription: "api")
        XCTAssertEqual(credits3k.formattedDockIconValue(showPercentageSign: true), "3.2k")
        XCTAssertEqual(credits3k.formattedCardValue(showPercentageSign: true), "3177 积分")
        XCTAssertEqual(credits3k.formattedTooltipValue(showPercentageSign: true), "剩 3177/6068 积分")

        let unauth = QuotaSnapshot(agentID: .gemini, remainingPercent: nil, sourceDescription: "web", requiresWebLogin: true)
        XCTAssertEqual(unauth.formattedCardValue(showPercentageSign: true), "—")
        XCTAssertEqual(unauth.formattedDockIconValue(showPercentageSign: true), "")
        XCTAssertEqual(unauth.formattedTooltipValue(showPercentageSign: true), "—")
    }

    // MARK: - 10. QuotaWindow Countdown Formatting

    func testQuotaWindowCountdownFormatting() {
        let now = Date(timeIntervalSince1970: 1_795_600_000)
        let expired = QuotaWindow(label: "5h", remainingPercent: 40, resetsAt: now.addingTimeInterval(-10))
        XCTAssertEqual(expired.formattedCountdown(now: now), "即将重置")

        let untouched = QuotaWindow(label: "5h", remainingPercent: 100, resetsAt: nil, resetText: "未消耗")
        XCTAssertEqual(untouched.formattedCountdown(now: now), "未消耗")

        let twoHours = QuotaWindow(label: "5h", remainingPercent: 50, resetsAt: now.addingTimeInterval(2 * 3600 + 15 * 60))
        XCTAssertEqual(twoHours.formattedCountdown(now: now), "2h 15m")

        let threeDays = QuotaWindow(label: "7d", remainingPercent: 50, resetsAt: now.addingTimeInterval(3 * 86400 + 4 * 3600))
        XCTAssertEqual(threeDays.formattedCountdown(now: now), "3d 4h")
    }

    // MARK: - 11. Product-Boundary Bundle ID Disjointness

    func testProductBoundaryBundleIDsDisjoint() {
        var seen: [String: AgentID] = [:]
        for agent in AgentID.allCases {
            for bid in agent.bundleIdentifiers {
                if let prior = seen[bid] {
                    XCTFail("Bundle ID '\(bid)' collides between \(prior.rawValue) and \(agent.rawValue)")
                }
                seen[bid] = agent
            }
        }
        XCTAssertTrue(Set(AgentID.gemini.bundleIdentifiers).isDisjoint(with: Set(AgentID.antigravity.bundleIdentifiers)))
        XCTAssertTrue(Set(AgentID.grok.bundleIdentifiers).isDisjoint(with: Set(AgentID.grokbot.bundleIdentifiers)))
    }

    // MARK: - 12. Meaningful Snapshot Diff Filtering

    func testMeaningfulSnapshotChangeDetection() {
        let a = QuotaSnapshot(
            agentID: .codex,
            remainingPercent: 80.1,
            planTier: "ChatGPT Pro Lite (5x)",
            windows: [QuotaWindow(label: "5h", remainingPercent: 80.1, isPrimary: true)],
            sourceDescription: "cli"
        )
        let bSameRounded = QuotaSnapshot(
            agentID: .codex,
            remainingPercent: 80.4,
            planTier: "ChatGPT Pro Lite (5x)",
            windows: [QuotaWindow(label: "5h", remainingPercent: 80.4, isPrimary: true)],
            sourceDescription: "cli"
        )
        let cTierChanged = bSameRounded.applyingPlanMultiplier(.x20)

        XCTAssertTrue(a.hasMeaningfulChange(from: nil))
        XCTAssertFalse(bSameRounded.hasMeaningfulChange(from: a))
        XCTAssertTrue(cTierChanged.hasMeaningfulChange(from: bSameRounded))
    }

    // MARK: - 13. Fail-Closed Unsigned OTA Update Rejection

    func testUnsignedOrDigestlessUpdateManifestIsAlwaysRejected() throws {
        let payloadBytes = Data("unverified-archive-payload".utf8)
        let shaHex = SHA256.hash(data: payloadBytes).map { String(format: "%02x", $0) }.joined()
        let tmpArchive = FileManager.default.temporaryDirectory.appendingPathComponent("ag-unsigned-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: tmpArchive) }
        try payloadBytes.write(to: tmpArchive)

        // Even with `isFromSignedFeed: false`, missing signature or missing sha256 MUST throw!
        let unsignedManifest = ReleaseManifest(
            version: "1.3.4",
            build: 134,
            zipUrl: "https://github.com/HazelKahlil/AgentGauge/releases/latest/download/AgentGauge-macOS.zip",
            sha256: shaHex,
            signature: nil,
            isFromSignedFeed: false
        )
        XCTAssertThrowsError(try UpdateManager.verifyArchiveCryptographically(at: tmpArchive, manifest: unsignedManifest))

        let digestlessManifest = ReleaseManifest(
            version: "1.3.4",
            build: 134,
            zipUrl: "https://github.com/HazelKahlil/AgentGauge/releases/latest/download/AgentGauge-macOS.zip",
            sha256: nil,
            signature: nil,
            isFromSignedFeed: false
        )
        XCTAssertThrowsError(try UpdateManager.verifyArchiveCryptographically(at: tmpArchive, manifest: digestlessManifest))
    }

    // MARK: - 14. Strict Cursor <-> Grok Bot Cross-Product Sharing & Exact Slot Selection

    func testGrokBotCrossProductSharingAndExactSlotIsolation() {
        let baseReset = Date(timeIntervalSince1970: 1_800_000_000)

        // Matching email + valid resets within 300s -> allowed
        XCTAssertTrue(GrokBotProvider.canShareCrossProductQuota(
            grokAccountSlot: "grok|user_1",
            cursorAuthId: "grok|user_1",
            grokEmail: "User@Example.com",
            cursorEmail: "user@example.com",
            grokResetsAt: baseReset,
            cursorResetsAt: baseReset.addingTimeInterval(300)
        ))

        // Different emails -> strictly rejected even if reset epochs match!
        XCTAssertFalse(GrokBotProvider.canShareCrossProductQuota(
            grokAccountSlot: "grok|user_1",
            cursorAuthId: "grok|user_1",
            grokEmail: "alice@example.com",
            cursorEmail: "bob@example.com",
            grokResetsAt: baseReset,
            cursorResetsAt: baseReset
        ))

        // Different xAI slots (`grok|` prefix heuristic MUST NOT bypass identity!) -> rejected
        XCTAssertFalse(GrokBotProvider.canShareCrossProductQuota(
            grokAccountSlot: "grok|user_A",
            cursorAuthId: "grok|user_B",
            grokEmail: nil,
            cursorEmail: "user@example.com",
            grokResetsAt: baseReset,
            cursorResetsAt: baseReset
        ))

        // Missing reset timestamp on either side -> strictly rejected
        XCTAssertFalse(GrokBotProvider.canShareCrossProductQuota(
            grokAccountSlot: "grok|user_1",
            cursorAuthId: "grok|user_1",
            grokEmail: "user@example.com",
            cursorEmail: "user@example.com",
            grokResetsAt: nil,
            cursorResetsAt: baseReset
        ))
        XCTAssertFalse(GrokBotProvider.canShareCrossProductQuota(
            grokAccountSlot: "grok|user_1",
            cursorAuthId: "grok|user_1",
            grokEmail: "user@example.com",
            cursorEmail: "user@example.com",
            grokResetsAt: baseReset,
            cursorResetsAt: nil
        ))

        // 301s reset drift -> strictly rejected
        XCTAssertFalse(GrokBotProvider.canShareCrossProductQuota(
            grokAccountSlot: "grok|user_1",
            cursorAuthId: "grok|user_1",
            grokEmail: "user@example.com",
            cursorEmail: "user@example.com",
            grokResetsAt: baseReset,
            cursorResetsAt: baseReset.addingTimeInterval(301)
        ))

        // Exact slot parsing & new active slot with no cache must NEVER return older account's blob!
        XCTAssertEqual(
            GrokBotProvider.extractSlot(fromWeeklyCacheKey: "sand.client.slice.account.grok%7Cuser_ABC.weekly-usage.cache"),
            "grok|user_ABC"
        )
        let candidates = [
            (slot: "grok|user_OLD", readAtMs: 999_999.0, payload: "old_quota"),
            (slot: "grok|user_1", readAtMs: 500_000.0, payload: "slot1_quota")
        ]
        XCTAssertEqual(GrokBotProvider.selectUsageCandidate(activeSlot: "grok|user_1", candidates: candidates), "slot1_quota")
        XCTAssertNil(GrokBotProvider.selectUsageCandidate(activeSlot: "grok|user_NEW_NO_CACHE", candidates: candidates))
    }

    // MARK: - 15. Store Transient-Error Identity & Pool Preservation Guard

    @MainActor
    func testStorePreservesQuotaOnlyForSameConfirmedIdentityAndPool() {
        let prevA = QuotaSnapshot(
            agentID: .cursor,
            remainingPercent: 64,
            accountEmail: "alice@example.com",
            planTier: "Ultra · 20x",
            primaryLabel: "Cursor",
            sourceDescription: "api"
        )
        let transientSameA = QuotaSnapshot(
            agentID: .cursor,
            remainingPercent: nil,
            accountEmail: "ALICE@example.com",
            planTier: "Ultra · 20x",
            primaryLabel: "Cursor",
            sourceDescription: "api",
            requiresWebLogin: false,
            errorMessage: "timeout"
        )
        let transientSwitchedB = QuotaSnapshot(
            agentID: .cursor,
            remainingPercent: nil,
            accountEmail: "bob@example.com",
            planTier: "Pro",
            primaryLabel: "Cursor",
            sourceDescription: "api",
            requiresWebLogin: false,
            errorMessage: "timeout"
        )
        let transientSignedOut = QuotaSnapshot(
            agentID: .cursor,
            remainingPercent: nil,
            accountEmail: nil,
            sourceDescription: "api",
            requiresWebLogin: false
        )

        XCTAssertTrue(AgentGaugeStore.shouldPreservePreviousQuota(previous: prevA, fresh: transientSameA))
        XCTAssertFalse(AgentGaugeStore.shouldPreservePreviousQuota(previous: prevA, fresh: transientSwitchedB))
        XCTAssertFalse(AgentGaugeStore.shouldPreservePreviousQuota(previous: prevA, fresh: transientSignedOut))

        // Antigravity switching from Gemini pool to missing Claude/GPT pool MUST NOT restore Gemini pool!
        let agPrevGem = QuotaSnapshot(
            agentID: .antigravity,
            remainingPercent: 88,
            accountEmail: "dev@example.com",
            primaryLabel: "Gemini · 5h 限额",
            sourceDescription: "cli"
        )
        let agMissing3P = QuotaSnapshot(
            agentID: .antigravity,
            remainingPercent: nil,
            accountEmail: "dev@example.com",
            primaryLabel: "Claude / GPT",
            sourceDescription: "cli",
            errorMessage: "所选 Claude / GPT 池暂无数据"
        )
        XCTAssertFalse(AgentGaugeStore.shouldPreservePreviousQuota(previous: agPrevGem, fresh: agMissing3P))
    }

    // MARK: - 16. Antigravity Fixed-Pool Isolation When Target Pool Is Missing

    func testAntigravityMissingFixedPoolNeverBorrowsOtherPool() {
        let now = Date()
        let geminiOnlyPayload = CachedAGYPayload(
            email: "dev@example.com",
            planTier: "Google AI Ultra",
            cliFallbackPool: .gemini,
            buckets: [
                ParsedAGYBucket(key: "gemini-5h", pool: .gemini, isWeekly: false, is5h: true, label: "Gemini · 5h 限额", percent: 80, resetsAt: nil, resetText: nil)
            ],
            fetchedAt: now
        )

        let snapAnthropicFixed = AntigravityProvider.buildSnapshot(
            from: geminiOnlyPayload,
            poolFocus: .anthropicOnly,
            detectedDesktopPool: nil,
            isWorking: false
        )
        XCTAssertNotNil(snapAnthropicFixed)
        XCTAssertNil(snapAnthropicFixed?.remainingPercent, "Fixed Claude/GPT pool MUST NOT display Gemini's 80%!")
        XCTAssertEqual(snapAnthropicFixed?.windows.first?.isPrimary, false)

        let snapMin = AntigravityProvider.buildSnapshot(
            from: geminiOnlyPayload,
            poolFocus: .minBottleneck,
            detectedDesktopPool: nil,
            isWorking: false
        )
        XCTAssertEqual(snapMin?.remainingPercent, 80)

        let claudeOnlyPayload = CachedAGYPayload(
            email: "dev@example.com",
            planTier: "Google AI Ultra",
            cliFallbackPool: .anthropic,
            buckets: [
                ParsedAGYBucket(key: "3p-weekly", pool: .anthropic, isWeekly: true, is5h: false, label: "Claude / GPT · 周限额", percent: 45, resetsAt: nil, resetText: nil)
            ],
            fetchedAt: now
        )
        let snapGeminiFixed = AntigravityProvider.buildSnapshot(
            from: claudeOnlyPayload,
            poolFocus: .geminiOnly,
            detectedDesktopPool: nil,
            isWorking: false
        )
        XCTAssertNotNil(snapGeminiFixed)
        XCTAssertNil(snapGeminiFixed?.remainingPercent, "Fixed Gemini pool MUST NOT display Claude/GPT's 45%!")
    }

    // MARK: - 17. Per-Product Multiplier Isolation & Clean `.auto` Reset

    @MainActor
    func testPlanMultiplierStrictProductIsolationAndAutoReset() {
        // Missing email MUST NOT generate a global key
        XCTAssertNil(AgentGaugeStore.planMultiplierAccountKey(agentID: .antigravity, email: nil))
        XCTAssertNil(AgentGaugeStore.planMultiplierAccountKey(agentID: .antigravity, email: "   "))
        XCTAssertEqual(
            AgentGaugeStore.planMultiplierAccountKey(agentID: .antigravity, email: "Test@Example.com"),
            "antigravity|test@example.com"
        )

        let store = AgentGaugeStore.shared
        let testEmail = "unit-isolation-\(UUID().uuidString)@example.com"
        defer {
            store.setPlanMultiplier(.auto, for: .gemini, email: testEmail)
            store.setPlanMultiplier(.auto, for: .antigravity, email: testEmail)
        }

        // Setting Gemini 5x MUST NOT leak into Antigravity for the same email
        store.setPlanMultiplier(.x5, for: .gemini, email: testEmail)
        XCTAssertEqual(store.planMultiplier(for: .gemini, email: testEmail), .x5)
        XCTAssertEqual(store.planMultiplier(for: .antigravity, email: testEmail), .auto)

        // Applying 5x -> receiving raw snapshot -> resetting to .auto MUST restore clean raw badge ("AI Ultra")
        store.setPlanMultiplier(.x5, for: .antigravity, email: testEmail)
        let rawSnap = QuotaSnapshot(
            agentID: .antigravity,
            remainingPercent: 90,
            accountEmail: testEmail,
            planTier: "Google AI Ultra",
            sourceDescription: "unit-test"
        )
        XCTAssertEqual(store.applySavedPlanMultiplier(to: rawSnap).compactPlanBadge, "AI Ultra · 5x")
        store.setPlanMultiplier(.auto, for: .antigravity, email: testEmail)
        XCTAssertEqual(store.applySavedPlanMultiplier(to: rawSnap).compactPlanBadge, "AI Ultra")
    }

    // MARK: - 18. GeminiSnapshotCache Source Isolation When Desktop App Is Installed

    func testGeminiSnapshotCacheRejectsDeveloperCLIWhenDesktopInstalled() {
        let cache = GeminiSnapshotCache()
        let cliSnap = QuotaSnapshot(
            agentID: .gemini,
            remainingPercent: 77,
            sourceDescription: "Gemini CLI 本地凭证"
        )
        cache.set(cliSnap, source: .developerCLI)
        XCTAssertNotNil(cache.get(maxAge: 300, isWorking: false, allowDeveloperCLI: true))
        XCTAssertNil(cache.get(maxAge: 300, isWorking: false, allowDeveloperCLI: false), "Installing Gemini.app MUST immediately reject cached Gemini CLI quota!")
    }

    // MARK: - 19. Shared Reset-Date Sanitizer Across Providers (Zero / 1970 Sentinels)

    func testSharedResetDateSanitizerFiltersZeroAnd1970AcrossProviders() {
        XCTAssertNil(CodexProvider.dateValue(0))
        XCTAssertNil(CodexProvider.dateValue(0.0))
        XCTAssertNil(QuotaSnapshot.parseValidResetDate(from: "1970-01-01T00:00:00Z"))
        XCTAssertNil(QuotaSnapshot.parseValidResetDate(from: 0))

        // QuotaWindow & QuotaSnapshot initializers themselves strip epoch sentinels
        let win = QuotaWindow(label: "7d", remainingPercent: 100, resetsAt: Date(timeIntervalSince1970: 0), resetText: "未消耗")
        XCTAssertNil(win.resetsAt)
        XCTAssertEqual(win.formattedCountdown(), "未消耗")

        // Legitimately expired recent timestamp (after 2000-01-01) is preserved and formats as "即将重置"
        let recentPast = Date(timeIntervalSince1970: 1_795_000_000)
        XCTAssertNotNil(CodexProvider.dateValue(recentPast.timeIntervalSince1970))
        let expiredWin = QuotaWindow(label: "5h", remainingPercent: 10, resetsAt: recentPast)
        XCTAssertNotNil(expiredWin.resetsAt)
        XCTAssertEqual(expiredWin.formattedCountdown(now: recentPast.addingTimeInterval(60)), "即将重置")
    }

    // MARK: - 20. Provider Auth Capability Alignment

    func testProviderAuthCapabilitiesMatchActualDataSources() {
        for cliOrDesktopOnly: AgentID in [.codex, .antigravity, .grokbot, .vscode] {
            XCTAssertFalse(cliOrDesktopOnly.usesWebKitSessionForQuota, "\(cliOrDesktopOnly.rawValue) must not show misleading WebKit login button")
            XCTAssertNotNil(cliOrDesktopOnly.localAuthGuidance)
        }
        for webSupported: AgentID in [.claude, .cursor, .gemini, .workbuddy] {
            XCTAssertTrue(webSupported.usesWebKitSessionForQuota)
        }
    }
}
