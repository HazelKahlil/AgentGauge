import AgentGaugeCore
import AppKit
import SwiftUI

struct VisualEffectBackdrop: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Static App Icon Cache (Never queries NSWorkspace during body renders)

@MainActor
enum AppIconCache {
    private static var cache: [AgentID: NSImage] = [:]
    private static var checked: Set<AgentID> = []

    static func icon(for agentID: AgentID) -> NSImage? {
        if checked.contains(agentID) {
            return cache[agentID]
        }
        checked.insert(agentID)

        // 1. Prefer real installed macOS app icon when present
        if let appURL = agentID.installedAppURL {
            let img = NSWorkspace.shared.icon(forFile: appURL.path)
            cache[agentID] = img
            return img
        }

        // 2. Fall back to bundled high-res squircle brand icon for uninstalled agents
        if let bundledURL = Bundle.main.url(forResource: agentID.rawValue, withExtension: "png", subdirectory: "AgentIcons"),
           let img = NSImage(contentsOf: bundledURL) {
            cache[agentID] = img
            return img
        }

        return nil
    }
}

// MARK: - Zero-Lag Specular Glass Surfaces (Eliminates nested CABackdropLayer / WindowServer stalls!)

private extension View {
    /// Lightweight layered specular glass card sitting over the window's behind-window VisualEffectBackdrop.
    @ViewBuilder
    func nativeGlassSurface(cornerRadius: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        self
            .background(Color.primary.opacity(0.055), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75))
            .clipShape(shape)
    }

    /// Crisp zero-blur-pass capsule pill for inline micro-buttons (0ms hit-test & click response).
    @ViewBuilder
    func nativeGlassCapsuleButton(tint: Color? = nil) -> some View {
        self
            .contentShape(Capsule())
            .background(tint ?? Color.primary.opacity(0.065), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.65)
            )
            .clipShape(Capsule())
    }

    /// Crisp zero-blur-pass rounded-rect for inline card & grid buttons.
    @ViewBuilder
    func nativeGlassSquareButton(cornerRadius: CGFloat = 8, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        self
            .contentShape(shape)
            .background(tint ?? Color.primary.opacity(0.06), in: shape)
            .overlay(
                shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.65)
            )
            .clipShape(shape)
    }

    /// True macOS 26 Apple native hardware-accelerated Liquid Glass button style (`NSButton` C++/CoreAnimation layer).
    @ViewBuilder
    func appleNativeGlassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self
                    .buttonBorderShape(.capsule)
                    .buttonStyle(.glassProminent)
            } else {
                self
                    .buttonBorderShape(.capsule)
                    .buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Zero-Overshoot Clear Native Capsule Pill Slider (0.0px Jitter, Pure Neutral Glass)

private struct SmoothCapsuleSegment<Value: Hashable>: View {
    struct Option {
        let title: String
        let value: Value
    }

    let options: [Option]
    @Binding var selection: Value
    let width: CGFloat
    var height: CGFloat = 24

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let count = max(1, options.count)
        let inset: CGFloat = 2.5
        let innerW = width - inset * 2
        let itemW = innerW / CGFloat(count)
        let selectedIdx = options.firstIndex(where: { $0.value == selection }) ?? 0

        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.085 : 0.07))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.65)
                )

            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.95))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.06),
                            lineWidth: 0.65
                        )
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.09), radius: 1.8, x: 0, y: 0.8)
                .frame(width: itemW, height: height - inset * 2)
                .offset(x: inset + CGFloat(selectedIdx) * itemW)
                .animation(.spring(response: 0.21, dampingFraction: 0.98), value: selectedIdx)

            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                    let isSelected = (idx == selectedIdx)
                    Button {
                        if selection != opt.value {
                            selection = opt.value
                        }
                    } label: {
                        Text(opt.title)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .frame(width: itemW, height: height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                }
            }
            .padding(.horizontal, inset)
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Deterministic Window Metrics (Exact 14pt Left = 14pt Right = 14pt Bottom Concentric Geometry)

enum SettingsWindowMetrics {
    static let width: CGFloat = 436
    static let outerMargin: CGFloat = 14
    static let concentricCornerRadius: CGFloat = 13
    static let baseHeight: CGFloat = 528
    static let permissionExtraHeight: CGFloat = 45

    static func height(accessibilityTrusted: Bool) -> CGFloat {
        var h = baseHeight
        if !accessibilityTrusted { h += permissionExtraHeight }
        return h
    }
}

// MARK: - Main Settings View

struct SettingsWindowView: View {
    @ObservedObject var store = AgentGaugeStore.shared
    @State private var isLogsExpanded = false
    @State private var showCatalog = false
    @State private var showBadgeStudio = false
    var onHeightChange: ((CGFloat) -> Void)?

    private var currentHeight: CGFloat {
        SettingsWindowMetrics.height(accessibilityTrusted: store.accessibilityTrusted)
    }

    private var cardRows: [[AgentID]] {
        let list = store.pinnedAgents
        var rows: [[AgentID]] = []
        var idx = 0
        while idx < list.count {
            let end = min(idx + 2, list.count)
            rows.append(Array(list[idx..<end]))
            idx += 2
        }
        return rows
    }

