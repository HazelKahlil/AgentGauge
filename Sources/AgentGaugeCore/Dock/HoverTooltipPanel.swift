import AppKit
import QuartzCore
import SwiftUI

@MainActor
private enum TooltipIconCache {
    private static var cache: [AgentID: NSImage] = [:]

    static func icon(for agentID: AgentID) -> NSImage? {
        if let hit = cache[agentID] { return hit }
        if let url = agentID.installedAppURL {
            let img = NSWorkspace.shared.icon(forFile: url.path)
            cache[agentID] = img
            return img
        }
        if let bundled = Bundle.main.url(forResource: agentID.rawValue, withExtension: "png", subdirectory: "AgentIcons"),
           let img = NSImage(contentsOf: bundled) {
            cache[agentID] = img
            return img
        }
        return nil
    }
}

@MainActor
private final class TooltipPresentationModel: ObservableObject {
    @Published var snapshot: QuotaSnapshot?
    @Published var detailMode: TooltipDetailMode = .multiModel
    @Published var showPercentageSign: Bool = true
    @Published var accentColor: NSColor = .systemBlue
    @Published var appIcon: NSImage?
    @Published var isVisibleOnScreen: Bool = false
}

@MainActor
private final class TooltipDisplayLinkProxy: NSObject {
    weak var owner: HoverTooltipPanel?

    init(owner: HoverTooltipPanel) {
        self.owner = owner
    }

    @objc func onFrame(_ link: CADisplayLink) {
        owner?.handleDisplayLinkTick(link)
    }
}

@MainActor
public final class HoverTooltipPanel {
    private let panel: NSPanel
    private let hostingView: NSHostingView<TooltipRootContainer>
    private let model = TooltipPresentationModel()

    private var currentAgentID: AgentID?
    private var pendingHideWorkItem: DispatchWorkItem?
    private var animationGeneration: Int = 0
    private var isHiding: Bool = false

    // 120Hz critically-damped spring state (never cancelled by async SwiftUI layout resizes)
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: TooltipDisplayLinkProxy?
    private var lastMotionTimestamp: CFTimeInterval = 0

    private var latestAnchorRect: NSRect = .zero
    private var latestOrientation: DockOrientation = .bottom
    private var hasAnchorPosition: Bool = false

    /// Logical anchor point of the visual card (excluding shadowInset):
    /// - `.bottom`: (centerX, bottomY)
    /// - `.left`:   (leftX, centerY)
    /// - `.right`:  (rightX, centerY)
    private var currentAnchor: NSPoint = .zero
    private var targetAnchor: NSPoint = .zero
    private var velocity: NSPoint = .zero
    private var settleChecksRemaining: Int = 0

    /// Transparent outer margin inside NSPanel so native Liquid Glass shadow & spring bloom never clip at window edges.
    private static let shadowInset: CGFloat = 16

