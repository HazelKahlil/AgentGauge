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

    private struct PendingRelease {
        let pid: pid_t
        let psn: NativeDockPSN
    }

    private struct WatchCmd {
        var op: UInt32 // 1 = add, 2 = remove, 3 = clear
        var high: UInt32
        var low: UInt32
    }

    private var activeTiles: [AgentID: ActiveTile] = [:]
    private var pendingReleases: [PendingRelease] = []
    private var inFlightDrawAgents: Set<AgentID> = []
    private var nonRunningCheckedAt: [String: TimeInterval] = [:]
    private var cleanupProcess: Process?
    private var cleanupPipe: Pipe?
    private var consecutiveFailures: Int = 0
    private var circuitCooldownUntil: Date = .distantPast
    public var isCircuitBroken: Bool { Date() < circuitCooldownUntil }

    /// Dedicated ordered serial queue so Dock Mach IPC (`draw` & `release`) NEVER blocks @MainActor.
    private let ipcQueue = DispatchQueue(label: "com.kahlil.AgentGauge.dock-ipc", qos: .userInteractive)

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

        // Opportunistically flush any previously failed releases once Dock is healthy again
        flushPendingReleasesIfNeeded()

        // Coalesce stale frames if this icon already has a Mach draw in flight on ipcQueue
        guard !inFlightDrawAgents.contains(agentID) else { return true }

        let missKey = preferredBundleID ?? agentID.rawValue

        // Avoid 60Hz LaunchServices queries when hovering a closed Dock icon that still has valid cloud quota
        if activeTiles[agentID] == nil,
           let lastMiss = nonRunningCheckedAt[missKey],
           (nowTs - lastMiss) < 1.2 {
            return false
        }

        // Zero-IPC 30Hz fast path: reuse resolved PID/PSN/bundleID via <1µs kill(pid, 0) liveness check
        let pid: pid_t
        let psn: NativeDockPSN
        let resolvedBundleID: String
        let appURL: URL

        if let existing = activeTiles[agentID],
           (preferredBundleID == nil || existing.bundleID == preferredBundleID),
           Self.isProcessAlive(existing.pid) {
            pid = existing.pid
            psn = existing.psn
            resolvedBundleID = existing.bundleID
            appURL = existing.appURL
        } else {
            // Strict Dock-variant isolation: ONLY target the exact hovered bundle ID
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
                activeTiles.removeValue(forKey: agentID)
                enqueueRelease(pid: old.pid, psn: old.psn)
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

        // Render pixels on GPU and copy the 165KB half-float frame so Mach send executes strictly off @MainActor
        var capturedPixels: Data? = nil
        var capturedSide: UInt32 = 0
        let rendered = NativeIconRenderer.shared.renderHalfFloatTile(
            agentID: agentID,
            appURL: appURL,
            snapshot: snapshot,
            params: params
        ) { rawPtr, side in
            let byteCount = Int(side) * Int(side) * 8
            capturedPixels = Data(bytes: rawPtr, count: byteCount)
            capturedSide = side
            return true
        }
        guard rendered, let pixelData = capturedPixels, capturedSide > 0 else {
            return false
        }
        let sideToSend = capturedSide

        // Register with watchdog BEFORE sending frame so even a mid-flight crash guarantees cleanup
        if activeTiles[agentID] == nil {
            activeTiles[agentID] = ActiveTile(pid: pid, psn: psn, bundleID: resolvedBundleID, appURL: appURL)
            sendWatchCmd(op: 1, psn: psn)
        }
        // If this PSN had a pending release, cancel that pending release since we are actively drawing it again
        pendingReleases.removeAll { $0.psn.high == psn.high && $0.psn.low == psn.low }
        inFlightDrawAgents.insert(agentID)

        ipcQueue.async { [weak self] in
            let kr: Int32 = pixelData.withUnsafeBytes { buf in
                guard let base = buf.baseAddress else { return -1 }
                return native_dock_draw_half_float_bytes(psn, base, sideToSend)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlightDrawAgents.remove(agentID)
                if kr == 0 {
                    self.consecutiveFailures = 0
                } else {
                    self.consecutiveFailures += 1
                    AppLogger.shared.log("NativeTile", "\(agentID.displayName) 原生磁贴投递失败 (kr=\(kr))")
                    if self.consecutiveFailures >= 5 {
                        self.consecutiveFailures = 0
                        self.circuitCooldownUntil = Date().addingTimeInterval(5.0)
                        // Move active tiles to pendingReleases (NEVER drop them or tell watchdog they were released!)
                        for tile in self.activeTiles.values {
                            self.recordPendingRelease(pid: tile.pid, psn: tile.psn)
                        }
                        self.activeTiles.removeAll()
                        AppLogger.shared.log("NativeTile", "Dock 通信波动，暂停磁贴投递 5 秒后自动自愈并补偿释放")
                    }
                }
            }
        }
        return true
    }

    public func release(agentID: AgentID) {
        guard let tile = activeTiles.removeValue(forKey: agentID) else { return }
        enqueueRelease(pid: tile.pid, psn: tile.psn)
    }

    public func releaseAll() {
        let tiles = Array(activeTiles.values)
        activeTiles.removeAll()
        for tile in tiles {
            enqueueRelease(pid: tile.pid, psn: tile.psn)
        }
        flushPendingReleasesIfNeeded()
    }

    public func shutdown() {
        // Snapshot every active + pending PSN for deterministic synchronous release before process exit
        var toRelease: [PendingRelease] = activeTiles.values.map { PendingRelease(pid: $0.pid, psn: $0.psn) }
        for p in pendingReleases where !toRelease.contains(where: { $0.psn.high == p.psn.high && $0.psn.low == p.psn.low }) {
            toRelease.append(p)
        }
        activeTiles.removeAll()
        pendingReleases.removeAll()

        let itemsToRelease = toRelease
        let sem = DispatchSemaphore(value: 0)
        final class LockedPSNs: @unchecked Sendable {
            private let lock = NSLock()
            private var list: [NativeDockPSN] = []
            func append(_ psn: NativeDockPSN) { lock.lock(); list.append(psn); lock.unlock() }
            func snapshot() -> [NativeDockPSN] { lock.lock(); defer { lock.unlock() }; return list }
        }
        let releasedBox = LockedPSNs()
        ipcQueue.async {
            for item in itemsToRelease {
                let kr = native_dock_release_tile(item.psn)
                if kr == 0 || !Self.isProcessAlive(item.pid) {
                    releasedBox.append(item.psn)
                }
            }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .milliseconds(120))

        // Only remove successfully released PSNs from watchdog; any still-failed PSNs stay tracked so watchdog retries on EOF!
        for psn in releasedBox.snapshot() {
            sendWatchCmd(op: 2, psn: psn)
        }

        // Close pipe EOF so AgentGaugeCleanup performs its final release sweep and exits naturally
        try? cleanupPipe?.fileHandleForWriting.close()
        cleanupPipe = nil
        if let proc = cleanupProcess {
            let deadline = Date().addingTimeInterval(0.18)
            while proc.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.015)
            }
            if proc.isRunning {
                proc.terminate()
            }
        }
        cleanupProcess = nil
    }

    // MARK: - Pending Release Tracking & Compensation

    private func recordPendingRelease(pid: pid_t, psn: NativeDockPSN) {
        if !pendingReleases.contains(where: { $0.psn.high == psn.high && $0.psn.low == psn.low }) {
            pendingReleases.append(PendingRelease(pid: pid, psn: psn))
        }
    }

    private func enqueueRelease(pid: pid_t, psn: NativeDockPSN) {
        recordPendingRelease(pid: pid, psn: psn)
        ipcQueue.async { [weak self] in
            let kr = native_dock_release_tile(psn)
            let targetDead = !Self.isProcessAlive(pid)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if kr == 0 || targetDead {
                    self.pendingReleases.removeAll { $0.psn.high == psn.high && $0.psn.low == psn.low }
                    // Only remove from watchdog AFTER release actually succeeded or target process exited!
                    if !self.activeTiles.values.contains(where: { $0.psn.high == psn.high && $0.psn.low == psn.low }) {
                        self.sendWatchCmd(op: 2, psn: psn)
                    }
                }
            }
        }
    }

    private func flushPendingReleasesIfNeeded() {
        guard !pendingReleases.isEmpty, Date() >= circuitCooldownUntil else { return }
        let items = pendingReleases
        for item in items {
            // Skip any PSN that has since become active again
            if activeTiles.values.contains(where: { $0.psn.high == item.psn.high && $0.psn.low == item.psn.low }) {
                pendingReleases.removeAll { $0.psn.high == item.psn.high && $0.psn.low == item.psn.low }
                continue
            }
            ipcQueue.async { [weak self] in
                let kr = native_dock_release_tile(item.psn)
                let targetDead = !Self.isProcessAlive(item.pid)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if kr == 0 || targetDead {
                        self.pendingReleases.removeAll { $0.psn.high == item.psn.high && $0.psn.low == item.psn.low }
                        if !self.activeTiles.values.contains(where: { $0.psn.high == item.psn.high && $0.psn.low == item.psn.low }) {
                            self.sendWatchCmd(op: 2, psn: item.psn)
                        }
                    }
                }
            }
        }
    }

    private nonisolated static func isProcessAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if Darwin.kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    private func sendWatchCmd(op: UInt32, psn: NativeDockPSN) {
        guard let fh = cleanupPipe?.fileHandleForWriting else { return }
        var cmd = WatchCmd(op: op, high: psn.high, low: psn.low)
        let data = withUnsafeBytes(of: &cmd) { Data($0) }
        try? fh.write(contentsOf: data)
    }
}