    var body: some View {
        let margin = SettingsWindowMetrics.outerMargin

        ZStack(alignment: .top) {
            // Full-window backdrop extends all the way behind traffic lights (zero top clipping!)
            VisualEffectBackdrop(material: .underWindowBackground, blendingMode: .behindWindow)
                .frame(width: SettingsWindowMetrics.width, height: currentHeight)

            VStack(spacing: 8.5) {
                titlebarHeader

                if !store.accessibilityTrusted {
                    permissionCallout
                }

                // Compact section bar with one-click 32-agent catalog manager
                HStack {
                    Text("监控应用")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text("\(store.enabledAgents.count) / \(AgentID.allCases.count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.065), in: Capsule())

                    Spacer()

                    Button {
                        showCatalog = true
                    } label: {
                        HStack(spacing: 3.5) {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("选择应用")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                    }
                    .controlSize(.small)
                    .appleNativeGlassButton()
                    .focusEffectDisabled()
                    .help("从 \(AgentID.allCases.count) 款主流 AI / Coding Agent 中自由勾选需要 Dock 液态玻璃效果的应用")
                }
                .frame(height: 22)

                // Compact 2-column Bento grid: locked 200pt column width + hidden scroller gutter = zero horizontal shift!
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6.5) {
                        if cardRows.isEmpty {
                            VStack(spacing: 6) {
                                Text("尚未选择监控应用")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Button("从 \(AgentID.allCases.count) 款应用中选择") {
                                    showCatalog = true
                                }
                                .controlSize(.small)
                                .appleNativeGlassButton()
                            }
                            .frame(width: 408, height: 180)
                        } else {
                            ForEach(Array(cardRows.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 8) {
                                    ForEach(row) { id in
                                        agentCard(id)
                                            .frame(width: 200)
                                    }
                                    if row.count == 1 {
                                        Color.clear.frame(width: 200, height: 52)
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: 408)
                }
                .frame(width: 408, height: 228)

                preferencesPanel

                Spacer(minLength: 0)

                LogsTriggerBar(isExpanded: $isLogsExpanded)
            }
            .padding(.horizontal, margin)
            .padding(.top, 36)
            .padding(.bottom, margin)
            .frame(width: SettingsWindowMetrics.width, height: currentHeight, alignment: .top)

            // 120Hz Pure GPU Slide-Up Console Drawer: exact 14pt Left = 14pt Right = 14pt Bottom + concentric R-corners!
            if isLogsExpanded {
                Color.black.opacity(0.12)
                    .padding(.top, 68)
                    .frame(width: SettingsWindowMetrics.width, height: currentHeight)
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
                            isLogsExpanded = false
                        }
                    }
            }

            ZStack(alignment: .bottom) {
                Color.clear
                LogsSlideUpDrawer(isExpanded: $isLogsExpanded)
                    .compositingGroup()
                    .padding(.horizontal, margin)
                    .padding(.bottom, margin)
                    .offset(y: isLogsExpanded ? 0 : 370)
                    .opacity(isLogsExpanded ? 1.0 : 0.0)
                    .allowsHitTesting(isLogsExpanded)
            }
            .frame(width: SettingsWindowMetrics.width, height: currentHeight, alignment: .bottom)
            .clipped()
            .allowsHitTesting(isLogsExpanded)
        }
        .frame(width: SettingsWindowMetrics.width, height: currentHeight, alignment: .top)
        .ignoresSafeArea()
        .sheet(isPresented: $showCatalog) {
            AgentCatalogSheet(store: store, isPresented: $showCatalog)
        }
        .sheet(isPresented: $showBadgeStudio) {
            BadgeCustomizationSheet(store: store, isPresented: $showBadgeStudio)
        }
        .onAppear {
            onHeightChange?(currentHeight)
            if CommandLine.arguments.contains("--promo-badge-studio") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showBadgeStudio = true
                }
            }
        }
        .onChange(of: currentHeight) { _, newHeight in
            onHeightChange?(newHeight)
        }
    }

    private func agentCard(_ agentID: AgentID) -> some View {
        let wc = store.waterColor(for: agentID)
        return AgentBentoCard(
            agentID: agentID,
            isEnabled: store.enabledAgents.contains(agentID),
            snapshot: store.snapshots[agentID],
            showPercentageSign: store.showPercentageSign,
            waterColor: wc,
            waterColorHex: wc.srgbHexString,
            isCustomColor: store.customWaterColors[agentID] != nil,
            numberColorMode: store.numberColorMode,
            onToggle: { enabled in
                store.toggleAgent(agentID, enabled: enabled)
            },
            onRefresh: {
                Task { await store.refresh(agentID: agentID) }
            },
            onLogin: {
                store.openWebLogin(for: agentID)
            },
            onColorChange: { hex in
                store.setCustomWaterColor(hex, for: agentID)
            }
        )
        .equatable()
    }

    // MARK: - Header (Left-aligned with cards below + Sleek Live Status Pill & Refresh)

    private var titlebarHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(nsImage: Bundle.main.image(forResource: "AppIcon") ?? NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 25, height: 25)

