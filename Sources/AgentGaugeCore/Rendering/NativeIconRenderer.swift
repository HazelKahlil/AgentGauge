import AppKit
import CoreGraphics
import CoreText
import Foundation
import Metal
import simd

public struct IconRenderParams: Sendable {
    public let waveTime: CGFloat
    public let bubbleTime: CGFloat
    public let hoverAlpha: CGFloat   // 0 = calm idle, 1 = hovered awake
    public let tilt: CGFloat
    public let ripple: CGFloat
    public let animate: Bool
    public let showDockBadge: Bool
    public let showPercentageSign: Bool
    public let waterTintHex: String?
    public let numberColorMode: NumberColorMode
    public let badgeStyle: DockBadgeStyle
    public let badgeScale: CGFloat
    public let badgeOpacity: CGFloat

    public init(
        waveTime: CGFloat,
        bubbleTime: CGFloat,
        hoverAlpha: CGFloat,
        tilt: CGFloat,
        ripple: CGFloat,
        animate: Bool,
        showDockBadge: Bool = true,
        showPercentageSign: Bool,
        waterTintHex: String? = nil,
        numberColorMode: NumberColorMode = .smartInvert,
        badgeStyle: DockBadgeStyle = .refTopTimerScrim,
        badgeScale: CGFloat = 1.50,
        badgeOpacity: CGFloat = 0.85
    ) {
        self.waveTime = waveTime
        self.bubbleTime = bubbleTime
        self.hoverAlpha = max(0, min(1, hoverAlpha))
        self.tilt = max(-0.55, min(0.55, tilt))
        self.ripple = max(0, min(0.6, ripple))
        self.animate = animate
        self.showDockBadge = showDockBadge
        self.showPercentageSign = showPercentageSign
        self.waterTintHex = waterTintHex
        self.numberColorMode = numberColorMode
        self.badgeStyle = badgeStyle
        self.badgeScale = max(0.60, min(1.85, badgeScale))
        self.badgeOpacity = max(0.35, min(0.99, badgeOpacity))
    }
}

private struct ShaderUniforms {
    var level: Float
    var waveT: Float
    var bubbleT: Float
    var wake: Float
    var tilt: Float
    var ripple: Float
    var isDark: Float
    var working: Float
    var phase: Float
    var bodyMinX: Float
    var bodyMinY: Float
    var bodySpanX: Float
    var bodySpanY: Float
    var hasLabel: Float
    var colorMode: Float
    var styleKind: Float
    var waterMode: Float
    var badgeOpacity: Float
    var tintR: Float
    var tintG: Float
    var tintB: Float
}

@MainActor
public final class NativeIconRenderer {
    public static let shared = NativeIconRenderer()

    private struct CachedIcon {
        let cgImage: CGImage
        let metalTexture: MTLTexture?
        let bodyRect: CGRect
        let isDark: Bool
        let extractedTint: SIMD3<Float>
    }

    private var iconCache: [String: CachedIcon] = [:]
    private var labelTexCache: [String: MTLTexture] = [:]
    /// Native 256×256 Retina tile resolution (offscreen export renderers may use a larger side).
    public let dockTileSide: Int

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let halfFloatPipeline: MTLRenderPipelineState?
    private let previewPipeline: MTLRenderPipelineState?
    private let outTexture16: MTLTexture?
    private let outTexture8: MTLTexture?
    private let previewSlotTextures: [MTLTexture]
    private var halfFloatReadback: [UInt8]
    private var previewReadback: [UInt8]

    /// Independent high-resolution renderer for offline export (e.g. promo frames). Never used by the live Dock path.
    public static func makeOffscreenRenderer(side: Int) -> NativeIconRenderer {
        NativeIconRenderer(side: max(64, min(1024, side)))
    }

    private init(side: Int = 256) {
        self.dockTileSide = side
        self.halfFloatReadback = [UInt8](repeating: 0, count: side * side * 8)
        self.previewReadback = [UInt8](repeating: 0, count: side * side * 4)

        guard let dev = MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue() else {
            self.device = nil
            self.commandQueue = nil
            self.halfFloatPipeline = nil
            self.previewPipeline = nil
            self.outTexture16 = nil
            self.outTexture8 = nil
            self.previewSlotTextures = []
            return
        }

        self.device = dev
        self.commandQueue = queue

        let td16 = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: side,
            height: side,
            mipmapped: false
        )
        td16.usage = [.renderTarget, .shaderRead]
        td16.storageMode = .shared
        self.outTexture16 = dev.makeTexture(descriptor: td16)