    public init() {
        let root = TooltipRootContainer(model: model, shadowInset: Self.shadowInset)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 140)
        hosting.autoresizingMask = [.width, .height]

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 140),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Shadow is rendered smoothly around the continuous squircle inside SwiftUI so WindowServer never draws rectangular shadow fringes
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .fullScreenAuxiliary]
        panel.contentView = hosting

        self.hostingView = hosting
        self.panel = panel
    }

    public func show(
        snapshot: QuotaSnapshot,
        anchorRect: NSRect,
        orientation: DockOrientation,
        detailMode: TooltipDetailMode,
        showPercentageSign: Bool,
        accentColor: NSColor
    ) {
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil

        let wasVisible = panel.isVisible && panel.alphaValue > 0.08 && currentAgentID != nil && hasAnchorPosition
        let switchedAgent = wasVisible && currentAgentID != snapshot.agentID
        let orientationChanged = wasVisible && latestOrientation != orientation
        let wasMidHide = isHiding
        isHiding = false

        let contentChanged = (model.snapshot != snapshot)
            || (model.detailMode != detailMode)
            || (model.showPercentageSign != showPercentageSign)
            || (model.accentColor.srgbHexString != accentColor.srgbHexString)

        if contentChanged {
            let icon = TooltipIconCache.icon(for: snapshot.agentID)
            model.snapshot = snapshot
            model.detailMode = detailMode
            model.showPercentageSign = showPercentageSign
            model.accentColor = accentColor
            model.appIcon = icon
            hostingView.invalidateIntrinsicContentSize()
            hostingView.layoutSubtreeIfNeeded()
        }

        latestAnchorRect = anchorRect
        latestOrientation = orientation
        currentAgentID = snapshot.agentID

        let (panelSize, cardSize) = measurePanelAndCardSize()
        let nextTarget = computeTargetAnchor(anchorRect: anchorRect, orientation: orientation, cardSize: cardSize)
        targetAnchor = nextTarget

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if !wasVisible || orientationChanged {
            // Fresh appearance: snap dead-center over the hovered app immediately, then spring-pop in
            animationGeneration += 1
            currentAnchor = nextTarget
            velocity = .zero
            hasAnchorPosition = true
            settleChecksRemaining = 6
            model.isVisibleOnScreen = false

            applyPanelFrame(anchor: currentAnchor, panelSize: panelSize, cardSize: cardSize, orientation: orientation)
            panel.alphaValue = 1.0
            panel.orderFrontRegardless()

            withAnimation(.spring(response: 0.24, dampingFraction: 0.80)) {
                model.isVisibleOnScreen = true
            }
            // Keep display link active briefly so async SwiftUI layout finalization stays centered
            ensureDisplayLinkRunning()
        } else {
            // Already visible (sliding across apps, jumping horizontally, or tracking live Dock magnification):
            // Continuously glide from currentAnchor -> targetAnchor without ever cancelling on resize!
            if wasMidHide || !model.isVisibleOnScreen {
                animationGeneration += 1
                withAnimation(.spring(response: 0.20, dampingFraction: 0.84)) {
                    model.isVisibleOnScreen = true
                }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.12
                    panel.animator().alphaValue = 1.0
                }
            } else if panel.alphaValue < 0.99 {
                panel.alphaValue = 1.0
            }

            if switchedAgent {
                animationGeneration += 1
                settleChecksRemaining = 10
            } else if contentChanged {
                settleChecksRemaining = max(settleChecksRemaining, 6)
            }

            if reduceMotion {
                currentAnchor = nextTarget
                velocity = .zero
                applyPanelFrame(anchor: currentAnchor, panelSize: panelSize, cardSize: cardSize, orientation: orientation)
                ensureDisplayLinkRunning()
            } else {
                // Immediately apply updated size/clamping around current smoothly gliding anchor and drive 120Hz spring
                applyPanelFrame(anchor: currentAnchor, panelSize: panelSize, cardSize: cardSize, orientation: orientation)
                ensureDisplayLinkRunning()
            }
        }
    }

    private func measurePanelAndCardSize() -> (panelSize: NSSize, cardSize: NSSize) {
        let fitting = hostingView.fittingSize
        let intrinsic = hostingView.intrinsicContentSize
        let pad = Self.shadowInset
        let width = ceil(max(290 + pad * 2, max(fitting.width, intrinsic.width)))
        let height = ceil(max(66 + pad * 2, max(fitting.height, intrinsic.height)))
        return (
            NSSize(width: width, height: height),
            NSSize(width: width - pad * 2, height: height - pad * 2)
        )
    }

    private func screenVisibleBounds(for anchorRect: NSRect) -> NSRect? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchorRect) }) ?? NSScreen.main else {
            return nil
        }
        return screen.frame.insetBy(dx: 10, dy: 10)
    }

    private func computeTargetAnchor(
        anchorRect: NSRect,
        orientation: DockOrientation,
        cardSize: NSSize
    ) -> NSPoint {
        var pt: NSPoint
        switch orientation {
        case .bottom:
            pt = NSPoint(x: anchorRect.midX, y: anchorRect.maxY + 58)
        case .left:
            pt = NSPoint(x: anchorRect.maxX + 26, y: anchorRect.midY)
        case .right:
            pt = NSPoint(x: anchorRect.minX - 26, y: anchorRect.midY)
        }
        return clampAnchor(pt, anchorRect: anchorRect, orientation: orientation, cardSize: cardSize)
    }

    private func clampAnchor(
        _ pt: NSPoint,
        anchorRect: NSRect,
        orientation: DockOrientation,
        cardSize: NSSize
    ) -> NSPoint {
        guard let visible = screenVisibleBounds(for: anchorRect) else { return pt }
        var out = pt
        switch orientation {
        case .bottom:
            let minX = visible.minX + cardSize.width / 2.0
            let maxX = visible.maxX - cardSize.width / 2.0
            out.x = minX <= maxX ? max(minX, min(maxX, out.x)) : visible.midX
            out.y = max(visible.minY, min(visible.maxY - cardSize.height, out.y))
        case .left:
            out.x = max(visible.minX, min(visible.maxX - cardSize.width, out.x))
            let minY = visible.minY + cardSize.height / 2.0
            let maxY = visible.maxY - cardSize.height / 2.0
            out.y = minY <= maxY ? max(minY, min(maxY, out.y)) : visible.midY
        case .right:
            out.x = max(visible.minX + cardSize.width, min(visible.maxX, out.x))
            let minY = visible.minY + cardSize.height / 2.0
            let maxY = visible.maxY - cardSize.height / 2.0
            out.y = minY <= maxY ? max(minY, min(maxY, out.y)) : visible.midY
        }
        return out
    }

    private func applyPanelFrame(
        anchor: NSPoint,
        panelSize: NSSize,
        cardSize: NSSize,
        orientation: DockOrientation
    ) {
        let pad = Self.shadowInset
        let clamped = clampAnchor(anchor, anchorRect: latestAnchorRect, orientation: orientation, cardSize: cardSize)
        let cardOrigin: NSPoint
        switch orientation {
        case .bottom:
            cardOrigin = NSPoint(x: clamped.x - cardSize.width / 2.0, y: clamped.y)
        case .left:
            cardOrigin = NSPoint(x: clamped.x, y: clamped.y - cardSize.height / 2.0)
        case .right:
            cardOrigin = NSPoint(x: clamped.x - cardSize.width, y: clamped.y - cardSize.height / 2.0)
        }

        let targetFrame = NSRect(
            x: round(cardOrigin.x - pad),
            y: round(cardOrigin.y - pad),
            width: panelSize.width,
            height: panelSize.height
        )

        let sizeChanged = abs(panel.frame.width - targetFrame.width) > 0.5
            || abs(panel.frame.height - targetFrame.height) > 0.5
        let originChanged = abs(panel.frame.origin.x - targetFrame.origin.x) > 0.25
            || abs(panel.frame.origin.y - targetFrame.origin.y) > 0.25

        if sizeChanged {
            hostingView.frame = NSRect(origin: .zero, size: targetFrame.size)
            panel.setFrame(targetFrame, display: true)
        } else if originChanged {
            panel.setFrameOrigin(targetFrame.origin)
        }
    }

    private func ensureDisplayLinkRunning() {
        if displayLink == nil {
            let proxy = TooltipDisplayLinkProxy(owner: self)
            let link = panel.displayLink(target: proxy, selector: #selector(TooltipDisplayLinkProxy.onFrame(_:)))
            link.add(to: .main, forMode: .common)
            self.displayLinkProxy = proxy
            self.displayLink = link
        }
        if displayLink?.isPaused == true {
            lastMotionTimestamp = CACurrentMediaTime()
            displayLink?.isPaused = false
        }
    }

    private func pauseDisplayLink() {
        displayLink?.isPaused = true
        lastMotionTimestamp = 0
    }

    fileprivate func handleDisplayLinkTick(_ link: CADisplayLink) {
        guard panel.isVisible, hasAnchorPosition else {
            pauseDisplayLink()
            return
        }

        let now = link.timestamp > 0 ? link.timestamp : CACurrentMediaTime()
        let rawDt = lastMotionTimestamp > 0 ? (now - lastMotionTimestamp) : (1.0 / 60.0)
        lastMotionTimestamp = now
        let dt = CGFloat(min(0.04, max(0.004, rawDt)))

        // Re-measure SwiftUI card every frame so async width/height transitions stay perfectly centered
        let (panelSize, cardSize) = measurePanelAndCardSize()
        let freshTarget = computeTargetAnchor(
            anchorRect: latestAnchorRect,
            orientation: latestOrientation,
            cardSize: cardSize
        )
        targetAnchor = freshTarget

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            currentAnchor = freshTarget
            velocity = .zero
        } else {
            // Critically-damped spring (zeta = 1.0, omega = 26 rad/s -> ~0.20s silky glide matching website)
            let omega: CGFloat = 26.0
            let omegaSq = omega * omega
            let twoOmega = 2.0 * omega

            let dx = targetAnchor.x - currentAnchor.x
            let dy = targetAnchor.y - currentAnchor.y
            let ax = omegaSq * dx - twoOmega * velocity.x
            let ay = omegaSq * dy - twoOmega * velocity.y

            velocity.x += ax * dt
            velocity.y += ay * dt
            currentAnchor.x += velocity.x * dt
            currentAnchor.y += velocity.y * dt
        }

        let remainingX = abs(targetAnchor.x - currentAnchor.x)
        let remainingY = abs(targetAnchor.y - currentAnchor.y)
        let speed = hypot(velocity.x, velocity.y)

        let settled = remainingX < 0.35 && remainingY < 0.35 && speed < 2.0
        if settled {
            currentAnchor = targetAnchor
            velocity = .zero
        }

        applyPanelFrame(
            anchor: currentAnchor,
            panelSize: panelSize,
            cardSize: cardSize,
            orientation: latestOrientation
        )

        if settled {
            if settleChecksRemaining > 0 {
                settleChecksRemaining -= 1
            } else {
                pauseDisplayLink()
            }
        }
    }

    public var currentFrame: NSRect {
        panel.frame.insetBy(dx: Self.shadowInset, dy: Self.shadowInset)
    }

    public var windowNumber: Int {
        panel.windowNumber
    }

    public var rawWindowFrame: NSRect {
        panel.frame
    }

    public func saveDiagnosticPNG(to path: String) {
        let bounds = hostingView.bounds
        guard bounds.width > 10, bounds.height > 10,
              let rep = hostingView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        hostingView.cacheDisplay(in: bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    public func hide(immediate: Bool = false) {
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil

        if immediate {
            animationGeneration += 1
            currentAgentID = nil
            hasAnchorPosition = false
            velocity = .zero
            isHiding = false
            pauseDisplayLink()
            model.isVisibleOnScreen = false
            if panel.isVisible {
                panel.orderOut(nil)
            }
            return
        }

        guard panel.isVisible, !isHiding else { return }

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.performAnimatedHide()
            }
        }
        pendingHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.085, execute: work)
    }

    private func performAnimatedHide() {
        guard panel.isVisible else { return }
        isHiding = true
        animationGeneration += 1
        let gen = animationGeneration

        withAnimation(.easeIn(duration: 0.14)) {
            model.isVisibleOnScreen = false
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.animationGeneration == gen else { return }
                self.isHiding = false
                self.currentAgentID = nil
                self.hasAnchorPosition = false
                self.velocity = .zero
                self.pauseDisplayLink()
                self.panel.orderOut(nil)
            }
        })
    }
}

