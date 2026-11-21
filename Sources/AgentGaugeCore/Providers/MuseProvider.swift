import AppKit
import Foundation

/// Native provider for Meta Muse (`com.meta.endo`):
/// Detects local Muse Desktop authentication & live activity, plus web quota sync when available.
public struct MuseProvider: UsageProvider {
    public let agentID: AgentID = .muse

    public init() {}

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isWorking = Self.checkIsWorking()
        let isRunning = await MainActor.run {
            !NSRunningApplication.runningApplications(withBundleIdentifier: "com.meta.endo").isEmpty
        }

        if await WebUsageFetcher.shared.hasCookies(matchingDomainSuffixes: agentID.cookieDomainSuffixes) {
            let webSnap = await GenericWebUsageProvider(agentID: .muse).fetchSnapshot()
            if webSnap.remainingPercent != nil {
                return webSnap
            }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let hasLocalMuseState = FileManager.default.fileExists(atPath: "\(home)/Library/Application Support/com.meta.endo/AuthRollout")
            || FileManager.default.fileExists(atPath: "\(home)/.config/muse/auth.json")

        if hasLocalMuseState || isRunning {
            return QuotaSnapshot(
                agentID: .muse,
                remainingPercent: 100.0,
                planTier: "客户端直连",
                primaryLabel: "Muse",
                resetText: isRunning ? "在线" : "就绪",
                windows: [
                    QuotaWindow(
                        label: "Meta Muse 本地服务",
                        remainingPercent: 100.0,
                        resetText: isRunning ? "运行中" : "已就绪",
                        isPrimary: true
                    )
                ],
                subtitle: "Meta Muse 无独立数字配额表",
                isWorking: isWorking,
                sourceDescription: "Muse 本地状态"
            )
        }

        return QuotaSnapshot(
            agentID: .muse,
            remainingPercent: nil,
            isWorking: isWorking,
            sourceDescription: "Muse 未连接",
            requiresWebLogin: true,
            errorMessage: "请启动 Muse 客户端"
        )
    }

    private static func checkIsWorking() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "\(home)/Library/Application Support/com.meta.endo/analytics",
            "\(home)/Library/Application Support/Muse"
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