        let td8 = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: side,
            height: side,
            mipmapped: false
        )
        td8.usage = [.renderTarget, .shaderRead]
        td8.storageMode = .shared
        self.outTexture8 = dev.makeTexture(descriptor: td8)
        self.previewSlotTextures = (0..<4).compactMap { _ in dev.makeTexture(descriptor: td8) }

        do {
            let lib = try dev.makeLibrary(source: Self.metalShaderSource, options: nil)
            let vs = lib.makeFunction(name: "vs_quad")
            let fs = lib.makeFunction(name: "fs_liquid_glass")

            let d16 = MTLRenderPipelineDescriptor()
            d16.vertexFunction = vs
            d16.fragmentFunction = fs
            d16.colorAttachments[0].pixelFormat = .rgba16Float
            let p16 = try dev.makeRenderPipelineState(descriptor: d16)

            let d8 = MTLRenderPipelineDescriptor()
            d8.vertexFunction = vs
            d8.fragmentFunction = fs
            d8.colorAttachments[0].pixelFormat = .rgba8Unorm
            let p8 = try dev.makeRenderPipelineState(descriptor: d8)

            self.halfFloatPipeline = p16
            self.previewPipeline = p8
            AppLogger.shared.log("Metal", "256x256 Retina 多模态余量着色器初始化成功 (\(dev.name))")
        } catch {
            self.halfFloatPipeline = nil
            self.previewPipeline = nil
            AppLogger.shared.log("Metal", "着色器编译失败: \(error.localizedDescription)")
        }
    }

    public func renderHalfFloatTile(
        agentID: AgentID,
        appURL: URL,
        snapshot: QuotaSnapshot,
        params: IconRenderParams,
        submit: (UnsafeRawPointer, UInt32) -> Bool
    ) -> Bool {
        guard let remaining = snapshot.remainingPercent,
              let cached = loadBaseIcon(for: appURL),
              let queue = commandQueue,
              let pipeline = halfFloatPipeline,
              let outTex = outTexture16,
              let srcTex = cached.metalTexture,
              let cmdBuf = queue.makeCommandBuffer() else {
            return false
        }

        let waterColor = resolvedWaterColor(agentID: agentID, hexOverride: params.waterTintHex)
        let lblTex = resolveOverlayTexture(
            for: cached,
            snapshot: snapshot,
            remaining: remaining,
            waterColor: waterColor,
            params: params
        )

        encodePass(
            cmdBuf: cmdBuf,
            pipeline: pipeline,
            targetTex: outTex,
            srcTex: srcTex,
            labelTex: lblTex,
            agentID: agentID,
            cached: cached,
            waterColor: waterColor,
            remaining: remaining,
            isWorking: snapshot.isWorking,
            params: params
        )

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        let side = dockTileSide
        return halfFloatReadback.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return false }
            outTex.getBytes(
                base,
                bytesPerRow: side * 8,
                from: MTLRegionMake2D(0, 0, side, side),
                mipmapLevel: 0
            )
            return submit(base, UInt32(side))
        }
    }

    public func renderTileImage(
        agentID: AgentID,
        appURL: URL,
        snapshot: QuotaSnapshot,
        params: IconRenderParams
    ) -> CGImage? {
        guard let remaining = snapshot.remainingPercent,
              let cached = loadBaseIcon(for: appURL) else { return nil }

        guard let queue = commandQueue,
              let pipeline = previewPipeline,
              let outTex = outTexture8,
              let srcTex = cached.metalTexture,
              let cmdBuf = queue.makeCommandBuffer() else {
            return cached.cgImage
        }

        let waterColor = resolvedWaterColor(agentID: agentID, hexOverride: params.waterTintHex)
        let lblTex = resolveOverlayTexture(
            for: cached,
            snapshot: snapshot,
            remaining: remaining,
            waterColor: waterColor,
            params: params
        )

        encodePass(
            cmdBuf: cmdBuf,
            pipeline: pipeline,
            targetTex: outTex,
            srcTex: srcTex,
            labelTex: lblTex,
            agentID: agentID,
            cached: cached,
            waterColor: waterColor,
            remaining: remaining,
            isWorking: snapshot.isWorking,
            params: params
        )

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        let side = dockTileSide
        previewReadback.withUnsafeMutableBytes { ptr in
            if let base = ptr.baseAddress {
                outTex.getBytes(
                    base,
                    bytesPerRow: side * 4,
                    from: MTLRegionMake2D(0, 0, side, side),
                    mipmapLevel: 0
                )
            }
        }

        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &previewReadback,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return cached.cgImage
        }
        return ctx.makeImage() ?? cached.cgImage
    }

    public struct PreviewBatchItem {
        public let agentID: AgentID
        public let appURL: URL
        public let snapshot: QuotaSnapshot
        public let params: IconRenderParams

        public init(agentID: AgentID, appURL: URL, snapshot: QuotaSnapshot, params: IconRenderParams) {
            self.agentID = agentID
            self.appURL = appURL
            self.snapshot = snapshot
            self.params = params
        }
    }

    /// Non-blocking single-command-buffer batch renderer for interactive UI sliders.
    public func renderPreviewBatchAsync(_ items: [PreviewBatchItem]) async -> [AgentID: CGImage] {
        guard let queue = commandQueue,
              let pipeline = previewPipeline,
              previewSlotTextures.count >= items.count,
              let cmdBuf = queue.makeCommandBuffer() else {
            var fallback: [AgentID: CGImage] = [:]
            for item in items {
                if let cg = renderTileImage(agentID: item.agentID, appURL: item.appURL, snapshot: item.snapshot, params: item.params) {
                    fallback[item.agentID] = cg
                }
            }
            return fallback
        }

        var encodedSlots: [(AgentID, MTLTexture, CGImage)] = []
        for (idx, item) in items.prefix(previewSlotTextures.count).enumerated() {
            guard let remaining = item.snapshot.remainingPercent,
                  let cached = loadBaseIcon(for: item.appURL),
                  let srcTex = cached.metalTexture else { continue }

            let slotTex = previewSlotTextures[idx]
            let waterColor = resolvedWaterColor(agentID: item.agentID, hexOverride: item.params.waterTintHex)
            let lblTex = resolveOverlayTexture(
                for: cached,
                snapshot: item.snapshot,
                remaining: remaining,
                waterColor: waterColor,
                params: item.params
            )

            encodePass(
                cmdBuf: cmdBuf,
                pipeline: pipeline,
                targetTex: slotTex,
                srcTex: srcTex,
                labelTex: lblTex,
                agentID: item.agentID,
                cached: cached,
                waterColor: waterColor,
                remaining: remaining,
                isWorking: item.snapshot.isWorking,
                params: item.params
            )
            encodedSlots.append((item.agentID, slotTex, cached.cgImage))
        }

        guard !encodedSlots.isEmpty else { return [:] }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            cmdBuf.addCompletedHandler { _ in
                cont.resume()
            }
            cmdBuf.commit()
        }

        let side = dockTileSide
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var results: [AgentID: CGImage] = [:]

        for (agentID, slotTex, fallbackCG) in encodedSlots {
            previewReadback.withUnsafeMutableBytes { ptr in
                if let base = ptr.baseAddress {
                    slotTex.getBytes(
                        base,
                        bytesPerRow: side * 4,
                        from: MTLRegionMake2D(0, 0, side, side),
                        mipmapLevel: 0
                    )
                }
            }
            if let ctx = CGContext(
                data: &previewReadback,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ), let cg = ctx.makeImage() {
                results[agentID] = cg
            } else {
                results[agentID] = fallbackCG
            }
        }
        return results
    }

    private func resolvedWaterColor(agentID: AgentID, hexOverride: String?) -> NSColor {
        if let hex = hexOverride, let custom = NSColor.fromHex(hex) {
            return custom
        }
        return agentID.defaultAccentColor
    }

    private func srgbVector(from color: NSColor) -> SIMD3<Float> {
        let c = color.usingColorSpace(.sRGB) ?? color
        return SIMD3<Float>(
            Float(max(0, min(1, c.redComponent))),
            Float(max(0, min(1, c.greenComponent))),
            Float(max(0, min(1, c.blueComponent)))
        )
    }

    private func resolveOverlayTexture(
        for cached: CachedIcon,
        snapshot: QuotaSnapshot,
        remaining: Double,
        waterColor: NSColor,
        params: IconRenderParams
    ) -> MTLTexture? {
        guard params.showDockBadge, params.hoverAlpha > 0.01 else {
            return nil
        }
        let labelStr = snapshot.formattedDockIconValue(showPercentageSign: params.showPercentageSign)
        guard !labelStr.isEmpty else { return nil }

        switch params.badgeStyle {
        case .haloText, .pureSplitText:
            return pureTextMaskTexture(
                for: cached,
                labelText: labelStr,
                badgeStyle: params.badgeStyle,
                badgeScale: params.badgeScale
            )
        default:
            return craftedRGBAOverlayTexture(
                for: cached,
                snapshot: snapshot,
                labelText: labelStr,
                remaining: remaining,
                waterColor: waterColor,
                params: params
            )
        }
    }

    private func encodePass(
        cmdBuf: MTLCommandBuffer,
        pipeline: MTLRenderPipelineState,
        targetTex: MTLTexture,
        srcTex: MTLTexture,
        labelTex: MTLTexture?,
        agentID: AgentID,
        cached: CachedIcon,
        waterColor: NSColor,
        remaining: Double,
        isWorking: Bool,
        params: IconRenderParams
    ) {
        let rpDesc = MTLRenderPassDescriptor()
        rpDesc.colorAttachments[0].texture = targetTex
        rpDesc.colorAttachments[0].loadAction = .clear
        rpDesc.colorAttachments[0].storeAction = .store
        rpDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpDesc) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(srcTex, index: 0)
        enc.setFragmentTexture(labelTex ?? srcTex, index: 1)

        let modeCode: Float
        switch params.numberColorMode {
        case .smartInvert:   modeCode = 0.0
        case .adaptiveInk:   modeCode = 1.0
        case .white:         modeCode = 2.0
        case .smokeGray:     modeCode = 3.0
        case .obsidianBlack: modeCode = 4.0
        }

        let styleKind: Float
        switch params.badgeStyle {
        case .haloText:      styleKind = 1.0
        case .pureSplitText: styleKind = 2.0
        default:             styleKind = 3.0
        }

        // Signature optical refractive liquid water wave underneath ALL 11 styles
        let waterMode: Float = 1.0

        // Alert-aware water tint on critical/low quota
        let effectiveWaterNS: NSColor = if remaining <= 15 {
            NSColor(srgbRed: 0.90, green: 0.25, blue: 0.22, alpha: 1.0)
        } else if remaining <= 30 {
            NSColor(srgbRed: 0.90, green: 0.54, blue: 0.12, alpha: 1.0)
        } else {
            waterColor
        }

        let tintVec = srgbVector(from: effectiveWaterNS)
        let fSide = Float(dockTileSide)
        let phase = Float(abs(agentID.rawValue.hashValue % 100)) * 0.06
        var uniforms = ShaderUniforms(
            level: Float(max(0, min(1, remaining / 100.0))),
            waveT: Float(params.animate ? params.waveTime : 0),
            bubbleT: Float(params.animate ? params.bubbleTime : 0),
            wake: Float(params.hoverAlpha),
            tilt: Float(params.tilt),
            ripple: Float(params.ripple),
            isDark: cached.isDark ? 1.0 : 0.0,
            working: isWorking ? 1.0 : 0.0,
            phase: phase,
            bodyMinX: Float(cached.bodyRect.minX) / fSide,
            bodyMinY: Float(cached.bodyRect.minY) / fSide,
            bodySpanX: Float(cached.bodyRect.width) / fSide,
            bodySpanY: Float(cached.bodyRect.height) / fSide,
            hasLabel: labelTex != nil ? 1.0 : 0.0,
            colorMode: modeCode,
            styleKind: styleKind,
            waterMode: waterMode,
            badgeOpacity: Float(params.badgeOpacity),
            tintR: tintVec.x,
            tintG: tintVec.y,
            tintB: tintVec.z
        )
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
    }

    // MARK: - Typography Helpers

    private func futuraBoldFont(size: CGFloat) -> NSFont {
        if let f = NSFont(name: "Futura-Bold", size: size) {
            return f
        }
        if let f = NSFont(name: "Futura", size: size) {
            return NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask)
        }
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: .heavy)
    }

    private func sfRoundedFont(size: CGFloat, weight: NSFont.Weight = .heavy) -> NSFont {
        let sys = NSFont.systemFont(ofSize: size, weight: weight)
        if let desc = sys.fontDescriptor.withDesign(.rounded),
           let rounded = NSFont(descriptor: desc, size: size) {
            return rounded
        }
        return sys
    }

    private func sfMonoFont(size: CGFloat, weight: NSFont.Weight = .bold) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    // MARK: - Preserved Pure-Text Multi-Channel Mask (`pureSplitText` & `haloText`)

    private func pureTextMaskTexture(
        for cached: CachedIcon,
        labelText: String,
        badgeStyle: DockBadgeStyle,
        badgeScale: CGFloat
    ) -> MTLTexture? {
        guard let dev = device, !labelText.isEmpty else { return nil }
        let bRect = cached.bodyRect
        let sMin = min(bRect.width, bRect.height)
        let sc = max(0.60, min(1.85, badgeScale))
        let scalePct = Int(round(sc * 100.0))

        let key = "pt-v6-\(badgeStyle.rawValue)-\(scalePct)-\(labelText)-\(Int(bRect.minX))-\(Int(bRect.minY))-\(Int(bRect.width))-\(Int(bRect.height))"
        if let hit = labelTexCache[key] {
            return hit
        }
        trimLabelCacheIfNeeded()

        let side = dockTileSide
        let fSide = CGFloat(side)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: fSide, height: fSide))
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.setAllowsFontSmoothing(true)
        ctx.setShouldSmoothFonts(false)

        let hasPercent = labelText.hasSuffix("%")
        let mainStr = hasPercent ? String(labelText.dropLast()) : labelText
        let unitStr = hasPercent ? "%" : ""
        let isCreditOrLong = !hasPercent && labelText.count >= 4

        var mainFs = max(14.0, round(sMin * 0.158 * sc * (isCreditOrLong ? 0.85 : 1.0)))
        var unitFs = max(9.0, round(mainFs * 0.54))
        var mainFont = futuraBoldFont(size: mainFs)
        var unitFont = futuraBoldFont(size: unitFs)

        func makeColoredCTLine(_ str: String, font: NSFont, r: CGFloat, g: CGFloat, b: CGFloat) -> CTLine {
            let color = NSColor(deviceRed: r, green: g, blue: b, alpha: 1)
            return CTLineCreateWithAttributedString(
                NSAttributedString(string: str, attributes: [.font: font, .foregroundColor: color])
            )
        }

        var mainLine = makeColoredCTLine(mainStr, font: mainFont, r: 0, g: 1, b: 0)
        var mainAdv = CGFloat(CTLineGetTypographicBounds(mainLine, nil, nil, nil))
        var unitLine: CTLine?
        var unitAdv: CGFloat = 0
        let unitGap = unitStr.isEmpty ? 0 : round(sMin * 0.010)
        if !unitStr.isEmpty {
            let uLine = makeColoredCTLine(unitStr, font: unitFont, r: 0, g: 1, b: 0)
            unitLine = uLine
            unitAdv = CGFloat(CTLineGetTypographicBounds(uLine, nil, nil, nil))
        }
        var totalTextW = mainAdv + unitGap + unitAdv

        let maxTextW = sMin * 0.78
        if totalTextW > maxTextW && totalTextW > 1 {
            let ratio = maxTextW / totalTextW
            mainFs = max(13.0, round(mainFs * ratio))
            unitFs = max(8.5, round(mainFs * 0.54))
            mainFont = futuraBoldFont(size: mainFs)
            unitFont = futuraBoldFont(size: unitFs)
            mainLine = makeColoredCTLine(mainStr, font: mainFont, r: 0, g: 1, b: 0)
            mainAdv = CGFloat(CTLineGetTypographicBounds(mainLine, nil, nil, nil))
            if !unitStr.isEmpty {
                let uLine = makeColoredCTLine(unitStr, font: unitFont, r: 0, g: 1, b: 0)
                unitLine = uLine
                unitAdv = CGFloat(CTLineGetTypographicBounds(uLine, nil, nil, nil))
            }
            totalTextW = mainAdv + unitGap + unitAdv
        }

        ctx.setBlendMode(.plusLighter)
        let textStartX = round(bRect.minX + sMin * 0.085)
        let textBaseY = round(bRect.minY + sMin * 0.115)

        if badgeStyle == .haloText {
            let blueMain = makeColoredCTLine(mainStr, font: mainFont, r: 0, g: 0, b: 1)
            let blueUnit = unitStr.isEmpty ? nil : makeColoredCTLine(unitStr, font: unitFont, r: 0, g: 0, b: 1)
            ctx.saveGState()
            ctx.setLineWidth(max(3.5, fSide * 0.024))
            ctx.setLineJoin(.round)
            ctx.setTextDrawingMode(.stroke)
            ctx.textMatrix = .identity
            ctx.textPosition = CGPoint(x: textStartX, y: textBaseY)
            CTLineDraw(blueMain, ctx)
            if let bu = blueUnit {
                ctx.textPosition = CGPoint(x: textStartX + mainAdv + unitGap, y: textBaseY)
                CTLineDraw(bu, ctx)
            }
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.setTextDrawingMode(.fill)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: textStartX, y: textBaseY)
        CTLineDraw(mainLine, ctx)
        if let uLine = unitLine {
            ctx.textPosition = CGPoint(x: textStartX + mainAdv + unitGap, y: textBaseY)
            CTLineDraw(uLine, ctx)
        }
        ctx.restoreGState()

        return uploadTexture(from: ctx, dev: dev, cacheKey: key)
    }

    // MARK: - High-Craft Premultiplied RGBA Overlay Renderer (All 9 Curated Playground Styles)

    private func craftedRGBAOverlayTexture(
        for cached: CachedIcon,
        snapshot: QuotaSnapshot,
        labelText: String,
        remaining: Double,
        waterColor: NSColor,
        params: IconRenderParams
    ) -> MTLTexture? {
        guard let dev = device else { return nil }

        let bRect = cached.bodyRect
        let side = dockTileSide
        let fSide = CGFloat(side)

        // Normalize around default slider settings (1.50 scale, 0.85 opacity) so 150% matches 1:1 calibrated proportions!
        let relScale = max(0.68, min(1.24, params.badgeScale / 1.50))
        let relOpacity = max(0.48, min(1.16, params.badgeOpacity / 0.85))

        let rawCountdown = snapshot.formattedCountdown()
        let countdownStr: String? = (rawCountdown == "—" || rawCountdown == "未启动" || rawCountdown == "运行中" || rawCountdown.isEmpty)
            ? nil
            : rawCountdown

        let secondaryPct: Double = {
            if let wk = snapshot.windows.first(where: { $0.label.contains("周") || $0.label.lowercased().contains("week") }) {
                return wk.remainingPercent
            }
            if snapshot.windows.count >= 2 {
                return snapshot.windows[1].remainingPercent
            }
            return remaining
        }()

        let remKey = Int(round(remaining))
        let secKey = Int(round(secondaryPct))
        let scKey = Int(round(relScale * 100))
        let opKey = Int(round(relOpacity * 100))
        let hexKey = waterColor.srgbHexString
        let cdKey = countdownStr ?? "-"
        let darkKey = cached.isDark ? "D" : "L"
        let key = "rgba-v8-\(darkKey)-\(params.badgeStyle.rawValue)-\(params.numberColorMode.rawValue)-\(remKey)-\(secKey)-\(scKey)-\(opKey)-\(hexKey)-\(labelText)-\(cdKey)-\(side)-\(Int(bRect.minX))-\(Int(bRect.minY))"

        if let hit = labelTexCache[key] {
            return hit
        }
        trimLabelCacheIfNeeded()

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        ctx.clear(CGRect(x: 0, y: 0, width: fSide, height: fSide))
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        // Top-left origin (+x right, +y down) matching Playground Canvas 2D coordinates 1:1
        ctx.translateBy(x: 0, y: fSide)
        ctx.scaleBy(x: 1, y: -1)

        let bx = bRect.minX
        let by = fSide - bRect.maxY
        let bw = bRect.width
        let bh = bRect.height
        let S = min(bw, bh)
        let cx = bx + bw * 0.5
        let cy = by + bh * 0.5

        // Calibrated accent & smoked glass backing colors
        let baseSRGB = waterColor.usingColorSpace(.sRGB) ?? waterColor
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        baseSRGB.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let vividTheme = NSColor(hue: h, saturation: min(0.82, max(0.54, s * 1.25)), brightness: max(0.88, b), alpha: 1.0)
            .usingColorSpace(.sRGB) ?? baseSRGB

        let accentRGB: (CGFloat, CGFloat, CGFloat) = if remaining <= 15 {
            (1.0, 0.27, 0.23)   // Alert Coral #FF453A
        } else if remaining <= 30 {
            (1.0, 0.62, 0.04)   // Alert Amber #FF9F0A
        } else {
            (vividTheme.redComponent, vividTheme.greenComponent, vividTheme.blueComponent)
        }

        let bandRGB: (CGFloat, CGFloat, CGFloat) = switch params.numberColorMode {
        case .smokeGray:
            (0.23, 0.25, 0.30)
        case .obsidianBlack:
            (0.05, 0.06, 0.09)
        case .smartInvert, .adaptiveInk, .white:
            if remaining <= 15 {
                (0.55, 0.13, 0.11)
            } else if remaining <= 30 {
                (0.54, 0.31, 0.06)
            } else {
                (
                    baseSRGB.redComponent * 0.44 + 0.05,
                    baseSRGB.greenComponent * 0.44 + 0.07,
                    baseSRGB.blueComponent * 0.44 + 0.10
                )
            }
        }

        func cgColor(_ rgb: (CGFloat, CGFloat, CGFloat), _ alpha: CGFloat) -> CGColor {
            CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: max(0, min(1, alpha)))
        }

        func addPill(_ rect: CGRect, radius: CGFloat) {
            let r = max(0, min(radius, rect.width * 0.5, rect.height * 0.5))
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        }

        func addClockwiseArc(center: CGPoint, radius: CGFloat, from a0: CGFloat, to a1: CGFloat, includeCenter: Bool = false) {
            let steps = max(16, Int(ceil(abs(a1 - a0) * 28.0)))
            if includeCenter {
                ctx.move(to: center)
                ctx.addLine(to: CGPoint(x: center.x + cos(a0) * radius, y: center.y + sin(a0) * radius))
            } else {
                ctx.move(to: CGPoint(x: center.x + cos(a0) * radius, y: center.y + sin(a0) * radius))
            }
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let ang = a0 + (a1 - a0) * t
                ctx.addLine(to: CGPoint(x: center.x + cos(ang) * radius, y: center.y + sin(ang) * radius))
            }
            if includeCenter {
                ctx.closePath()
            }
        }

        func drawSmokedGlassPill(_ rect: CGRect, radius: CGFloat, tint: (CGFloat, CGFloat, CGFloat), alpha: CGFloat) {
            let effA = max(0.35, min(0.95, alpha * relOpacity))
            let path = CGPath(
                roundedRect: rect,
                cornerWidth: min(radius, rect.width * 0.5, rect.height * 0.5),
                cornerHeight: min(radius, rect.width * 0.5, rect.height * 0.5),
                transform: nil
            )

            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -rect.height * 0.07),
                blur: rect.height * 0.22,
                color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.26)
            )
            ctx.addPath(path)
            ctx.setFillColor(cgColor(tint, effA))
            ctx.fillPath()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let topC = cgColor((min(1, tint.0 * 0.85 + 0.06), min(1, tint.1 * 0.85 + 0.07), min(1, tint.2 * 0.85 + 0.10)), effA)
            let botC = cgColor((0.05, 0.06, 0.09), min(0.94, effA + 0.10))
            if let grad = CGGradient(colorsSpace: colorSpace, colors: [topC, botC] as CFArray, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: rect.midX, y: rect.minY),
                    end: CGPoint(x: rect.midX, y: rect.maxY),
                    options: []
                )
            }
            ctx.restoreGState()

            ctx.saveGState()
            ctx.addPath(path)
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.24))
            ctx.setLineWidth(max(1.0, S * 0.008))
            ctx.strokePath()
            ctx.restoreGState()
        }

        enum TextAlignMode { case left, center, right }

        func drawCrispText(
            _ text: String,
            font: NSFont,
            color: NSColor = .white,
            x: CGFloat,
            midY: CGFloat,
            align: TextAlignMode,
            maxWidth: CGFloat? = nil,
            shadowAlpha: CGFloat = 0.28,
            shadowBlur: CGFloat = 0.022
        ) {
            var useFont = font
            var attr = NSAttributedString(string: text, attributes: [.font: useFont, .foregroundColor: color])
            var sz = attr.size()
            if let mw = maxWidth, sz.width > mw, sz.width > 1 {
                let scaled = max(9.0, floor(useFont.pointSize * (mw / sz.width)))
                useFont = useFont.fontName.lowercased().contains("mono")
                    ? sfMonoFont(size: scaled, weight: .bold)
                    : sfRoundedFont(size: scaled, weight: .heavy)
                attr = NSAttributedString(string: text, attributes: [.font: useFont, .foregroundColor: color])
                sz = attr.size()
            }

            let drawX: CGFloat = switch align {
            case .left:   x
            case .center: x - sz.width * 0.5
            case .right:  x - sz.width
            }
            let drawY = midY - sz.height * 0.5

            ctx.saveGState()
            if shadowAlpha > 0.01 {
                ctx.setShadow(
                    offset: CGSize(width: 0, height: -S * 0.007),
                    blur: S * shadowBlur,
                    color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: shadowAlpha)
                )
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            attr.draw(at: NSPoint(x: drawX, y: drawY))
            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()
        }

        // Exact screenshot-caliber bottom-left subtle shadow patch + crisp white percentage
        func drawRefCornerPercent(scale: CGFloat = 0.258, baseScrimAlpha: CGFloat = 0.26) {
            let isLong = !labelText.hasSuffix("%") && labelText.count >= 4
            let fs = round(S * scale * relScale * (isLong ? 0.86 : 1.0))
            var font = sfRoundedFont(size: max(12, fs), weight: .heavy)
            var attr = NSAttributedString(string: labelText, attributes: [.font: font, .foregroundColor: NSColor.white])
            var sz = attr.size()
            let maxW = S * 0.72
            if sz.width > maxW && sz.width > 1 {
                font = sfRoundedFont(size: max(11, floor(fs * (maxW / sz.width))), weight: .heavy)
                attr = NSAttributedString(string: labelText, attributes: [.font: font, .foregroundColor: NSColor.white])
                sz = attr.size()
            }

            let padL = S * 0.078
            let padR = S * 0.048
            let tabR = S * 0.064
            let capH = font.capHeight
            let textBottomInset = S * 0.056
            let tabRightX = bx + padL + sz.width + padR
            let tabTopY = (by + bh) - (textBottomInset + capH + S * 0.052)

            // Boost corner scrim automatically on light/white icons when low water drops below the top of the digits!
            let lowWaterLightBoost: CGFloat = (!cached.isDark && remaining < 34.0) ? 0.18 : ((!cached.isDark) ? 0.06 : 0.0)
            let effectiveBaseScrim = baseScrimAlpha + lowWaterLightBoost
            let scrimA: CGFloat = switch params.numberColorMode {
            case .obsidianBlack: min(0.72, (effectiveBaseScrim + 0.16) * relOpacity)
            case .smokeGray:     min(0.62, (effectiveBaseScrim + 0.06) * relOpacity)
            default:             min(0.62, effectiveBaseScrim * relOpacity)
            }

            // Extend left & bottom past bodyRect so Metal's orig.a clips flush to the native squircle corner!
            ctx.saveGState()
            ctx.beginPath()
            ctx.move(to: CGPoint(x: -4, y: fSide + 4))
            ctx.addLine(to: CGPoint(x: -4, y: tabTopY))
            ctx.addLine(to: CGPoint(x: tabRightX - tabR, y: tabTopY))
            ctx.addQuadCurve(to: CGPoint(x: tabRightX, y: tabTopY + tabR), control: CGPoint(x: tabRightX, y: tabTopY))
            ctx.addLine(to: CGPoint(x: tabRightX, y: fSide + 4))
            ctx.closePath()
            ctx.setFillColor(CGColor(srgbRed: 0.03, green: 0.05, blue: 0.09, alpha: scrimA))
            ctx.fillPath()
            ctx.restoreGState()

            let visualMidY = (by + bh) - textBottomInset - capH * 0.52
            drawCrispText(
                labelText,
                font: font,
                x: bx + padL,
                midY: visualMidY,
                align: .left,
                shadowAlpha: 0.34,
                shadowBlur: 0.026
            )
        }

        switch params.badgeStyle {
        case .refTopTimerScrim:
            // #01 Reference Screenshot 1:1 Replica (Top translucent countdown band + bottom-left subtle dark shadow white %)
            if let cd = countdownStr {
                let bandH = S * 0.235 * max(0.85, min(1.12, relScale))
                let bandBotY = by + bandH
                ctx.saveGState()
                let c0 = cgColor(bandRGB, min(0.90, 0.72 * relOpacity))
                let c1 = cgColor(bandRGB, min(0.92, 0.80 * relOpacity))
                if let g = CGGradient(colorsSpace: colorSpace, colors: [c0, c1] as CFArray, locations: [0, 1]) {
                    ctx.saveGState()
                    ctx.clip(to: CGRect(x: 0, y: 0, width: fSide, height: bandBotY))
                    ctx.drawLinearGradient(g, start: CGPoint(x: cx, y: by), end: CGPoint(x: cx, y: bandBotY), options: [])
                    ctx.restoreGState()
                }
                let sepH = max(1.2, S * 0.008)
                ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.38))
                ctx.fill(CGRect(x: 0, y: bandBotY - sepH, width: fSide, height: sepH))
                ctx.restoreGState()

                let cdFont = sfRoundedFont(size: round(S * 0.138 * max(0.85, min(1.12, relScale))), weight: .bold)
                drawCrispText(cd, font: cdFont, x: cx, midY: by + bandH * 0.52, align: .center, maxWidth: bw * 0.84, shadowAlpha: 0.28)
            }
            drawRefCornerPercent(scale: 0.262, baseScrimAlpha: 0.26)

        case .concentricAutoDodge:
            // #19 Concentric R-Corner Smoked Glass Pill (Auto-dodges to top-left when remaining <= 30%!)
            let m = S * 0.068
            let ph = min(bh * 0.42, S * 0.228 * relScale)
            let fs = round(S * 0.148 * relScale)
            let font = sfRoundedFont(size: max(11, fs), weight: .heavy)
            let textW = NSAttributedString(string: labelText, attributes: [.font: font]).size().width
            let pw = min(bw - m * 2, max(S * 0.48 * relScale, textW + S * 0.15))
            let dodgeCutoff = Double(min(42.0, max(28.0, (ph / bh) * 100.0 + 7.0)))
            let py = (remaining <= dodgeCutoff) ? (by + m) : (by + bh - ph - m)
            let pillRect = CGRect(x: bx + m, y: py, width: pw, height: ph)

            drawSmokedGlassPill(pillRect, radius: S * 0.115, tint: bandRGB, alpha: 0.80)
            drawCrispText(labelText, font: font, x: pillRect.midX, midY: pillRect.midY, align: .center, maxWidth: pw * 0.84)

        case .apertureSweep:
            // #07 Camera Optical Aperture Sweep + Subtle Corner Scrim (Lightened sector so signature optical water shines underneath!)
            let consumed = max(0.0, min(1.0, 1.0 - remaining / 100.0))
            let startA = -CGFloat.pi * 0.5
            let splitA = startA + CGFloat.pi * 2.0 * CGFloat(consumed)

            if consumed > 0.005 {
                ctx.saveGState()
                ctx.beginPath()
                addClockwiseArc(center: CGPoint(x: cx, y: cy), radius: S * 0.85, from: startA, to: splitA, includeCenter: true)
                ctx.clip()
                let r0 = CGColor(srgbRed: 0.04, green: 0.06, blue: 0.09, alpha: min(0.42, 0.18 * relOpacity))
                let r1 = CGColor(srgbRed: 0.03, green: 0.04, blue: 0.07, alpha: min(0.54, 0.34 * relOpacity))
                if let rg = CGGradient(colorsSpace: colorSpace, colors: [r0, r1] as CFArray, locations: [0, 1]) {
                    ctx.drawRadialGradient(
                        rg,
                        startCenter: CGPoint(x: cx, y: cy),
                        startRadius: S * 0.04,
                        endCenter: CGPoint(x: cx, y: cy),
                        endRadius: S * 0.68,
                        options: [.drawsAfterEndLocation]
                    )
                }
                ctx.restoreGState()
            }

            // 12 precision inner horology ticks (no outer ring!)
            ctx.saveGState()
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.38))
            ctx.setLineWidth(max(1.2, S * 0.011))
            for i in 0..<12 {
                let ang = (CGFloat(i) / 12.0) * CGFloat.pi * 2.0 - CGFloat.pi * 0.5
                let r1 = S * 0.36
                let r2 = S * ((i % 3 == 0) ? 0.405 : 0.385)
                ctx.move(to: CGPoint(x: cx + cos(ang) * r1, y: cy + sin(ang) * r1))
                ctx.addLine(to: CGPoint(x: cx + cos(ang) * r2, y: cy + sin(ang) * r2))
            }
            ctx.strokePath()

            // Glowing white sweep blade + anodized center pivot
            ctx.setShadow(offset: .zero, blur: S * 0.038, color: cgColor(accentRGB, 0.85))
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96))
            ctx.setLineWidth(max(1.6, S * 0.016))
            ctx.move(to: CGPoint(x: cx, y: cy))
            ctx.addLine(to: CGPoint(x: cx + cos(splitA) * S * 0.72, y: cy + sin(splitA) * S * 0.72))
            ctx.strokePath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)

            let pivR = S * 0.028
            let pivRect = CGRect(x: cx - pivR, y: cy - pivR, width: pivR * 2, height: pivR * 2)
            ctx.setFillColor(cgColor(accentRGB, 1.0))
            ctx.fillEllipse(in: pivRect)
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
            ctx.setLineWidth(max(1.0, S * 0.01))
            ctx.strokeEllipse(in: pivRect)
            ctx.restoreGState()

            drawRefCornerPercent(scale: 0.248, baseScrimAlpha: 0.28)

        case .retroLEDMatrix:
            // #08 Retro Pixel Phosphor LED Matrix Window over Signature Optical Water
            let m = S * 0.066
            let winW = bw - m * 2
            let winH = min(bh * 0.38, S * 0.262 * relScale)
            let winRect = CGRect(x: bx + m, y: by + bh - winH - m, width: winW, height: winH)
            drawSmokedGlassPill(winRect, radius: S * 0.126, tint: (0.08, 0.10, 0.14), alpha: 0.76)

            let cols = 14, rows = 3
            let mx0 = winRect.minX + winW * 0.10
            let mw = winW * 0.80
            let my0 = winRect.minY + winH * 0.22
            let stepX = mw / CGFloat(cols - 1)
            let stepY = winH * 0.135
            let litCols = Int(round((remaining / 100.0) * Double(cols)))
            let dotR = max(1.3, S * 0.0125 * relScale)

            ctx.saveGState()
            for c in 0..<cols {
                let isLit = c < litCols
                if isLit {
                    ctx.setShadow(offset: .zero, blur: S * 0.028, color: cgColor(accentRGB, 0.85))
                    ctx.setFillColor(cgColor(accentRGB, 1.0))
                } else {
                    ctx.setShadow(offset: .zero, blur: 0, color: nil)
                    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14))
                }
                for rr in 0..<rows {
                    let px = mx0 + CGFloat(c) * stepX
                    let py = my0 + CGFloat(rr) * stepY
                    ctx.fillEllipse(in: CGRect(x: px - dotR, y: py - dotR, width: dotR * 2, height: dotR * 2))
                }
            }
            ctx.restoreGState()

            let readFont = sfMonoFont(size: max(9.5, round(S * 0.106 * relScale)), weight: .bold)
            let readY = winRect.minY + winH * 0.76
            if let cd = countdownStr {
                let compactCD = cd.replacingOccurrences(of: " ", with: "")
                drawCrispText(labelText, font: readFont, x: mx0, midY: readY, align: .left, maxWidth: mw * 0.48, shadowAlpha: 0)
                drawCrispText(
                    compactCD,
                    font: readFont,
                    color: NSColor(white: 1.0, alpha: 0.72),
                    x: mx0 + mw,
                    midY: readY,
                    align: .right,
                    maxWidth: mw * 0.50,
                    shadowAlpha: 0
                )
            } else {
                drawCrispText(labelText, font: readFont, x: winRect.midX, midY: readY, align: .center, maxWidth: mw * 0.90, shadowAlpha: 0)
            }

        case .dualTrackHUD:
            // #09 Bottom Dual-Track Micro HUD (5h + Weekly + Bold %) over Signature Optical Water
            let m = S * 0.066
            let hudW = bw - m * 2
            let hudH = min(bh * 0.37, S * 0.248 * relScale)
            let hudRect = CGRect(x: bx + m, y: by + bh - hudH - m, width: hudW, height: hudH)
            drawSmokedGlassPill(hudRect, radius: S * 0.124, tint: bandRGB, alpha: 0.74)

            let trackX = hudRect.minX + hudW * 0.09
            let trackW = hudW * 0.43
            let trackH = max(2.5, S * 0.042 * relScale)
            let y1 = hudRect.minY + hudH * 0.36
            let y2 = hudRect.minY + hudH * 0.67

            // Track 1: Primary 5h quota
            ctx.saveGState()
            ctx.beginPath()
            addPill(CGRect(x: trackX, y: y1 - trackH * 0.5, width: trackW, height: trackH), radius: trackH * 0.5)
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16))
            ctx.fillPath()

            let w1 = max(trackH, trackW * CGFloat(max(0, min(100, remaining)) / 100.0))
            ctx.setShadow(offset: .zero, blur: S * 0.025, color: cgColor(accentRGB, 0.75))
            ctx.beginPath()
            addPill(CGRect(x: trackX, y: y1 - trackH * 0.5, width: w1, height: trackH), radius: trackH * 0.5)
            ctx.setFillColor(cgColor(accentRGB, 1.0))
            ctx.fillPath()
            ctx.restoreGState()

            // Track 2: Secondary / Weekly emerald quota
            ctx.saveGState()
            ctx.beginPath()
            addPill(CGRect(x: trackX, y: y2 - trackH * 0.5, width: trackW, height: trackH), radius: trackH * 0.5)
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14))
            ctx.fillPath()

            let w2 = max(trackH, trackW * CGFloat(max(0, min(100, secondaryPct)) / 100.0))
            ctx.beginPath()
            addPill(CGRect(x: trackX, y: y2 - trackH * 0.5, width: w2, height: trackH), radius: trackH * 0.5)
            ctx.setFillColor(CGColor(srgbRed: 0.37, green: 0.92, blue: 0.83, alpha: 1.0))
            ctx.fillPath()
            ctx.restoreGState()

            let numFont = sfRoundedFont(size: max(11, round(S * 0.158 * relScale)), weight: .heavy)
            drawCrispText(
                labelText,
                font: numFont,
                x: hudRect.minX + hudW * 0.91,
                midY: hudRect.midY,
                align: .right,
                maxWidth: hudW * 0.38,
                shadowAlpha: 0.22
            )

        case .braunAnalogNeedle:
            // #11 Braun Dieter Rams Analog Scale Arc + Orange-Red Needle over Signature Optical Water
            // Adaptively deepen bottom smoked dial canopy on light/white icons when water drops below the scale!
            let needsLightIconDialBoost = !cached.isDark && remaining < 48.0
            let vTop = by + bh * (needsLightIconDialBoost ? 0.48 : 0.56)
            let dialMaxA = needsLightIconDialBoost ? min(0.74, 0.58 * relOpacity) : min(0.56, 0.38 * relOpacity)
            ctx.saveGState()
            let vc0 = CGColor(srgbRed: 0.04, green: 0.05, blue: 0.08, alpha: 0)
            let vc1 = CGColor(srgbRed: 0.04, green: 0.05, blue: 0.08, alpha: dialMaxA)
            if let vg = CGGradient(colorsSpace: colorSpace, colors: [vc0, vc1] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(vg, start: CGPoint(x: cx, y: vTop), end: CGPoint(x: cx, y: fSide), options: [.drawsAfterEndLocation])
            }

            let arcCy = by + bh * 0.94
            let rad = S * 0.34 * max(0.86, min(1.10, relScale))
            let a0 = -CGFloat.pi * 0.84
            let a1 = -CGFloat.pi * 0.16

            ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.006), blur: S * 0.022, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: cached.isDark ? 0.38 : 0.68))
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: cached.isDark ? 0.64 : 0.88))
            ctx.setLineWidth(max(1.2, S * 0.015))
            ctx.beginPath()
            addClockwiseArc(center: CGPoint(x: cx, y: arcCy), radius: rad, from: a0, to: a1)
            ctx.strokePath()

            for i in 0...8 {
                let ang = a0 + (a1 - a0) * (CGFloat(i) / 8.0)
                let rIn = rad - S * ((i % 2 == 0) ? 0.042 : 0.024)
                ctx.move(to: CGPoint(x: cx + cos(ang) * rIn, y: arcCy + sin(ang) * rIn))
                ctx.addLine(to: CGPoint(x: cx + cos(ang) * rad, y: arcCy + sin(ang) * rad))
            }
            ctx.strokePath()

            let needleA = a0 + (a1 - a0) * CGFloat(max(0, min(100, remaining)) / 100.0)
            let needleInnerR = rad * 0.48
            ctx.setShadow(offset: .zero, blur: S * 0.022, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
            ctx.setStrokeColor(CGColor(srgbRed: 1.0, green: 0.35, blue: 0.21, alpha: 1.0))
            ctx.setLineWidth(max(2.0, S * 0.022))
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: cx + cos(needleA) * needleInnerR, y: arcCy + sin(needleA) * needleInnerR))
            ctx.addLine(to: CGPoint(x: cx + cos(needleA) * (rad + S * 0.026), y: arcCy + sin(needleA) * (rad + S * 0.026)))
            ctx.strokePath()
            ctx.restoreGState()

            let dialFont = sfRoundedFont(size: max(11, round(S * 0.148 * relScale)), weight: .heavy)
            drawCrispText(labelText, font: dialFont, x: cx, midY: by + bh * 0.875, align: .center, maxWidth: bw * 0.56, shadowAlpha: cached.isDark ? 0.52 : 0.75)

        case .bottomPrismCells:
            // #15 Bottom 5 Luminous Micro-Blocks + Floating Dual Readout over Signature Optical Water
            let needsLightPrismBoost = !cached.isDark && remaining < 42.0
            ctx.saveGState()
            let vTop = by + bh * (needsLightPrismBoost ? 0.50 : 0.58)
            let prismMaxA = needsLightPrismBoost ? min(0.76, 0.60 * relOpacity) : min(0.56, 0.38 * relOpacity)
            let vc0 = CGColor(srgbRed: 0.03, green: 0.04, blue: 0.07, alpha: 0)
            let vc1 = CGColor(srgbRed: 0.03, green: 0.04, blue: 0.07, alpha: prismMaxA)
            if let vg = CGGradient(colorsSpace: colorSpace, colors: [vc0, vc1] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(vg, start: CGPoint(x: cx, y: vTop), end: CGPoint(x: cx, y: fSide), options: [.drawsAfterEndLocation])
            }
            ctx.restoreGState()

            let cells = 5
            let px0 = bx + S * 0.09
            let totalW = bw - S * 0.18
            let gap = S * 0.026
            let cw = (totalW - gap * CGFloat(cells - 1)) / CGFloat(cells)
            let ch = max(4.0, S * 0.074 * relScale)
            let cellY = by + bh - ch - S * 0.074
            let step = 100.0 / Double(cells)

            for i in 0..<cells {
                let frac = CGFloat(max(0.0, min(1.0, (remaining - Double(i) * step) / step)))
                let cellRect = CGRect(x: px0 + CGFloat(i) * (cw + gap), y: cellY, width: cw, height: ch)
                let cr = ch * 0.40

                ctx.saveGState()
                ctx.beginPath()
                addPill(cellRect, radius: cr)
                ctx.setFillColor(CGColor(srgbRed: 0.06, green: 0.08, blue: 0.12, alpha: 0.38))
                ctx.fillPath()
                ctx.beginPath()
                addPill(cellRect, radius: cr)
                ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.24))
                ctx.setLineWidth(max(0.9, S * 0.006))
                ctx.strokePath()

                if frac > 0.005 {
                    ctx.beginPath()
                    addPill(cellRect, radius: cr)
                    ctx.clip()
                    ctx.setFillColor(cgColor(accentRGB, 1.0))
                    ctx.fill(CGRect(x: cellRect.minX, y: cellRect.minY, width: cw * frac, height: ch))
                    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.30))
                    ctx.fill(CGRect(x: cellRect.minX, y: cellRect.minY, width: cw * frac, height: ch * 0.30))
                }
                ctx.restoreGState()
            }

            let bigFont = sfRoundedFont(size: max(12, round(S * 0.212 * relScale)), weight: .heavy)
            let textMidY = cellY - S * 0.118 * relScale
            drawCrispText(labelText, font: bigFont, x: px0, midY: textMidY, align: .left, maxWidth: totalW * 0.58, shadowAlpha: 0.52)

            if let cd = countdownStr {
                let cdFont = sfRoundedFont(size: max(9, round(S * 0.108 * relScale)), weight: .semibold)
                drawCrispText(
                    cd,
                    font: cdFont,
                    color: NSColor(white: 1.0, alpha: 0.88),
                    x: bx + bw - S * 0.09,
                    midY: textMidY + S * 0.015,
                    align: .right,
                    maxWidth: totalW * 0.40,
                    shadowAlpha: 0.45
                )
            }

        case .topDynamicIsland:
            // #20 Top-Center Smoked Glass Dynamic Island (Mini Ring + Bold %) over Signature Optical Water
            let ph = min(bh * 0.34, S * 0.222 * relScale)
            let pw = min(bw * 0.86, S * 0.65 * max(0.84, min(1.14, relScale)))
            let islandRect = CGRect(x: cx - pw * 0.5, y: by + S * 0.068, width: pw, height: ph)
            drawSmokedGlassPill(islandRect, radius: ph * 0.5, tint: bandRGB, alpha: 0.78)

            let ringCenter = CGPoint(x: islandRect.minX + ph * 0.54, y: islandRect.midY)
            let ringR = ph * 0.27
            let ringW = max(1.6, S * 0.022 * relScale)

            ctx.saveGState()
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22))
            ctx.setLineWidth(ringW)
            ctx.strokeEllipse(in: CGRect(x: ringCenter.x - ringR, y: ringCenter.y - ringR, width: ringR * 2, height: ringR * 2))

            let endA = -CGFloat.pi * 0.5 + CGFloat.pi * 2.0 * CGFloat(max(0.02, min(1.0, remaining / 100.0)))
            ctx.setStrokeColor(cgColor(accentRGB, 1.0))
            ctx.setLineCap(.round)
            ctx.beginPath()
            addClockwiseArc(center: ringCenter, radius: ringR, from: -CGFloat.pi * 0.5, to: endA)
            ctx.strokePath()
            ctx.restoreGState()

            let isFont = sfRoundedFont(size: max(10.5, round(S * 0.136 * relScale)), weight: .heavy)
            drawCrispText(
                labelText,
                font: isFont,
                x: islandRect.minX + pw * 0.63,
                midY: islandRect.midY,
                align: .center,
                maxWidth: pw * 0.54,
                shadowAlpha: 0.20
            )

        case .topEnergyBrow:
            // #23 Top Curved Luminous Energy Brow + Centered Readout over Signature Optical Water
            // Ensure rich smoked canopy on light/white icons so white brow & readout have >10:1 contrast!
            ctx.saveGState()
            let vBot = by + bh * (cached.isDark ? 0.33 : 0.37)
            let topA = cached.isDark ? min(0.84, 0.64 * relOpacity) : min(0.92, 0.84 * relOpacity)
            let midA = cached.isDark ? min(0.42, 0.30 * relOpacity) : min(0.76, 0.64 * relOpacity)
            let bc0 = cgColor(bandRGB, topA)
            let bc1 = cgColor(bandRGB, midA)
            let bc2 = cgColor(bandRGB, 0)
            if let bg = CGGradient(colorsSpace: colorSpace, colors: [bc0, bc1, bc2] as CFArray, locations: [0.0, 0.62, 1.0]) {
                ctx.saveGState()
                ctx.clip(to: CGRect(x: 0, y: 0, width: fSide, height: vBot))
                ctx.drawLinearGradient(bg, start: CGPoint(x: cx, y: by), end: CGPoint(x: cx, y: vBot), options: [])
                ctx.restoreGState()
            }

            let browCy = by + S * 0.455
            let rad = S * 0.385
            let a0 = -CGFloat.pi * 0.77
            let a1 = -CGFloat.pi * 0.23
            let strokeW = max(2.2, S * 0.035 * max(0.82, min(1.12, relScale)))

            ctx.setLineCap(.round)
            ctx.setLineWidth(strokeW)
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.24))
            ctx.beginPath()
            addClockwiseArc(center: CGPoint(x: cx, y: browCy), radius: rad, from: a0, to: a1)
            ctx.strokePath()

            let progEnd = a0 + (a1 - a0) * CGFloat(max(0.02, min(1.0, remaining / 100.0)))
            ctx.setShadow(offset: .zero, blur: S * 0.04, color: cgColor(accentRGB, 0.90))
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.98))
            ctx.beginPath()
            addClockwiseArc(center: CGPoint(x: cx, y: browCy), radius: rad, from: a0, to: progEnd)
            ctx.strokePath()
            ctx.restoreGState()

            let browText: String = if let cd = countdownStr, let shortT = cd.split(separator: " ").first {
                "\(labelText) · \(shortT)"
            } else {
                labelText
            }
            let browFont = sfRoundedFont(size: max(10.0, round(S * 0.118 * relScale)), weight: .heavy)
            drawCrispText(browText, font: browFont, x: cx, midY: by + S * 0.248, align: .center, maxWidth: bw * 0.70, shadowAlpha: 0.40)

        case .haloText, .pureSplitText:
            break
        }

        return uploadTexture(from: ctx, dev: dev, cacheKey: key)
    }

    private func trimLabelCacheIfNeeded() {
        if labelTexCache.count > 360 {
            for k in labelTexCache.keys.prefix(140) {
                labelTexCache.removeValue(forKey: k)
            }
        }
    }

    private func uploadTexture(from ctx: CGContext, dev: MTLDevice, cacheKey: String) -> MTLTexture? {
        guard let bytes = ctx.data else { return nil }
        let side = dockTileSide
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: side,
            height: side,
            mipmapped: false
        )
        td.usage = [.shaderRead]
        td.storageMode = .shared
        guard let tex = dev.makeTexture(descriptor: td) else { return nil }
        tex.replace(
            region: MTLRegionMake2D(0, 0, side, side),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: side * 4
        )
        labelTexCache[cacheKey] = tex
        return tex
    }

    private func loadBaseIcon(for appURL: URL) -> CachedIcon? {
        let key = appURL.path
        if let cached = iconCache[key] {
            return cached
        }

        let nsIcon = NSWorkspace.shared.icon(forFile: key)
        let side = dockTileSide
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        ctx.interpolationQuality = .high
        var drewFromCG = false
        if side > 512 {
            var proposed = NSRect(x: 0, y: 0, width: 512, height: 512)
            if let srcCG = nsIcon.cgImage(forProposedRect: &proposed, context: nil, hints: nil) {
                ctx.draw(srcCG, in: CGRect(x: 0, y: 0, width: side, height: side))
                drewFromCG = true
            }
        }
        if !drewFromCG {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            nsIcon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
            NSGraphicsContext.restoreGraphicsState()
        }

        guard let cgImage = ctx.makeImage(), let data = ctx.data else {
            return nil
        }

        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var minX = side
        var maxX = 0
        var minRow = side
        var maxRow = 0

        var lumSum: Double = 0
        var lumCount: Int = 0
        var chromaSumR: Double = 0
        var chromaSumG: Double = 0
        var chromaSumB: Double = 0
        var chromaWeight: Double = 0

        let inset = side / 6
        let midLo = side * 38 / 100
        let midHi = side * 62 / 100
        for row in 0..<side {
            for col in 0..<side {
                let idx = (row * side + col) * 4
                let alpha = bytes[idx + 3]
                if alpha >= 246 {
                    if row >= midLo && row <= midHi {
                        if col < minX { minX = col }
                        if col > maxX { maxX = col }
                    }
                    if col >= midLo && col <= midHi {
                        if row < minRow { minRow = row }
                        if row > maxRow { maxRow = row }
                    }
                }
                if alpha >= 200 && row >= inset && row < side - inset && col >= inset && col < side - inset && (col % 2 == 0) && (row % 2 == 0) {
                    let aF = Double(alpha) / 255.0
                    let r = min(1.0, (Double(bytes[idx]) / 255.0) / aF)
                    let g = min(1.0, (Double(bytes[idx + 1]) / 255.0) / aF)
                    let b = min(1.0, (Double(bytes[idx + 2]) / 255.0) / aF)
                    lumSum += 0.299 * r + 0.587 * g + 0.114 * b
                    lumCount += 1

                    let maxC = max(r, max(g, b))
                    let minC = min(r, min(g, b))
                    let chroma = maxC - minC
                    if chroma > 0.18 && maxC > 0.20 {
                        let w = chroma * chroma
                        chromaSumR += r * w
                        chromaSumG += g * w
                        chromaSumB += b * w
                        chromaWeight += w
                    }
                }
            }
        }

        let bodyRect: CGRect
        if maxX > minX && maxRow > minRow {
            let cgMinY = CGFloat(side - 1 - maxRow)
            let cgMaxY = CGFloat(side - 1 - minRow)
            bodyRect = CGRect(
                x: CGFloat(minX),
                y: cgMinY,
                width: CGFloat(maxX - minX + 1),
                height: cgMaxY - cgMinY + 1
            )
        } else {
            let defPad = round(CGFloat(side) * 0.0975)
            bodyRect = CGRect(x: defPad, y: defPad, width: CGFloat(side) - defPad * 2, height: CGFloat(side) - defPad * 2)
        }

        let avgLum = lumCount > 0 ? (lumSum / Double(lumCount)) : 0.5
        let isDark = avgLum < 0.48

        let extractedTint: SIMD3<Float>
        if chromaWeight > 2.5 {
            var er = Float(chromaSumR / chromaWeight)
            var eg = Float(chromaSumG / chromaWeight)
            var eb = Float(chromaSumB / chromaWeight)
            let baseCrystal = isDark ? SIMD3<Float>(0.76, 0.86, 0.96) : SIMD3<Float>(0.55, 0.72, 0.98)
            er = er * 0.62 + baseCrystal.x * 0.38
            eg = eg * 0.62 + baseCrystal.y * 0.38
            eb = eb * 0.62 + baseCrystal.z * 0.38
            extractedTint = SIMD3<Float>(er, eg, eb)
        } else {
            extractedTint = isDark ? SIMD3<Float>(0.76, 0.84, 0.94) : SIMD3<Float>(0.42, 0.66, 0.98)
        }

        var mtlTex: MTLTexture?
        if let dev = device {
            let td = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: side,
                height: side,
                mipmapped: false
            )
            td.usage = [.shaderRead]
            td.storageMode = .shared
            if let tex = dev.makeTexture(descriptor: td) {
                tex.replace(
                    region: MTLRegionMake2D(0, 0, side, side),
                    mipmapLevel: 0,
                    withBytes: bytes,
                    bytesPerRow: side * 4
                )
                mtlTex = tex
            }
        }

        AppLogger.shared.log(
            "Icon",
            "\(appURL.deletingPathExtension().lastPathComponent) body=(\(Int(bodyRect.minX)),\(Int(bodyRect.minY)),\(Int(bodyRect.width))x\(Int(bodyRect.height))) 亮度 \(String(format: "%.2f", avgLum)) → \(isDark ? "深色" : "浅色")"
        )

        let cached = CachedIcon(
            cgImage: cgImage,
            metalTexture: mtlTex,
            bodyRect: bodyRect,
            isDark: isDark,
            extractedTint: extractedTint
        )
        iconCache[key] = cached
        return cached
    }

    private static let metalShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texUv;
    };

    struct Uniforms {
        float level;
        float waveT;
        float bubbleT;
        float wake;
        float tilt;
        float ripple;
        float isDark;
        float working;
        float phase;
        float bodyMinX;
        float bodyMinY;
        float bodySpanX;
        float bodySpanY;
        float hasLabel;
        float colorMode;
        float styleKind;
        float waterMode;
        float badgeOpacity;
        float tintR;
        float tintG;
        float tintB;
    };

    vertex VertexOut vs_quad(uint vid [[vertex_id]]) {
        const float2 pos[4] = {
            float2(-1.0,  1.0),
            float2( 1.0,  1.0),
            float2(-1.0, -1.0),
            float2( 1.0, -1.0)
        };
        const float2 uv[4] = {
            float2(0.0, 0.0),
            float2(1.0, 0.0),
            float2(0.0, 1.0),
            float2(1.0, 1.0)
        };
        VertexOut out;
        out.position = float4(pos[vid], 0.0, 1.0);
        out.texUv = uv[vid];
        return out;
    }

    inline float sdRoundedBox(float2 p, float2 b, float r) {
        float2 q = abs(p) - b + r;
        return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
    }

    inline float waveH(float x, float t, float amp, float tilt, float ph, float fr) {
        float nx = (x - 0.5) * 2.0;
        return nx * tilt * 0.055
             + sin(nx * 3.14159 * fr + t + ph) * amp
             + sin(nx * 5.2 * fr - t * 1.15 + ph * 1.7) * (amp * 0.22);
    }

    inline float3 boostSat(float3 c, float a) {
        float l = dot(c, float3(0.299, 0.587, 0.114));
        return clamp(mix(float3(l), c, 1.0 + a), 0.0, 1.0);
    }

    inline float3 sampleIconInterior(texture2d<float> tex, sampler s, float2 uv, float3 fallbackRGB) {
        float4 c = tex.sample(s, clamp(uv, 0.02, 0.98));
        float3 straight = clamp(c.rgb / max(c.a, 1e-4), 0.0, 1.0);
        if (c.a < 0.88) {
            return mix(fallbackRGB, straight, smoothstep(0.45, 0.88, c.a));
        }
        return straight;
    }

    inline float3 sampleFrostedBackdrop(texture2d<float> tex, sampler s, float2 uv, float3 fallbackRGB) {
        float3 acc = float3(0.0);
        float wSum = 0.0;
        for (int dx = -1; dx <= 1; dx++) {
            for (int dy = -1; dy <= 1; dy++) {
                float2 off = float2(float(dx), float(dy)) * 0.026;
                float3 rgb = sampleIconInterior(tex, s, uv + off, fallbackRGB);
                float w = (dx == 0 && dy == 0) ? 2.0 : 1.0;
                acc += rgb * w;
                wSum += w;
            }
        }
        return acc / wSum;
    }

    fragment float4 fs_liquid_glass(
        VertexOut in [[stage_in]],
        texture2d<float> iconTex [[texture(0)]],
        texture2d<float> labelTex [[texture(1)]],
        constant Uniforms& u [[buffer(0)]]
    ) {
        constexpr sampler samp(coord::normalized, address::clamp_to_edge, filter::linear);

        float2 texUv = in.texUv;
        float2 uv = float2(texUv.x, 1.0 - texUv.y);

        float4 orig = iconTex.sample(samp, texUv);
        if (orig.a < 0.62) {
            return orig;
        }

        float pres = smoothstep(0.0, 1.0, u.wake);
        if (pres <= 0.005) {
            return orig;
        }

        float3 origRGB = clamp(orig.rgb / max(orig.a, 1e-4), 0.0, 1.0);
        float3 tint = float3(u.tintR, u.tintG, u.tintB);
        float3 col = origRGB;
        float3 cleanCol = origRGB;

        float2 bodyCenter = float2(u.bodyMinX + u.bodySpanX * 0.5, u.bodyMinY + u.bodySpanY * 0.5);
        float2 halfSpan   = float2(u.bodySpanX * 0.5, u.bodySpanY * 0.5);
        float bodyY       = (uv.y - u.bodyMinY) / max(0.2, u.bodySpanY);
        float2 p          = uv - bodyCenter;
        float rIcon       = min(u.bodySpanX, u.bodySpanY) * 0.225;
        float distToWall  = max(0.0, -sdRoundedBox(p, halfSpan, rIcon));

        // ==================== Water Mode 2.0: Screenshot-Caliber Clean Translucent Gel Water ====================
        if (u.waterMode > 1.5) {
            float amp = 0.008 + u.wake * 0.010 + u.working * 0.004 + u.ripple * 0.022;
            if (u.level <= 0.02 || u.level >= 0.98) amp *= 0.18;

            float hFront = u.level + waveH(uv.x, u.waveT, amp, u.tilt, u.phase, 1.02);
            float hBack  = u.level + 0.020 + waveH(uv.x, -u.waveT * 0.75, amp * 0.85, -u.tilt * 0.40, u.phase + 2.1, 0.86);
            float aa = 0.0022;
            float maskFront = smoothstep(hFront + aa, hFront - aa, bodyY);
            float maskBack  = smoothstep(hBack + aa * 1.2, hBack - aa * 1.2, bodyY) * (1.0 - maskFront);

            float3 gelColor = boostSat(tint, 0.28);
            if (maskBack > 0.001) {
                float3 bc = mix(origRGB, gelColor, 0.28);
                col = mix(col, bc, maskBack * pres);
            }
            if (maskFront > 0.001) {
                float depthBelow = max(0.0, hFront - bodyY);
                float normDepth = clamp(depthBelow / max(0.18, u.level), 0.0, 1.0);
                float surfaceLens = exp(-depthBelow * 14.0);
                float2 bs = texUv + float2(0.0, surfaceLens * 0.012);
                float3 refr = sampleIconInterior(iconTex, samp, bs, origRGB);

                float gelAlpha = mix(0.50, 0.68, normDepth);
                float3 gelTarget = mix(gelColor * 1.08, gelColor * 0.88, normDepth);
                float3 wc = mix(refr, gelTarget, gelAlpha);

                // Soft sub-meniscus glow + razor-sharp white meniscus crest (matching reference screenshot!)
                float subGlow = smoothstep(0.028, 0.0, abs(depthBelow - 0.011));
                float crest = smoothstep(0.0055, 0.0, depthBelow);
                wc = mix(wc, float3(1.0), subGlow * 0.25);
                wc = mix(wc, float3(1.0), crest * 0.90);

                cleanCol = mix(cleanCol, wc, maskFront * pres);
                col = mix(col, wc, maskFront * pres);
            }
        }
        // ==================== Water Mode 1.0: Signature Optical Refractive Bubble Water ====================
        else if (u.waterMode > 0.5) {
            const float kSharp    = 1.00;
            const float kRim      = 0.50;
            const float kAmp      = 1.04;
            const float kDual     = 1.00;
            const float kRefract  = 2.10;
            const float kDisp     = 0.39;
            const float kCrest    = 0.79;
            const float kReflect  = 0.99;
            const float kCaustics = 0.35;
            const float kDepth    = 1.00;
            const float kBSize    = 1.38;

            float amp = (0.0065 + u.wake * 0.0092 + u.working * 0.0035 + u.ripple * 0.018) * kAmp;
            if (u.level <= 0.02 || u.level >= 0.98) amp *= 0.18;

            float hFront = u.level + waveH(uv.x, u.waveT, amp, u.tilt, u.phase, 1.02);
            float hBack  = u.level + 0.022 * kDual + waveH(uv.x, -u.waveT * 0.74, amp * 0.88, -u.tilt * 0.40, u.phase + 2.40, 0.86);

            float eps = 0.004;
            float slope = (waveH(uv.x + eps, u.waveT, amp, u.tilt, u.phase, 1.02)
                         - waveH(uv.x - eps, u.waveT, amp, u.tilt, u.phase, 1.02)) / (2.0 * eps);

            float aa = mix(0.0085, 0.0014, kSharp);
            float maskFront = smoothstep(hFront + aa, hFront - aa, bodyY);
            float maskBack  = smoothstep(hBack + aa * 1.15, hBack - aa * 1.15, bodyY) * (1.0 - maskFront) * kDual;

            if (maskBack > 0.001) {
                float3 bc = (u.isDark > 0.5)
                    ? (col + tint * (0.16 * kDepth))
                    : (col * exp(-(float3(1.0) - tint) * (0.44 * kDepth)));
                float bLine = smoothstep(0.0045, 0.0, abs(bodyY - hBack));
                float3 bRimCol = (u.isDark > 0.5)
                    ? mix(tint, float3(1.0), 0.78)
                    : mix(tint * 0.42, tint * 0.75, 0.5);
                bc = mix(bc, bRimCol, bLine * (0.35 + 0.45 * kRim));
                col = mix(col, bc, maskBack * pres);
            }

            cleanCol = col;

            if (maskFront > 0.001) {
                float depthBelow = max(0.0, hFront - bodyY);
                float normDepth = clamp(depthBelow / max(0.18, u.level), 0.0, 1.0);
                float surfaceLens = exp(-depthBelow * 13.0);
                float wallSoft = smoothstep(0.055, 0.0, distToWall);

                float2 refOff = float2(-slope * 0.022 * surfaceLens * kRefract, -0.013 * surfaceLens * kRefract)
                              - p * (0.024 * kRefract);
                refOff.x += sin(bodyY * 15.0 + u.waveT + u.phase) * 0.003 * kRefract;

                float bSpec = 0.0;
                float bRim = 0.0;
                float bDarkRim = 0.0;
                float bAlpha = mix(0.92, 1.0, u.working);

                for (int i = 0; i < 24; i++) {
                    float fi = float(i);
                    float seed = fract(fi * 0.3183 + u.phase * 0.17);
                    float bx = 0.11 + fract(fi * 0.271 + seed * 0.31) * 0.78;
                    float spd = 0.055 + fmod(fi, 5.0) * 0.019;
                    float prog = fract(fi * 0.163 + u.bubbleT * spd);
                    float by = 0.03 + prog * max(0.08, u.level - 0.045);
                    float sway = sin(u.waveT * 1.05 + fi * 2.3) * (u.working > 0.5 ? 0.015 : 0.012);
                    float2 bC = float2(u.bodyMinX + (bx + sway) * u.bodySpanX, u.bodyMinY + by * u.bodySpanY);
                    bool isHero = fmod(fi, 3.0) < 0.5;
                    float br = (isHero ? (0.0125 + fmod(fi, 2.0) * 0.0045) : (0.0055 + fmod(fi, 4.0) * 0.0022)) * kBSize;

                    if (by < hFront - br * 1.2) {
                        float2 dv = uv - bC;
                        float dl = length(dv);
                        if (dl < br * 1.3) {
                            float lf = sin(prog * 3.14159) * bAlpha;
                            if (dl < br) {
                                float nz = sqrt(max(0.0, 1.0 - (dl / br) * (dl / br)));
                                refOff += (dv / max(br, 1e-4)) * (1.0 - nz) * 0.022 * kRefract * lf;
                            }
                            float ringW = max(0.0022, br * 0.26);
                            bRim = max(bRim, smoothstep(ringW, 0.0, abs(dl - br * 0.90)) * lf);
                            bDarkRim = max(bDarkRim, smoothstep(ringW * 1.2, 0.0, abs(dl - br * 1.02)) * lf * 0.65);
                            bSpec = max(bSpec, smoothstep(max(0.0020, br * 0.38), 0.0, length(dv - float2(-br * 0.32, br * 0.32))) * lf);
                        }
                    }
                }

                float disp = (surfaceLens + wallSoft * 0.4) * 0.0032 * kDisp;
                float2 bs = texUv + float2(refOff.x, -refOff.y);
                float3 refracted;
                refracted.r = sampleIconInterior(iconTex, samp, bs + float2(disp, 0.0), origRGB).r;
                refracted.g = sampleIconInterior(iconTex, samp, bs, origRGB).g;
                refracted.b = sampleIconInterior(iconTex, samp, bs - float2(disp, 0.0), origRGB).b;
                refracted = boostSat(refracted, 0.18);

                float3 wc;
                if (u.isDark > 0.5) {
                    wc = refracted * exp(-(float3(1.0) - tint) * (0.18 * kDepth * (0.3 + 0.7 * normDepth)));
                    wc += tint * ((0.08 + 0.24 * smoothstep(0.0, 1.0, normDepth)) * kDepth);
                } else {
                    wc = refracted * exp(-(float3(1.0) - tint) * (0.88 * kDepth) * (0.28 + 0.72 * smoothstep(0.0, 1.0, normDepth)));
                }

                float c1 = sin(uv.x * 26.0 + slope * 8.0 + u.waveT * 1.6) * sin(bodyY * 20.0 - u.waveT * 1.1);
                wc += mix(tint, float3(1.0), 0.7) * pow(max(0.0, c1), 3.0) * (1.0 - normDepth * 0.55) * (0.26 * kCaustics);

                float diag = smoothstep(0.22, 0.0, abs((uv.x * 0.72 + uv.y * 0.52) - 0.56 - slope * 0.08));
                float wallGlow = smoothstep(0.032, 0.0, distToWall);
                wc += float3(1.0) * (diag * 0.13 + wallGlow * 0.14) * kReflect;

                float3 wcClean = wc;

                if (u.isDark > 0.5) {
                    wc = mix(wc, mix(tint, float3(1.0), 0.82), bRim * 0.78);
                    wc += float3(1.0) * bSpec * 0.95;
                } else {
                    wc = mix(wc, tint * 0.28, bDarkRim * 0.55);
                    wc = mix(wc, float3(1.0), bRim * 0.72);
                    wc = mix(wc, float3(1.0), bSpec * 0.98);
                }

                float crestW = 0.0042;
                float capRim = smoothstep(crestW, 0.0, depthBelow);
                float specBand = smoothstep(crestW * 1.5, 0.0, abs(depthBelow - crestW * 1.35));
                if (u.isDark > 0.5) {
                    wc += mix(tint, float3(1.0), 0.6) * specBand * (0.32 * kCrest);
                    wc = mix(wc, float3(0.97, 0.99, 1.0), capRim * (0.65 + 0.30 * kRim) * kCrest);
                } else {
                    wc = mix(wc, float3(1.0), specBand * (0.78 * kCrest));
                    float3 darkCap = mix(tint * 0.36, float3(0.05, 0.18, 0.42), 0.35);
                    wc = mix(wc, darkCap, capRim * (0.76 * kRim));
                }

                cleanCol = mix(cleanCol, wcClean, maskFront * pres);
                col = mix(col, wc, maskFront * pres);
            }
        }

        // ==================== Overlay Compositor ====================
        if (u.hasLabel > 0.5 && pres > 0.01) {
            float4 m = labelTex.sample(samp, clamp(texUv, 0.0, 1.0));

            if (u.styleKind > 2.5) {
                // StyleKind 3.0: Premultiplied RGBA High-Craft Overlay + GPU Frosted Glass Backdrop
                float ovA = clamp(m.a, 0.0, 1.0) * pres;
                if (ovA > 0.002) {
                    // Apply genuine 9-tap frosted blur behind smoked-glass capsules/windows while keeping <38% shadow scrims crisp
                    float frostAmt = smoothstep(0.42, 0.72, m.a) * 0.70 * pres;
                    if (frostAmt > 0.01) {
                        float3 frosted = sampleFrostedBackdrop(iconTex, samp, texUv, origRGB);
                        col = mix(col, frosted, frostAmt);
                    }
                    col = clamp(m.rgb * pres + col * (1.0 - ovA), 0.0, 1.0);
                }
            } else if (u.styleKind > 1.5) {
                // StyleKind 2.0: Pure Split Text (`动态反相字`)
                float gA = clamp(m.g, 0.0, 1.0) * pres;
                if (gA > 0.002) {
                    float bgLum = dot(cleanCol, float3(0.299, 0.587, 0.114));
                    float darkPart = smoothstep(0.56, 0.62, bgLum);
                    float3 inkDark = mix(float3(0.04, 0.06, 0.12), tint * 0.22, 0.28);
                    float3 splitCol = mix(float3(1.0), inkDark, darkPart);
                    col = mix(col, splitCol, gA);
                }
            } else {
                // StyleKind 1.0: Pure Halo Text (`微晶描边字`)
                float gA = clamp(m.g, 0.0, 1.0) * pres;
                float hA = clamp(m.b, 0.0, 1.0) * pres;
                if (gA > 0.002 || hA > 0.002) {
                    float3 glyphCol;
                    float3 haloCol;
                    if (u.colorMode < 0.5) {
                        bool darkText = (u.isDark < 0.5);
                        glyphCol = darkText ? float3(0.05, 0.08, 0.16) : float3(1.0);
                        haloCol  = darkText ? float3(0.97, 0.99, 1.0)  : float3(0.05, 0.08, 0.15);
                    } else if (u.colorMode < 1.5) {
                        bool darkText = (u.isDark < 0.5);
                        glyphCol = darkText ? mix(float3(0.05, 0.08, 0.16), tint * 0.30, 0.55) : float3(1.0);
                        haloCol  = darkText ? float3(0.97, 0.99, 1.0) : mix(float3(0.05, 0.08, 0.15), tint * 0.35, 0.45);
                    } else if (u.colorMode > 2.5 && u.colorMode < 3.5) {
                        glyphCol = float3(1.0);
                        haloCol  = float3(0.24, 0.27, 0.32);
                    } else {
                        glyphCol = float3(1.0);
                        haloCol  = float3(0.05, 0.07, 0.12);
                    }
                    col = mix(col, haloCol, hA * 0.92);
                    col = mix(col, glyphCol, gA);
                }
            }
        }

        return float4(col * orig.a, orig.a);
    }
    """
}
