import AgentGaugeCore
import AppKit
import ApplicationServices
import CNativeDockTile
import CoreGraphics
import Foundation

@main
struct DiagProbe {
    static func main() async {
        let argv = CommandLine.arguments
        if let i = argv.firstIndex(of: "--promo") {
            let out = (i + 1 < argv.count) ? argv[i + 1] : "\(PromoExport.repoRoot)/Promo/public"
            await PromoExport.run(outDir: out)
            return
        }
        if let i = argv.firstIndex(of: "--promo-hd-only") {
            let out = (i + 1 < argv.count) ? argv[i + 1] : "\(PromoExport.repoRoot)/Promo/public"
            await PromoExport.exportHDHeroes(outDir: out)
            return
        }
        if let i = argv.firstIndex(of: "--promo-capture-app") {
            let prefix = (i + 1 < argv.count) ? argv[i + 1] : "settings"
            await PromoExport.captureApp(outDir: "\(PromoExport.repoRoot)/Promo/public", prefix: prefix)
            return
        }

        print("1. AXIsProcessTrusted:", AXIsProcessTrusted())

        let t0 = Date()
        let ag = await AntigravityProvider().fetchSnapshot()
        print("2a. Antigravity (\(String(format: "%.2fs", Date().timeIntervalSince(t0)))):",
              "rem=", ag.remainingPercent as Any,
              "tier=", ag.planTier ?? "nil", "badge=", ag.compactPlanBadge ?? "nil",
              "acct=", ag.accountEmail != nil ? "present" : "nil",
              "err=", ag.errorMessage ?? "nil",
              "windows=", ag.windows.map { "\($0.label)=\(Int($0.remainingPercent))" })

        let t1 = Date()
        let cx = await CodexProvider().fetchSnapshot()
        print("2b. Codex (\(String(format: "%.2fs", Date().timeIntervalSince(t1)))):",
              "rem=", cx.remainingPercent as Any,
              "tier=", cx.planTier ?? "nil", "badge=", cx.compactPlanBadge ?? "nil",
              "acct=", cx.accountEmail != nil ? "present" : "nil",
              "sub=", cx.subtitle ?? "")

        let tCur = Date()
        let cur = await CursorProvider().fetchSnapshot()
        print("2c. Cursor (\(String(format: "%.2fs", Date().timeIntervalSince(tCur)))):",
              "rem=", cur.remainingPercent as Any,
              "tier=", cur.planTier ?? "nil", "badge=", cur.compactPlanBadge ?? "nil",
              "acct=", cur.accountEmail != nil ? "present" : "nil")

        let tGb = Date()
        let gb = await GrokBotProvider().fetchSnapshot()
        print("2d. GrokBot (\(String(format: "%.2fs", Date().timeIntervalSince(tGb)))):",
              "rem=", gb.remainingPercent as Any,
              "tier=", gb.planTier ?? "nil", "badge=", gb.compactPlanBadge ?? "nil",
              "acct=", gb.accountEmail != nil ? "present" : "nil",
              "src=", gb.sourceDescription)

        let tCl = Date()
        let cl = await ClaudeProvider().fetchSnapshot()
        print("2e. Claude (\(String(format: "%.2fs", Date().timeIntervalSince(tCl)))):",
              "rem=", cl.remainingPercent as Any,
              "tier=", cl.planTier ?? "nil", "badge=", cl.compactPlanBadge ?? "nil",
              "err=", cl.errorMessage ?? "nil")

        let tGem = Date()
        let gem = await GeminiProvider().fetchSnapshot()
        print("2f. Gemini (\(String(format: "%.2fs", Date().timeIntervalSince(tGem)))):",
              "rem=", gem.remainingPercent as Any,
              "tier=", gem.planTier ?? "nil", "badge=", gem.compactPlanBadge ?? "nil")

        let tCop = Date()
        let cop = await CopilotProvider().fetchSnapshot()
        print("2g. Copilot/VSCode (\(String(format: "%.2fs", Date().timeIntervalSince(tCop)))):",
              "rem=", cop.remainingPercent as Any,
              "tier=", cop.planTier ?? "nil", "badge=", cop.compactPlanBadge ?? "nil",
              "sub=", cop.subtitle ?? "")

        let tDs = Date()
        let ds = await DeepSeekProvider().fetchSnapshot()
        print("2h. DeepSeek (\(String(format: "%.2fs", Date().timeIntervalSince(tDs)))):",
              "rem=", ds.remainingPercent as Any,
              "bal=", ds.balanceDisplay ?? "nil",
              "dockBal=", ds.dockBalanceShort ?? "nil",
              "tier=", ds.planTier ?? "nil",
              "badge=", ds.compactPlanBadge ?? "nil")

        let tGk = Date()
        let gk = await GrokDesktopProvider().fetchSnapshot()
        print("2i. GrokDesktop (\(String(format: "%.2fs", Date().timeIntervalSince(tGk)))):",
              "rem=", gk.remainingPercent as Any,
              "tier=", gk.planTier ?? "nil", "badge=", gk.compactPlanBadge ?? "nil")

        let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier ?? 0
        let locator = DockLocator()
        let t2 = Date()
        let hit = await locator.hitTestHoveredTileAsync(
            for: AgentID.allCases,
            dockPID: dockPID,
            mainDisplayHeight: CGDisplayBounds(CGMainDisplayID()).height
        )
        print("4. Async AX hitTest took \(String(format: "%.2fms", Date().timeIntervalSince(t2)*1000)), match=", hit.match?.agentID.rawValue ?? "nil")

        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.antigravity").first,
           let url = app.bundleURL {
            let t3 = Date()
            _ = await MainActor.run {
                NativeIconRenderer.shared.renderTileImage(
                    agentID: .antigravity,
                    appURL: url,
                    snapshot: ag,
                    params: IconRenderParams(waveTime: 1.0, bubbleTime: 1.0, hoverAlpha: 1.0, tilt: 0.1, ripple: 0.2, animate: true, showPercentageSign: false)
                )
            }
            print("5a. Metal warmup render: \(String(format: "%.2fms", Date().timeIntervalSince(t3)*1000))")

            let t4 = Date()
            let img = await MainActor.run {
                NativeIconRenderer.shared.renderTileImage(
                    agentID: .antigravity,
                    appURL: url,
                    snapshot: QuotaSnapshot(agentID: .antigravity, remainingPercent: 49, sourceDescription: "diag"),
                    params: IconRenderParams(waveTime: 1.5, bubbleTime: 2.0, hoverAlpha: 1.0, tilt: 0.12, ripple: 0.2, animate: true, showPercentageSign: true)
                )
            }
            print("5b. Metal steady-state preview render: \(String(format: "%.2fms", Date().timeIntervalSince(t4)*1000))")

            var psn = NativeDockPSN(high: 0, low: 0)
            _ = native_dock_get_psn_for_pid(app.processIdentifier, &psn)
            let t5 = Date()
            var krOut: Int32 = -999
            let okHF = await MainActor.run {
                NativeIconRenderer.shared.renderHalfFloatTile(
                    agentID: .antigravity,
                    appURL: url,
                    snapshot: QuotaSnapshot(agentID: .antigravity, remainingPercent: 49, sourceDescription: "diag"),
                    params: IconRenderParams(waveTime: 1.5, bubbleTime: 2.0, hoverAlpha: 1.0, tilt: 0.12, ripple: 0.2, animate: true, showPercentageSign: true)
                ) { ptr, side in
                    krOut = native_dock_draw_half_float_bytes(psn, ptr, side)
                    return krOut == 0
                }
            }
            print("5c. End-to-end 256x256 Half-Float + Mach IPC: \(String(format: "%.2fms", Date().timeIntervalSince(t5)*1000)), ok=\(okHF), kr=\(krOut)")
            _ = native_dock_release_tile(psn)

            let diagDir = NSTemporaryDirectory() + "agentgauge-diag"
            try? FileManager.default.createDirectory(atPath: diagDir, withIntermediateDirectories: true)

            if let img {
                let outURL = URL(fileURLWithPath: "\(diagDir)/diag_tile_v4_256.png")
                let rep = NSBitmapImageRep(cgImage: img)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: outURL)
                    print("6. Saved clean 256x256 tile to:", outURL.path)
                }
            }

