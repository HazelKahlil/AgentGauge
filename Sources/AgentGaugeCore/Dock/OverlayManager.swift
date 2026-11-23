import AppKit
import Foundation

@MainActor
public final class OverlayManager {
    private struct IconMotionState {
        var hoverAlpha: CGFloat = 0
        var tilt: CGFloat = 0
        var tiltVel: CGFloat = 0
        var ripple: CGFloat = 0
        var isHovered: Bool = false
        var targetTilt: CGFloat = 0
        var isActiveOnDock: Bool = false
        var lastDrawTime: TimeInterval = 0
        var lastBundleID: String? = nil
    }

    private let locator = DockLocator()
    private let nativeChannel = NativeTileChannel()
    private let tooltipPanel = HoverTooltipPanel()

    private var snapshots: [AgentID: QuotaSnapshot] = [:]
    private var motionStates: [AgentID: IconMotionState] = [:]
    private var enabledAgents: Set<AgentID> = Set(AgentID.defaultCoreSet)
    private var isMasterEnabled: Bool = true
    private var animationIntensity: AnimationIntensity = .always
    private var showDockBadge: Bool = true
    private var showPercentageSign: Bool = true
    private var tooltipDetailMode: TooltipDetailMode = .multiModel
    private var numberColorMode: NumberColorMode = .smartInvert
    private var badgeStyle: DockBadgeStyle = .refTopTimerScrim
    private var badgeScale: Double = 1.50
    private var badgeOpacity: Double = 0.85
    private var customWaterColors: [AgentID: String] = [:]

    private var renderTimer: Timer?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var lastFrameDate: Date = Date()
    private var waveTime: CGFloat = 0
    private var bubbleTime: CGFloat = 0
    private var lastCursorX: CGFloat = 0
    private var hasValidLastCursorX: Bool = false

    // Single-authority 60Hz AX state machine + Schmitt-trigger boundary hysteresis (zero seam oscillation!)
    private var cachedDockTiles: [CachedDockTile] = []
    private var isTileListRefreshInFlight: Bool = false
    private var lastTileListRefreshDate: Date = .distantPast
    private var isAXHitInFlight: Bool = false
    private var lastAXHitDate: Date = .distantPast
    private var activeMatch: DockTileMatch?
    private var hasAXAuthority: Bool = false
    private var outsideGraceStart: Date?
    private var hasOpenDockMenu: Bool = false

    private var cachedDockPID: pid_t = 0
    private var lastDockPIDCheck: Date = .distantPast

    // Calm, steady optical liquid speed & critically-damped slosh scale (zero jitter)
    private let calibratedSpeedFactor: CGFloat = 1.12
    private let calibratedTiltScale: CGFloat = 0.58

    public var onWakeNearDock: (() -> Void)?

    public init() {
        for id in AgentID.allCases {
            motionStates[id] = IconMotionState()
        }
    }

    public var isAccessibilityTrusted: Bool {
        locator.isAccessibilityTrusted
    }

    public var isActivelyHovering: Bool {
        motionStates.values.contains { $0.isHovered || $0.isActiveOnDock }
    }

    public func requestAccessibilityPermission() {
        locator.requestAccessibilityPermission()
    }