private struct TooltipRootContainer: View {
    @ObservedObject var model: TooltipPresentationModel
    let shadowInset: CGFloat

    var body: some View {
        TooltipContentView(
            snapshot: model.snapshot,
            detailMode: model.detailMode,
            showPercentageSign: model.showPercentageSign,
            accentColor: model.accentColor,
            appIcon: model.appIcon
        )
        .scaleEffect(model.isVisibleOnScreen ? 1.0 : 0.94, anchor: .bottom)
        .offset(y: model.isVisibleOnScreen ? 0 : 5)
        .opacity(model.isVisibleOnScreen ? 1.0 : 0.0)
        .padding(shadowInset)
    }
}

struct TooltipContentView: View {
    let snapshot: QuotaSnapshot?
    let detailMode: TooltipDetailMode
    let showPercentageSign: Bool
    let accentColor: NSColor
    var appIcon: NSImage? = nil

    private static let cardCornerRadius: CGFloat = 18

    var body: some View {
        if let snapshot {
            let accent = Color(nsColor: accentColor)
            let badge = snapshot.compactPlanBadge

            VStack(alignment: .leading, spacing: 9) {
                // 1. Hero Header: App Squircle Icon + Title & Plan Badge + Account | Big Hero Metric & Countdown
                HStack(alignment: .center, spacing: 9) {
                    ZStack(alignment: .bottomTrailing) {
                        if let appIcon {
                            Image(nsImage: appIcon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 28, height: 28)
                        } else {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(accent.opacity(0.22))
                                .frame(width: 28, height: 28)
                        }

                        if snapshot.isWorking {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 7.5, height: 7.5)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.2))
                                .offset(x: 1.5, y: 1.5)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5.5) {
                            Text(snapshot.agentID.displayName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)

                            if let badge {
                                PlanTierBadgePill(text: badge, accentColor: accentColor, size: .regular)
                            }
                        }

                        if let identityLine = headerIdentitySubtitle(for: snapshot, badge: badge) {
                            Text(identityLine)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }

                    Spacer(minLength: 16)

                    // Right Hero Quota Readout
                    VStack(alignment: .trailing, spacing: 1.5) {
                        if snapshot.remainingPercent != nil {
                            Text(heroValueString(for: snapshot))
                                .font(.system(size: snapshot.isCreditsBased ? 13.5 : 16, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(barColor(for: snapshot.remainingPercent ?? 100, base: accent, textMode: true))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .contentTransition(.numericText())
                        }

                        let cd = snapshot.isWorking ? "正在工作中" : snapshot.formattedCountdown()
                        if cd != "—" {
                            Text(snapshot.isWorking ? cd : "\(cd) 重置")
                                .font(.system(size: 10, weight: .medium).monospacedDigit())
                                .foregroundStyle(snapshot.isWorking ? Color.green : Color.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }

                // 2. Multi-Window Visual Gauge Rows (with sleek Liquid Capsule bars!)
                if detailMode == .multiModel && snapshot.windows.count > 1 {
                    Divider().opacity(0.32)

                    VStack(alignment: .leading, spacing: 5.5) {
                        ForEach(Array(snapshot.windows.prefix(8).enumerated()), id: \.offset) { _, win in
                            let isFeatured = win.isPrimary || win.label.contains("周")
                            let rowAccent = barColor(for: win.remainingPercent, base: accent, textMode: false)

                            HStack(spacing: 9) {
                                Text(win.label)
                                    .font(.system(size: 11, weight: isFeatured ? .semibold : .regular))
                                    .foregroundStyle(isFeatured ? Color.primary : Color.secondary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)

                                Spacer(minLength: 10)

                                // Crisp 52pt visual quota bar
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.09))
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [rowAccent.opacity(0.76), rowAccent],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(3.5, 52.0 * CGFloat(max(0, min(100, win.remainingPercent)) / 100.0)))
                                        .animation(.spring(response: 0.30, dampingFraction: 0.84), value: win.remainingPercent)
                                }
                                .frame(width: 52, height: isFeatured ? 5.5 : 4.5)

                                Text(formatNum(win.remainingPercent))
                                    .font(.system(size: 11, weight: isFeatured ? .bold : .semibold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(win.remainingPercent <= 15 ? Color.red : Color.primary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(minWidth: 33, alignment: .trailing)
                                    .contentTransition(.numericText())

                                Text(win.formattedCountdown())
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(minWidth: 44, alignment: .trailing)
                            }
                        }
                    }
                } else if let rem = snapshot.remainingPercent, snapshot.windows.count <= 1 {
                    // Single-window sleek full-width liquid bar
                    GeometryReader { geo in
                        let rowAccent = barColor(for: rem, base: accent, textMode: false)
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.09))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [rowAccent.opacity(0.75), rowAccent],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(5, geo.size.width * CGFloat(max(0, min(100, rem)) / 100.0)))
                                .animation(.spring(response: 0.30, dampingFraction: 0.84), value: rem)
                        }
                    }
                    .frame(height: 5)
                }

                // 3. Footer Metadata Pill (Credits / Reset Vouchers / Note)
                if detailMode == .multiModel, let sub = snapshot.subtitle, !sub.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(accent.opacity(0.85))
                        Text(sub)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.top, 1)
                }
            }
            .frame(minWidth: 262)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .fixedSize(horizontal: true, vertical: true)
            .modifier(TooltipNativeLiquidGlassModifier(cornerRadius: Self.cardCornerRadius))
        } else {
            EmptyView()
        }
    }

    private func heroValueString(for snap: QuotaSnapshot) -> String {
        if let c = snap.creditsRemaining {
            if let tot = snap.creditsTotal, tot > 0 {
                return "\(c) / \(tot)"
            }
            return "\(c) 积分"
        }
        guard let rem = snap.remainingPercent else { return "—" }
        return "\(Int(round(rem)))\(showPercentageSign ? "%" : "")"
    }

    private func headerIdentitySubtitle(for snap: QuotaSnapshot, badge: String?) -> String? {
        if let email = snap.accountEmail {
            if let tier = snap.planTier, tier != badge {
                return "\(email) · \(tier)"
            }
            return email
        }
        if let tier = snap.planTier, tier != badge {
            return tier
        }
        return snap.sourceDescription
    }

    private func barColor(for pct: Double, base: Color, textMode: Bool) -> Color {
        if pct <= 15 { return .red }
        if pct <= 30 { return .orange }
        return textMode ? .primary : base
    }

    private func formatNum(_ val: Double) -> String {
        let num = Int(round(val))
        return showPercentageSign ? "\(num)%" : "\(num)"
    }
}

private struct TooltipNativeLiquidGlassModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .shadow(color: Color.black.opacity(0.14), radius: 12, y: 5)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75))
                .shadow(color: Color.black.opacity(0.16), radius: 12, y: 5)
        }
    }
}

// MARK: - Low-Saturation Anodized Mineral Subscription Badge (Linear / Apple Titanium Craft · WCAG >= 6.0:1)

public struct PlanTierBadgePill: View {
    public enum SizeStyle {
        case regular
        case compact
    }

    public let text: String
    public let accentColor: NSColor
    public var size: SizeStyle

    public init(text: String, accentColor: NSColor, size: SizeStyle = .regular) {
        self.text = text
        self.accentColor = accentColor
        self.size = size
    }

    public var body: some View {
        let palette = Self.mineralPalette(from: accentColor)
        let isCompact = (size == .compact)

        HStack(spacing: isCompact ? 0 : 4.2) {
            if !isCompact {
                Circle()
                    .fill(palette.dot)
                    .frame(width: 4.6, height: 4.6)
            }

            Text(text)
                .font(.system(size: isCompact ? 8.6 : 9.6, weight: .semibold, design: .rounded))
                .tracking(0.15)
                .foregroundStyle(palette.text)
        }
        .padding(.leading, isCompact ? 5.2 : 6.2)
        .padding(.trailing, isCompact ? 5.2 : 7.0)
        .padding(.vertical, isCompact ? 1.2 : 2.0)
        .background(
            LinearGradient(
                colors: [palette.top, palette.bottom],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [palette.rimTop, palette.rimBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 1.5, x: 0, y: 0.8)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private struct MineralPalette {
        let top: Color
        let bottom: Color
        let dot: Color
        let text: Color
        let rimTop: Color
        let rimBottom: Color
    }

    private static func mineralPalette(from raw: NSColor) -> MineralPalette {
        let fallback = NSColor.fromHex(MineralColorPreset.defaultUIAccentHex)?.usingColorSpace(.sRGB) ?? raw
        let srgb = raw.usingColorSpace(.sRGB) ?? fallback
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        // Tame any neon/high-chroma input into a calm anodized mineral slate (saturation strictly 20%..36%)
        let isNeutral = (s < 0.08)
        let hue = isNeutral ? 0.60 : h
        let mineralSat = isNeutral ? 0.08 : min(0.36, max(0.22, s * 0.52))

        // Smoked mineral charcoal-slate base (luminance ~0.09..0.13) -> effortless >6.2:1 contrast on light & dark glass
        let topNS = NSColor(hue: hue, saturation: mineralSat * 0.92, brightness: 0.36, alpha: 0.90)
        let botNS = NSColor(hue: hue, saturation: mineralSat, brightness: 0.27, alpha: 0.93)

        // Luminous pastel-300 indicator micro-dot & off-white porcelain text
        let dotNS = NSColor(hue: hue, saturation: isNeutral ? 0.06 : min(0.50, max(0.36, s * 0.72)), brightness: 0.92, alpha: 1.0)
        let textNS = NSColor(hue: hue, saturation: isNeutral ? 0.02 : 0.06, brightness: 0.97, alpha: 1.0)
        let rimTopNS = NSColor(hue: hue, saturation: mineralSat * 0.5, brightness: 0.88, alpha: 0.30)
        let rimBotNS = NSColor(hue: hue, saturation: mineralSat * 0.6, brightness: 0.55, alpha: 0.14)

        return MineralPalette(
            top: Color(nsColor: topNS),
            bottom: Color(nsColor: botNS),
            dot: Color(nsColor: dotNS),
            text: Color(nsColor: textNS),
            rimTop: Color(nsColor: rimTopNS),
            rimBottom: Color(nsColor: rimBotNS)
        )
    }
}
