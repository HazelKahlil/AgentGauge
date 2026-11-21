import AppKit
import Foundation
import WebKit

public enum WebFetchOutcome: Sendable {
    case payload(Data)
    case missingCookies
    case transientFailure
}

@MainActor
public final class WebUsageFetcher: NSObject, WKNavigationDelegate {
    public static let shared = WebUsageFetcher()

    private var loginWindows: [AgentID: NSWindow] = [:]
    private var hiddenWebView: WKWebView?
    private var pendingContinuation: CheckedContinuation<WebFetchOutcome, Never>?
    private var pendingScript: String?
    private var pollTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var isEvaluating: Bool = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var cachedBlockRules: WKContentRuleList?
    private var didCompileRules: Bool = false
    private var cachedCookieDomains: [String]?
    private var lastCookieFetch: Date = .distantPast

    private override init() {
        super.init()
    }

    public func openLoginWindow(for agentID: AgentID, url: URL, onClose: @escaping @MainActor () -> Void) {
        if let existing = loginWindows[agentID] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 700), configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15"
        webView.load(URLRequest(url: url))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "登录 \(agentID.displayName) 以同步订阅与用量"
        window.center()
        window.contentView = webView
        window.isReleasedWhenClosed = false

        let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loginWindows.removeValue(forKey: agentID)
                self?.invalidateCookieCache()
                onClose()
            }
        }
        objc_setAssociatedObject(window, "closeObserver", closeObserver, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        loginWindows[agentID] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func invalidateCookieCache() {
        cachedCookieDomains = nil
        lastCookieFetch = .distantPast
    }

    public func hasCookies(matchingDomainSuffixes suffixes: [String]) async -> Bool {
        guard !suffixes.isEmpty else { return false }
        let now = Date()
        let domains: [String]
        if let cached = cachedCookieDomains, now.timeIntervalSince(lastCookieFetch) < 30.0 {
            domains = cached
        } else {
            let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
            domains = Array(Set(cookies.map {
                $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            }))
            cachedCookieDomains = domains
            lastCookieFetch = Date()
        }

        let cleanSuffixes = suffixes.map {
            $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        return domains.contains { dom in
            cleanSuffixes.contains { suf in
                dom == suf || dom.hasSuffix("." + suf)
            }
        }
    }

    private func ensureLightweightRules() async -> WKContentRuleList? {
        if let cachedBlockRules { return cachedBlockRules }
        guard !didCompileRules else { return nil }
        didCompileRules = true
        let rulesJSON = """
        [{"trigger":{"url-filter":".*","resource-type":["image","media","font"]},"action":{"type":"block"}}]
        """
        if let list = try? await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "AgentGaugeScraperSlim",
            encodedContentRuleList: rulesJSON
        ) {
            cachedBlockRules = list
            return list
        }
        return nil
    }

    public func evaluatePageOutcome(
        url: URL,
        script: String,
        requireExistingCookiesFor suffixes: [String]? = nil
    ) async -> WebFetchOutcome {
        if let suffixes, !(await hasCookies(matchingDomainSuffixes: suffixes)) {
            return .missingCookies
        }

        if isEvaluating {
            await withCheckedContinuation { cont in
                waiters.append(cont)
            }
        }
        isEvaluating = true
        defer {
            isEvaluating = false
            if !waiters.isEmpty {
                let next = waiters.removeFirst()
                next.resume()
            }
        }

        let ruleList = await ensureLightweightRules()

        return await withCheckedContinuation { continuation in
            self.pendingContinuation = continuation
            self.pendingScript = script

            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            config.suppressesIncrementalRendering = true
            if let ruleList {
                config.userContentController.add(ruleList)
            }

            let wv = WKWebView(frame: NSRect(x: -10000, y: -10000, width: 640, height: 480), configuration: config)
            wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15"
            wv.navigationDelegate = self
            self.hiddenWebView = wv

            self.timeoutTask?.cancel()
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_500_000_000)
                self?.finishPending(result: .transientFailure)
            }

            // Keep JS/CSS bundles cached so SPA pages hydrate in <1s without main-thread stalls!
            wv.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10))
        }
    }

    public func evaluatePage(url: URL, script: String, requireExistingCookiesFor suffixes: [String]? = nil) async -> Data? {
        if case let .payload(data) = await evaluatePageOutcome(url: url, script: script, requireExistingCookiesFor: suffixes) {
            return data
        }
        return nil
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard webView === hiddenWebView else { return }
        // Start polling right after DOM commit so slow 3rd-party analytics subresources NEVER cause timeouts!
        startDOMPolling(for: webView, initialDelayNs: 1_200_000_000)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === hiddenWebView else { return }
        startDOMPolling(for: webView, initialDelayNs: 450_000_000)
    }

    private func startDOMPolling(for webView: WKWebView, initialDelayNs: UInt64) {
        guard let script = pendingScript else { return }
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            let delays: [UInt64] = [initialDelayNs, 1_100_000_000, 1_400_000_000, 1_800_000_000]
            var lastData: Data? = nil
            for (idx, delay) in delays.enumerated() {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled, let self, self.hiddenWebView === webView else { return }
                do {
                    let cleanExpr = script
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
                    let wrapped = "return await (\(cleanExpr));"
                    let raw: Any? = try await webView.callAsyncJavaScript(wrapped, arguments: [:], in: nil, contentWorld: .page)
                    var data: Data? = nil
                    if let str = raw as? String {
                        data = str.data(using: .utf8)
                    } else if let dict = raw as? [String: Any] {
                        data = try? JSONSerialization.data(withJSONObject: dict)
                    }
                    if let data {
                        lastData = data
                        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if (obj["loggedIn"] as? Bool) == true {
                                self.finishPending(result: .payload(data))
                                return
                            }
                            if (obj["isLoginRedirect"] as? Bool) == true {
                                self.finishPending(result: .payload(data))
                                return
                            }
                        }
                    }
                } catch {
                    // Page still loading JS context; retry on next poll tick
                }
                if idx == delays.count - 1 {
                    if let lastData {
                        self.finishPending(result: .payload(lastData))
                    } else {
                        self.finishPending(result: .transientFailure)
                    }
                }
            }
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === hiddenWebView {
            finishPending(result: .transientFailure)
        }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView === hiddenWebView {
            finishPending(result: .transientFailure)
        }
    }

    private func finishPending(result: WebFetchOutcome) {
        pollTask?.cancel()
        pollTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        hiddenWebView?.navigationDelegate = nil
        hiddenWebView?.stopLoading()
        hiddenWebView?.loadHTMLString("", baseURL: nil)
        hiddenWebView = nil
        pendingScript = nil
        let cont = pendingContinuation
        pendingContinuation = nil
        cont?.resume(returning: result)
    }
}
