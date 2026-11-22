import AgentGaugeCore
import AppKit
import Combine
import QuartzCore
import SwiftUI

@main
@MainActor
final class AgentGaugeAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    static func main() {
        let app = NSApplication.shared
        let delegate = AgentGaugeAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private var promoPopoverAgent: AgentID? {
        for arg in CommandLine.arguments where arg.hasPrefix("--promo-popover=") {
            let raw = String(arg.dropFirst("--promo-popover=".count))
            return AgentID(rawValue: raw) ?? .antigravity
        }
        return nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure any older running instance (e.g. v1.1.0–v1.2.1 in memory after Finder drag-replace) yields cleanly!
        UpdateManager.terminateOlderRunningInstancesIfNeeded()

        if CommandLine.arguments.contains("--promo-dark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        let store = AgentGaugeStore.shared
        if CommandLine.arguments.contains("--promo-demo-data") {
            store.enablePromoDemoMode()
        }

        setupPopover()
        setupStatusItem()
        setupSignalHandlers()

        store.start()
        if !CommandLine.arguments.contains("--promo-demo-data") {
            UpdateManager.shared.start()
        }

        if promoPopoverAgent != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
                guard let self, let btn = self.statusItem.button else { return }
                self.popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
                self.popover.contentViewController?.view.window?.makeKey()
                self.popover.contentViewController?.view.window?.makeFirstResponder(nil)
            }
        } else if !store.accessibilityTrusted
            || CommandLine.arguments.contains("--open-settings")
            || CommandLine.arguments.contains("--promo-badge-studio") {
            openSettingsWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        UpdateManager.shared.stop()
        AgentGaugeStore.shared.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindow()
        return true
    }

    private func setupPopover() {
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 448, height: 344)
        pop.behavior = (promoPopoverAgent != nil) ? .applicationDefined : .transient
        pop.animates = (promoPopoverAgent == nil)

        let rootView = MenuBarPopoverView(
            onOpenSettings: { [weak self] in
                self?.popover.performClose(nil)
                self?.openSettingsWindow()
            },
            onOpenLogin: { [weak self] agentID in
                self?.popover.performClose(nil)
                AgentGaugeStore.shared.openWebLogin(for: agentID)
            },
            onQuit: { [weak self] in
                self?.popover.performClose(nil)
                self?.quitApp()
            },
            initialAgent: promoPopoverAgent
        )
        pop.contentViewController = NSHostingController(rootView: rootView)
        self.popover = pop
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.makeMenuBarTemplateIcon(hasUpdateDot: UpdateManager.shared.state.hasUnreadUpdate)
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        UpdateManager.shared.$state
            .map(\.hasUnreadUpdate)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] hasUpdate in
                guard let btn = self?.statusItem?.button else { return }
                btn.image = Self.makeMenuBarTemplateIcon(hasUpdateDot: hasUpdate)
                btn.image?.isTemplate = true
            }
            .store(in: &cancellables)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            AgentGaugeStore.shared.syncFastLocalStateOnUIWake()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            popover.contentViewController?.view.window?.makeFirstResponder(nil)
        }
    }

    /// Crisp 18x18 monochrome template icon matching Concept 01 (Liquid Wave Vessel + back wave + knockout bubble + optional update dot).
    private static func makeMenuBarTemplateIcon(hasUpdateDot: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            let rect = NSRect(x: 1.8, y: 1.8, width: 14.4, height: 14.4)
            let squircle = NSBezierPath(roundedRect: rect, xRadius: 3.6, yRadius: 3.6)

            NSGraphicsContext.saveGraphicsState()
            if hasUpdateDot {
                // Carve clean halo around top-right update dot so it reads sharply on any wallpaper
                let clipPath = NSBezierPath(rect: NSRect(origin: .zero, size: size))
                clipPath.windingRule = .evenOdd
                clipPath.appendOval(in: NSRect(x: 12.1, y: 12.1, width: 5.2, height: 5.2))
                clipPath.addClip()
            }

            NSColor.black.setStroke()
            squircle.lineWidth = 1.4
            squircle.stroke()

            NSGraphicsContext.saveGraphicsState()
            let inner = NSBezierPath(roundedRect: rect.insetBy(dx: 1.15, dy: 1.15), xRadius: 2.5, yRadius: 2.5)
            inner.addClip()

            let backWave = NSBezierPath()
            backWave.move(to: NSPoint(x: 2.2, y: 9.8))
            backWave.curve(
                to: NSPoint(x: 15.8, y: 9.6),
                controlPoint1: NSPoint(x: 6.2, y: 11.8),
                controlPoint2: NSPoint(x: 11.2, y: 7.8)
            )
            NSColor.black.withAlphaComponent(0.48).setStroke()
            backWave.lineWidth = 1.0
            backWave.stroke()

            let front = NSBezierPath()
            front.windingRule = .evenOdd
            front.move(to: NSPoint(x: 2.0, y: 2.0))
            front.line(to: NSPoint(x: 2.0, y: 8.2))
            front.curve(
                to: NSPoint(x: 16.0, y: 8.6),
                controlPoint1: NSPoint(x: 6.4, y: 6.4),
                controlPoint2: NSPoint(x: 11.4, y: 10.6)
            )
            front.line(to: NSPoint(x: 16.0, y: 2.0))
            front.close()

            front.appendOval(in: NSRect(x: 5.5, y: 4.1, width: 2.3, height: 2.3))

            NSColor.black.setFill()
            front.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.restoreGraphicsState()

            if hasUpdateDot {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 13.0, y: 13.0, width: 3.4, height: 3.4)).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    @objc private func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)

        if let window = settingsWindow {
            centerWindowOnActiveScreen(window)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let initialHeight = SettingsWindowMetrics.height(
            accessibilityTrusted: AgentGaugeStore.shared.accessibilityTrusted
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsWindowMetrics.width, height: initialHeight),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "AgentGauge"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.initialFirstResponder = nil
        window.collectionBehavior = [.moveToActiveSpace, .managed]
        window.isReleasedWhenClosed = false

        let rootView = SettingsWindowView { [weak window] newHeight in
            guard let window else { return }
            let currentHeight = window.frame.height
            guard abs(currentHeight - newHeight) > 0.5 else { return }
            var frame = window.frame
            let delta = newHeight - currentHeight
            frame.size.height = newHeight
            frame.origin.y -= delta
            frame.size.width = SettingsWindowMetrics.width
            window.setFrame(frame, display: true, animate: false)
        }
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        window.contentView = hosting

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if AgentGaugeStore.shared.accessibilityTrusted {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }

        self.settingsWindow = window
        centerWindowOnActiveScreen(window)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func centerWindowOnActiveScreen(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            window.center()
            return
        }
        let wSize = window.frame.size
        let x = visible.midX - wSize.width / 2.0
        let y = visible.midY - wSize.height / 2.0
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func quitApp() {
        AgentGaugeStore.shared.shutdown()
        NSApp.terminate(nil)
    }

    private func setupSignalHandlers() {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        for sig in [SIGINT, SIGTERM] {
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                AgentGaugeStore.shared.shutdown()
                NSApp.terminate(nil)
            }
            source.resume()
            objc_setAssociatedObject(self, "sig_\(sig)", source, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
