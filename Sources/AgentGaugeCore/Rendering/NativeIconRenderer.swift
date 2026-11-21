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
        badgeStyle: DockBadgeStyle = .concentricAutoDodge,
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
    /// S2 Low-Water Auto-Dodge threshold (scaled for 1.5x badge height ~35%): when remaining <= 38%, badge parks in Top-Left concentric R-corner!
    private let lowWaterDodgeThreshold: Double = 38.0

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
            AppLogger.shared.log("Metal", "256x256 Retina S2 同心 R角着色器初始化成功 (\(dev.name))")
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
        let labelStr = snapshot.formattedDockIconValue(showPercentageSign: params.showPercentageSign)
        let lblTex = (params.showDockBadge && params.hoverAlpha > 0.01)
            ? badgeMaskTexture(
                for: cached,
                labelText: labelStr,
                remaining: remaining,
                badgeStyle: params.badgeStyle,
                badgeScale: params.badgeScale
            )
            : nil

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
        let labelStr = snapshot.formattedDockIconValue(showPercentageSign: params.showPercentageSign)
        let lblTex = (params.showDockBadge && params.hoverAlpha > 0.01)
            ? badgeMaskTexture(
                for: cached,
                labelText: labelStr,
                remaining: remaining,
                badgeStyle: params.badgeStyle,
                badgeScale: params.badgeScale
            )
            : nil

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

    /// Non-blocking single-command-buffer batch renderer for interactive UI sliders:
    /// encodes up to 4 icons into ONE `MTLCommandBuffer` and awaits GPU completion asynchronously via `addCompletedHandler`
    /// so `@MainActor` never blocks `NSSlider` mouse tracking!
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
            let labelStr = item.snapshot.formattedDockIconValue(showPercentageSign: item.params.showPercentageSign)
            let lblTex = (item.params.showDockBadge && item.params.hoverAlpha > 0.01)
                ? badgeMaskTexture(
                    for: cached,
                    labelText: labelStr,
                    remaining: remaining,
                    badgeStyle: item.params.badgeStyle,
                    badgeScale: item.params.badgeScale
                )
                : nil

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
        default:             styleKind = 0.0
        }

        let tintVec = srgbVector(from: waterColor)
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
            badgeOpacity: Float(params.badgeOpacity),
            tintR: tintVec.x,
            tintG: tintVec.y,
            tintB: tintVec.z
        )
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
    }

    private func futuraBoldFont(size: CGFloat) -> NSFont {
        if let f = NSFont(name: "Futura-Bold", size: size) {
            return f
        }
        if let f = NSFont(name: "Futura", size: size) {
            return NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask)
        }
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: .heavy)
    }

    /// Generates a `256×256` multi-channel mask for all 11 customizable `DockBadgeStyle`s + `badgeScale`:
    /// - R channel = Badge / Semi-Circle / Quarter-Circle solid body (`0..1`, `0` for pure text styles)
    /// - G channel = Optically centered `Futura-Bold` glyph fill (`0..1`)
    /// - B channel = Crisp circular / R-corner border arc (`0..1`) or micro-halo stroke (`haloText`)
    private func badgeMaskTexture(
        for cached: CachedIcon,
        labelText: String,
        remaining: Double,
        badgeStyle: DockBadgeStyle,
        badgeScale: CGFloat
    ) -> MTLTexture? {
        guard let dev = device, !labelText.isEmpty else { return nil }
        let bRect = cached.bodyRect
        let sMin = min(bRect.width, bRect.height)
        let sc = max(0.60, min(1.85, badgeScale))
        let scalePct = Int(round(sc * 100.0))

        // Only auto-dodge styles depend on whether remaining is above/below cutoff!
        let approxDodgeH: CGFloat = (badgeStyle == .concentricCircle) ? (0.29 * sc) : (0.232 * sc)
        let dodgeCutoff = Double(min(54.0, max(25.0, approxDodgeH * 100.0 + 4.0)))
        let autoTopFlag: String
        switch badgeStyle {
        case .concentricAutoDodge, .concentricCircle:
            autoTopFlag = (remaining <= dodgeCutoff) ? "T" : "B"
        default:
            autoTopFlag = "F"
        }

        let key = "v5-\(badgeStyle.rawValue)-\(scalePct)-\(autoTopFlag)-\(labelText)-\(Int(bRect.minX))-\(Int(bRect.minY))-\(Int(bRect.width))-\(Int(bRect.height))"
        if let hit = labelTexCache[key] {
            return hit
        }
        if labelTexCache.count > 400 {
            for k in labelTexCache.keys.prefix(150) {
                labelTexCache.removeValue(forKey: k)
            }
        }

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

        let rIcon = sMin * 0.225
        let margin = round(sMin * 0.048)

        let baseFactor: CGFloat
        let maxTextWidthRatio: CGFloat
        switch badgeStyle {
        case .haloText, .pureSplitText:
            baseFactor = 0.158
            maxTextWidthRatio = 0.78
        case .cornerQuarterTopLeft, .cornerQuarterBottomLeft, .semiLeft, .semiRight:
            baseFactor = 0.136
            maxTextWidthRatio = 0.56
        case .semiTop, .semiBottom:
            baseFactor = 0.138
            maxTextWidthRatio = 0.68
        case .concentricCircle:
            baseFactor = 0.138
            maxTextWidthRatio = 0.70
        case .concentricAutoDodge, .concentricTopLeft:
            baseFactor = 0.140
            maxTextWidthRatio = 0.77
        }

        var mainFs = max(14.0, round(sMin * baseFactor * sc * (isCreditOrLong ? 0.85 : 1.0)))
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

        let maxTextW = sMin * maxTextWidthRatio
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

        let capH = mainFont.capHeight
        ctx.setBlendMode(.plusLighter)

        var shapePath: CGPath?
        var textStartX: CGFloat = 0
        var textBaseY: CGFloat = 0

        switch badgeStyle {
        case .concentricAutoDodge, .concentricTopLeft:
            let pillH = min(sMin - margin * 2, round(max(sMin * 0.232 * sc, mainFs * 1.44)))
            let pillW = min(sMin - margin * 2, round(max(pillH * 1.18, totalTextW + sMin * 0.125 * min(1.3, sc))))
            let rPill = min(pillH * 0.48, max(8.0, rIcon - margin))
            let topLeft = (badgeStyle == .concentricTopLeft) ? true : (remaining <= dodgeCutoff)
            let pillX = round(bRect.minX + margin)
            let pillY = topLeft ? round(bRect.maxY - margin - pillH) : round(bRect.minY + margin)
            shapePath = CGPath(roundedRect: CGRect(x: pillX, y: pillY, width: pillW, height: pillH), cornerWidth: rPill, cornerHeight: rPill, transform: nil)
            textStartX = round(pillX + (pillW - totalTextW) * 0.5)
            textBaseY = round(pillY + (pillH - capH) * 0.5)

        case .concentricCircle:
            let maxRad = (sMin - margin * 2) * 0.48
            let rad = min(maxRad, round(max(sMin * 0.145 * sc, (totalTextW + sMin * 0.10) * 0.55)))
            let topLeft = (remaining <= dodgeCutoff)
            let cx = round(bRect.minX + margin + rad)
            let cy = topLeft ? round(bRect.maxY - margin - rad) : round(bRect.minY + margin + rad)
            shapePath = CGPath(ellipseIn: CGRect(x: cx - rad, y: cy - rad, width: rad * 2, height: rad * 2), transform: nil)
            textStartX = round(cx - totalTextW * 0.5)
            textBaseY = round(cy - capH * 0.5)

        case .cornerQuarterTopLeft, .cornerQuarterBottomLeft:
            let isTop = (badgeStyle == .cornerQuarterTopLeft)
            let cOff = sMin * 0.04
            let cx0 = bRect.minX + cOff
            let cy0 = isTop ? (bRect.maxY - cOff) : (bRect.minY + cOff)
            let rad = min(sMin * 0.82, max(sMin * (0.31 + 0.15 * sc), totalTextW + sMin * 0.22))
            shapePath = CGPath(ellipseIn: CGRect(x: cx0 - rad, y: cy0 - rad, width: rad * 2, height: rad * 2), transform: nil)
            let span = rad + cOff
            let tcx = bRect.minX + max(totalTextW * 0.5 + sMin * 0.08, span * 0.44)
            let tcy = isTop
                ? (bRect.maxY - max(capH * 0.5 + sMin * 0.09, span * 0.39))
                : (bRect.minY + max(capH * 0.5 + sMin * 0.09, span * 0.39))
            textStartX = round(tcx - totalTextW * 0.5)
            textBaseY = round(tcy - capH * 0.5)

        case .semiLeft, .semiRight:
            let isLeft = (badgeStyle == .semiLeft)
            let outShift = sMin * 0.08
            let visW = min(sMin * 0.74, max(sMin * (0.25 + 0.145 * sc), totalTextW + sMin * 0.125))
            let rad = visW + outShift
            let cx0 = isLeft ? (bRect.minX - outShift) : (bRect.maxX + outShift)
            let cy0 = bRect.midY
            shapePath = CGPath(ellipseIn: CGRect(x: cx0 - rad, y: cy0 - rad, width: rad * 2, height: rad * 2), transform: nil)
            let tcx = isLeft ? (bRect.minX + visW * 0.46) : (bRect.maxX - visW * 0.46)
            textStartX = round(tcx - totalTextW * 0.5)
            textBaseY = round(cy0 - capH * 0.5)

        case .semiTop, .semiBottom:
            let isTop = (badgeStyle == .semiTop)
            let outShiftY = sMin * 0.18
            let visH = min(sMin * 0.66, max(sMin * (0.21 + 0.125 * sc), capH + sMin * 0.16))
            let dyWorst = outShiftY + visH * 0.47 + capH * 0.55
            let halfWNeeded = totalTextW * 0.5 + sMin * 0.08
            let rad = max(visH + outShiftY, hypot(dyWorst, halfWNeeded))
            let effVisH = rad - outShiftY
            let cx0 = bRect.midX
            let cy0 = isTop ? (bRect.maxY + outShiftY) : (bRect.minY - outShiftY)
            shapePath = CGPath(ellipseIn: CGRect(x: cx0 - rad, y: cy0 - rad, width: rad * 2, height: rad * 2), transform: nil)
            let tcy = isTop ? (bRect.maxY - effVisH * 0.46) : (bRect.minY + effVisH * 0.46)
            textStartX = round(cx0 - totalTextW * 0.5)
            textBaseY = round(tcy - capH * 0.5)

        case .haloText, .pureSplitText:
            shapePath = nil
            textStartX = round(bRect.minX + sMin * 0.085)
            textBaseY = round(bRect.minY + sMin * 0.115)
        }

        if let path = shapePath {
            // 1. Blue channel = Crisp 1pt Dock-scale circular / R-corner border arc (~4px at 256px Retina)
            ctx.saveGState()
            ctx.addPath(path)
            ctx.setStrokeColor(red: 0, green: 0, blue: 1, alpha: 1)
            ctx.setLineWidth(max(3.2, fSide * 0.016))
            ctx.strokePath()
            ctx.restoreGState()

            // 2. Red channel = Badge / Semi-Circle / Quarter-Circle solid body
            ctx.saveGState()
            ctx.addPath(path)
            ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            ctx.fillPath()
            ctx.restoreGState()
        } else if badgeStyle == .haloText {
            // Pure halo text: stroke outer protective ring into Blue channel
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

        // 3. Green channel = Optically cap-height-centered Futura-Bold glyphs
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

        guard let bytes = ctx.data else { return nil }
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
        labelTexCache[key] = tex
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
        // Scan near-center column/row with strict alpha >= 246 so bottom drop-shadows NEVER skew bodyRect downward!
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
        return nx * tilt * 0.085
             + sin(nx * 3.14159 * fr + t + ph) * amp
             + sin(nx * 5.6 * fr - t * 1.28 + ph * 1.7) * (amp * 0.25);
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

    // 9-tap frosted glass blur behind the Concentric Apple R-Corner Badge so underlying icon strokes never shatter small Dock text
    inline float3 sampleFrostedBackdrop(texture2d<float> tex, sampler s, float2 uv, float3 fallbackRGB) {
        float3 acc = float3(0.0);
        float wSum = 0.0;
        for (int dx = -1; dx <= 1; dx++) {
            for (int dy = -1; dy <= 1; dy++) {
                float2 off = float2(float(dx), float(dy)) * 0.028;
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

        float2 bodyCenter = float2(u.bodyMinX + u.bodySpanX * 0.5, u.bodyMinY + u.bodySpanY * 0.5);
        float2 halfSpan   = float2(u.bodySpanX * 0.5, u.bodySpanY * 0.5);
        float bodyY       = (uv.y - u.bodyMinY) / max(0.2, u.bodySpanY);
        float2 p          = uv - bodyCenter;
        float rIcon       = min(u.bodySpanX, u.bodySpanY) * 0.225;
        float distToWall  = max(0.0, -sdRoundedBox(p, halfSpan, rIcon));

        const float kSharp    = 1.00;
        const float kRim      = 0.50;
        const float kAmp      = 1.50;
        const float kDual     = 1.00;
        const float kRefract  = 2.20;
        const float kDisp     = 0.39;
        const float kCrest    = 0.79;
        const float kReflect  = 0.99;
        const float kCaustics = 0.35;
        const float kDepth    = 1.00;
        const float kBSize    = 1.42;

        float amp = (0.008 + u.wake * 0.014 + u.working * 0.005 + u.ripple * 0.026) * kAmp;
        if (u.level <= 0.02 || u.level >= 0.98) amp *= 0.18;

        float hFront = u.level + waveH(uv.x, u.waveT, amp, u.tilt, u.phase, 1.06);
        float hBack  = u.level + 0.028 * kDual + waveH(uv.x, -u.waveT * 0.78, amp * 0.92, -u.tilt * 0.45, u.phase + 2.40, 0.88);

        float eps = 0.004;
        float slope = (waveH(uv.x + eps, u.waveT, amp, u.tilt, u.phase, 1.06)
                     - waveH(uv.x - eps, u.waveT, amp, u.tilt, u.phase, 1.06)) / (2.0 * eps);

        float aa = mix(0.0085, 0.0014, kSharp);
        float maskFront = smoothstep(hFront + aa, hFront - aa, bodyY);
        float maskBack  = smoothstep(hBack + aa * 1.15, hBack - aa * 1.15, bodyY) * (1.0 - maskFront) * kDual;

        float3 tint = float3(u.tintR, u.tintG, u.tintB);
        float3 col = origRGB;

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

        float3 cleanCol = col;

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

        // Customizable Badge / Semi-Circle / Quarter-Circle / Pure Text Compositor
        if (u.hasLabel > 0.5 && pres > 0.01) {
            float4 m = labelTex.sample(samp, clamp(texUv, 0.0, 1.0));

            if (u.styleKind > 1.5) {
                // Pure Split Text: bubble-free dynamic polarity cut
                float gA = clamp(m.g, 0.0, 1.0) * pres;
                if (gA > 0.002) {
                    float bgLum = dot(cleanCol, float3(0.299, 0.587, 0.114));
                    float darkPart = smoothstep(0.56, 0.62, bgLum);
                    float3 inkDark = mix(float3(0.04, 0.06, 0.12), tint * 0.22, 0.28);
                    float3 splitCol = mix(float3(1.0), inkDark, darkPart);
                    col = mix(col, splitCol, gA);
                }
            } else if (u.styleKind > 0.5) {
                // Pure Halo Text: crisp glyph + protective micro-crystal outline
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
            } else {
                // 9 Geometric Badge / Semi-Circle / Quarter-Circle / R-Corner Styles
                float badgeA = clamp(m.r, 0.0, 1.0) * pres;
                float textA  = clamp(m.g, 0.0, 1.0) * pres;
                float rimA   = clamp(m.b, 0.0, 1.0) * pres;

                if (badgeA > 0.002 || rimA > 0.002 || textA > 0.002) {
                    float3 frosted = sampleFrostedBackdrop(iconTex, samp, texUv, origRGB);
                    if (maskFront > 0.5) {
                        frosted = mix(frosted, tint, 0.34);
                    }

                    float3 plateTarget;
                    float3 glyphCol;
                    float3 rimCol;
                    float rimAlpha;

                    if (u.colorMode < 0.5) {
                        // Smart Invert (continuous uniform hairline rim — zero mid-curve color jump!)
                        if (u.isDark > 0.5) {
                            plateTarget = mix(float3(0.96, 0.98, 1.0), tint, 0.06);
                            glyphCol    = float3(0.05, 0.08, 0.15);
                            rimCol      = float3(0.72, 0.76, 0.84);
                            rimAlpha    = 0.55;
                        } else {
                            plateTarget = mix(float3(0.06, 0.09, 0.16), tint * 0.20, 0.25);
                            glyphCol    = float3(1.0);
                            rimCol      = float3(0.36, 0.42, 0.52);
                            rimAlpha    = 0.62;
                        }
                    } else if (u.colorMode < 1.5) {
                        // Adaptive Theme Ink
                        if (u.isDark > 0.5) {
                            plateTarget = mix(float3(0.08, 0.11, 0.18), tint * 0.62, 0.52);
                            glyphCol    = float3(1.0);
                            rimCol      = mix(tint, float3(1.0), 0.55);
                            rimAlpha    = 0.68;
                        } else {
                            plateTarget = mix(float3(0.93, 0.96, 1.0), tint, 0.24);
                            glyphCol    = mix(float3(0.04, 0.07, 0.14), tint * 0.28, 0.55);
                            rimCol      = mix(tint * 0.65, float3(0.35, 0.42, 0.52), 0.40);
                            rimAlpha    = 0.62;
                        }
                    } else if (u.colorMode < 2.5) {
                        // Classic White
                        plateTarget = float3(0.08, 0.10, 0.16);
                        glyphCol    = float3(1.0);
                        rimCol      = float3(0.44, 0.48, 0.56);
                        rimAlpha    = 0.62;
                    } else if (u.colorMode < 3.5) {
                        // Smoke Gray (高级烟灰半圆 + 均匀钛银灰细边 + 纯白字)
                        plateTarget = float3(0.31, 0.34, 0.39);
                        glyphCol    = float3(1.0);
                        rimCol      = float3(0.56, 0.60, 0.66);
                        rimAlpha    = 0.86;
                    } else {
                        // Obsidian Black (深黑曜石半圆 + 均匀枪灰细边 + 纯白字)
                        plateTarget = float3(0.06, 0.07, 0.10);
                        glyphCol    = float3(1.0);
                        rimCol      = float3(0.42, 0.46, 0.53);
                        rimAlpha    = 0.84;
                    }

                    float3 frostedPlate = mix(frosted, plateTarget, clamp(u.badgeOpacity, 0.35, 0.98));
                    col = mix(col, frostedPlate, badgeA);
                    col = mix(col, rimCol, rimA * rimAlpha);
                    col = mix(col, glyphCol, textA);
                }
            }
        }

        return float4(col * orig.a, orig.a);
    }
    """
}