                Text("AgentGauge")
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))

                Text("v1.2.1")
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    store.isMasterEnabled.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusDotColor)
                            .frame(width: 6.5, height: 6.5)

                        Text(statusLabelText)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(store.isMasterEnabled ? Color.primary : Color.secondary)
                    }
                }
                .controlSize(.small)
                .appleNativeGlassButton()
                .focusEffectDisabled()
                .help(statusHelpText)

                Button {
                    Task { await store.refreshAll(forceWebProbe: true) }
                } label: {
                    ZStack {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .opacity(store.isRefreshing ? 0 : 1)
                        if store.isRefreshing {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                    .frame(width: 14, height: 14)
                }
                .controlSize(.small)
                .appleNativeGlassButton()
                .focusEffectDisabled()
                .disabled(store.isRefreshing)
                .help("立即刷新全部额度")
            }
        }
        .frame(height: 26)
    }

    private var statusDotColor: Color {
        if !store.accessibilityTrusted {
            return .orange
        }
        return store.isMasterEnabled ? .green : .secondary.opacity(0.55)
    }

    private var statusLabelText: String {
        if !store.accessibilityTrusted {
            return "待授权"
        }
        return store.isMasterEnabled ? "运行中" : "已暂停"
    }

    private var statusHelpText: String {
        if !store.accessibilityTrusted {
            return "等待授予辅助功能权限"
        }
        return store.isMasterEnabled
            ? "实时感应就绪：鼠标悬停 Dock 图标即可显示液态水位，移开恢复原生"
            : "已暂停：所有 Dock 图标保持原生"
    }

    // MARK: - Permission Callout

    private var permissionCallout: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)

            Text("需要「辅助功能」权限以感应 Dock 悬停")
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)

            Spacer()

            Button {
                store.requestAccessibility()
            } label: {
                Text("去授权")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .frame(width: 52, height: 22)
                    .nativeGlassSquareButton(cornerRadius: 7, tint: Color.orange.opacity(0.18))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("在 系统设置 → 隐私与安全性 → 辅助功能 中勾选 AgentGauge")
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .nativeGlassSurface(cornerRadius: 12)
    }

    // MARK: - Native Preferences Panel (True macOS 26 Native Liquid Glass Controls)

    private var preferencesPanel: some View {
        let animBinding = Binding<Bool>(
            get: { store.animationIntensity != .reduced },
            set: { store.animationIntensity = $0 ? .always : .reduced }
        )

        return VStack(spacing: 0) {
            HStack {
                Text("悬停详情")
                    .font(.system(size: 12))
                    .help("控制鼠标移到 Dock 图标上时，图标上方是否显示详细额度小框（支持多模型、仅主额度或直接关闭）")
                Spacer()
                SmoothCapsuleSegment(
                    options: [
                        .init(title: "多模型", value: TooltipDetailMode.multiModel),
                        .init(title: "仅主额度", value: TooltipDetailMode.primaryOnly),
                        .init(title: "关闭", value: TooltipDetailMode.off)
                    ],
                    selection: $store.tooltipDetailMode,
                    width: 186,
                    height: 24
                )
            }
            .padding(.horizontal, 12)
            .frame(height: 33)

            Divider().padding(.leading, 12).opacity(0.42)

            HStack(spacing: 8) {
                Text("图标余量")
                    .font(.system(size: 12))
                    .help("开关 Dock 图标内部的余量展示，点击右侧胶囊可自由切换 11 种水波、光学仪表与微岛样式")
                Spacer()

                Button {
                    showBadgeStudio = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("\(store.badgeStyle.shortTitle) · \(store.numberColorMode.title) · \(Int(round(store.badgeScale * 100)))%")
                            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(store.showDockBadge ? .primary : .secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .controlSize(.small)
                .appleNativeGlassButton()
                .focusEffectDisabled()
                .help("打开图标余量自定义工作台：实时调节大小、衬底浓度、色调与 11 款精选展示样式")

                Toggle("", isOn: $store.showDockBadge)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .focusEffectDisabled()
                    .help("开启或关闭在 Dock 图标内部显示数字百分比/余量")
            }
            .padding(.horizontal, 12)
            .frame(height: 33)

            Divider().padding(.leading, 12).opacity(0.42)

            HStack {
                Text("水波动态")
                    .font(.system(size: 12))
                    .help("控制悬停时的波浪起伏与微泡涌动，可随时切为静止")
                Spacer()
                SmoothCapsuleSegment(
                    options: [
                        .init(title: "灵动", value: true),
                        .init(title: "静止", value: false)
                    ],
                    selection: animBinding,
                    width: 124,
                    height: 24
                )
            }
            .padding(.horizontal, 12)
            .frame(height: 33)

            Divider().padding(.leading, 12).opacity(0.45)

            HStack(spacing: 14) {
                HStack {
                    Text("显示 %")
                        .font(.system(size: 12))
                        .help("开启后数字右侧附带紧凑百分号 %，也可随时关闭只显示纯数字")
                    Spacer()
                    Toggle("", isOn: $store.showPercentageSign)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .focusEffectDisabled()
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 16)
                    .opacity(0.45)

                HStack {
                    Text("开机自启")
                        .font(.system(size: 12))
                        .help("登录 macOS 时自动在菜单栏静默启动 AgentGauge")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { store.launchAtLogin },
                        set: { store.toggleLaunchAtLogin($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .focusEffectDisabled()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
        }
        .nativeGlassSurface(cornerRadius: SettingsWindowMetrics.concentricCornerRadius)
    }
}

// MARK: - Zero-Resize 120Hz Slide-Up Logs Drawer (Exact 14pt Left = Right = Bottom + Concentric R-Corners)

private struct LogsTriggerBar: View {
    @ObservedObject var logger = AppLogger.shared
    @Binding var isExpanded: Bool
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SettingsWindowMetrics.concentricCornerRadius, style: .continuous)

        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.90)) {
                isExpanded = true
            }
        } label: {
            HStack(spacing: 6.5) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("运行日志")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("\(logger.entries.count)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.07), in: Capsule())

                if let latest = logger.entries.last {
                    Text("\(latest.category) · \(latest.message)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)

                HStack(spacing: 3) {
                    Text("展开")
                        .font(.system(size: 10.5, weight: .medium))
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(width: 408, height: 34, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(isHovered ? 0.08 : 0.055), in: shape)
            .overlay(
                shape
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.15 : 0.10), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        .help("点击从底部丝滑展开实时运行日志抽屉")
    }
}

private struct LogsSlideUpDrawer: View {
    @ObservedObject var logger = AppLogger.shared
    @Binding var isExpanded: Bool
    @State private var copied = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let recent = isExpanded ? Array(logger.entries.suffix(80).reversed()) : []
        let drawerShape = RoundedRectangle(cornerRadius: SettingsWindowMetrics.concentricCornerRadius, style: .continuous)

        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
                        isExpanded = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text("运行日志")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("\(logger.entries.count)")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08), in: Capsule())

                        Spacer(minLength: 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()

                HStack(spacing: 6) {
                    Button {
                        let text = logger.entries.map {
                            "\($0.timeString) [\($0.category)] \($0.message)"
                        }.joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text(copied ? "已复制" : "复制")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .padding(.horizontal, 8.5)
                        .frame(height: 22)
                        .nativeGlassCapsuleButton()
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .disabled(logger.entries.isEmpty)

                    Button {
                        logger.clear()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "trash")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("清空")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .padding(.horizontal, 8.5)
                        .frame(height: 22)
                        .nativeGlassCapsuleButton()
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .disabled(logger.entries.isEmpty)

                    Button {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
                            isExpanded = false
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text("收起")
                                .font(.system(size: 10.5, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9.5, weight: .bold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .nativeGlassCapsuleButton()
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                }
            }
            .padding(.horizontal, 12)
            .frame(width: 408, height: 38)

            Divider().opacity(0.42)

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 5) {
                    if recent.isEmpty {
                        Text("暂无运行日志")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        ForEach(recent) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(entry.timeString)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 50, alignment: .leading)

                                Text(entry.category)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(categoryColor(entry.category))
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 1)
                                    .background(categoryColor(entry.category).opacity(0.14), in: Capsule())
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)

                                Text(entry.message)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.primary.opacity(0.88))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
            }
            .frame(width: 408, height: 286)
        }
        .frame(width: 408, height: 325)
        .background(.thickMaterial, in: drawerShape)
        .overlay(
            drawerShape
                .strokeBorder(Color.primary.opacity(0.13), lineWidth: 0.85)
        )
        .clipShape(drawerShape)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.42 : 0.16), radius: 16, x: 0, y: -3)
    }

    private func categoryColor(_ cat: String) -> Color {
        switch cat {
        case "Antigravity": return Color(nsColor: AgentID.antigravity.defaultAccentColor)
        case "Cursor": return Color(nsColor: AgentID.cursor.defaultAccentColor)
        case "ChatGPT / Codex": return Color(nsColor: AgentID.codex.defaultAccentColor)
        case "Claude": return Color(nsColor: AgentID.claude.defaultAccentColor)
        case "WorkBuddy": return Color(nsColor: AgentID.workbuddy.defaultAccentColor)
        case "Grok Bot": return Color(nsColor: AgentID.grokbot.defaultAccentColor)
        case "Metal", "NativeTile": return Color(nsColor: MineralColorPreset.curated[2].nsColor)
        default: return .secondary
        }
    }
}

// MARK: - Refined Compact 52pt Liquid Glass Bento Card (Fits 8 Apps at Once, Zero Truncation)

private struct AgentBentoCard: View, Equatable {
    let agentID: AgentID
    let isEnabled: Bool
    let snapshot: QuotaSnapshot?
    let showPercentageSign: Bool
    let waterColor: NSColor
    let waterColorHex: String
    let isCustomColor: Bool
    let numberColorMode: NumberColorMode
    let onToggle: (Bool) -> Void
    let onRefresh: () -> Void
    let onLogin: () -> Void
    let onColorChange: (String?) -> Void

    nonisolated static func == (lhs: AgentBentoCard, rhs: AgentBentoCard) -> Bool {
        lhs.agentID == rhs.agentID
            && lhs.isEnabled == rhs.isEnabled
            && lhs.snapshot == rhs.snapshot
            && lhs.showPercentageSign == rhs.showPercentageSign
            && lhs.waterColorHex == rhs.waterColorHex
            && lhs.isCustomColor == rhs.isCustomColor
            && lhs.numberColorMode == rhs.numberColorMode
    }

