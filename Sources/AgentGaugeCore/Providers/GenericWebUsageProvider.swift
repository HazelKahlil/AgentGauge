import AppKit
import Foundation

private final class GenericWebSnapshotCache: @unchecked Sendable {
    static let shared = GenericWebSnapshotCache()
    private let lock = NSLock()
    private var entries: [AgentID: (snap: QuotaSnapshot, at: Date)] = [:]

    func invalidate(for id: AgentID? = nil) {
        lock.lock()
        if let id {
            entries.removeValue(forKey: id)
        } else {
            entries.removeAll()
        }
        lock.unlock()
    }

    func get(for id: AgentID, maxAge: TimeInterval, isWorking: Bool) -> QuotaSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let item = entries[id], Date().timeIntervalSince(item.at) <= maxAge else {
            return nil
        }
        let c = item.snap
        return QuotaSnapshot(
            agentID: c.agentID,
            remainingPercent: c.remainingPercent,
            creditsRemaining: c.creditsRemaining,
            creditsTotal: c.creditsTotal,
            balanceDisplay: c.balanceDisplay,
            dockBalanceShort: c.dockBalanceShort,
            accountEmail: c.accountEmail,
            planTier: c.planTier,
            primaryLabel: c.primaryLabel,
            resetsAt: c.resetsAt,
            resetText: c.resetText,
            windows: c.windows,
            subtitle: c.subtitle,
            isWorking: isWorking,
            sourceDescription: c.sourceDescription,
            updatedAt: c.updatedAt
        )
    }

    func set(_ snap: QuotaSnapshot, for id: AgentID) {
        lock.lock()
        entries[id] = (snap, Date())
        lock.unlock()
    }
}

/// Universal provider powering all mainstream Coding Agents & AI Desktop Apps in the 32-agent catalog.
public struct GenericWebUsageProvider: UsageProvider {
    public let agentID: AgentID

    public init(agentID: AgentID) {
        self.agentID = agentID
    }

    public static func invalidateCache(for id: AgentID? = nil) {
        GenericWebSnapshotCache.shared.invalidate(for: id)
    }

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isRunning = await MainActor.run {
            agentID.bundleIdentifiers.contains { bid in
                !NSRunningApplication.runningApplications(withBundleIdentifier: bid).isEmpty
            }
        }

        let ttl: TimeInterval = isRunning ? 150.0 : 360.0
        if let cached = GenericWebSnapshotCache.shared.get(for: agentID, maxAge: ttl, isWorking: isRunning) {
            return cached
        }

        guard let url = agentID.webLoginURL, !agentID.cookieDomainSuffixes.isEmpty else {
            return QuotaSnapshot(
                agentID: agentID,
                remainingPercent: nil,
                isWorking: isRunning,
                sourceDescription: "\(agentID.shortName) 未连接",
                requiresWebLogin: false
            )
        }

