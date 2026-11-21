import AppKit
import Foundation

/// Universal provider powering all mainstream Coding Agents & AI Desktop Apps in the 32-agent catalog.
public struct GenericWebUsageProvider: UsageProvider {
    public let agentID: AgentID

    public init(agentID: AgentID) {
        self.agentID = agentID
    }

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isRunning = await MainActor.run {
            agentID.bundleIdentifiers.contains { bid in
                !NSRunningApplication.runningApplications(withBundleIdentifier: bid).isEmpty
            }
        }

        // Local-only / orchestrator tools without a vendor quota API (e.g. Multica, Hermes, Xcode, LM Studio)
        guard let url = agentID.webLoginURL, !agentID.cookieDomainSuffixes.isEmpty else {
            return QuotaSnapshot(
                agentID: agentID,
                remainingPercent: isRunning ? 100.0 : nil,
                planTier: "本地应用",
                primaryLabel: agentID.shortName,
                resetText: isRunning ? "运行中" : "未启动",
                windows: isRunning ? [QuotaWindow(label: "本地运行状态（无独立配额）", remainingPercent: 100, resetText: "在线", isPrimary: true)] : [],
                subtitle: isRunning ? "本地编排 / 工具客户端（不设百分比限额）" : "启动应用后自动联动",
                isWorking: isRunning,
                sourceDescription: "\(agentID.shortName) 本地状态",
                requiresWebLogin: false
            )
        }

        let script = """
        (function() {
          const text = document.body ? document.body.innerText : '';
          const href = location.href || '';
          const isLoginRedirect = /\\/(login|signin|sign-in|sso|oauth|auth)/i.test(href);
          if (isLoginRedirect) return JSON.stringify({ loggedIn: false, isLoginRedirect: true, href });

          let remaining = null;
          let subtitle = null;
          let resetText = null;
          let email = null;
          let planTier = null;

          const em = text.match(/[\\w.+-]+@[\\w-]+\\.[\\w.-]+/);
          if (em) email = em[0];

          const pm = text.match(/\\b(Ultra|Max\\s*20x|Max\\s*5x|SuperGrok|Pro\\+|Pro\\s*Plus|Premium|Enterprise|Team|Plus|Pro|VIP|Free)\\b/i);
          if (pm) planTier = pm[1].trim();

          const pctRem = text.match(/(?:remaining|left|剩余|可用)[^\\d%]{0,18}(\\d+(?:\\.\\d+)?)\\s*%/i);
          const pctUsed = text.match(/(?:used|usage|已使用|已用)[^\\d%]{0,18}(\\d+(?:\\.\\d+)?)\\s*%/i);
          const usedPctAfter = text.match(/(\\d+(?:\\.\\d+)?)\\s*%\\s*(?:used|utilized)/i);
          const remPctAfter = text.match(/(\\d+(?:\\.\\d+)?)\\s*%\\s*(?:remaining|left)/i);

          const usedFrac = text.match(/(?:used|已使用|已用)[^\\d]{0,16}([\\d,]+(?:\\.\\d+)?)\\s*\\/\\s*([\\d,]+(?:\\.\\d+)?)/i);
          const remFrac = text.match(/(?:remaining|left|剩余|可用)[^\\d]{0,16}([\\d,]+(?:\\.\\d+)?)\\s*\\/\\s*([\\d,]+(?:\\.\\d+)?)/i);
          const genericFrac = text.match(/(?:credits?|requests?|prompts?|quota|tokens?|积分|额度|用量|配额)[\\s\\S]{0,36}?([\\d,]+(?:\\.\\d+)?)\\s*\\/\\s*([\\d,]+(?:\\.\\d+)?)/i);

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
          }

          const resetMatch = text.match(/(?:resets?\\s+(?:in\\s+|on\\s+)?|重置|刷新|到期)[^\\n.。]{1,28}/i);
          if (resetMatch) resetText = resetMatch[0].trim();

          return JSON.stringify({
            loggedIn: remaining !== null,
            isLoginRedirect: false,
            remaining,
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
            return QuotaSnapshot(
                agentID: agentID,
                remainingPercent: remaining,
                accountEmail: email,
                planTier: plan,
                primaryLabel: agentID.shortName,
                resetText: resetText,
                windows: [QuotaWindow(label: "\(agentID.shortName) 额度", remainingPercent: remaining, resetText: resetText, isPrimary: true)],
                subtitle: subtitle,
                isWorking: isRunning,
                sourceDescription: "\(agentID.shortName) Web"
            )
        }
    }
}