    @State private var showColorPopover = false
    @State private var showDetailPopover = false

    var body: some View {
        let accent = Color(nsColor: waterColor)

        VStack(alignment: .leading, spacing: 5.5) {
            // Row 1: Crisp 19pt Icon + App Name + Plan Tier Pill + Theme Dot + Mini Toggle
            HStack(spacing: 4.5) {
                Button {
                    showDetailPopover.toggle()
                } label: {
                    HStack(spacing: 5) {
                        if let icon = AppIconCache.icon(for: agentID) {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 19, height: 19)
                        } else {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(accent.opacity(0.25))
                                .frame(width: 19, height: 19)
                        }

                        Text(shortTitle)
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        if let planBadge = snapshot?.compactPlanBadge {
                            PlanTierBadgePill(text: planBadge, accentColor: waterColor, size: .compact)
                        }

                        if snapshot?.isWorking == true {
                            Circle()
                                .fill(.green)
                                .frame(width: 5, height: 5)
                                .help("正在工作中")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .opacity(isEnabled ? 1.0 : 0.5)
                .popover(isPresented: $showDetailPopover, arrowEdge: .bottom) {
                    AgentDetailPopover(
                        agentID: agentID,
                        snapshot: snapshot,
                        showPercentageSign: showPercentageSign,
                        accent: accent,
                        waterColor: waterColor,
                        onRefresh: onRefresh,
                        onLogin: onLogin
                    )
                }

                Spacer(minLength: 2)

                Button {
                    showColorPopover.toggle()
                } label: {
                    Circle()
                        .fill(accent)
                        .frame(width: 9.5, height: 9.5)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.72), lineWidth: 0.9)
                        )
                        .shadow(color: accent.opacity(0.42), radius: 1.5, y: 0.5)
                        .frame(width: 15, height: 15)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("水波颜色：\(isCustomColor ? "自定义" : agentID.themeColorName)（点击自定义）")
                .popover(isPresented: $showColorPopover, arrowEdge: .bottom) {
                    AgentColorPopover(
                        agentID: agentID,
                        waterColor: waterColor,
                        isCustomColor: isCustomColor,
                        numberColorMode: numberColorMode,
                        onColorChange: onColorChange
                    )
                }

                Toggle("", isOn: Binding(get: { isEnabled }, set: { onToggle($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .scaleEffect(0.86)
                    .frame(width: 28, height: 16)
                    .labelsHidden()
                    .focusEffectDisabled()
            }
            .frame(height: 19)

            // Row 2: Inline Value + Sleek Capsule Liquid Bar + Reset Countdown (or Login pill)
            ZStack(alignment: .leading) {
                if !isEnabled {
                    Text("已暂停")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                } else if let snap = snapshot, let rem = snap.remainingPercent {
                    Button {
                        showDetailPopover.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Text(snap.formattedCardValue(showPercentageSign: showPercentageSign))
                                .font(.system(size: snap.isCreditsBased ? 11.5 : 13, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(rem <= 15 ? Color.red : .primary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)

                            GeometryReader { geo in
                                let pct = max(0.04, min(1.0, rem / 100.0))
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.09))
                                    Capsule()
                                        .fill(rem <= 15 ? Color.red : accent)
                                        .frame(width: geo.size.width * pct)
                                }
                            }
                            .frame(height: 4)

                            Text(snap.formattedCountdown())
                                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                } else {
                    HStack(spacing: 4) {
                        Text(snapshot?.requiresWebLogin == true ? "需登录" : "探测中")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(snapshot?.requiresWebLogin == true ? Color.orange : Color.secondary)

                        Spacer()

                        if agentID.webLoginURL != nil {
                            Button {
                                onLogin()
                            } label: {
                                Text("登录")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 8)
                                    .frame(height: 17)
                                    .nativeGlassCapsuleButton(tint: Color.accentColor.opacity(0.16))
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                            .help("登录一次即可同步订阅等级与实时额度")
                        } else {
                            Button {
                                onRefresh()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .frame(width: 20, height: 17)
                                    .nativeGlassCapsuleButton()
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                            .help("重新探测本地服务")
                        }
                    }
                }
            }
            .frame(height: 17, alignment: .leading)
        }
        .padding(.horizontal, 9.5)
        .padding(.vertical, 6.5)
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .topLeading)
        .nativeGlassSurface(cornerRadius: 12)
        .help(cardTooltip)
    }

    private var shortTitle: String {
        agentID.shortName
    }

    private var cardTooltip: String {
        guard let snap = snapshot else { return agentID.displayName }
        var lines: [String] = []
        if let email = snap.accountEmail {
            lines.append("登录账号：\(email)")
        }
        if let tier = snap.planTier {
            lines.append("订阅等级：\(tier)")
        }
        if snap.windows.count > 1 {
            let parts = snap.windows.prefix(5).map {
                "\($0.label.replacingOccurrences(of: " (当前)", with: "")): \(Int(round($0.remainingPercent)))\(showPercentageSign ? "%" : "") (\($0.formattedCountdown()))"
            }
            lines.append(parts.joined(separator: "\n"))
        }
        if let sub = snap.subtitle, !sub.isEmpty {
            lines.append(sub)
        }
        if let err = snap.errorMessage, !err.isEmpty {
            lines.append("提示：\(err)")
        }
        lines.append("来源：\(snap.sourceDescription)（点击卡片查看详情）")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Per-Agent Account, Subscription Tier & Quota Inspector Popover

private struct AgentDetailPopover: View {
    let agentID: AgentID
    let snapshot: QuotaSnapshot?
    let showPercentageSign: Bool
    let accent: Color
    let waterColor: NSColor
    let onRefresh: () -> Void
    let onLogin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                if let icon = AppIconCache.icon(for: agentID) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 24, height: 24)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 5.5) {
                        Text(agentID.displayName)
                            .font(.system(size: 12.5, weight: .semibold))
                        if let badge = snapshot?.compactPlanBadge {
                            PlanTierBadgePill(text: badge, accentColor: waterColor, size: .regular)
                        }
                    }
                    Text(snapshot?.sourceDescription ?? agentID.themeColorName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider().opacity(0.45)

            // Account & Subscription Tier Rows
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("登录账号")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(snapshot?.accountEmail ?? "未识别 / 未登录")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(snapshot?.accountEmail != nil ? .primary : .secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Text("订阅套餐")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(snapshot?.planTier ?? "—")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(snapshot?.planTier != nil ? .primary : .secondary)
                }
            }

            if let wins = snapshot?.windows, !wins.isEmpty {
                Divider().opacity(0.45)
                VStack(alignment: .leading, spacing: 4.5) {
                    ForEach(Array(wins.prefix(6).enumerated()), id: \.offset) { _, win in
                        HStack(spacing: 8) {
                            Text(win.label)
                                .font(.system(size: 11, weight: win.isPrimary ? .semibold : .regular))
                                .foregroundStyle(win.isPrimary ? .primary : .secondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(round(win.remainingPercent)))\(showPercentageSign ? "%" : "")")
                                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                            Text(win.formattedCountdown())
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 42, alignment: .trailing)
                        }
                    }
                }
            }

            if let sub = snapshot?.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let err = snapshot?.errorMessage, !err.isEmpty {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            Divider().opacity(0.45)

            HStack {
                Button {
                    onRefresh()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text("立即刷新")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 23)
                    .nativeGlassCapsuleButton()
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()

                Spacer()

                if agentID.webLoginURL != nil {
                    Button {
                        onLogin()
                    } label: {
                        Text(snapshot?.remainingPercent == nil ? "立即登录" : "切换/重新登录")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 9)
                            .frame(height: 23)
                            .nativeGlassCapsuleButton(tint: Color.accentColor.opacity(0.15))
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                }
            }
        }
        .padding(12)
        .frame(width: 268)
    }
}

// MARK: - Per-Agent Theme Color Popover (Brand Default + Curated Swatches + Native ColorPicker)

private struct AgentColorPopover: View {
    let agentID: AgentID
    let waterColor: NSColor
    let isCustomColor: Bool
    let numberColorMode: NumberColorMode
    let onColorChange: (String?) -> Void

    @State private var draftColor: NSColor
    @State private var hasPendingCommit = false
    @State private var isCommitLoopRunning = false

    init(
        agentID: AgentID,
        waterColor: NSColor,
        isCustomColor: Bool,
        numberColorMode: NumberColorMode,
        onColorChange: @escaping (String?) -> Void
    ) {
        self.agentID = agentID
        self.waterColor = waterColor
        self.isCustomColor = isCustomColor
        self.numberColorMode = numberColorMode
        self.onColorChange = onColorChange
        self._draftColor = State(initialValue: waterColor)
    }

    private static let curatedSwatches: [(String, String)] = [
        ("#10A37F", "翡翠绿"),
        ("#3B82F6", "宝石蓝"),
        ("#7C5CFF", "棱镜紫"),
        ("#06B6D4", "晴空青"),
        ("#F97316", "琥珀橙"),
        ("#EC4899", "珊瑚粉")
    ]

    private var activeHex: String {
        draftColor.srgbHexString
    }

    private var previewNumberColor: Color {
        switch numberColorMode {
        case .smartInvert, .smokeGray, .obsidianBlack, .white:
            return .white
        case .adaptiveInk:
            return Color(nsColor: draftColor.adaptiveDigitColor(isDarkIcon: false))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // Mini water + complementary digit live preview swatch
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(nsColor: draftColor).opacity(0.45),
                                    Color(nsColor: draftColor).opacity(0.88)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text("68")
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(previewNumberColor)
                        .shadow(color: .black.opacity(0.55), radius: 2, y: 0.5)
                }
                .frame(width: 34, height: 28)

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(agentID.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(isCustomColor ? "自定义 \(activeHex)" : "默认 · \(agentID.themeColorName)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }

            HStack(spacing: 6) {
                ForEach(MineralColorPreset.curated) { preset in
                    let isSelected = activeHex.caseInsensitiveCompare(preset.hex) == .orderedSame
                    let swatchColor = Color(nsColor: preset.nsColor)
                    Button {
                        if preset.hex.caseInsensitiveCompare(agentID.defaultAccentHex) == .orderedSame {
                            draftColor = agentID.defaultAccentColor
                            onColorChange(nil)
                        } else {
                            draftColor = preset.nsColor
                            onColorChange(preset.hex)
                        }
                    } label: {
                        Circle()
                            .fill(swatchColor)
                            .frame(width: 19, height: 19)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(isSelected ? 0.95 : 0.42), lineWidth: isSelected ? 2 : 0.75)
                            )
                            .shadow(color: swatchColor.opacity(isSelected ? 0.48 : 0.16), radius: isSelected ? 2.5 : 1)
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help(preset.name)
                }
            }

            Divider().opacity(0.45)

            HStack {
                ColorPicker(
                    "色盘",
                    selection: Binding(
                        get: { Color(nsColor: draftColor) },
                        set: { newColor in
                            draftColor = NSColor(newColor)
                            scheduleThrottledColorCommit()
                        }
                    ),
                    supportsOpacity: false
                )
                .font(.system(size: 11.5))

                Spacer()

                if isCustomColor {
                    Button("恢复主题色") {
                        draftColor = agentID.defaultAccentColor
                        onColorChange(nil)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .focusEffectDisabled()
                }
            }
        }
        .padding(12)
        .frame(width: 210)
        .onDisappear {
            if hasPendingCommit {
                hasPendingCommit = false
                onColorChange(draftColor.srgbHexString)
            }
        }
    }

    private func scheduleThrottledColorCommit() {
        hasPendingCommit = true
        guard !isCommitLoopRunning else { return }
        isCommitLoopRunning = true
        Task { @MainActor in
            while hasPendingCommit {
                hasPendingCommit = false
                onColorChange(draftColor.srgbHexString)
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            isCommitLoopRunning = false
        }
    }
}

// MARK: - 32 Mainstream AI & Coding Agents Selector Sheet (Native Liquid Glass + Fixed-Width Zero-Jitter Grid)

private struct AgentCatalogSheet: View {
    @ObservedObject var store: AgentGaugeStore
    @Binding var isPresented: Bool

    @State private var searchText: String = ""
    @State private var showInstalledOnly: Bool = false

    private let installedCount: Int = AgentID.allCases.filter(\.isInstalledOnMac).count
    private static let contentWidth: CGFloat = 420
    private static let columnSpacing: CGFloat = 8
    private static let tileWidth: CGFloat = (contentWidth - columnSpacing) / 2.0 // Exact 206.0pt invariant width!

    private var filteredAgents: [AgentID] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return AgentID.allCases.filter { id in
            if showInstalledOnly && !id.isInstalledOnMac {
                return false
            }
            if q.isEmpty { return true }
            return id.displayName.lowercased().contains(q)
                || id.shortName.lowercased().contains(q)
                || id.rawValue.lowercased().contains(q)
                || id.category.rawValue.lowercased().contains(q)
        }
    }

    private func pairedRows(for items: [AgentID]) -> [[AgentID]] {
        var rows: [[AgentID]] = []
        var idx = 0
        while idx < items.count {
            let end = min(idx + 2, items.count)
            rows.append(Array(items[idx..<end]))
            idx += 2
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text("选择需要液态效果的应用")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text("支持 \(AgentID.allCases.count) 款主流 AI / Coding Agent · 本机已装 \(installedCount) 款")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("完成") {
                    isPresented = false
                }
                .controlSize(.regular)
                .appleNativeGlassButton(prominent: true)
                .focusEffectDisabled()
            }
            .frame(width: Self.contentWidth)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("搜索 Claude、Cursor、Windsurf…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(Color.primary.opacity(0.065), in: Capsule())

                SmoothCapsuleSegment(
                    options: [
                        .init(title: "全部 \(AgentID.allCases.count)", value: false),
                        .init(title: "已装 \(installedCount)", value: true)
                    ],
                    selection: $showInstalledOnly,
                    width: 156,
                    height: 26
                )
            }
            .frame(width: Self.contentWidth)

            // Hidden scroller gutter + exact 206pt fixed columns + animation-isolated swap = 0.0px stretch & 0.0ms jitter!
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(AgentCategory.allCases, id: \.self) { category in
                        let items = filteredAgents.filter { $0.category == category }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(category.rawValue)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 4)

                                let rows = pairedRows(for: items)
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                        HStack(spacing: Self.columnSpacing) {
                                            ForEach(row) { agentID in
                                                catalogTile(agentID)
                                                    .frame(width: Self.tileWidth, height: 34)
                                            }
                                            if row.count == 1 {
                                                Color.clear
                                                    .frame(width: Self.tileWidth, height: 34)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
                .frame(width: Self.contentWidth, alignment: .topLeading)
                .transaction { $0.animation = nil }
            }
            .frame(width: Self.contentWidth)
        }
        .padding(14)
        .frame(width: 448, height: 466)
    }

    private func catalogTile(_ agentID: AgentID) -> some View {
        let isPinned = store.pinnedAgents.contains(agentID)
        let isInstalled = agentID.isInstalledOnMac
        let accent = Color(nsColor: store.waterColor(for: agentID))

        return HStack(spacing: 6.5) {
            if let icon = AppIconCache.icon(for: agentID) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(accent.opacity(0.20))
                    Text(String(agentID.shortName.prefix(1)).uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                }
                .frame(width: 20, height: 20)
            }

            HStack(spacing: 4) {
                Text(agentID.shortName)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if isInstalled {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                        .help("本机已安装")
                }
            }

            Spacer(minLength: 2)

            Circle()
                .fill(accent)
                .frame(width: 6.5, height: 6.5)

            Toggle("", isOn: Binding(
                get: { isPinned },
                set: { store.setAgentPinned(agentID, pinned: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .scaleEffect(0.84)
            .frame(width: 26, height: 16)
            .labelsHidden()
            .focusEffectDisabled()
        }
        .padding(.horizontal, 8.5)
        .frame(width: Self.tileWidth, height: 34)
        .nativeGlassSurface(cornerRadius: 10)
    }
}

// MARK: - Live Dock Badge Style, Size, Tone & Switch Studio Sheet (Zero-Lag 120Hz Local Sliders + 60fps Async Metal Batch)

private struct BadgeCustomizationSheet: View {
    @ObservedObject var store: AgentGaugeStore
    @Binding var isPresented: Bool

    // Local draft slider states so 120Hz NSSlider dragging NEVER broadcasts objectWillChange across the whole app!
    @State private var draftScale: Double
    @State private var draftOpacity: Double
    @State private var previewWaterLevel: Double = 64
    @State private var previewImages: [AgentID: NSImage] = [:]
    @State private var needsPreviewRender = false
    @State private var isPreviewLoopRunning = false

    private let previewAgents: [AgentID]

    init(store: AgentGaugeStore, isPresented: Binding<Bool>) {
        self.store = store
        self._isPresented = isPresented
        self._draftScale = State(initialValue: store.badgeScale)
        self._draftOpacity = State(initialValue: store.badgeOpacity)

        var candidates: [AgentID] = []
        for id in [AgentID.antigravity, .cursor, .workbuddy, .codex, .claude, .grokbot, .deepseek] {
            if id.installedAppURL != nil && !candidates.contains(id) {
                candidates.append(id)
            }
            if candidates.count == 3 { break }
        }
        if candidates.count < 3 {
            for id in store.pinnedAgents where id.installedAppURL != nil && !candidates.contains(id) {
                candidates.append(id)
                if candidates.count == 3 { break }
            }
        }
        self.previewAgents = candidates
    }

    private var previewRenderKey: String {
        "\(Int(round(previewWaterLevel)))-\(store.showDockBadge)-\(store.showPercentageSign)-\(store.numberColorMode.rawValue)-\(store.badgeStyle.rawValue)-\(Int(round(draftScale * 100)))-\(Int(round(draftOpacity * 100)))"
    }

    private var isPureTextStyle: Bool {
        store.badgeStyle == .haloText || store.badgeStyle == .pureSplitText
    }

    private func commitDraftSliders() {
        if abs(store.badgeScale - draftScale) > 0.001 {
            store.badgeScale = draftScale
        }
        if abs(store.badgeOpacity - draftOpacity) > 0.001 {
            store.badgeOpacity = draftOpacity
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text("图标余量 · 样式与大小自定义")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text("精选 11 款水波液位、光学光圈、LED 点阵与灵动微岛样式 · 实时同步 Dock")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Button("恢复默认") {
                        store.resetBadgeCustomization()
                        draftScale = store.badgeScale
                        draftOpacity = store.badgeOpacity
                        previewWaterLevel = 64
                    }
                    .controlSize(.small)
                    .appleNativeGlassButton()
                    .focusEffectDisabled()

                    Button("完成") {
                        commitDraftSliders()
                        isPresented = false
                    }
                    .controlSize(.small)
                    .appleNativeGlassButton(prominent: true)
                    .focusEffectDisabled()
                }
            }

            // Live 256x256 Retina Metal Preview Stage (Zoom + 1:1 Real Dock Size + Water Slider)
            VStack(spacing: 7) {
                HStack(alignment: .top, spacing: 12) {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(previewAgents) { id in
                            VStack(spacing: 4) {
                                livePreviewImage(for: id, size: 58)
                                Text(id.shortName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .frame(width: 66)
                        }
                    }

                    Spacer(minLength: 8)

                    if let first = previewAgents.first {
                        Divider().frame(height: 58).opacity(0.35)

                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                ForEach(previewAgents.prefix(2)) { id in
                                    livePreviewImage(for: id, size: 42)
                                }
                            }
                            .frame(height: 58, alignment: .center)

                            Text("1:1 真实 Dock 尺寸")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .id(first.rawValue)
                        }
                        .padding(.horizontal, 4)
                    }
                }

                Divider().opacity(0.35)

                HStack(spacing: 8) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                    Text("拖动测试水位")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Slider(value: $previewWaterLevel, in: 8...94)
                        .controlSize(.small)
                    Text("\(Int(round(previewWaterLevel)))%")
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .nativeGlassSurface(cornerRadius: 13)

            // 3 Independent Display Toggles: In-Icon Badge, % Sign, Hover Detail Card
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Text("图标内显示余量")
                        .font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 2)
                    Toggle("", isOn: $store.showDockBadge)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .focusEffectDisabled()
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 15).opacity(0.4)

                HStack(spacing: 5) {
                    Text("显示 % 号")
                        .font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 2)
                    Toggle("", isOn: $store.showPercentageSign)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .focusEffectDisabled()
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 15).opacity(0.4)

                HStack(spacing: 5) {
                    Text("上方悬停详情")
                        .font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 2)
                    Toggle("", isOn: Binding(
                        get: { store.tooltipDetailMode != .off },
                        set: { store.setHoverTooltipEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .focusEffectDisabled()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .nativeGlassSurface(cornerRadius: 11)

            // Size & Frosted Opacity Sliders (Local @State during drag -> 0ms main-thread overhead!)
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text("字号与组件大小")
                        .font(.system(size: 11.5, weight: .medium))
                        .frame(width: 88, alignment: .leading)
                    Slider(value: $draftScale, in: 0.65...1.80) { editing in
                        if !editing { commitDraftSliders() }
                    }
                    .controlSize(.small)
                    Text("\(Int(round(draftScale * 100)))%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .frame(width: 40, alignment: .trailing)
                }

                HStack(spacing: 8) {
                    Text("底座与衬底浓度")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(isPureTextStyle ? .tertiary : .primary)
                        .frame(width: 88, alignment: .leading)
                    Slider(value: $draftOpacity, in: 0.40...0.98) { editing in
                        if !editing { commitDraftSliders() }
                    }
                    .controlSize(.small)
                    .disabled(isPureTextStyle)
                    Text("\(Int(round(draftOpacity * 100)))%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isPureTextStyle ? .tertiary : .primary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .nativeGlassSurface(cornerRadius: 11)
            .opacity(store.showDockBadge ? 1.0 : 0.48)

            // Equatable Visual Tone Swatches (Skipped completely during slider drags!)
            BadgeToneSelectorSection(
                selectedMode: store.numberColorMode,
                isEnabled: store.showDockBadge
            ) { chosen in
                store.numberColorMode = chosen
            }
            .equatable()

            // Equatable Fixed-Row Style Grid (Skipped completely during slider drags!)
            BadgeStyleGridSection(
                selectedStyle: store.badgeStyle,
                isEnabled: store.showDockBadge
            ) { chosen in
                store.badgeStyle = chosen
                if !store.showDockBadge {
                    store.showDockBadge = true
                }
            }
            .equatable()
        }
        .padding(14)
        .frame(width: 484, height: 528)
        .onAppear {
            triggerCoalescedPreviewRender()
        }
        .onChange(of: previewRenderKey) { _, _ in
            triggerCoalescedPreviewRender()
        }
        .onDisappear {
            commitDraftSliders()
        }
    }

    private func triggerCoalescedPreviewRender() {
        needsPreviewRender = true
        guard !isPreviewLoopRunning else { return }
        isPreviewLoopRunning = true

        Task { @MainActor in
            while needsPreviewRender {
                needsPreviewRender = false
                let batchItems = makeCurrentPreviewBatchItems()
                let cgMap = await NativeIconRenderer.shared.renderPreviewBatchAsync(batchItems)
                var updated = previewImages
                for (id, cg) in cgMap {
                    updated[id] = NSImage(cgImage: cg, size: NSSize(width: 128, height: 128))
                }
                previewImages = updated
                try? await Task.sleep(nanoseconds: 14_000_000)
            }
            isPreviewLoopRunning = false
        }
    }

    private func makeCurrentPreviewBatchItems() -> [NativeIconRenderer.PreviewBatchItem] {
        let level = previewWaterLevel
        let showBadge = store.showDockBadge
        let showPct = store.showPercentageSign
        let colorMode = store.numberColorMode
        let style = store.badgeStyle
        let scale = CGFloat(draftScale)
        let opacity = CGFloat(draftOpacity)

        return previewAgents.map { agentID in
            let appURL = agentID.installedAppURL ?? Bundle.main.bundleURL
            let demoReset: String = switch agentID {
            case .antigravity: "19h 0m"
            case .cursor:      "5d 4h"
            case .workbuddy:   "9d 3h"
            default:           "19h 0m"
            }
            let demoWindows: [QuotaWindow] = [
                QuotaWindow(label: "5h 限额", remainingPercent: level, resetText: demoReset, isPrimary: true),
                QuotaWindow(label: "周限额", remainingPercent: min(96, max(24, level * 0.65 + 32)), resetText: "5d 4h", isPrimary: false)
            ]
            let snap: QuotaSnapshot = {
                if agentID == .workbuddy {
                    let credits = max(120, Int(round(level * 60.0)))
                    return QuotaSnapshot(
                        agentID: .workbuddy,
                        remainingPercent: level,
                        creditsRemaining: credits,
                        creditsTotal: 6000,
                        resetText: demoReset,
                        windows: demoWindows,
                        sourceDescription: "preview"
                    )
                }
                return QuotaSnapshot(
                    agentID: agentID,
                    remainingPercent: level,
                    resetText: demoReset,
                    windows: demoWindows,
                    sourceDescription: "preview"
                )
            }()

            let params = IconRenderParams(
                waveTime: 1.55,
                bubbleTime: 2.25,
                hoverAlpha: 1.0,
                tilt: 0.03,
                ripple: 0.06,
                animate: true,
                showDockBadge: showBadge,
                showPercentageSign: showPct,
                waterTintHex: store.customWaterColors[agentID],
                numberColorMode: colorMode,
                badgeStyle: style,
                badgeScale: scale,
                badgeOpacity: opacity
            )
            return NativeIconRenderer.PreviewBatchItem(
                agentID: agentID,
                appURL: appURL,
                snapshot: snap,
                params: params
            )
        }
    }

    @ViewBuilder
    private func livePreviewImage(for agentID: AgentID, size: CGFloat) -> some View {
        if let img = previewImages[agentID] ?? AppIconCache.icon(for: agentID) {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        }
    }
}

private struct BadgeToneSelectorSection: View, Equatable {
    let selectedMode: NumberColorMode
    let isEnabled: Bool
    let onSelect: (NumberColorMode) -> Void

    nonisolated static func == (lhs: BadgeToneSelectorSection, rhs: BadgeToneSelectorSection) -> Bool {
        lhs.selectedMode == rhs.selectedMode && lhs.isEnabled == rhs.isEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("底座与水体色调")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 3)

            HStack(spacing: 6) {
                ForEach(NumberColorMode.studioCases) { mode in
                    let isSelected = (selectedMode == mode)
                    Button {
                        onSelect(mode)
                    } label: {
                        HStack(spacing: 5.5) {
                            toneSwatch(for: mode)
                            Text(mode.title)
                                .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .nativeGlassSquareButton(
                            cornerRadius: 8.5,
                            tint: isSelected ? Color.accentColor.opacity(0.20) : nil
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                                .strokeBorder(isSelected ? Color.accentColor.opacity(0.65) : Color.clear, lineWidth: 1.1)
                        )
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                }
            }
        }
        .opacity(isEnabled ? 1.0 : 0.48)
    }

    @ViewBuilder
    private func toneSwatch(for mode: NumberColorMode) -> some View {
        switch mode {
        case .smartInvert:
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
        case .smokeGray:
            Circle()
                .fill(Color(white: 0.52))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.75), lineWidth: 1.0))
                .frame(width: 11, height: 11)
        case .obsidianBlack:
            Circle()
                .fill(Color(white: 0.14))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.0))
                .frame(width: 11, height: 11)
        case .adaptiveInk, .white:
            Circle()
                .fill(Color.cyan)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.80), lineWidth: 1.0))
                .frame(width: 11, height: 11)
        }
    }
}

