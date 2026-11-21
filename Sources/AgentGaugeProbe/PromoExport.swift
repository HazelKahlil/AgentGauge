import AgentGaugeCore
import AppKit
import CoreGraphics
import Foundation

/// Offline asset exporter for the AgentGauge promo video.
/// Renders real Metal tiles, real Liquid Glass hover dashboards and real app windows into PNGs.
enum PromoExport {
    static let repoRoot: String = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }()

    // MARK: - Shared helpers

    static func ensureDir(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    static func writePNG(_ cg: CGImage, to path: String) {
        let rep = NSBitmapImageRep(cgImage: cg)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    @MainActor
    static func iconPNG(for url: URL, side: Int) -> CGImage? {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: cs, bitmapInfo: info) else { return nil }
        ctx.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// Deep midnight aurora wallpaper shared by the video backgrounds and the glass capture backdrop.
    static func makeWallpaper(width: Int, height: Int) -> CGImage? {
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: cs, bitmapInfo: info) else { return nil }
        let w = CGFloat(width), h = CGFloat(height)

        let base = CGGradient(colorsSpace: cs, colors: [
            CGColor(srgbRed: 0.055, green: 0.067, blue: 0.118, alpha: 1),
            CGColor(srgbRed: 0.035, green: 0.043, blue: 0.075, alpha: 1)
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])

        func glow(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: (CGFloat, CGFloat, CGFloat, CGFloat)) {
            let g = CGGradient(colorsSpace: cs, colors: [
                CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3),
                CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 0)
            ] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
        }
        glow(w * 0.18, h * 0.82, w * 0.55, (0.23, 0.36, 0.86, 0.42))
        glow(w * 0.86, h * 0.70, w * 0.46, (0.45, 0.30, 0.88, 0.30))
        glow(w * 0.62, h * 0.08, w * 0.52, (0.10, 0.62, 0.62, 0.26))
        glow(w * 0.40, h * 0.40, w * 0.30, (0.20, 0.28, 0.55, 0.20))
        return ctx.makeImage()
    }

    struct TileState {
        var hover: CGFloat = 0
        var tilt: CGFloat = 0
        var tiltVel: CGFloat = 0
        var ripple: CGFloat = 0.36
        var waveTime: CGFloat = 0
        var bubbleTime: CGFloat = 0
    }

    /// Physically faithful replay of OverlayManager's hover motion integrator (30fps, calibrated speed/tilt).
    @MainActor
    static func renderSequence(
        renderer: NativeIconRenderer,
        agent: AgentID,
        appURL: URL,
        frames: Int,
        dir: String,
        initialTiltVel: CGFloat,
        style: DockBadgeStyle = .concentricAutoDodge,
        tone: NumberColorMode = .smartInvert,
        scale: CGFloat = 1.5,
        startHover: CGFloat = 0,
        seed: CGFloat = 0,
        agitation: ((Int) -> CGFloat)? = nil,
        impulses: [Int: CGFloat] = [:],
        snapshot: (Int) -> QuotaSnapshot
    ) {
        ensureDir(dir)
        let dt: CGFloat = 1.0 / 30.0
        let speed: CGFloat = 0.25 + 0.80 * 1.12
        let tiltScale: CGFloat = 0.25 + 0.67 * 0.58
        var st = TileState()
        st.hover = startHover
        st.tiltVel = initialTiltVel
        st.waveTime = seed
        st.bubbleTime = seed * 1.3

        for f in 0..<frames {
            st.waveTime += dt * 1.85 * speed
            st.bubbleTime += dt * 2.4 * speed
            st.hover += (1.0 - st.hover) * min(1.0, dt * 16.0)
            if 1.0 - st.hover < 0.006 { st.hover = 1.0 }
            let accel = 20.0 * (0 - st.tilt) - 8.4 * st.tiltVel
            st.tiltVel += accel * dt
            st.tilt = max(-0.42, min(0.42, st.tilt + st.tiltVel * dt))
            st.ripple *= pow(0.14, dt)
            if let kick = impulses[f] {
                st.tiltVel += kick
                st.ripple = max(st.ripple, 0.30)
            }
            if let agitation {
                st.ripple = max(st.ripple, agitation(f))
            }

            let params = IconRenderParams(
                waveTime: st.waveTime,
                bubbleTime: st.bubbleTime,
                hoverAlpha: st.hover,
                tilt: st.tilt * tiltScale,
                ripple: st.ripple,
                animate: true,
                showDockBadge: true,
                showPercentageSign: true,
                numberColorMode: tone,
                badgeStyle: style,
                badgeScale: scale,
                badgeOpacity: 0.85
            )
            if let cg = renderer.renderTileImage(agentID: agent, appURL: appURL, snapshot: snapshot(f), params: params) {
                writePNG(cg, to: String(format: "%@/f_%03d.png", dir, f))
            }
        }
    }

    static func runCapture(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
    }

    // MARK: - Demo snapshots (synthetic account data, never the user's real emails)

    static func demoSnapshots() -> [AgentID: QuotaSnapshot] {
        PromoDemoData.snapshots()
    }

    // MARK: - Entry

    @MainActor
    static func run(outDir: String) async {
        let t0 = Date()
        ensureDir(outDir)
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)

        // 1) Wallpaper
        if let wp = makeWallpaper(width: 3840, height: 2160) {
            writePNG(wp, to: "\(outDir)/wallpaper.png")
        }

        // 2) App icons (real installed icons, bundled brand icons as fallback) + system Dock icons
        let iconsDir = "\(outDir)/icons"
        ensureDir(iconsDir)
        var iconCount = 0
        for id in AgentID.allCases {
            if let url = id.installedAppURL, let cg = iconPNG(for: url, side: 512) {
                writePNG(cg, to: "\(iconsDir)/\(id.rawValue).png")
                iconCount += 1
            } else {
                let bundled = "\(repoRoot)/Resources/AgentIcons/\(id.rawValue).png"
                if FileManager.default.fileExists(atPath: bundled) {
                    try? FileManager.default.removeItem(atPath: "\(iconsDir)/\(id.rawValue).png")
                    try? FileManager.default.copyItem(atPath: bundled, toPath: "\(iconsDir)/\(id.rawValue).png")
                    iconCount += 1
                }
            }
        }
        let systemApps: [(String, String)] = [
            ("finder", "/System/Library/CoreServices/Finder.app"),
            ("safari", "/System/Cryptexes/App/System/Applications/Safari.app"),
            ("settings", "/System/Applications/System Settings.app"),
            ("terminal", "/System/Applications/Utilities/Terminal.app"),
            ("agentgauge", "/Applications/AgentGauge.app")
        ]
        for (name, path) in systemApps where FileManager.default.fileExists(atPath: path) {
            if let cg = iconPNG(for: URL(fileURLWithPath: path), side: 512) {
                writePNG(cg, to: "\(iconsDir)/\(name).png")
            }
        }
        print("PROMO icons:", iconCount, "agent icons")

        // 3) Real Metal tile sequences
        let snaps = demoSnapshots()
        let r512 = NativeIconRenderer.makeOffscreenRenderer(side: 512)
        let r320 = NativeIconRenderer.makeOffscreenRenderer(side: 320)
        let r768 = NativeIconRenderer.makeOffscreenRenderer(side: 768)
        let r1024 = NativeIconRenderer.makeOffscreenRenderer(side: 1024)

        // HD hero close-ups (user's chosen style: 动态反相字 + 智能反转 @155%), lively mouse-sway impulses
        let heroes: [(AgentID, CGFloat)] = [(.grokbot, 0.4), (.cursor, 1.7), (.antigravity, 2.9)]
        for (hi, hero) in heroes.enumerated() {
            guard let url = hero.0.installedAppURL, let snap = snaps[hero.0] else { continue }
            var kicks: [Int: CGFloat] = [:]
            for k in stride(from: 26, to: 240, by: 34) { kicks[k] = ((k / 34 + hi) % 2 == 0 ? 0.85 : -0.85) }
            renderSequence(renderer: r1024, agent: hero.0, appURL: url, frames: 240, dir: "\(outDir)/seq/hd_\(hero.0.rawValue)",
                           initialTiltVel: (hi % 2 == 0 ? 0.9 : -0.9), style: .pureSplitText, tone: .smartInvert, scale: 1.55,
                           seed: hero.1, impulses: kicks) { _ in snap }
        }
        print("PROMO HD heroes done", String(format: "%.1fs", Date().timeIntervalSince(t0)))

        let wakeAgents: [(AgentID, CGFloat, CGFloat)] = [
            (.antigravity, 0.72, 1.0), (.codex, -0.66, 2.3), (.grokbot, 0.70, 3.1),
            (.cursor, -0.60, 4.4), (.claude, 0.64, 5.2), (.workbuddy, -0.58, 6.0)
        ]
        for (id, vel, seed) in wakeAgents {
            guard let url = id.installedAppURL, let snap = snaps[id] else {
                print("PROMO skip wake (not installed):", id.rawValue)
                continue
            }
            renderSequence(renderer: r512, agent: id, appURL: url, frames: 96, dir: "\(outDir)/seq/wake_\(id.rawValue)",
                           initialTiltVel: vel, seed: seed) { _ in snap }
        }
        print("PROMO wake sequences done", String(format: "%.1fs", Date().timeIntervalSince(t0)))

        // Drain hero: 100% -> 22% (crosses the low-water auto-dodge threshold)
        if let agURL = AgentID.antigravity.installedAppURL {
            let frames = 180
            func level(_ f: Int) -> Double {
                let a = 14.0, b = 150.0
                let x = max(0, min(1, (Double(f) - a) / (b - a)))
                let e = x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
                return 100.0 - 78.0 * e
            }
            renderSequence(renderer: r768, agent: .antigravity, appURL: agURL, frames: frames, dir: "\(outDir)/seq/drain_antigravity",
                           initialTiltVel: 0.55, startHover: 0.0, seed: 0.7,
                           agitation: { f in (f > 14 && f < 150) ? 0.10 : 0 }) { f in
                QuotaSnapshot(agentID: .antigravity, remainingPercent: level(f), sourceDescription: "promo")
            }
        }
        print("PROMO drain done", String(format: "%.1fs", Date().timeIntervalSince(t0)))

        // Style showcase grid (12 cells)
        let cells: [(DockBadgeStyle, NumberColorMode, AgentID, Double)] = [
            (.refTopTimerScrim, .smartInvert, .codex, 37),
            (.pureSplitText, .smartInvert, .claude, 54),
            (.haloText, .adaptiveInk, .grokbot, 61),
            (.concentricAutoDodge, .smartInvert, .antigravity, 72),
            (.apertureSweep, .smartInvert, .codex, 37),
            (.retroLEDMatrix, .obsidianBlack, .claude, 42),
            (.dualTrackHUD, .smartInvert, .cursor, 57),
            (.braunAnalogNeedle, .obsidianBlack, .grokbot, 58),
            (.bottomPrismCells, .smartInvert, .cursor, 64),
            (.topDynamicIsland, .smartInvert, .claude, 77),
            (.topEnergyBrow, .smartInvert, .antigravity, 70),
            (.concentricAutoDodge, .adaptiveInk, .antigravity, 22)
        ]
        for (i, cell) in cells.enumerated() {
            guard let url = cell.2.installedAppURL else { continue }
            let demoWin = [QuotaWindow(label: "5h 限额", remainingPercent: cell.3, resetText: "19h 0m", isPrimary: true)]
            renderSequence(renderer: r320, agent: cell.2, appURL: url, frames: 150,
                           dir: String(format: "%@/seq/style_%02d", outDir, i),
                           initialTiltVel: (i % 2 == 0 ? 0.42 : -0.42), style: cell.0, tone: cell.1,
                           startHover: 0.0, seed: CGFloat(i) * 0.9) { _ in
                QuotaSnapshot(agentID: cell.2, remainingPercent: cell.3, resetText: "19h 0m", windows: demoWin, sourceDescription: "promo")
            }
        }
        print("PROMO style grid done", String(format: "%.1fs", Date().timeIntervalSince(t0)))

        // 4) Real Liquid Glass hover dashboards captured from WindowServer over the shared wallpaper backdrop
        let shotsDir = "\(outDir)/shots"
        ensureDir(shotsDir)
        guard let screen = NSScreen.main else { return }
        let vis = screen.frame
        let backFrame = NSRect(x: vis.midX - 520, y: vis.midY - 340, width: 1040, height: 680)
        let backdrop = NSWindow(contentRect: backFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.isOpaque = true
        backdrop.hasShadow = false
        backdrop.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) - 1)
        backdrop.collectionBehavior = [.canJoinAllSpaces, .stationary]
        let iv = NSImageView(frame: NSRect(origin: .zero, size: backFrame.size))
        iv.imageScaling = .scaleAxesIndependently
        if let wp = makeWallpaper(width: 2080, height: 1360) {
            iv.image = NSImage(cgImage: wp, size: backFrame.size)
        }
        backdrop.contentView = iv
        backdrop.orderFrontRegardless()

        let tip = HoverTooltipPanel()
        let anchor = NSRect(x: backFrame.midX - 32, y: backFrame.minY + 30, width: 64, height: 64)
        let order: [AgentID] = [.antigravity, .codex, .grokbot, .cursor, .claude, .workbuddy]
        for id in order {
            guard let snap = snaps[id] else { continue }
            tip.hide(immediate: true)
            try? await Task.sleep(nanoseconds: 120_000_000)
            tip.show(snapshot: snap, anchorRect: anchor, orientation: .bottom, detailMode: .multiModel,
                     showPercentageSign: true, accentColor: id.defaultAccentColor)
            try? await Task.sleep(nanoseconds: 650_000_000)
            runCapture(["-x", "-o", "-l", "\(tip.windowNumber)", "\(shotsDir)/tooltip_\(id.rawValue).png"])
        }
        tip.hide(immediate: true)
        backdrop.orderOut(nil)
        print("PROMO tooltips captured", String(format: "%.1fs", Date().timeIntervalSince(t0)))
    }

    @MainActor
    static func exportHDHeroes(outDir: String) async {
        let t0 = Date()
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let snaps = demoSnapshots()
        let r1024 = NativeIconRenderer.makeOffscreenRenderer(side: 1024)
        let heroes: [(AgentID, CGFloat)] = [(.grokbot, 0.4), (.cursor, 1.7), (.antigravity, 2.9)]
        for (hi, hero) in heroes.enumerated() {
            guard let url = hero.0.installedAppURL, let snap = snaps[hero.0] else { continue }
            var kicks: [Int: CGFloat] = [:]
            for k in stride(from: 26, to: 240, by: 34) { kicks[k] = ((k / 34 + hi) % 2 == 0 ? 0.85 : -0.85) }
            renderSequence(renderer: r1024, agent: hero.0, appURL: url, frames: 240, dir: "\(outDir)/seq/hd_\(hero.0.rawValue)",
                           initialTiltVel: (hi % 2 == 0 ? 0.9 : -0.9), style: .pureSplitText, tone: .smartInvert, scale: 1.55,
                           seed: hero.1, impulses: kicks) { _ in snap }
        }
        print("PROMO HD heroes (1024px) done", String(format: "%.1fs", Date().timeIntervalSince(t0)))
    }

    /// Captures the running AgentGauge app windows (settings / sheets / menu bar popovers) over the shared wallpaper backdrop.
    @MainActor
    static func captureApp(outDir: String, prefix: String) async {
        let shotsDir = "\(outDir)/shots"
        ensureDir(shotsDir)
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            print("PROMO no window list")
            return
        }
        let mine = list.filter {
            ($0[kCGWindowOwnerName as String] as? String) == "AgentGauge"
                && (($0[kCGWindowLayer as String] as? Int) ?? -1) >= 0
        }
        let mainH = NSScreen.screens.first?.frame.height ?? 0
        var idx = 0
        for w in mine {
            guard let num = w[kCGWindowNumber as String] as? Int,
                  let layer = w[kCGWindowLayer as String] as? Int,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let bw = b["Width"], let bh = b["Height"], bw > 300, bh > 260,
                  let bx = b["X"], let by = b["Y"] else { continue }
            let cocoa = NSRect(x: bx - 120, y: mainH - by - bh - 120, width: bw + 240, height: bh + 240)
            let backdrop = NSWindow(contentRect: cocoa, styleMask: [.borderless], backing: .buffered, defer: false)
            backdrop.isOpaque = true
            backdrop.hasShadow = false
            backdrop.level = NSWindow.Level(rawValue: layer)
            let iv = NSImageView(frame: NSRect(origin: .zero, size: cocoa.size))
            iv.imageScaling = .scaleAxesIndependently
            if let wp = makeWallpaper(width: Int(cocoa.width * 2), height: Int(cocoa.height * 2)) {
                iv.image = NSImage(cgImage: wp, size: cocoa.size)
            }
            backdrop.contentView = iv
            backdrop.orderFrontRegardless()
            backdrop.order(.below, relativeTo: num)
            try? await Task.sleep(nanoseconds: 700_000_000)
            let path = "\(shotsDir)/\(prefix)_\(idx)_\(Int(bw))x\(Int(bh)).png"
            runCapture(["-x", "-o", "-l", "\(num)", path])
            print("PROMO captured window", num, "layer=\(layer)", Int(bw), Int(bh), "->", path)
            backdrop.orderOut(nil)
            idx += 1
        }
    }
}
