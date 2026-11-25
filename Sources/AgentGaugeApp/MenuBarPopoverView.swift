import AgentGaugeCore
import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var store = AgentGaugeStore.shared
    @ObservedObject var updater = UpdateManager.shared
    let onOpenSettings: () -> Void
    let onOpenLogin: (AgentID) -> Void
    let onQuit: () -> Void
    var initialAgent: AgentID? = nil

    @State private var selectedAgent: AgentID?
    @Namespace private var sidebarNamespace

    private var activeAgent: AgentID? {
        if let sel = selectedAgent, store.pinnedAgents.contains(sel) {
            return sel
        }
        return store.pinnedAgents.first
    }

    var body: some View {
        let hasUpdateBanner = updater.state.hasUnreadUpdate

        VStack(spacing: 0) {
            if hasUpdateBanner {
                remoteUpdatePushBanner
                    .frame(height: 32)
                Divider().opacity(0.38)
            }

            // Main Two-Column Split: Left = Monitored Apps, Right = Live Liquid Gauge Dashboard
            HStack(spacing: 0) {
                leftAppList
                    .frame(width: 168)
                    .background(Color.primary.opacity(0.024))

                Divider().opacity(0.38)

                rightModelDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: hasUpdateBanner ? 270 : 302)

            Divider().opacity(0.38)

            bottomActionBar
                .frame(height: 42)
        }
        .frame(width: 448, height: 344)
        .onAppear {
            if selectedAgent == nil {
                if let initID = initialAgent, store.pinnedAgents.contains(initID) {
                    selectedAgent = initID
                } else {
                    selectedAgent = store.pinnedAgents.first
                }
            }
        }
    }

    // MARK: - Remote Push Update Banner

    @ViewBuilder
    private var remoteUpdatePushBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            switch updater.state {
            case .available(let m):
                Text(m.title ?? "发现新版本 v\(m.version)")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                popoverGlassCapsuleButton(prominent: true) {
                    Task { await updater.installUpdate(m) }
                } label: {
                    Text("一键更新")
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 4)
                }

            case .downloading(let m, let progress):
                Text("正在下载 v\(m.version)… \(Int(round(progress * 100)))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .lineLimit(1)
                Spacer(minLength: 4)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 90)

            case .installing(let m):
                Text("正在原子覆盖并重启至 v\(m.version)…")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                ProgressView()
                    .controlSize(.mini)

            case .failed(let msg, let retryable):
                Text(msg)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let m = retryable {
                    popoverGlassCapsuleButton(prominent: false) {
                        Task { await updater.installUpdate(m) }
                    } label: {
                        Text("重试")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                }

            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 12)
        .background(Color.accentColor.opacity(0.08))
    }

    // MARK: - Left Column (Monitored Applications with Silky Sliding Selection Pill)

    private var leftAppList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 3) {
                ForEach(store.pinnedAgents) { id in
                    let isSelected = (activeAgent == id)
                    let snap = store.snapshots[id]
                    let isEnabled = store.enabledAgents.contains(id)
                    let rowAccent = Color(nsColor: store.waterColor(for: id))

                    HStack(spacing: 7.5) {
                        ZStack(alignment: .bottomTrailing) {
                            if let icon = AppIconCache.icon(for: id) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 21, height: 21)
                                    .opacity(isEnabled ? 1.0 : 0.45)
                            } else {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(rowAccent.opacity(0.25))
                                    .frame(width: 21, height: 21)
                            }

                            if isEnabled && snap?.isWorking == true {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                    .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.0))
                                    .offset(x: 1.5, y: 1.5)
                            }
                        }

                        Text(id.shortName)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isEnabled ? .primary : .secondary)
                            .lineLimit(1)

                        Spacer(minLength: 2)

                        compactBadge(for: snap, isEnabled: isEnabled, isSelected: isSelected)
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 8)
                    .frame(height: 33)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.primary.opacity(0.09))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
                                )
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(rowAccent)
                                        .frame(width: 3, height: 15)
                                        .padding(.leading, 3)
                                }
                                .matchedGeometryEffect(id: "selectedSidebarRow", in: sidebarNamespace)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .onHover { hovering in
                        if hovering && selectedAgent != id {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                                selectedAgent = id
                            }
                        }
                    }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                            selectedAgent = id
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func compactBadge(for snap: QuotaSnapshot?, isEnabled: Bool, isSelected: Bool) -> some View {
        if !isEnabled {
            Text("暂停")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
        } else if let s = snap, let rem = s.remainingPercent {
            Text(s.formattedDockIconValue(showPercentageSign: store.showPercentageSign))
                .font(.system(size: 11, weight: isSelected ? .bold : .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(rem <= 15 ? Color.red : (rem <= 30 ? Color.orange : (isSelected ? .primary : .secondary)))
                .contentTransition(.numericText())
        } else if snap?.requiresWebLogin == true {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
        } else {
            Text("—")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Right Column (Selected App's Remaining Models & Quota Windows)

    private var rightModelDetail: some View {
        Group {
            if let agentID = activeAgent {
                let snap = store.snapshots[agentID]
                let waterNSColor = store.waterColor(for: agentID)
                let waterColor = Color(nsColor: waterNSColor)
                let planBadge = snap?.compactPlanBadge

                VStack(alignment: .leading, spacing: 10) {
                    // Hero Header: App Squircle + Plan Pill + Account | Big Hero Metric + Refresh
                    HStack(alignment: .center, spacing: 9) {
                        ZStack(alignment: .bottomTrailing) {
                            if let icon = AppIconCache.icon(for: agentID) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 28, height: 28)
                            } else {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(waterColor.opacity(0.22))
                                    .frame(width: 28, height: 28)
                            }

                            if snap?.isWorking == true {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 7.5, height: 7.5)
                                    .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.2))
                                    .offset(x: 1.5, y: 1.5)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5.5) {
                                Text(agentID.displayName)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .lineLimit(1)

                                if let planBadge {
                                    if agentID.supportsPlanMultiplierBadge {
                                        let email = snap?.accountEmail
                                        let currentMult = store.planMultiplier(for: agentID, email: email)
                                        Menu {
                                            ForEach(agentID.supportedMultiplierChoices) { mult in
                                                Button {
                                                    store.setPlanMultiplier(mult, for: agentID, email: email)
                                                } label: {
                                                    let labelText = mult == .auto ? "自动识别" : "\(mult.shortTitle) 倍档位"
                                                    if currentMult == mult {
                                                        Label(labelText, systemImage: "checkmark")
                                                    } else {
                                                        Text(labelText)
                                                    }
                                                }
                                            }
                                        } label: {
                                            PlanTierBadgePill(text: planBadge, accentColor: waterNSColor, size: .regular)
                                        }
                                        .menuStyle(.borderlessButton)
                                        .menuIndicator(.hidden)
                                        .fixedSize()
                                        .help("点击切换当前账号套餐倍率（按账号独立记忆）")
                                    } else {
                                        PlanTierBadgePill(text: planBadge, accentColor: waterNSColor, size: .regular)
                                    }
                                }
                            }

                            if let acctLine = accountSubtitleLine(for: snap, badge: planBadge, fallback: agentID.themeColorName) {
                                Text(acctLine)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        Spacer(minLength: 4)

                        if let s = snap, let hero = heroReadoutString(for: s) {
                            Text(hero)
                                .font(.system(size: s.isCreditsBased ? 12.5 : 15, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(semanticColor(for: s.remainingPercent ?? 100, base: waterColor, textMode: true))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .contentTransition(.numericText())
                        }

                        popoverGlassIconButton(helpText: "刷新 \(agentID.shortName)") {
                            Task { await store.refresh(agentID: agentID, forceWebProbe: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                    }

                    Divider().opacity(0.36)

                    // Models / Quota Windows Body
                    if let s = snap, s.remainingPercent != nil {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 9) {
                                if agentID == .antigravity {
                                    antigravityPoolSelector(accent: waterColor)
                                }

                                let wins = s.windows.isEmpty
                                    ? [QuotaWindow(
                                        label: "\(agentID.shortName) 总额度",
                                        remainingPercent: s.remainingPercent ?? 0,
                                        resetsAt: s.resetsAt,
                                        resetText: s.resetText,
                                        isPrimary: true
                                    )]
                                    : s.windows

                                ForEach(Array(wins.enumerated()), id: \.offset) { idx, win in
                                    modelRow(win: win, snapshot: s, isFirst: idx == 0, accent: waterColor)
                                }

                                if let sub = s.subtitle, !sub.isEmpty {
                                    HStack(spacing: 5) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(waterColor.opacity(0.85))
                                        Text(sub)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4.5)
                                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .padding(.top, 2)
                                }
                            }
                            .padding(.vertical, 2)
                            .animation(.spring(response: 0.28, dampingFraction: 0.84), value: agentID)
                        }
                    } else {
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: snap?.requiresWebLogin == true ? "person.crop.circle.badge.exclamationmark" : "waveform.path.ecg")
                                .font(.system(size: 22, weight: .light))
                                .foregroundStyle(.tertiary)

                            Text(snap?.errorMessage ?? (snap?.requiresWebLogin == true ? "尚未连接 \(agentID.shortName) 账号" : "正在探测本地状态…"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 10)

                            if agentID.webLoginURL != nil {
                                popoverGlassCapsuleButton(prominent: true) {
                                    onOpenLogin(agentID)
                                } label: {
                                    Text("立即登录连接")
                                        .font(.system(size: 11, weight: .semibold))
                                        .padding(.horizontal, 6)
                                }
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(13)
            } else {
                Text("未选择监控应用")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func heroReadoutString(for snap: QuotaSnapshot) -> String? {
        if let bal = snap.balanceDisplay {
            return bal
        }
        if let c = snap.creditsRemaining {
            if let tot = snap.creditsTotal, tot > 0 {
                return "\(c)/\(tot)"
            }
            return "\(c)"
        }
        guard let rem = snap.remainingPercent else { return nil }
        let n = QuotaSnapshot.displayPercentInt(rem)
        return store.showPercentageSign ? "\(n)%" : "\(n)"
    }

    @ViewBuilder
    private func antigravityPoolSelector(accent: Color) -> some View {
        HStack(spacing: 3) {
            ForEach(AntigravityPoolFocus.allCases) { mode in
                let isSelected = (store.antigravityPoolFocus == mode)
                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                        store.antigravityPoolFocus = mode
                    }
                } label: {
                    Text(mode.shortTitle)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .background(
                            isSelected ? accent.opacity(0.18) : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(isSelected ? accent.opacity(0.38) : Color.clear, lineWidth: 0.7)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help(mode.helpDescription)
            }
        }
        .padding(2.5)
        .background(Color.primary.opacity(0.055), in: Capsule())
    }

    private func accountSubtitleLine(for snap: QuotaSnapshot?, badge: String?, fallback: String) -> String? {
        guard let snap else { return fallback }
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

    private func semanticColor(for pct: Double, base: Color, textMode: Bool) -> Color {
        if pct <= 15 { return .red }
        if pct <= 30 { return .orange }
        return textMode ? .primary : base
    }

    private func modelRow(win: QuotaWindow, snapshot: QuotaSnapshot, isFirst: Bool, accent: Color) -> some View {
        let isFeatured = win.isPrimary || win.label.contains("周")
        let barTone = semanticColor(for: win.remainingPercent, base: accent, textMode: false)

        let valueStr: String
        if isFirst, let bal = snapshot.balanceDisplay {
            valueStr = bal
        } else if isFirst, snapshot.isCreditsBased, let c = snapshot.creditsRemaining {
            valueStr = "\(c) 积分"
        } else {
            let n = QuotaSnapshot.displayPercentInt(win.remainingPercent)
            valueStr = store.showPercentageSign ? "\(n)%" : "\(n)"
        }

        return VStack(alignment: .leading, spacing: 4.5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(win.label)
                    .font(.system(size: 11.5, weight: isFeatured ? .semibold : .regular))
                    .foregroundStyle(isFeatured ? .primary : .secondary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(valueStr)
                    .font(.system(size: 11.5, weight: isFeatured ? .bold : .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(win.remainingPercent <= 15 ? Color.red : .primary)
                    .contentTransition(.numericText())

                let cd = win.formattedCountdown()
                if cd != "—" {
                    Text(cd)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.085))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [barTone.opacity(0.75), barTone],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4.5, geo.size.width * CGFloat(max(0, min(100, win.remainingPercent)) / 100.0)))
                        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: win.remainingPercent)
                }
            }
            .frame(height: isFeatured ? 5.5 : 4.5)
        }
    }

    // MARK: - Bottom Action Bar (Native macOS 26 Liquid Glass Buttons)

    private var bottomActionBar: some View {
        HStack(spacing: 8) {
            popoverGlassCapsuleButton(prominent: false) {
                store.isMasterEnabled.toggle()
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.isMasterEnabled ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 6.5, height: 6.5)
                    Text(store.isMasterEnabled ? "运行中" : "已暂停")
                        .font(.system(size: 11, weight: .medium))
                }
            }

            popoverGlassCapsuleButton(prominent: false, disabled: store.isRefreshing) {
                Task { await store.refreshAll(forceWebProbe: true) }
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                    Text("刷新")
                        .font(.system(size: 11, weight: .medium))
                }
            }

            Spacer()

            popoverGlassCapsuleButton(prominent: false) {
                onOpenSettings()
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .medium))
                    Text("设置")
                        .font(.system(size: 11, weight: .medium))
                }
            }

            popoverGlassIconButton(helpText: "退出 AgentGauge") {
                onQuit()
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 11)
    }

    // MARK: - Native macOS 26 Liquid Glass Control Helpers

    @ViewBuilder
    private func popoverGlassCapsuleButton<Label: View>(
        prominent: Bool,
        disabled: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                Button(action: action, label: label)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .disabled(disabled)
            } else {
                Button(action: action, label: label)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .disabled(disabled)
            }
        } else {
            Button(action: action) {
                label()
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(prominent ? Color.accentColor : Color.primary.opacity(0.065), in: Capsule())
                    .foregroundStyle(prominent ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .disabled(disabled)
        }
    }

    @ViewBuilder
    private func popoverGlassIconButton<Label: View>(
        helpText: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        if #available(macOS 26.0, *) {
            Button(action: action, label: label)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .help(helpText)
        } else {
            Button(action: action) {
                label()
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.065), in: Circle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help(helpText)
        }
    }
}