private struct BadgeStyleGridSection: View, Equatable {
    let selectedStyle: DockBadgeStyle
    let isEnabled: Bool
    let onSelect: (DockBadgeStyle) -> Void

    nonisolated static func == (lhs: BadgeStyleGridSection, rhs: BadgeStyleGridSection) -> Bool {
        lhs.selectedStyle == rhs.selectedStyle && lhs.isEnabled == rhs.isEnabled
    }

    private static let styleRows: [[DockBadgeStyle]] = {
        let all = DockBadgeStyle.allCases
        var rows: [[DockBadgeStyle]] = []
        var idx = 0
        while idx < all.count {
            let end = min(idx + 4, all.count)
            rows.append(Array(all[idx..<end]))
            idx += 4
        }
        return rows
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("余量展示样式（水波液位 · 精密仪表 · 灵动微岛）")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 3)

            VStack(spacing: 6) {
                ForEach(Array(Self.styleRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        ForEach(row) { style in
                            styleTile(style)
                        }
                        if row.count < 4 {
                            ForEach(0..<(4 - row.count), id: \.self) { _ in
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 31)
                            }
                        }
                    }
                }
            }
        }
        .opacity(isEnabled ? 1.0 : 0.48)
    }

    private func styleTile(_ style: DockBadgeStyle) -> some View {
        let isSelected = (selectedStyle == style)
        return Button {
            onSelect(style)
        } label: {
            HStack(spacing: 5.5) {
                BadgeStyleMiniDiagram(style: style, isSelected: isSelected)
                Text(style.shortTitle)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7.5)
            .frame(maxWidth: .infinity)
            .frame(height: 31)
            .nativeGlassSquareButton(
                cornerRadius: 8.5,
                tint: isSelected ? Color.accentColor.opacity(0.20) : nil
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.65) : Color.clear, lineWidth: 1.1)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(style.title)
    }
}