        let script = """
        (function() {
          const href = location.href || '';
          const isLoginRedirect = /\\/(login|signin|sign-in|sso|oauth|auth|passport)/i.test(href);
          if (isLoginRedirect) return JSON.stringify({ loggedIn: false, isLoginRedirect: true, href });

          // Strip user chat messages, code blocks, and markdown articles so conversational text is NEVER mistaken for account quota!
          let text = '';
          if (document.body) {
            const clone = document.body.cloneNode(true);
            const noisy = clone.querySelectorAll('script, style, noscript, pre, code, textarea, [data-message-author-role], [data-testid*="message"], [data-testid*="conversation"], .prose, .markdown-body');
            for (const el of noisy) el.remove();
            text = clone.innerText || clone.textContent || '';
          }

          let remaining = null;
          let subtitle = null;
          let resetText = null;
          let email = null;
          let planTier = null;
          let balanceDisplay = null;
          let dockBalanceShort = null;

          const em = text.match(/[\\w.+-]+@[\\w-]+\\.[\\w.-]+/);
          if (em) email = em[0];

          const pm = text.match(/\\b(Coding\\s*Plan\\s*(?:Max|Pro|Lite)?|Token\\s*Plan|Ultra(?:\\s*(?:20x|5x))?|Max\\s*(?:20x|5x)|SuperGrok\\s*Heavy|SuperGrok|Pro\\+(?:\\s*3x)?|Pro\\s*Plus|Pro\\s*Lite(?:\\s*5x)?|Premium|Enterprise|Team|Plus|Pro|Lite|VIP|Free)\\b/i);
          if (pm) planTier = pm[1].trim();

          const pctRem = text.match(/(?:remaining|left|剩余|可用比例)[^\\d%]{0,18}(\\d+(?:\\.\\d+)?)\\s*%/i);
          const pctUsed = text.match(/(?:used|usage|已使用|已用|消耗)[^\\d%]{0,18}(\\d+(?:\\.\\d+)?)\\s*%/i);
          const usedPctAfter = text.match(/(\\d+(?:\\.\\d+)?)\\s*%\\s*(?:used|utilized)/i);
          const remPctAfter = text.match(/(\\d+(?:\\.\\d+)?)\\s*%\\s*(?:remaining|left)/i);

          const usedFrac = text.match(/(?:used|已使用|已用)[^\\d]{0,16}([\\d,]+(?:\\.\\d+)?)\\s*\\/\\s*([\\d,]+(?:\\.\\d+)?)/i);
          const remFrac = text.match(/(?:remaining|left|剩余|可用)[^\\d]{0,16}([\\d,]+(?:\\.\\d+)?)\\s*\\/\\s*([\\d,]+(?:\\.\\d+)?)/i);
          const genericFrac = text.match(/(?:credits?|requests?|prompts?|points?|quota|tokens?|积分|额度|用量|配额|算力|次数)[\\s\\S]{0,36}?([\\d,]+(?:\\.\\d+)?)\\s*\\/\\s*([\\d,]+(?:\\.\\d+)?)/i);
          const cashBal = text.match(/(?:账户余额|可用余额|现金余额|Available\\s*Balance|Balance)[\\s:：]{0,12}([¥￥$])\\s*([\\d,]+(?:\\.\\d+)?)/i);
          const cashBalSuffix = text.match(/(?:账户余额|可用余额|现金余额|Available\\s*Balance|Balance)[\\s:：]{0,12}([\\d,]+(?:\\.\\d+)?)\\s*(CNY|RMB|USD|元)/i);

          const toNum = (s) => parseFloat(String(s).replace(/,/g, ''));

          if (pctRem) {
            remaining = parseFloat(pctRem[1]);
          } else if (remPctAfter) {
            remaining = parseFloat(remPctAfter[1]);
          } else if (pctUsed) {
            remaining = Math.max(0, Math.min(100, 100 - parseFloat(pctUsed[1])));
          } else if (usedPctAfter) {
            remaining = Math.max(0, Math.min(100, 100 - parseFloat(usedPctAfter[1])));
          } else if (usedFrac) {
            const u = toNum(usedFrac[1]), tot = toNum(usedFrac[2]);
            if (tot > 0) {
              remaining = Math.max(0, Math.min(100, (1 - u / tot) * 100));
              subtitle = `${Math.round(u)} / ${Math.round(tot)}`;
            }
          } else if (remFrac) {
            const r = toNum(remFrac[1]), tot = toNum(remFrac[2]);
            if (tot > 0) {
              remaining = Math.max(0, Math.min(100, (r / tot) * 100));
              subtitle = `${Math.round(r)} / ${Math.round(tot)}`;
            }
          } else if (genericFrac) {
            const a = toNum(genericFrac[1]), tot = toNum(genericFrac[2]);
            if (tot > 0) {
              const isUsed = /used|已用|已使用|消耗/i.test(genericFrac[0]);
              remaining = Math.max(0, Math.min(100, (isUsed ? (1 - a / tot) : (a / tot)) * 100));
              subtitle = `${Math.round(a)} / ${Math.round(tot)}`;
            }
          } else if (cashBal || cashBalSuffix) {
            let sym = '¥';
            let val = 0;
            if (cashBal) {
              sym = cashBal[1] === '￥' ? '¥' : cashBal[1];
              val = toNum(cashBal[2]);
            } else if (cashBalSuffix) {
              sym = cashBalSuffix[2].toUpperCase() === 'USD' ? '$' : '¥';
              val = toNum(cashBalSuffix[1]);
            }
            const half = sym === '$' ? 3.0 : 15.0;
            remaining = val > 0 ? Math.max(4, Math.min(98, (val / (val + half)) * 100)) : 0;
            balanceDisplay = `${sym}${val.toFixed(2)}`;
            dockBalanceShort = val >= 10 ? `${sym}${Math.round(val)}` : `${sym}${val.toFixed(1)}`;
            subtitle = `可用余额 ${balanceDisplay}`;
            resetText = '按量计费';
          }

          if (!resetText) {
            const resetMatch = text.match(/(?:resets?\\s+(?:in\\s+|on\\s+)?|重置|刷新|到期)[^\\n.。]{1,28}/i);
            if (resetMatch) resetText = resetMatch[0].trim();
          }

          return JSON.stringify({
            loggedIn: remaining !== null,
            isLoginRedirect: false,
            remaining,
            balanceDisplay,
            dockBalanceShort,
            email,
            planTier,
            subtitle,
            resetText,
            href
          });
        })();
        """

