import AppKit
import CNativeDockTile
import CoreGraphics
import Foundation

@MainActor
public final class NativeTileChannel {
    private struct ActiveTile {
        let pid: pid_t
        let psn: NativeDockPSN
        let appURL: URL
    }

    private struct WatchCmd {
        var op: UInt32 // 1 = add, 2 = remove, 3 = clear
        var high: UInt32
        var low: UInt32
    }

    private var activeTiles: [AgentID: ActiveTile] = [:]
    private var cleanupProcess: Process?
    private var cleanupPipe: Pipe?
    private var consecutiveFailures: Int = 0
    public private(set) var isCircuitBroken: Bool = false

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
        params: IconRenderParams
    ) -> Bool {
        guard !isCircuitBroken else { return false }

        guard let runningApp = agentID.bundleIdentifiers.lazy
                .compactMap({ NSRunningApplication.runningApplications(withBundleIdentifier: $0).first })
                .first,
              let appURL = runningApp.bundleURL else {
            release(agentID: agentID)
            return false
        }

        let pid = runningApp.processIdentifier
        var psn: NativeDockPSN

        if let existing = activeTiles[agentID], existing.pid == pid {
            psn = existing.psn
        } else {
            if let old = activeTiles[agentID] {
                _ = native_dock_release_tile(old.psn)
                sendWatchCmd(op: 2, psn: old.psn)
                activeTiles.removeValue(forKey: agentID)
            }
            var lookedUp = NativeDockPSN(high: 0, low: 0)
            guard native_dock_get_psn_for_pid(pid, &lookedUp) else {
                return false
            }
            psn = lookedUp
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
                activeTiles[agentID] = ActiveTile(pid: pid, psn: psn, appURL: appURL)
                sendWatchCmd(op: 1, psn: psn)
            }
            return true
        } else {
            consecutiveFailures += 1
            AppLogger.shared.log("NativeTile", "\(agentID.displayName) 原生磁贴投递失败 (kr=\(sendResult))")
            if consecutiveFailures >= 5 {
                isCircuitBroken = true
                AppLogger.shared.log("NativeTile", "连续失败 5 次，已熔断原生磁贴通道")
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
