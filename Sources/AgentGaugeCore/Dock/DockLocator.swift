import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public enum DockOrientation: String, Sendable {
    case bottom
    case left
    case right
}

public struct DockTileMatch: Sendable {
    public let agentID: AgentID
    public let bundleID: String
    public let appURL: URL
    public let cocoaFrame: NSRect
    public let axFrame: CGRect
    public let cgCursor: CGPoint
    public let isLiveAX: Bool

    public init(
        agentID: AgentID,
        bundleID: String,
        appURL: URL,
        cocoaFrame: NSRect,
        axFrame: CGRect,
        cgCursor: CGPoint,
        isLiveAX: Bool = false
    ) {
        self.agentID = agentID
        self.bundleID = bundleID
        self.appURL = appURL
        self.cocoaFrame = cocoaFrame
        self.axFrame = axFrame
        self.cgCursor = cgCursor
        self.isLiveAX = isLiveAX
    }
}

public struct CachedDockTile: Sendable {
    public let agentID: AgentID
    public let bundleID: String
    public let appURL: URL
    public let cocoaFrame: NSRect
    public let axFrame: CGRect
}

public enum DockAXHitOutcome: Sendable {
    case matched(DockTileMatch)
    case dockGap(cgCursor: CGPoint)
    case untrackedItem(axFrame: CGRect, cgCursor: CGPoint)
    case outsideDock(cgCursor: CGPoint)
    case openMenu
}

public final class DockLocator: @unchecked Sendable {
    private let axQueue = DispatchQueue(label: "com.kahlil.AgentGauge.ax", qos: .userInteractive)
    private let cacheLock = NSLock()
    private var cachedBundleIDByPath: [String: String] = [:]
    private var cachedOrientation: DockOrientation = .bottom
    private var lastOrientationFetch: TimeInterval = 0

    public init() {}