            if let imgLow = await MainActor.run(body: {
                NativeIconRenderer.shared.renderTileImage(
                    agentID: .antigravity,
                    appURL: url,
                    snapshot: QuotaSnapshot(agentID: .antigravity, remainingPercent: 18, sourceDescription: "diag-low"),
                    params: IconRenderParams(waveTime: 1.5, bubbleTime: 2.0, hoverAlpha: 1.0, tilt: 0.12, ripple: 0.2, animate: true, showPercentageSign: true)
                )
            }) {
                let rep = NSBitmapImageRep(cgImage: imgLow)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "\(diagDir)/diag_lowwater_18_256.png"))
                }
            }

            if let cursorURL = AgentID.cursor.installedAppURL,
               let imgCursor = await MainActor.run(body: {
                   NativeIconRenderer.shared.renderTileImage(
                       agentID: .cursor,
                       appURL: cursorURL,
                       snapshot: QuotaSnapshot(agentID: .cursor, remainingPercent: 84, sourceDescription: "diag"),
                       params: IconRenderParams(waveTime: 2.1, bubbleTime: 3.4, hoverAlpha: 1.0, tilt: -0.08, ripple: 0.15, animate: true, showPercentageSign: true)
                   )
               }) {
                let rep = NSBitmapImageRep(cgImage: imgCursor)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "\(diagDir)/diag_cursor_v4_256.png"))
                }
            }

            if let wbURL = AgentID.workbuddy.installedAppURL,
               let imgWB = await MainActor.run(body: {
                   NativeIconRenderer.shared.renderTileImage(
                       agentID: .workbuddy,
                       appURL: wbURL,
                       snapshot: QuotaSnapshot(agentID: .workbuddy, remainingPercent: 52.7, creditsRemaining: 3197, creditsTotal: 6068, sourceDescription: "diag"),
                       params: IconRenderParams(waveTime: 0.9, bubbleTime: 1.8, hoverAlpha: 1.0, tilt: 0.06, ripple: 0.12, animate: true, showPercentageSign: true)
                   )
               }) {
                let rep = NSBitmapImageRep(cgImage: imgWB)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "\(diagDir)/diag_wb_v4_256.png"))
                }
            }

            // Render a 4x3 visual verification sheet across ALL 11 final curated styles + badge-off mode!
            await MainActor.run {
                let codexURL = AgentID.codex.installedAppURL ?? url
                let claudeURL = AgentID.claude.installedAppURL ?? url
                let cursorURL = AgentID.cursor.installedAppURL ?? url
                let dsURL = AgentID.deepseek.installedAppURL ?? url

                let cases: [(String, AgentID, URL, Double, Bool, DockBadgeStyle, NumberColorMode, CGFloat)] = [
                    ("1. 截图顶栏时间 (14%低水)", .codex, codexURL, 14, true, .refTopTimerScrim, .smartInvert, 1.50),
                    ("2. 动态反相字", .antigravity, url, 64, true, .pureSplitText, .smartInvert, 1.50),
                    ("3. 微晶描边字", .cursor, cursorURL, 57, true, .haloText, .smartInvert, 1.50),
                    ("4. 同心R角(避让 22%)", .codex, codexURL, 22, true, .concentricAutoDodge, .smartInvert, 1.50),
                    ("5. 光圈扇叶扫描", .codex, codexURL, 37, true, .apertureSweep, .smartInvert, 1.50),
                    ("6. 像素LED点阵", .claude, claudeURL, 42, true, .retroLEDMatrix, .smartInvert, 1.50),
                    ("7. 双轨微仪表", .cursor, cursorURL, 57, true, .dualTrackHUD, .smartInvert, 1.50),
                    ("8. 博朗指针(浅色低水24%)", .antigravity, url, 24, true, .braunAnalogNeedle, .smartInvert, 1.50),
                    ("9. 底部5格(浅色低水24%)", .codex, codexURL, 24, true, .bottomPrismCells, .smartInvert, 1.50),
                    ("10. 顶部灵动微岛", .claude, claudeURL, 37, true, .topDynamicIsland, .smartInvert, 1.50),
                    ("11. 顶部光眉(纯白图标)", .antigravity, url, 56, true, .topEnergyBrow, .smartInvert, 1.50),
                    ("12. DeepSeek 余额(¥11)", .deepseek, dsURL, 43, true, .refTopTimerScrim, .smartInvert, 1.50)
                ]

                let cols = 4
                let rows = 3
                let cellW = 280
                let cellH = 304
                let sheetW = cols * cellW
                let sheetH = rows * cellH
                let cs = CGColorSpaceCreateDeviceRGB()
                let bmi = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
                if let ctx = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8, bytesPerRow: sheetW * 4, space: cs, bitmapInfo: bmi) {
                    ctx.setFillColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0)
                    ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

                    for (idx, item) in cases.enumerated() {
                        let col = idx % cols
                        let row = idx / cols
                        let x = CGFloat(col * cellW)
                        let y = CGFloat((rows - 1 - row) * cellH)

                        let demoWin = [
                            QuotaWindow(label: "5h 限额", remainingPercent: item.3, resetText: "19h 0m", isPrimary: true),
                            QuotaWindow(label: "周限额", remainingPercent: 78, resetText: "5d 4h")
                        ]
                        let snap = QuotaSnapshot(
                            agentID: item.1,
                            remainingPercent: item.3,
                            creditsRemaining: item.1 == .workbuddy ? 3840 : nil,
                            creditsTotal: item.1 == .workbuddy ? 6000 : nil,
                            balanceDisplay: item.1 == .deepseek ? "¥11.28" : nil,
                            dockBalanceShort: item.1 == .deepseek ? "¥11" : nil,
                            resetText: item.1 == .deepseek ? "按量计费" : "19h 0m",
                            windows: demoWin,
                            sourceDescription: "sheet"
                        )

                        if let cg = NativeIconRenderer.shared.renderTileImage(
                            agentID: item.1,
                            appURL: item.2,
                            snapshot: snap,
                            params: IconRenderParams(
                                waveTime: 1.5,
                                bubbleTime: 2.1,
                                hoverAlpha: 1.0,
                                tilt: 0.03,
                                ripple: 0.05,
                                animate: true,
                                showDockBadge: item.4,
                                showPercentageSign: true,
                                numberColorMode: item.6,
                                badgeStyle: item.5,
                                badgeScale: item.7,
                                badgeOpacity: 0.85
                            )
                        ) {
                            ctx.draw(cg, in: CGRect(x: x + 12, y: y + 36, width: 256, height: 256))
                        }

                        NSGraphicsContext.saveGraphicsState()
                        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                        let attr: [NSAttributedString.Key: Any] = [
                            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                            .foregroundColor: NSColor(calibratedWhite: 0.90, alpha: 1.0)
                        ]
                        (item.0 as NSString).draw(at: NSPoint(x: x + 24, y: y + 12), withAttributes: attr)
                        NSGraphicsContext.restoreGraphicsState()
                    }

                    if let outCG = ctx.makeImage() {
                        let rep = NSBitmapImageRep(cgImage: outCG)
                        if let png = rep.representation(using: .png, properties: [:]) {
                            let sheetPath = "\(diagDir)/diag_custom_styles_sheet.png"
                            try? png.write(to: URL(fileURLWithPath: sheetPath))
                            print("6b. Saved custom styles verification sheet to:", sheetPath)
                        }
                    }
                }
            }

            let tip = await MainActor.run { () -> HoverTooltipPanel in
                let t = HoverTooltipPanel()
                t.show(
                    snapshot: ag,
                    anchorRect: NSRect(x: 500, y: 80, width: 64, height: 64),
                    orientation: .bottom,
                    detailMode: .multiModel,
                    showPercentageSign: true,
                    accentColor: AgentID.antigravity.defaultAccentColor
                )
                return t
            }
            try? await Task.sleep(nanoseconds: 260_000_000)

            await MainActor.run {
                print("7. Antigravity Tooltip frame:", tip.currentFrame)
                tip.saveDiagnosticPNG(to: "\(diagDir)/diag_tooltip_ag.png")
                tip.hide(immediate: true)
            }
        }
    }
}