// MARK: - Miniature Squircle Geometry Icon for All 11 Curated DockBadgeStyles

private struct BadgeStyleMiniDiagram: View {
    let style: DockBadgeStyle
    let isSelected: Bool

    var body: some View {
        let fg = isSelected ? Color.accentColor : Color.secondary
        let squircle = RoundedRectangle(cornerRadius: 4.2, style: .continuous)

        ZStack {
            squircle
                .fill(Color.primary.opacity(0.06))

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                // Signature optical liquid water base across ALL 11 styles
                Rectangle()
                    .fill(fg.opacity(0.22))
                    .frame(width: w, height: h * 0.44)
                    .position(x: w * 0.50, y: h * 0.78)

                switch style {
                case .refTopTimerScrim:
                    Rectangle()
                        .fill(fg.opacity(0.65))
                        .frame(width: w, height: h * 0.25)
                        .position(x: w * 0.50, y: h * 0.125)
                    Text("37")
                        .font(.system(size: 6.2, weight: .black, design: .rounded))
                        .foregroundStyle(fg)
                        .position(x: w * 0.36, y: h * 0.76)

                case .pureSplitText:
                    Text("84")
                        .font(.system(size: 7.4, weight: .black, design: .rounded))
                        .foregroundStyle(fg)
                        .underline()
                        .position(x: w * 0.50, y: h * 0.55)

                case .haloText:
                    Text("84")
                        .font(.system(size: 7.4, weight: .black, design: .rounded))
                        .foregroundStyle(fg)
                        .position(x: w * 0.50, y: h * 0.56)

                case .concentricAutoDodge:
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(fg)
                        .frame(width: w * 0.56, height: h * 0.34)
                        .position(x: w * 0.38, y: h * 0.72)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 5.5, weight: .bold))
                        .foregroundStyle(fg.opacity(0.85))
                        .position(x: w * 0.38, y: h * 0.30)

                case .apertureSweep:
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(fg)
                        .position(x: w * 0.50, y: h * 0.50)

                case .retroLEDMatrix:
                    RoundedRectangle(cornerRadius: 2.4, style: .continuous)
                        .fill(fg.opacity(0.25))
                        .overlay(
                            HStack(spacing: 1.4) {
                                ForEach(0..<4, id: \.self) { i in
                                    Circle()
                                        .fill(i < 3 ? fg : fg.opacity(0.35))
                                        .frame(width: 2.1, height: 2.1)
                                }
                            }
                        )
                        .frame(width: w * 0.82, height: h * 0.38)
                        .position(x: w * 0.50, y: h * 0.72)

                case .dualTrackHUD:
                    VStack(alignment: .leading, spacing: 1.8) {
                        Capsule().fill(fg).frame(width: w * 0.54, height: 2.1)
                        Capsule().fill(fg.opacity(0.65)).frame(width: w * 0.68, height: 2.1)
                    }
                    .position(x: w * 0.48, y: h * 0.72)

                case .braunAnalogNeedle:
                    Circle()
                        .trim(from: 0.58, to: 0.92)
                        .stroke(fg.opacity(0.65), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                        .frame(width: w * 0.80, height: h * 0.80)
                        .position(x: w * 0.50, y: h * 0.82)
                    Capsule()
                        .fill(Color.orange)
                        .frame(width: 1.4, height: h * 0.42)
                        .rotationEffect(.degrees(22))
                        .position(x: w * 0.56, y: h * 0.62)

                case .bottomPrismCells:
                    HStack(spacing: 1.3) {
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 0.9)
                                .fill(i < 3 ? fg : fg.opacity(0.28))
                                .frame(width: 2.6, height: 3.4)
                        }
                    }
                    .position(x: w * 0.50, y: h * 0.76)

                case .topDynamicIsland:
                    Capsule()
                        .fill(fg)
                        .frame(width: w * 0.68, height: h * 0.30)
                        .position(x: w * 0.50, y: h * 0.25)

                case .topEnergyBrow:
                    Circle()
                        .trim(from: 0.60, to: 0.90)
                        .stroke(fg, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        .frame(width: w * 0.86, height: h * 0.86)
                        .position(x: w * 0.50, y: h * 0.56)
                }
            }
            .clipShape(squircle)

            squircle
                .strokeBorder(Color.primary.opacity(0.24), lineWidth: 0.8)
        }
        .frame(width: 17, height: 17)
    }
}