    public var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    @MainActor
    public func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Cached (3.0s TTL) Dock orientation lookup so 60Hz hover ticks & global mouseMoved never spam CFPreferences IPC on @MainActor.
    public func currentOrientation() -> DockOrientation {
        let now = Date().timeIntervalSinceReferenceDate
        cacheLock.lock()
        if (now - lastOrientationFetch) < 3.0 {
            let hit = cachedOrientation
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        let resolved: DockOrientation
        if let raw = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation")?.lowercased(),
           let ori = DockOrientation(rawValue: raw) {
            resolved = ori
        } else {
            resolved = .bottom
        }

        cacheLock.lock()
        cachedOrientation = resolved
        lastOrientationFetch = now
        cacheLock.unlock()
        return resolved
    }

    /// Reads all matching Dock icon rectangles once off-main-thread so 60fps hover hit-testing is instant (0ms).
    public func fetchDockTilesAsync(
        for targetAgents: [AgentID],
        dockPID: pid_t,
        mainDisplayHeight: CGFloat
    ) async -> [CachedDockTile] {
        await withCheckedContinuation { continuation in
            axQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }
                let tiles = self.fetchDockTiles(
                    for: targetAgents,
                    dockPID: dockPID,
                    mainDisplayHeight: mainDisplayHeight
                )
                continuation.resume(returning: tiles)
            }
        }
    }

    private func fetchDockTiles(
        for targetAgents: [AgentID],
        dockPID: pid_t,
        mainDisplayHeight: CGFloat
    ) -> [CachedDockTile] {
        guard AXIsProcessTrusted(), !targetAgents.isEmpty else { return [] }

        let axDock = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(axDock, 0.25)

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axDock, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let topChildren = childrenRef as? [AXUIElement] else {
            return []
        }

        var listElement: AXUIElement?
        for child in topChildren {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            if (roleRef as? String) == (kAXListRole as String) {
                listElement = child
                break
            }
        }
        guard let list = listElement else { return [] }

        var itemsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &itemsRef) == .success,
              let items = itemsRef as? [AXUIElement] else {
            return []
        }

        var results: [CachedDockTile] = []
        for elem in items {
            var subroleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(elem, kAXSubroleAttribute as CFString, &subroleRef)
            guard (subroleRef as? String) == "AXApplicationDockItem" else { continue }

            var urlRef: CFTypeRef?
            AXUIElementCopyAttributeValue(elem, kAXURLAttribute as CFString, &urlRef)
            guard let appURL = urlRef as? URL,
                  let bundleID = resolveBundleID(for: appURL),
                  let agentID = targetAgents.first(where: { $0.matches(bundleIdentifier: bundleID) }) else {
                continue
            }

            var frameRef: CFTypeRef?
            AXUIElementCopyAttributeValue(elem, "AXFrame" as CFString, &frameRef)
            var axRect = CGRect.zero
            if let frameRef, CFGetTypeID(frameRef) == AXValueGetTypeID() {
                AXValueGetValue(frameRef as! AXValue, .cgRect, &axRect)
            }
            guard axRect.width > 10, axRect.height > 10 else { continue }

            let iconRect = makeCocoaIconRect(from: axRect, mainDisplayHeight: mainDisplayHeight)
            results.append(CachedDockTile(
                agentID: agentID,
                bundleID: bundleID,
                appURL: appURL,
                cocoaFrame: iconRect,
                axFrame: axRect
            ))
        }
        return results
    }

    /// Classifies the exact Dock element under the cursor off-main-thread so boundary hysteresis never confuses gaps with exits.
    public func classifyHoveredTileAsync(
        for targetAgents: [AgentID],
        dockPID: pid_t,
        mainDisplayHeight: CGFloat
    ) async -> DockAXHitOutcome {
        await withCheckedContinuation { continuation in
            axQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .outsideDock(cgCursor: .zero))
                    return
                }
                let outcome = self.classifyHitTest(
                    for: targetAgents,
                    dockPID: dockPID,
                    mainDisplayHeight: mainDisplayHeight
                )
                continuation.resume(returning: outcome)
            }
        }
    }

    /// Runs off-main-thread so AX IPC to Dock never stutters the UI or cursor.
    public func hitTestHoveredTileAsync(
        for targetAgents: [AgentID],
        dockPID: pid_t,
        mainDisplayHeight: CGFloat
    ) async -> (match: DockTileMatch?, hasOpenMenu: Bool) {
        let outcome = await classifyHoveredTileAsync(
            for: targetAgents,
            dockPID: dockPID,
            mainDisplayHeight: mainDisplayHeight
        )
        switch outcome {
        case .matched(let m): return (m, false)
        case .openMenu: return (nil, true)
        case .dockGap, .untrackedItem, .outsideDock: return (nil, false)
        }
    }

    public func classifyHitTest(
        for targetAgents: [AgentID],
        dockPID: pid_t,
        mainDisplayHeight: CGFloat
    ) -> DockAXHitOutcome {
        guard AXIsProcessTrusted() else { return .outsideDock(cgCursor: .zero) }
        guard let cgEvent = CGEvent(source: nil) else { return .outsideDock(cgCursor: .zero) }
        let cgCursor = cgEvent.location

        let axDock = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(axDock, 0.25)

        var hitElement: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(axDock, Float(cgCursor.x), Float(cgCursor.y), &hitElement)
        guard err == .success, let elem = hitElement else {
            return .outsideDock(cgCursor: cgCursor)
        }

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? ""
        if role == kAXMenuItemRole as String || role == kAXMenuRole as String {
            return .openMenu
        }

        // Empty inter-icon seam inside the Dock glass bar (AXList / AXApplication container)
        if role == (kAXListRole as String) || role == (kAXApplicationRole as String) {
            return .dockGap(cgCursor: cgCursor)
        }

        var frameRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, "AXFrame" as CFString, &frameRef)
        var axRect = CGRect.zero
        if let frameRef, CFGetTypeID(frameRef) == AXValueGetTypeID() {
            AXValueGetValue(frameRef as! AXValue, .cgRect, &axRect)
        }

        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXSubroleAttribute as CFString, &subroleRef)
        let subrole = (subroleRef as? String) ?? ""
        guard subrole == "AXApplicationDockItem" else {
            if subrole == "AXSeparatorDockItem" {
                return .dockGap(cgCursor: cgCursor)
            }
            if axRect.width > 8, axRect.height > 8 {
                return .untrackedItem(axFrame: axRect, cgCursor: cgCursor)
            }
            return .outsideDock(cgCursor: cgCursor)
        }

        var urlRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXURLAttribute as CFString, &urlRef)
        guard let appURL = urlRef as? URL,
              let bundleID = resolveBundleID(for: appURL) else {
            if axRect.width > 8, axRect.height > 8 {
                return .untrackedItem(axFrame: axRect, cgCursor: cgCursor)
            }
            return .outsideDock(cgCursor: cgCursor)
        }

        guard let agentID = targetAgents.first(where: { $0.matches(bundleIdentifier: bundleID) }) else {
            if axRect.width > 8, axRect.height > 8 {
                return .untrackedItem(axFrame: axRect, cgCursor: cgCursor)
            }
            return .outsideDock(cgCursor: cgCursor)
        }

        guard axRect.width > 10, axRect.height > 10 else {
            return .dockGap(cgCursor: cgCursor)
        }

        let iconRect = makeCocoaIconRect(from: axRect, mainDisplayHeight: mainDisplayHeight)

        return .matched(DockTileMatch(
            agentID: agentID,
            bundleID: bundleID,
            appURL: appURL,
            cocoaFrame: iconRect,
            axFrame: axRect,
            cgCursor: cgCursor,
            isLiveAX: true
        ))
    }

    public func performHitTest(
        for targetAgents: [AgentID],
        dockPID: pid_t,
        mainDisplayHeight: CGFloat
    ) -> (match: DockTileMatch?, hasOpenMenu: Bool) {
        switch classifyHitTest(for: targetAgents, dockPID: dockPID, mainDisplayHeight: mainDisplayHeight) {
        case .matched(let m): return (m, false)
        case .openMenu: return (nil, true)
        case .dockGap, .untrackedItem, .outsideDock: return (nil, false)
        }
    }

    private func makeCocoaIconRect(from axRect: CGRect, mainDisplayHeight: CGFloat) -> NSRect {
        let cocoaY = mainDisplayHeight - axRect.origin.y - axRect.height
        let cocoaRect = NSRect(x: axRect.origin.x, y: cocoaY, width: axRect.width, height: axRect.height)
        let side = min(cocoaRect.width, cocoaRect.height)
        return NSRect(
            x: cocoaRect.midX - side / 2.0,
            y: cocoaRect.midY - side / 2.0 + (cocoaRect.height - side) * 0.22,
            width: side,
            height: side
        )
    }

    private func resolveBundleID(for url: URL) -> String? {
        let path = url.path
        cacheLock.lock()
        let cached = cachedBundleIDByPath[path]
        cacheLock.unlock()
        if let cached { return cached }

        if let bid = Bundle(url: url)?.bundleIdentifier {
            cacheLock.lock()
            cachedBundleIDByPath[path] = bid
            cacheLock.unlock()
            return bid
        }
        return nil
    }
}