        let outcome = await WebUsageFetcher.shared.evaluatePageOutcome(
            url: url,
            script: script,
            requireExistingCookiesFor: agentID.cookieDomainSuffixes
        )
        switch outcome {
        case .missingCookies:
            return QuotaSnapshot(
                agentID: agentID,
                remainingPercent: nil,
                isWorking: isRunning,
                sourceDescription: "\(agentID.shortName) 未连接",
                requiresWebLogin: true,
                errorMessage: "点击「登录」连接 \(agentID.shortName)"
            )
        case .transientFailure:
            return QuotaSnapshot(
                agentID: agentID,
                remainingPercent: nil,
                isWorking: isRunning,
                sourceDescription: "\(agentID.shortName) Web",
                requiresWebLogin: false,
                errorMessage: "网页响应较慢（已保留上次状态）"
            )
        case .payload(let resultData):
            guard let result = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
                  let loggedIn = result["loggedIn"] as? Bool, loggedIn,
                  let remaining = result["remaining"] as? Double else {
                let redirected = ((try? JSONSerialization.jsonObject(with: resultData) as? [String: Any])?["isLoginRedirect"] as? Bool) ?? true
                return QuotaSnapshot(
                    agentID: agentID,
                    remainingPercent: nil,
                    isWorking: isRunning,
                    sourceDescription: "\(agentID.shortName) 未连接",
                    requiresWebLogin: redirected,
                    errorMessage: "点击「登录」连接 \(agentID.shortName)"
                )
            }

            let subtitle = result["subtitle"] as? String
            let resetText = result["resetText"] as? String
            let email = (result["email"] as? String)?.nilIfEmpty
            let plan = (result["planTier"] as? String)?.nilIfEmpty
            let balDisp = (result["balanceDisplay"] as? String)?.nilIfEmpty
            let dockBal = (result["dockBalanceShort"] as? String)?.nilIfEmpty
            let snap = QuotaSnapshot(
                agentID: agentID,
                remainingPercent: remaining,
                balanceDisplay: balDisp,
                dockBalanceShort: dockBal,
                accountEmail: email,
                planTier: plan,
                primaryLabel: agentID.shortName,
                resetText: resetText,
                windows: [QuotaWindow(label: "\(agentID.shortName) 额度", remainingPercent: remaining, resetText: balDisp ?? resetText, isPrimary: true)],
                subtitle: subtitle,
                isWorking: isRunning,
                sourceDescription: "\(agentID.shortName) Web"
            )
            GenericWebSnapshotCache.shared.set(snap, for: agentID)
            return snap
        }
    }
}