    public func start() {
        stop()
        nativeChannel.startWatchdogIfAvailable()
        lastFrameDate = Date()

        // Pre-warm Metal shader & running tracked app icons so first hover has ZERO lag
        _ = NativeIconRenderer.shared
        for id in enabledAgents {
            if let app = id.bundleIdentifiers.lazy
                .compactMap({ NSRunningApplication.runningApplications(withBundleIdentifier: $0).first })
                .first,
               let url = app.bundleURL {
                _ = NativeIconRenderer.shared.renderTileImage(
                    agentID: id,
                    appURL: url,
                    snapshot: QuotaSnapshot(agentID: id, remainingPercent: 50, sourceDescription: "warmup"),
                    params: IconRenderParams(
                        waveTime: 0,
                        bubbleTime: 0,
                        hoverAlpha: 0,
                        tilt: 0,
                        ripple: 0,
                        animate: false,
                        showPercentageSign: false
                    )
                )
            }
        }

        // Pre-fetch Dock icon rects immediately so first hover is 0ms instant!
        refreshCachedDockTilesAsync()

        // Event-driven wakeup: 0.0% CPU when mouse is away from Dock, instant 60Hz wakeup when entering Dock zone!
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseUp]) { [weak self] _ in
            Task { @MainActor in
                self?.wakeIfCursorNearDock()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.wakeIfCursorNearDock()
            return event
        }
        wakeIfCursorNearDock()
    }

    public func stop() {
        renderTimer?.invalidate()
        renderTimer = nil
        if let gm = globalMouseMonitor {
            NSEvent.removeMonitor(gm)
            globalMouseMonitor = nil
        }
        if let lm = localMouseMonitor {
            NSEvent.removeMonitor(lm)
            localMouseMonitor = nil
        }
        hideAll()
    }

    private func wakeIfCursorNearDock() {
        guard isMasterEnabled, renderTimer == nil else { return }
        let orientation = locator.currentOrientation()
        if isCursorNearAnyDockEdge(orientation: orientation, threshold: 215) {
            onWakeNearDock?()
            lastFrameDate = Date()
            tick()
            renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tick()
                }
            }
        }
    }

    public func updateSnapshots(_ newSnapshots: [AgentID: QuotaSnapshot]) {
        self.snapshots = newSnapshots
        for id in AgentID.allCases where motionStates[id]?.isActiveOnDock == true {
            renderSingleTile(id)
        }
    }

    public func updateSettings(
        isMasterEnabled: Bool,
        enabledAgents: Set<AgentID>,
        animationIntensity: AnimationIntensity,
        showDockBadge: Bool = true,
        showPercentageSign: Bool,
        tooltipDetailMode: TooltipDetailMode,
        numberColorMode: NumberColorMode,
        badgeStyle: DockBadgeStyle = .concentricAutoDodge,
        badgeScale: Double = 1.50,
        badgeOpacity: Double = 0.85,
        customWaterColors: [AgentID: String]
    ) {
        let agentsChanged = (self.enabledAgents != enabledAgents)
        self.isMasterEnabled = isMasterEnabled
        self.enabledAgents = enabledAgents
        self.animationIntensity = animationIntensity
        self.showDockBadge = showDockBadge
        self.showPercentageSign = showPercentageSign
        self.tooltipDetailMode = tooltipDetailMode
        self.numberColorMode = numberColorMode
        self.badgeStyle = badgeStyle
        self.badgeScale = badgeScale
        self.badgeOpacity = badgeOpacity
        self.customWaterColors = customWaterColors

        if tooltipDetailMode == .off {
            tooltipPanel.hide(immediate: true)
        }

        if agentsChanged {
            refreshCachedDockTilesAsync()
        }

        if !isMasterEnabled {
            hideAll()
        } else {
            for id in AgentID.allCases where motionStates[id]?.isActiveOnDock == true {
                renderSingleTile(id)
            }
        }
    }

    public func hideAll() {
        activeMatch = nil
        hasAXAuthority = false
        outsideGraceStart = nil
        tooltipPanel.hide(immediate: true)
        for id in AgentID.allCases {
            motionStates[id]?.isHovered = false
            motionStates[id]?.hoverAlpha = 0
            motionStates[id]?.isActiveOnDock = false
        }
        nativeChannel.releaseAll()
    }

    public func cleanupAll() {
        stop()
        nativeChannel.shutdown()
    }

    private func tick() {
        guard isMasterEnabled, locator.isAccessibilityTrusted else {
            if motionStates.values.contains(where: { $0.isActiveOnDock }) {
                hideAll()
            }
            return
        }

        let now = Date()
        let dt = CGFloat(min(0.05, max(0.004, now.timeIntervalSince(lastFrameDate))))
        lastFrameDate = now

        let orientation = locator.currentOrientation()
        let mouseNearDock = isCursorNearAnyDockEdge(orientation: orientation)

        if mouseNearDock {
            // 1. Frame-0 cold-start bootstrap ONLY before the first 1.2ms AX query returns.
            //    Once AX authority is established, unmagnified cached rects NEVER compete with live magnified AX rects!
            if !hasAXAuthority, activeMatch == nil, !hasOpenDockMenu,
               let pt = CGEvent(source: nil)?.location,
               let bootMatch = instantCachedHitTest(at: pt, orientation: orientation) {
                activeMatch = bootMatch
                applyHitResult(match: bootMatch, hasOpenMenu: false, orientation: orientation)
            } else if let cur = activeMatch, let pt = CGEvent(source: nil)?.location,
                      !isWithinSeamHoldBand(pt, of: cur.axFrame, orientation: orientation, lateralSlack: 40, verticalSlack: 20) {
                // Fast vertical exit onto desktop before in-flight AX returns -> release on Frame 0
                releaseActiveHover()
            }

            // 2. Refresh baseline cached Dock rects periodically ONLY when unhovered so magnified tiles don't skew cache
            if !isTileListRefreshInFlight && activeMatch == nil && now.timeIntervalSince(lastTileListRefreshDate) >= 1.5 {
                refreshCachedDockTilesAsync()
            }

            // 3. Single-authority 60Hz off-main-thread AX classification with Schmitt-trigger seam hysteresis
            if !isAXHitInFlight && now.timeIntervalSince(lastAXHitDate) >= 0.015 {
                triggerAsyncAXVerify(orientation: orientation)
            }
        } else {
            hasOpenDockMenu = false
            hasAXAuthority = false
            hasValidLastCursorX = false
            releaseActiveHover()
        }

        let anyHoveredOrSettling = motionStates.values.contains {
            $0.isHovered || $0.hoverAlpha > 0.006 || $0.isActiveOnDock
        }

        // When unhovered & away from Dock, suspend timer completely -> 0.00% idle CPU!
        guard anyHoveredOrSettling else {
            hasValidLastCursorX = false
            if !mouseNearDock {
                renderTimer?.invalidate()
                renderTimer = nil
            }
            return
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let allowAnimation = !reduceMotion && animationIntensity != .reduced

        // Monotonic once-per-frame cursor velocity for calm gravity-level liquid slosh (immune to async AX timestamps!)
        var frameVX: CGFloat = 0
        if allowAnimation, motionStates.values.contains(where: { $0.isHovered }),
           let liveCursor = CGEvent(source: nil)?.location {
            if hasValidLastCursorX {
                frameVX = (liveCursor.x - lastCursorX) / max(0.014, dt)
            }
            lastCursorX = liveCursor.x
            hasValidLastCursorX = true
        } else {
            hasValidLastCursorX = false
        }

        if allowAnimation {
            let anyWorking = enabledAgents.contains {
                motionStates[$0]?.isHovered == true && snapshots[$0]?.isWorking == true
            }
            let waveRate: CGFloat = (anyWorking ? 2.15 : 1.65) * calibratedSpeedFactor
            let bubbleRate: CGFloat = (anyWorking ? 2.65 : 1.95) * calibratedSpeedFactor
            waveTime += dt * waveRate
            bubbleTime += dt * bubbleRate
            if waveTime > 10_000 { waveTime = 0 }
            if bubbleTime > 10_000 { bubbleTime = 0 }
        }

        for id in AgentID.allCases {
            guard var st = motionStates[id] else { continue }

            guard enabledAgents.contains(id),
                  let snap = snapshots[id],
                  snap.remainingPercent != nil else {
                if st.isActiveOnDock {
                    nativeChannel.release(agentID: id)
                    st.isActiveOnDock = false
                    st.hoverAlpha = 0
                    motionStates[id] = st
                }
                continue
            }

            let targetHover: CGFloat = st.isHovered ? 1.0 : 0.0
            let rate: CGFloat = st.isHovered ? 16.0 : 11.0
            st.hoverAlpha += (targetHover - st.hoverAlpha) * min(1.0, dt * rate)
            if abs(targetHover - st.hoverAlpha) < 0.006 {
                st.hoverAlpha = targetHover
            }

            if allowAnimation {
                if st.isHovered && abs(frameVX) > 4.0 {
                    st.tiltVel += max(-0.40, min(0.40, -frameVX * 0.00042))
                }
                // Gravity always pulls liquid surface back to dead-horizontal (targetTilt = 0) with near-critical damping
                let stiffness: CGFloat = 20.0
                let damping: CGFloat = 8.4
                let accel = stiffness * (0.0 - st.tilt) - damping * st.tiltVel
                st.tiltVel += accel * dt
                st.tilt = max(-0.38, min(0.38, st.tilt + st.tiltVel * dt))
                if abs(st.tilt) < 0.002 && abs(st.tiltVel) < 0.005 {
                    st.tilt = 0
                    st.tiltVel = 0
                }
                st.ripple *= pow(0.14, dt)
                if st.ripple < 0.005 { st.ripple = 0 }
            } else {
                st.tilt = 0
                st.tiltVel = 0
                st.ripple = 0
            }

            if !st.isHovered && st.hoverAlpha <= 0.008 {
                if st.isActiveOnDock {
                    nativeChannel.release(agentID: id)
                    st.isActiveOnDock = false
                }
                st.hoverAlpha = 0
                st.tilt = 0
                st.tiltVel = 0
                motionStates[id] = st
                continue
            }

            let wasActive = st.isActiveOnDock
            st.isActiveOnDock = true

            // Draw immediately on frame 0 of hover, then throttle Dock Mach IPC to 30fps so Dock.app never drops frames!
            let nowTs = now.timeIntervalSinceReferenceDate
            if !wasActive || (nowTs - st.lastDrawTime) >= 0.031 {
                st.lastDrawTime = nowTs
                motionStates[id] = st

                let params = IconRenderParams(
                    waveTime: waveTime,
                    bubbleTime: bubbleTime,
                    hoverAlpha: st.hoverAlpha,
                    tilt: st.tilt * calibratedTiltScale,
                    ripple: st.ripple,
                    animate: allowAnimation,
                    showDockBadge: showDockBadge,
                    showPercentageSign: showPercentageSign,
                    waterTintHex: customWaterColors[id],
                    numberColorMode: numberColorMode,
                    badgeStyle: badgeStyle,
                    badgeScale: CGFloat(badgeScale),
                    badgeOpacity: CGFloat(badgeOpacity)
                )
                nativeChannel.draw(agentID: id, snapshot: snap, params: params)
            } else {
                motionStates[id] = st
            }
        }
    }

    private func isWithinSeamHoldBand(
        _ pt: CGPoint,
        of axFrame: CGRect,
        orientation: DockOrientation,
        lateralSlack: CGFloat,
        verticalSlack: CGFloat
    ) -> Bool {
        switch orientation {
        case .bottom:
            return axFrame.insetBy(dx: -lateralSlack, dy: -verticalSlack).contains(pt)
        case .left, .right:
            return axFrame.insetBy(dx: -verticalSlack, dy: -lateralSlack).contains(pt)
        }
    }

    private func releaseActiveHover() {
        activeMatch = nil
        outsideGraceStart = nil
        if motionStates.values.contains(where: { $0.isHovered }) {
            clearHoverFlags()
            tooltipPanel.hide()
        }
    }

    /// Evaluates whether a candidate neighbor icon has crossed the Schmitt-trigger interior penetration threshold.
    /// Prevents `A <-> B` oscillation when the cursor rests right on the boundary or inter-icon seam under Dock magnification.
    public static func shouldCommitNeighborSwitch(
        cursor: CGPoint,
        candidateAXFrame: CGRect,
        orientation: DockOrientation
    ) -> Bool {
        let inward: CGFloat = (orientation == .bottom)
            ? min(cursor.x - candidateAXFrame.minX, candidateAXFrame.maxX - cursor.x)
            : min(cursor.y - candidateAXFrame.minY, candidateAXFrame.maxY - cursor.y)
        let span: CGFloat = (orientation == .bottom) ? candidateAXFrame.width : candidateAXFrame.height
        let requiredPenetration = min(5.5, max(3.8, span * 0.075))
        return inward >= requiredPenetration
    }

    private func instantCachedHitTest(at pt: CGPoint, orientation: DockOrientation) -> DockTileMatch? {
        guard !cachedDockTiles.isEmpty else { return nil }
        var bestTile: CachedDockTile?
        var bestDist: CGFloat = .greatestFiniteMagnitude

        for tile in cachedDockTiles {
            guard enabledAgents.contains(tile.agentID) else { continue }
            if tile.axFrame.insetBy(dx: 2, dy: -2).contains(pt) {
                let axisDist: CGFloat = (orientation == .bottom)
                    ? abs(pt.x - tile.axFrame.midX)
                    : abs(pt.y - tile.axFrame.midY)
                if axisDist < bestDist {
                    bestDist = axisDist
                    bestTile = tile
                }
            }
        }

        guard let tile = bestTile else { return nil }
        return DockTileMatch(
            agentID: tile.agentID,
            bundleID: tile.bundleID,
            appURL: tile.appURL,
            cocoaFrame: tile.cocoaFrame,
            axFrame: tile.axFrame,
            cgCursor: pt,
            isLiveAX: false
        )
    }

    private func refreshCachedDockTilesAsync() {
        let dockPID = currentDockPID()
        guard dockPID > 0, !isTileListRefreshInFlight else { return }

        isTileListRefreshInFlight = true
        lastTileListRefreshDate = Date()
        let targets = Array(enabledAgents)
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height

        Task { @MainActor [weak self] in
            guard let self else { return }
            let tiles = await self.locator.fetchDockTilesAsync(
                for: targets,
                dockPID: dockPID,
                mainDisplayHeight: mainHeight
            )
            self.cachedDockTiles = tiles
            self.isTileListRefreshInFlight = false
        }
    }

    private func triggerAsyncAXVerify(orientation: DockOrientation) {
        let dockPID = currentDockPID()
        guard dockPID > 0 else { return }

        isAXHitInFlight = true
        lastAXHitDate = Date()
        let queryCursor = CGEvent(source: nil)?.location ?? .zero
        let targets = Array(enabledAgents)
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height

        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await self.locator.classifyHoveredTileAsync(
                for: targets,
                dockPID: dockPID,
                mainDisplayHeight: mainHeight
            )
            self.isAXHitInFlight = false
            self.hasAXAuthority = true

            let liveCursor = CGEvent(source: nil)?.location ?? queryCursor

            switch outcome {
            case .openMenu:
                self.hasOpenDockMenu = true
                self.releaseActiveHover()

            case .matched(let hm):
                self.hasOpenDockMenu = false
                self.outsideGraceStart = nil
                let cursorDrift = hypot(liveCursor.x - hm.cgCursor.x, liveCursor.y - hm.cgCursor.y)
                guard cursorDrift <= 38 else { return }

                // Seed uncached newly launched/added Dock apps without overwriting baseline unmagnified rects
                if !self.cachedDockTiles.contains(where: { $0.bundleID == hm.bundleID }) {
                    self.cachedDockTiles.append(CachedDockTile(
                        agentID: hm.agentID,
                        bundleID: hm.bundleID,
                        appURL: hm.appURL,
                        cocoaFrame: hm.cocoaFrame,
                        axFrame: hm.axFrame
                    ))
                }

                if let cur = self.activeMatch, (cur.agentID != hm.agentID || cur.bundleID != hm.bundleID) {
                    // Schmitt-trigger hysteresis: require clear inward penetration into neighbor before switching
                    guard Self.shouldCommitNeighborSwitch(
                        cursor: hm.cgCursor,
                        candidateAXFrame: hm.axFrame,
                        orientation: orientation
                    ) else {
                        return
                    }
                }

                self.activeMatch = hm
                self.applyHitResult(match: hm, hasOpenMenu: false, orientation: orientation)

            case .dockGap(let cgCursor):
                self.hasOpenDockMenu = false
                // Parked in the narrow inter-icon seam between two Dock icons -> hold current icon rock-steady!
                if let cur = self.activeMatch {
                    if self.isWithinSeamHoldBand(cgCursor, of: cur.axFrame, orientation: orientation, lateralSlack: 22, verticalSlack: 12) {
                        self.outsideGraceStart = nil
                    } else {
                        self.releaseActiveHover()
                    }
                }

            case .untrackedItem(let uRect, let cgCursor):
                self.hasOpenDockMenu = false
                if let cur = self.activeMatch {
                    let enteredUntracked = Self.shouldCommitNeighborSwitch(
                        cursor: cgCursor,
                        candidateAXFrame: uRect,
                        orientation: orientation
                    )
                    if enteredUntracked || !self.isWithinSeamHoldBand(cgCursor, of: cur.axFrame, orientation: orientation, lateralSlack: 24, verticalSlack: 12) {
                        self.releaseActiveHover()
                    }
                }

            case .outsideDock(let cgCursor):
                self.hasOpenDockMenu = false
                let cursorDrift = hypot(liveCursor.x - queryCursor.x, liveCursor.y - queryCursor.y)
                guard cursorDrift <= 18 else { return }
                if let cur = self.activeMatch {
                    if !self.isWithinSeamHoldBand(cgCursor, of: cur.axFrame, orientation: orientation, lateralSlack: 14, verticalSlack: 6) {
                        self.releaseActiveHover()
                    } else if let t0 = self.outsideGraceStart {
                        if Date().timeIntervalSince(t0) >= 0.055 {
                            self.releaseActiveHover()
                        }
                    } else {
                        self.outsideGraceStart = Date()
                    }
                }
            }
        }
    }

    private func isCursorNearAnyDockEdge(orientation: DockOrientation, threshold: CGFloat = 185) -> Bool {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            let f = screen.frame
            guard mouse.x >= f.minX - 10 && mouse.x <= f.maxX + 10 &&
                  mouse.y >= f.minY - 10 && mouse.y <= f.maxY + 10 else {
                return false
            }
            switch orientation {
            case .bottom: return (mouse.y - f.minY) <= threshold
            case .left:   return (mouse.x - f.minX) <= threshold
            case .right:  return (f.maxX - mouse.x) <= threshold
            }
        }
    }

    private func currentDockPID() -> pid_t {
        let now = Date()
        if cachedDockPID > 0 && now.timeIntervalSince(lastDockPIDCheck) < 5.0 {
            return cachedDockPID
        }
        lastDockPIDCheck = now
        if let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            cachedDockPID = dockApp.processIdentifier
        } else {
            cachedDockPID = 0
        }
        return cachedDockPID
    }

    private func applyHitResult(match: DockTileMatch?, hasOpenMenu: Bool, orientation: DockOrientation) {
        if hasOpenMenu {
            clearHoverFlags()
            tooltipPanel.hide()
            return
        }

        for id in AgentID.allCases {
            var st = motionStates[id] ?? IconMotionState()
            if let hm = match, hm.agentID == id,
               let snap = snapshots[id], snap.remainingPercent != nil {
                if !st.isHovered {
                    st.ripple = max(st.ripple, 0.18)
                    hasValidLastCursorX = false
                }
                st.isHovered = true
                st.targetTilt = 0
                st.lastBundleID = hm.bundleID
            } else {
                st.isHovered = false
                st.targetTilt = 0
            }
            motionStates[id] = st
        }

        if tooltipDetailMode != .off,
           let hm = match,
           let snap = snapshots[hm.agentID],
           snap.remainingPercent != nil {
            let accent = customWaterColors[hm.agentID].flatMap(NSColor.fromHex) ?? hm.agentID.defaultAccentColor
            tooltipPanel.show(
                snapshot: snap,
                anchorRect: hm.cocoaFrame,
                orientation: orientation,
                detailMode: tooltipDetailMode,
                showPercentageSign: showPercentageSign,
                accentColor: accent,
                isLiveAXRect: hm.isLiveAX
            )
        } else {
            tooltipPanel.hide()
        }
    }

    private func clearHoverFlags() {
        for id in AgentID.allCases {
            motionStates[id]?.isHovered = false
            motionStates[id]?.targetTilt = 0
        }
    }

    private func renderSingleTile(_ id: AgentID) {
        guard isMasterEnabled,
              enabledAgents.contains(id),
              let snap = snapshots[id],
              snap.remainingPercent != nil,
              let st = motionStates[id],
              st.hoverAlpha > 0.008 else {
            nativeChannel.release(agentID: id)
            return
        }

        let allowAnimation = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && animationIntensity != .reduced
        let params = IconRenderParams(
            waveTime: waveTime,
            bubbleTime: bubbleTime,
            hoverAlpha: st.hoverAlpha,
            tilt: st.tilt * calibratedTiltScale,
            ripple: st.ripple,
            animate: allowAnimation,
            showDockBadge: showDockBadge,
            showPercentageSign: showPercentageSign,
            waterTintHex: customWaterColors[id],
            numberColorMode: numberColorMode,
            badgeStyle: badgeStyle,
            badgeScale: CGFloat(badgeScale),
            badgeOpacity: CGFloat(badgeOpacity)
        )
        nativeChannel.draw(
            agentID: id,
            snapshot: snap,
            params: params,
            preferredBundleID: st.lastBundleID
        )
    }
}
