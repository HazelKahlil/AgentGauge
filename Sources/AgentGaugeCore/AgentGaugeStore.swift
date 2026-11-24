import AppKit
import Foundation
import ServiceManagement

@MainActor
public final class AgentGaugeStore: ObservableObject {
    public static let shared = AgentGaugeStore()

    @Published public var snapshots: [AgentID: QuotaSnapshot] = [:]
    @Published public var isRefreshing: Bool = false
    @Published public var accessibilityTrusted: Bool = false

    @Published public var isMasterEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMasterEnabled, forKey: "AgentGauge.masterEnabled")
            pushSettingsToOverlay()
        }
    }

    @Published public var pinnedAgents: [AgentID] {
        didSet {
            guard !promoFrozen else { return }
            UserDefaults.standard.set(pinnedAgents.map(\.rawValue), forKey: "AgentGauge.pinnedAgents.v2")
        }
    }

    @Published public var enabledAgents: Set<AgentID> {
        didSet {
            guard !promoFrozen else { return }
            UserDefaults.standard.set(enabledAgents.map(\.rawValue), forKey: "AgentGauge.enabledAgents")
            pushSettingsToOverlay()
        }
    }

    @Published public var animationIntensity: AnimationIntensity {
        didSet {
            UserDefaults.standard.set(animationIntensity.rawValue, forKey: "AgentGauge.animationIntensity")
            pushSettingsToOverlay()
        }
    }

    @Published public var showDockBadge: Bool {
        didSet {
            UserDefaults.standard.set(showDockBadge, forKey: "AgentGauge.showDockBadge")
            pushSettingsToOverlay()
        }
    }

    @Published public var showPercentageSign: Bool {
        didSet {
            UserDefaults.standard.set(showPercentageSign, forKey: "AgentGauge.showPercentageSign")
            pushSettingsToOverlay()
        }
    }

    @Published public var tooltipDetailMode: TooltipDetailMode {
        didSet {
            if tooltipDetailMode != .off {
                lastNonOffTooltipMode = tooltipDetailMode
                UserDefaults.standard.set(tooltipDetailMode.rawValue, forKey: "AgentGauge.lastNonOffTooltipMode")
            }
            UserDefaults.standard.set(tooltipDetailMode.rawValue, forKey: "AgentGauge.tooltipDetailMode")
            pushSettingsToOverlay()
        }
    }

    private var lastNonOffTooltipMode: TooltipDetailMode = .multiModel

    @Published public var antigravityPoolFocus: AntigravityPoolFocus {
        didSet {
            UserDefaults.standard.set(antigravityPoolFocus.rawValue, forKey: "AgentGauge.antigravityPoolFocus")
            let focus = antigravityPoolFocus
            let mult = antigravityUltraMultiplier
            Task.detached(priority: .userInitiated) {
                guard let updated = AntigravityProvider.reevaluateFromCache(poolFocus: focus, ultraMultiplier: mult) else { return }
                await MainActor.run {
                    let store = AgentGaugeStore.shared
                    guard !store.promoFrozen else { return }
                    store.snapshots[.antigravity] = updated
                    store.overlayManager.updateSnapshots(store.snapshots)
                }
            }
        }
    }

    @Published public var antigravityUltraMultiplier: AntigravityUltraMultiplier {
        didSet {
            UserDefaults.standard.set(antigravityUltraMultiplier.rawValue, forKey: "AgentGauge.antigravityUltraMultiplier")
            let focus = antigravityPoolFocus
            let mult = antigravityUltraMultiplier
            Task.detached(priority: .userInitiated) {
                guard let updated = AntigravityProvider.reevaluateFromCache(poolFocus: focus, ultraMultiplier: mult) else { return }
                await MainActor.run {
                    let store = AgentGaugeStore.shared
                    guard !store.promoFrozen else { return }
                    store.snapshots[.antigravity] = updated
                    store.overlayManager.updateSnapshots(store.snapshots)
                }
            }
        }
    }

    @Published public var numberColorMode: NumberColorMode {
        didSet {
            UserDefaults.standard.set(numberColorMode.rawValue, forKey: "AgentGauge.numberColorMode")
            pushSettingsToOverlay()
        }
    }

    @Published public var badgeStyle: DockBadgeStyle {
        didSet {
            UserDefaults.standard.set(badgeStyle.rawValue, forKey: "AgentGauge.badgeStyle")
            pushSettingsToOverlay()
        }
    }

    @Published public var badgeScale: Double {
        didSet {
            scheduleDebouncedSliderPersist()
            pushSettingsToOverlay()
        }
    }

    @Published public var badgeOpacity: Double {
        didSet {
            scheduleDebouncedSliderPersist()
            pushSettingsToOverlay()
        }
    }

    private var sliderPersistWorkItem: DispatchWorkItem?

    private func scheduleDebouncedSliderPersist() {
        sliderPersistWorkItem?.cancel()
        let scale = badgeScale
        let opacity = badgeOpacity
        let item = DispatchWorkItem {
            UserDefaults.standard.set(scale, forKey: "AgentGauge.badgeScale")
            UserDefaults.standard.set(opacity, forKey: "AgentGauge.badgeOpacity")
        }
        sliderPersistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    @Published public var customWaterColors: [AgentID: String] {
        didSet {
            scheduleDebouncedColorPersist()
            pushSettingsToOverlay()
        }
    }

    private var colorPersistWorkItem: DispatchWorkItem?

    private func scheduleDebouncedColorPersist() {
        colorPersistWorkItem?.cancel()
        let snapshotColors = customWaterColors
        let item = DispatchWorkItem {
            var dict: [String: String] = [:]
            for (k, v) in snapshotColors {
                dict[k.rawValue] = v
            }
            UserDefaults.standard.set(dict, forKey: "AgentGauge.customWaterColors")
        }
        colorPersistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    @Published public var uiAccentHex: String {
        didSet {
            scheduleDebouncedUIAccentPersist()
        }
    }

    private var uiAccentPersistWorkItem: DispatchWorkItem?

    private func scheduleDebouncedUIAccentPersist() {
        uiAccentPersistWorkItem?.cancel()
        let hex = uiAccentHex
        let item = DispatchWorkItem {
            UserDefaults.standard.set(hex, forKey: "AgentGauge.uiAccentHex")
        }
        uiAccentPersistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: item)
    }

    public var uiAccentColor: NSColor {
        NSColor.fromHex(uiAccentHex) ?? NSColor.fromHex(MineralColorPreset.defaultUIAccentHex) ?? .systemBlue
    }

    public func setUIAccentHex(_ hex: String?) {
        let resolved = (hex?.isEmpty == false) ? hex! : MineralColorPreset.defaultUIAccentHex
        guard uiAccentHex.caseInsensitiveCompare(resolved) != .orderedSame else { return }
        uiAccentHex = resolved
    }

    @Published public var launchAtLogin: Bool = false

    private var webAuthVerified: Set<AgentID> {
        didSet {
            UserDefaults.standard.set(webAuthVerified.map(\.rawValue), forKey: "AgentGauge.webAuthVerified")
        }
    }

    private let overlayManager = OverlayManager()
    private let providers: [any UsageProvider] = ProviderRegistry.allProviders()
    private var refreshTimer: Timer?
    private var permissionCheckTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isSystemSleeping: Bool = false
    private var lastFastWakeSyncAt: Date = .distantPast

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "AgentGauge.masterEnabled") != nil {
            self.isMasterEnabled = defaults.bool(forKey: "AgentGauge.masterEnabled")
        } else {
            self.isMasterEnabled = true
        }

        // Only auto-discover authentic AI Coding Agent / Foundation Model Token-Plan apps installed on this Mac
        let autoDiscoverCandidates: [AgentID] = [
            .antigravity, .cursor, .grokbot, .codex, .claude, .workbuddy,
            .gemini, .grok, .deepseek, .windsurf, .trae, .kiro, .qoder,
            .zed, .vscode, .warp, .kimi, .chatglm, .qwen, .doubao, .minimax, .perplexity
        ]
        let needsPureVendorSync = !defaults.bool(forKey: "AgentGauge.migratedPureVendors.v1")

        let resolvedPinned: [AgentID]
        if let savedPinned = defaults.stringArray(forKey: "AgentGauge.pinnedAgents.v2") {
            // compactMap(AgentID.init) automatically purges removed non-vendor browsers/shells (kaze, multica, quark, muse, chatcut, etc.)!
            var parsed = savedPinned.compactMap(AgentID.init(rawValue:))
            if parsed.isEmpty { parsed = AgentID.defaultCoreSet }
            if needsPureVendorSync {
                for extra in autoDiscoverCandidates where extra.isInstalledOnMac && !parsed.contains(extra) {
                    parsed.append(extra)
                }
            }
            resolvedPinned = parsed
        } else {
            var initial = autoDiscoverCandidates.filter { $0.isInstalledOnMac }
            if initial.isEmpty {
                initial = AgentID.defaultCoreSet
            }
            resolvedPinned = initial
        }
        self.pinnedAgents = resolvedPinned

        if let savedRaw = defaults.stringArray(forKey: "AgentGauge.enabledAgents") {
            var set = Set(savedRaw.compactMap(AgentID.init(rawValue:)))
            if needsPureVendorSync {
                for extra in autoDiscoverCandidates where extra.isInstalledOnMac {
                    set.insert(extra)
                }
                defaults.set(true, forKey: "AgentGauge.migratedPureVendors.v1")
                defaults.set(resolvedPinned.map(\.rawValue), forKey: "AgentGauge.pinnedAgents.v2")
                defaults.set(Array(set).map(\.rawValue), forKey: "AgentGauge.enabledAgents")
            }
            self.enabledAgents = set
        } else {
            defaults.set(true, forKey: "AgentGauge.migratedPureVendors.v1")
            self.enabledAgents = Set(resolvedPinned)
        }

        if let animRaw = defaults.string(forKey: "AgentGauge.animationIntensity"),
           let anim = AnimationIntensity(rawValue: animRaw) {
            self.animationIntensity = anim
        } else {
            self.animationIntensity = .always
        }

        if defaults.object(forKey: "AgentGauge.showDockBadge") != nil {
            self.showDockBadge = defaults.bool(forKey: "AgentGauge.showDockBadge")
        } else {
            self.showDockBadge = true
        }

        if defaults.object(forKey: "AgentGauge.showPercentageSign") != nil {
            self.showPercentageSign = defaults.bool(forKey: "AgentGauge.showPercentageSign")
        } else {
            self.showPercentageSign = true
        }

        if let lastRaw = defaults.string(forKey: "AgentGauge.lastNonOffTooltipMode"),
           let lastMode = TooltipDetailMode(rawValue: lastRaw),
           lastMode != .off {
            self.lastNonOffTooltipMode = lastMode
        } else {
            self.lastNonOffTooltipMode = .multiModel
        }

        if let tipRaw = defaults.string(forKey: "AgentGauge.tooltipDetailMode"),
           let tipMode = TooltipDetailMode(rawValue: tipRaw) {
            self.tooltipDetailMode = tipMode
            if tipMode != .off {
                self.lastNonOffTooltipMode = tipMode
            }
        } else {
            self.tooltipDetailMode = .multiModel
        }

        if let poolRaw = defaults.string(forKey: "AgentGauge.antigravityPoolFocus"),
           let poolMode = AntigravityPoolFocus(rawValue: poolRaw) {
            self.antigravityPoolFocus = poolMode
        } else {
            self.antigravityPoolFocus = .autoActiveModel
        }

        if let multRaw = defaults.string(forKey: "AgentGauge.antigravityUltraMultiplier"),
           let multMode = AntigravityUltraMultiplier(rawValue: multRaw) {
            self.antigravityUltraMultiplier = multMode
        } else {
            self.antigravityUltraMultiplier = .auto
        }

        if !defaults.bool(forKey: "AgentGauge.migratedSmartInvert.v1") {
            defaults.set(true, forKey: "AgentGauge.migratedSmartInvert.v1")
            defaults.set(NumberColorMode.smartInvert.rawValue, forKey: "AgentGauge.numberColorMode")
            self.numberColorMode = .smartInvert
        } else if let numRaw = defaults.string(forKey: "AgentGauge.numberColorMode"),
                  let numMode = NumberColorMode(rawValue: numRaw) {
            self.numberColorMode = numMode
        } else {
            self.numberColorMode = .smartInvert
        }

        if let styleRaw = defaults.string(forKey: "AgentGauge.badgeStyle"),
           let style = DockBadgeStyle(rawValue: styleRaw) {
            self.badgeStyle = style
        } else {
            self.badgeStyle = .refTopTimerScrim
        }

        if defaults.object(forKey: "AgentGauge.badgeScale") != nil {
            self.badgeScale = max(0.65, min(1.80, defaults.double(forKey: "AgentGauge.badgeScale")))
        } else {
            self.badgeScale = 1.50
        }

        if defaults.object(forKey: "AgentGauge.badgeOpacity") != nil {
            self.badgeOpacity = max(0.40, min(0.98, defaults.double(forKey: "AgentGauge.badgeOpacity")))
        } else {
            self.badgeOpacity = 0.85
        }

        if let savedColors = defaults.dictionary(forKey: "AgentGauge.customWaterColors") as? [String: String] {
            var parsed: [AgentID: String] = [:]
            var cleanedDict: [String: String] = [:]
            for (k, v) in savedColors {
                if let id = AgentID(rawValue: k) {
                    parsed[id] = v
                    cleanedDict[k] = v
                }
            }
            if cleanedDict.count != savedColors.count {
                defaults.set(cleanedDict, forKey: "AgentGauge.customWaterColors")
            }
            self.customWaterColors = parsed
        } else {
            self.customWaterColors = [:]
        }

        if let savedUIAccent = defaults.string(forKey: "AgentGauge.uiAccentHex"), !savedUIAccent.isEmpty {
            self.uiAccentHex = savedUIAccent
        } else {
            self.uiAccentHex = MineralColorPreset.defaultUIAccentHex
        }

        if let savedVerified = defaults.stringArray(forKey: "AgentGauge.webAuthVerified") {
            self.webAuthVerified = Set(savedVerified.compactMap(AgentID.init(rawValue:)))
        } else {
            self.webAuthVerified = []
        }

        self.accessibilityTrusted = overlayManager.isAccessibilityTrusted
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    public func start() {
        AppLogger.shared.log("System", "AgentGauge v1.3.2 已启动 · AX=\(overlayManager.isAccessibilityTrusted)")
        overlayManager.onWakeNearDock = { [weak self] in
            self?.syncFastLocalStateOnUIWake()
        }
        pushSettingsToOverlay()
        overlayManager.start()
        registerSleepWakeObservers()

        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isSystemSleeping, !self.overlayManager.isActivelyHovering else { return }
                await self.refreshAll()
            }
        }

        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isSystemSleeping else { return }
                let trusted = self.overlayManager.isAccessibilityTrusted
                if trusted != self.accessibilityTrusted {
                    self.accessibilityTrusted = trusted
                    AppLogger.shared.log("AX", trusted ? "辅助功能权限已授予" : "辅助功能权限未授予")
                }
            }
        }

        Task {
            await refreshAll()
        }
    }

    private func registerSleepWakeObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers {
            wsCenter.removeObserver(obs)
        }
        workspaceObservers.removeAll()

        let sleepNames: [Notification.Name] = [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ]
        for name in sleepNames {
            let token = wsCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.isSystemSleeping = true
                    self?.overlayManager.hideAll()
                }
            }
            workspaceObservers.append(token)
        }

        let wakeNames: [Notification.Name] = [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ]
        for name in wakeNames {
            let token = wsCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let wasSleeping = self.isSystemSleeping
                    self.isSystemSleeping = false
                    if wasSleeping {
                        await self.refreshAll()
                    }
                }
            }
            workspaceObservers.append(token)
        }
    }

    public func shutdown() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers {
            wsCenter.removeObserver(obs)
        }
        workspaceObservers.removeAll()
        refreshTimer?.invalidate()
        refreshTimer = nil
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
        overlayManager.cleanupAll()
        AppLogger.shared.log("System", "AgentGauge 已清理覆盖层并退出")
    }

    public func requestAccessibility() {
        overlayManager.requestAccessibilityPermission()
    }

    public func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        } catch {
            AppLogger.shared.log("System", "设置开机自启失败: \(error.localizedDescription)")
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    public func waterColor(for agentID: AgentID) -> NSColor {
        if let hex = customWaterColors[agentID], let custom = NSColor.fromHex(hex) {
            return custom
        }
        return agentID.defaultAccentColor
    }

    public func setCustomWaterColor(_ hex: String?, for agentID: AgentID) {
        if let hex, !hex.isEmpty {
            if customWaterColors[agentID]?.caseInsensitiveCompare(hex) == .orderedSame {
                return
            }
            customWaterColors[agentID] = hex
        } else {
            guard customWaterColors[agentID] != nil else { return }
            customWaterColors.removeValue(forKey: agentID)
        }
    }

    public func toggleAgent(_ agentID: AgentID, enabled: Bool) {
        if enabled {
            enabledAgents.insert(agentID)
            if !pinnedAgents.contains(agentID) {
                pinnedAgents.append(agentID)
            }
            Task { await refresh(agentID: agentID) }
        } else {
            enabledAgents.remove(agentID)
        }
    }

    public func setAgentPinned(_ agentID: AgentID, pinned: Bool) {
        if pinned {
            if !pinnedAgents.contains(agentID) {
                pinnedAgents.append(agentID)
            }
            enabledAgents.insert(agentID)
            Task { await refresh(agentID: agentID) }
        } else {
            pinnedAgents.removeAll { $0 == agentID }
            enabledAgents.remove(agentID)
        }
    }

    public func openWebLogin(for agentID: AgentID) {
        guard let url = agentID.webLoginURL else { return }
        WebUsageFetcher.shared.openLoginWindow(for: agentID, url: url) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if agentID == .workbuddy {
                    WorkBuddyProvider.invalidateCache()
                }
                self.webAuthVerified.insert(agentID)
                await self.refresh(agentID: agentID, forceWebProbe: true)
            }
        }
    }

    /// Promo capture mode: replace live snapshots with synthetic demo data (no real account info) and freeze refreshes.
    /// Never touches persisted pinned / enabled settings.
    private var promoFrozen = false

    public func enablePromoDemoMode() {
        promoFrozen = true
        pinnedAgents = [.antigravity, .cursor, .workbuddy, .deepseek, .grokbot, .gemini, .claude, .codex]
        enabledAgents = [.antigravity, .cursor, .workbuddy, .deepseek, .grokbot, .claude, .codex]
        snapshots = PromoDemoData.snapshots()
        overlayManager.updateSnapshots(snapshots)
    }

    /// Ultra-lightweight (<0.5ms off-main-thread) sync triggered when the pointer approaches the Dock or opens the Menu Bar popover:
    /// 1) Re-resolves Antigravity's active model pool (`Gemini` vs `Anthropic`) immediately after model dropdown switches;
    /// 2) Triggers background refresh for any enabled provider whose `resetsAt` deadline has just passed.
    public func syncFastLocalStateOnUIWake() {
        guard !promoFrozen, !isSystemSleeping else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFastWakeSyncAt) >= 2.0 else { return }
        lastFastWakeSyncAt = now

        if enabledAgents.contains(.antigravity) {
            let focus = antigravityPoolFocus
            Task.detached(priority: .userInitiated) {
                guard let reevaluated = AntigravityProvider.reevaluateFromCache(poolFocus: focus) else { return }
                await MainActor.run {
                    let store = AgentGaugeStore.shared
                    guard !store.promoFrozen else { return }
                    if store.snapshots[.antigravity] != reevaluated {
                        store.snapshots[.antigravity] = reevaluated
                        store.overlayManager.updateSnapshots(store.snapshots)
                    }
                }
            }
        }

        for id in enabledAgents {
            if let snap = snapshots[id], let r = snap.resetsAt, now >= r {
                Task { await refresh(agentID: id, forceWebProbe: false) }
            }
        }
    }

    public func refreshAll(forceWebProbe: Bool = false) async {
        guard !promoFrozen else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if forceWebProbe {
            ProviderRegistry.invalidateCaches(for: nil)
        }

        let activeProviders = providers.filter { enabledAgents.contains($0.agentID) }
        await withTaskGroup(of: Void.self) { group in
            for provider in activeProviders {
                group.addTask { [weak self] in
                    await self?.refreshProvider(provider, forceWebProbe: forceWebProbe)
                }
            }
        }
    }

    public func refresh(agentID: AgentID, forceWebProbe: Bool = false) async {
        guard !promoFrozen else { return }
        if forceWebProbe {
            ProviderRegistry.invalidateCaches(for: agentID)
        }
        guard let provider = providers.first(where: { $0.agentID == agentID }) else { return }
        await refreshProvider(provider, forceWebProbe: forceWebProbe)
    }

    private static let nativeLocalAgents: Set<AgentID> = [
        .codex, .antigravity, .cursor, .grokbot, .claude, .gemini,
        .vscode, .windsurf, .deepseek, .kimi, .grok
    ]

    private func refreshProvider(_ provider: any UsageProvider, forceWebProbe: Bool) async {
        guard !promoFrozen else { return }
        let id = provider.agentID

        // Only skip WorkBuddy WebView probing when neither verified nor cookies exist unless forceWebProbe is true.
        if id == .workbuddy && !forceWebProbe && !webAuthVerified.contains(id) {
            let hasSavedCookies = await WebUsageFetcher.shared.hasCookies(matchingDomainSuffixes: id.cookieDomainSuffixes)
            if !hasSavedCookies {
                let idleSnap = QuotaSnapshot(
                    agentID: id,
                    remainingPercent: nil,
                    sourceDescription: "\(id.shortName) 未连接",
                    requiresWebLogin: true,
                    errorMessage: nil
                )
                if snapshots[id]?.hasMeaningfulChange(from: idleSnap) != false {
                    snapshots[id] = idleSnap
                    overlayManager.updateSnapshots(snapshots)
                }
                return
            }
        }

        // Run provider fetch strictly off @MainActor so SQLite / File I/O / JSON parsing never blocks UI clicks!
        let fresh = await Task.detached(priority: .utility) {
            await provider.fetchSnapshot()
        }.value
        guard !promoFrozen else { return }

        if fresh.requiresWebLogin && !Self.nativeLocalAgents.contains(id) {
            webAuthVerified.remove(id)
        } else if fresh.remainingPercent != nil && !Self.nativeLocalAgents.contains(id) {
            webAuthVerified.insert(id)
        }

        let previous = snapshots[id]

        if fresh.remainingPercent != nil {
            snapshots[id] = fresh
            if fresh.hasMeaningfulChange(from: previous) {
                let valDesc = fresh.formattedTooltipValue(showPercentageSign: showPercentageSign)
                let tierTag = fresh.compactPlanBadge.map { " [\($0)]" } ?? ""
                AppLogger.shared.log(id.displayName, "\(valDesc)\(tierTag) · 重置: \(fresh.formattedCountdown()) · 来源: \(fresh.sourceDescription)")
            }
        } else if let prev = previous, prev.remainingPercent != nil, !fresh.requiresWebLogin {
            let preserved = QuotaSnapshot(
                agentID: id,
                remainingPercent: prev.remainingPercent,
                creditsRemaining: prev.creditsRemaining,
                creditsTotal: prev.creditsTotal,
                balanceDisplay: prev.balanceDisplay,
                dockBalanceShort: prev.dockBalanceShort,
                accountEmail: fresh.accountEmail ?? prev.accountEmail,
                planTier: fresh.planTier ?? prev.planTier,
                primaryLabel: prev.primaryLabel,
                resetsAt: prev.resetsAt,
                resetText: prev.resetText,
                windows: prev.windows,
                subtitle: prev.subtitle,
                isWorking: fresh.isWorking,
                sourceDescription: prev.sourceDescription,
                updatedAt: prev.updatedAt,
                requiresWebLogin: false,
                errorMessage: fresh.errorMessage
            )
            snapshots[id] = preserved
            if let err = fresh.errorMessage, err != prev.errorMessage {
                AppLogger.shared.log(id.displayName, err)
            }
        } else {
            snapshots[id] = fresh
            if let err = fresh.errorMessage, fresh.hasMeaningfulChange(from: previous) {
                AppLogger.shared.log(id.displayName, err)
            }
        }

        overlayManager.updateSnapshots(snapshots)
    }

    public func setHoverTooltipEnabled(_ enabled: Bool) {
        if enabled {
            if tooltipDetailMode == .off {
                tooltipDetailMode = lastNonOffTooltipMode
            }
        } else {
            tooltipDetailMode = .off
        }
    }

    public func resetBadgeCustomization() {
        showDockBadge = true
        showPercentageSign = true
        badgeStyle = .refTopTimerScrim
        numberColorMode = .smartInvert
        badgeScale = 1.50
        badgeOpacity = 0.85
    }

    private func pushSettingsToOverlay() {
        overlayManager.updateSettings(
            isMasterEnabled: isMasterEnabled,
            enabledAgents: enabledAgents,
            animationIntensity: animationIntensity,
            showDockBadge: showDockBadge,
            showPercentageSign: showPercentageSign,
            tooltipDetailMode: tooltipDetailMode,
            numberColorMode: numberColorMode,
            badgeStyle: badgeStyle,
            badgeScale: badgeScale,
            badgeOpacity: badgeOpacity,
            customWaterColors: customWaterColors
        )
    }
}
