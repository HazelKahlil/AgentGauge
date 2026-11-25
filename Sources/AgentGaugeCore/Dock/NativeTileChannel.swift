import AppKit
import CNativeDockTile
import CoreGraphics
import Darwin
import Foundation

@MainActor
public final class NativeTileChannel {
    private struct ActiveTile {
        let pid: pid_t
        let psn: NativeDockPSN
        let bundleID: String
        let appURL: URL
    }

    private struct WatchCmd {
        var op: UInt32 // 1 = add, 2 = remove, 3 = clear
        var high: UInt32
        var low: UInt32
    }

    private var activeTiles: [AgentID: ActiveTile] = [:]
    private var nonRunningCheckedAt: [String: TimeInterval] = [:]
    private var cleanupProcess: Process?
    private var cleanupPipe: Pipe?
    private var consecutiveFailures: Int = 0
    private var circuitCooldownUntil: Date = .distantPast
    public var isCircuitBroken: Bool { Date() < circuitCooldownUntil }

    public init() {}

    public func startWatchdogIfAvailable() {
        guard cleanupProcess == nil else { return }
        guard let execDir = Bundle.main.executableURL?.deletingLastPathComponent() else { return }
        let helperURL = execDir.appendingPathComponent("AgentGaugeCleanup")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else { return }

        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = helperURL
        proc.standardInput = pipe
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            cleanupProcess = proc
            cleanupPipe = pipe
            AppLogger.shared.log("NativeTile", "崩溃恢复守护进程已启动 (PID \(proc.processIdentifier))")
        } catch {
            AppLogger.shared.log("NativeTile", "守护进程启动失败: \(error.localizedDescription)")
        }
    }

    @discardableResult
    public func draw(
        agentID: AgentID,
        snapshot: QuotaSnapshot,
        params: IconRenderParams,
        preferredBundleID: String? = nil
    ) -> Bool {
        let nowTs = Date().timeIntervalSinceReferenceDate
        guard Date() >= circuitCooldownUntil else { return false }

        let missKey = preferredBundleID ?? agentID.rawValue

        // Avoid 60Hz LaunchServices queries when hovering a closed Dock icon that still has valid cloud quota
        if activeTiles[agentID] == nil,
           let lastMiss = nonRunningCheckedAt[missKey],
           (nowTs - lastMiss) < 1.2 {
            return false
        }

        // Zero-IPC 30Hz fast path: if we already resolved this hovered tile's PID/PSN/bundleID and the process is still alive
        // (`kill(pid, 0) == 0` takes <1µs), skip 30Hz LaunchServices queries on @MainActor!
        let pid: pid_t
        let psn: NativeDockPSN
        let resolvedBundleID: String
        let appURL: URL

        if let existing = activeTiles[agentID],
           (preferredBundleID == nil || existing.bundleID == preferredBundleID),
           (Darwin.kill(existing.pid, 0) == 0 || errno == EPERM) {
            pid = existing.pid
            psn = existing.psn
            resolvedBundleID = existing.bundleID
            appURL = existing.appURL
        } else {
            // Strict Dock-variant isolation: when hovering a specific bundle ID on the Dock, ONLY target that exact running bundle ID
            // (never light up an unhovered sibling variant such as Zed vs Zed Preview!).
            let targetBundleIDs: [String] = preferredBundleID.map { [$0] } ?? agentID.bundleIdentifiers
            guard let runningApp = targetBundleIDs.lazy
                    .compactMap({ NSRunningApplication.runningApplications(withBundleIdentifier: $0).first })
                    .first,
                  let foundURL = runningApp.bundleURL else {
                nonRunningCheckedAt[missKey] = nowTs
                release(agentID: agentID)
                return false
            }
            nonRunningCheckedAt.removeValue(forKey: missKey)

            let foundPID = runningApp.processIdentifier
            let foundBID = runningApp.bundleIdentifier ?? preferredBundleID ?? agentID.bundleIdentifier
            if let old = activeTiles[agentID], old.pid != foundPID {
                _ = native_dock_release_tile(old.psn)
                sendWatchCmd(op: 2, psn: old.psn)
                activeTiles.removeValue(forKey: agentID)
            }
            if let existing = activeTiles[agentID], existing.pid == foundPID {
                pid = existing.pid
                psn = existing.psn
                resolvedBundleID = existing.bundleID
                appURL = existing.appURL
            } else {
                var lookedUp = NativeDockPSN(high: 0, low: 0)
                guard native_dock_get_psn_for_pid(foundPID, &lookedUp) else {
                    return false
                }
                pid = foundPID
                psn = lookedUp
                resolvedBundleID = foundBID
                appURL = foundURL
            }
        }

        var sendResult: Int32 = -1
        let ok = NativeIconRenderer.shared.renderHalfFloatTile(
            agentID: agentID,
            appURL: appURL,
            snapshot: snapshot,
            params: params
        ) { rawPtr, side in
            sendResult = native_dock_draw_half_float_bytes(psn, rawPtr, side)
            return sendResult == 0
        }

        if ok {
            consecutiveFailures = 0
            if activeTiles[agentID] == nil {
                activeTiles[agentID] = ActiveTile(pid: pid, psn: psn, bundleID: resolvedBundleID, appURL: appURL)
                sendWatchCmd(op: 1, psn: psn)
            }
            return true
        } else {
            consecutiveFailures += 1
            AppLogger.shared.log("NativeTile", "\(agentID.displayName) 原生磁贴投递失败 (kr=\(sendResult))")
            if consecutiveFailures >= 5 {
                consecutiveFailures = 0
                circuitCooldownUntil = Date().addingTimeInterval(5.0)
                activeTiles.removeAll()
                AppLogger.shared.log("NativeTile", "Dock 通信波动，暂停磁贴投递 5 秒后自动自愈重连")
            }
            return false
        }
    }

    public func release(agentID: AgentID) {
        guard let tile = activeTiles.removeValue(forKey: agentID) else { return }
        _ = native_dock_release_tile(tile.psn)
        sendWatchCmd(op: 2, psn: tile.psn)
    }

    public func releaseAll() {
        for tile in activeTiles.values {
            _ = native_dock_release_tile(tile.psn)
        }
        activeTiles.removeAll()
        sendWatchCmd(op: 3, psn: NativeDockPSN(high: 0, low: 0))
    }

    public func shutdown() {
        releaseAll()
        try? cleanupPipe?.fileHandleForWriting.close()
        cleanupPipe = nil
        if let proc = cleanupProcess, proc.isRunning {
            proc.terminate()
        }
        cleanupProcess = nil
    }

    private func sendWatchCmd(op: UInt32, psn: NativeDockPSN) {
        guard let fh = cleanupPipe?.fileHandleForWriting else { return }
        var cmd = WatchCmd(op: op, high: psn.high, low: psn.low)
        let data = withUnsafeBytes(of: &cmd) { Data($0) }
        try? fh.write(contentsOf: data)
    }
}
