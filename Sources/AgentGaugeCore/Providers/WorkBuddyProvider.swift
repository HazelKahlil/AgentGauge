import Foundation

private final class WorkBuddySnapshotCache: @unchecked Sendable {
    static let shared = WorkBuddySnapshotCache()
    private let lock = NSLock()
    private var cached: QuotaSnapshot?
    private var cachedAt: Date = .distantPast

    func recent(maxAge: TimeInterval, isWorking: Bool) -> QuotaSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let c = cached, Date().timeIntervalSince(cachedAt) < maxAge else { return nil }
        return QuotaSnapshot(
            agentID: c.agentID,
            remainingPercent: c.remainingPercent,
            creditsRemaining: c.creditsRemaining,
            creditsTotal: c.creditsTotal,
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

    func store(_ snap: QuotaSnapshot) {
        lock.lock()
        cached = snap
        cachedAt = Date()
        lock.unlock()
    }

    func invalidate() {
        lock.lock()
        cached = nil
        cachedAt = .distantPast
        lock.unlock()
    }
}

public struct WorkBuddyProvider: UsageProvider {
    public let agentID: AgentID = .workbuddy

    public init() {}

    public static func invalidateCache() {
        WorkBuddySnapshotCache.shared.invalidate()
    }

    public func fetchSnapshot() async -> QuotaSnapshot {
        let isWorking = Self.checkIsWorking()

        // Reuse fresh (<5.5m) WorkBuddy web snapshot during periodic background polling so WKWebView never stalls UI!
        if let recent = WorkBuddySnapshotCache.shared.recent(maxAge: 330.0, isWorking: isWorking) {
            return recent
        }

        guard let url = agentID.webLoginURL else {
            return QuotaSnapshot(agentID: .workbuddy, remainingPercent: nil, isWorking: isWorking, sourceDescription: "WorkBuddy")
        }

        let script = """
        (function() {
          const text = document.body ? document.body.innerText : '';
          const href = location.href || '';
          const isLoginRedirect = /\\/(login|signin|sign-in|sso|auth)/i.test(href);
          if (isLoginRedirect) return JSON.stringify({ loggedIn: false, isLoginRedirect: true, href });

          let remainingPct = null;
          let creditsRem = null;
          let creditsTot = null;
          let subtitle = null;
          let resetDateStr = null;
          let resetText = null;
          let accountLabel = null;
          let planTier = null;

          // Extract logged-in email / masked phone / nickname from profile header
          const emailMatch = text.match(/[\\w.+-]+@[\\w-]+\\.[\\w.-]+/);
          const maskedPhone = text.match(/1[3-9]\\d\\*{4}\\d{4}/);
          if (emailMatch) accountLabel = emailMatch[0];
          else if (maskedPhone) accountLabel = maskedPhone[0];
          else {
            const nickMatch = text.match(/(?:账号|用户|昵称|ID)[：:\\s]+([^\\s\\n/|]{2,24})/i);
            if (nickMatch) accountLabel = nickMatch[1];
          }

          // Extract subscription plan tier
          const planMatch = text.match(/(旗舰版|企业版|专业版|团队版|Pro\\s*版|Ultra\\s*版|VIP\\s*版|体验版|免费版|个人专业版|个人版|\\bCodeBuddy\\s+Pro\\b|\\bPro\\b)/i);
          if (planMatch) {
            planTier = planMatch[1].replace(/\\s+/g, ' ').trim();
          }

          const toNum = (s) => parseFloat(String(s).replace(/,/g, ''));
          const textNoDates = text.replace(/20\\d{2}[\\/-]\\d{1,2}[\\/-]\\d{1,2}/g, '[DATE]');

          const remFrac = textNoDates.match(/(?:剩余|可用|Remaining)[^\\d/]{0,16}([\\d,]+(?:\\.\\d+)?)\\s*\\/\\s*([\\d,]+(?:\\.\\d+)?)/i);
          const usedFrac = textNoDates.match(/(?:已使用|已用|消耗|Used)[^\\d/]{0,16}([\\d,]+(?:\\.\\d+)?)\\s*\\/\\s*([\\d,]+(?:\\.\\d+)?)/i);
          const planFrac = textNoDates.match(/(?:积分|点数|Credits?|额度|用量|配额)[\\s\\S]{0,60}?([\\d,]+(?:\\.\\d+)?)\\s*\\/\\s*([\\d,]+(?:\\.\\d+)?)/i);
          const anyCleanFrac = textNoDates.match(/\\b([\\d,]+(?:\\.\\d+)?)\\s+\\/\\s+([\\d,]+(?:\\.\\d+)?)\\b/);

          const sepRem = textNoDates.match(/(?:剩余积分|可用积分|积分余额|当前积分|剩余额度|剩余点数|Remaining\\s*Credits?)[^\\d]{0,18}([\\d,]+(?:\\.\\d+)?)/i)
                      || textNoDates.match(/([\\d,]+(?:\\.\\d+)?)\\s*(?:可用积分|剩余积分|积分|Credits?)\\b/i);
          const sepUsed = textNoDates.match(/(?:已用积分|已使用积分|已消耗|Used\\s*Credits?)[^\\d]{0,18}([\\d,]+(?:\\.\\d+)?)/i);
          const sepTotal = textNoDates.match(/(?:总积分|总额度|每月积分|本月额度|套餐额度|Total\\s*Credits?)[^\\d]{0,18}([\\d,]+(?:\\.\\d+)?)/i);

          if (remFrac) {
            const r = toNum(remFrac[1]), tot = toNum(remFrac[2]);
            if (tot > 0 && r <= tot) {
              creditsRem = Math.round(r);
              creditsTot = Math.round(tot);
              remainingPct = Math.max(0, Math.min(100, (r / tot) * 100));
            }
          } else if (usedFrac) {
            const u = toNum(usedFrac[1]), tot = toNum(usedFrac[2]);
            if (tot > 0 && u <= tot) {
              creditsRem = Math.max(0, Math.round(tot - u));
              creditsTot = Math.round(tot);
              remainingPct = Math.max(0, Math.min(100, ((tot - u) / tot) * 100));
            }
          } else if (planFrac) {
            const a = toNum(planFrac[1]), tot = toNum(planFrac[2]);
            if (tot > 0 && a <= tot && !(a >= 2024 && a <= 2035 && tot <= 12)) {
              const before = planFrac[0].split(planFrac[1])[0] || '';
              const isExplicitRemaining = /剩余|可用|Remaining/i.test(before);
              const remVal = isExplicitRemaining ? a : (tot - a);
              creditsRem = Math.max(0, Math.round(remVal));
              creditsTot = Math.round(tot);
              remainingPct = Math.max(0, Math.min(100, (remVal / tot) * 100));
            }
          } else if (anyCleanFrac) {
            const u = toNum(anyCleanFrac[1]), tot = toNum(anyCleanFrac[2]);
            if (tot > 0 && u <= tot) {
              creditsRem = Math.max(0, Math.round(tot - u));
              creditsTot = Math.round(tot);
              remainingPct = Math.max(0, Math.min(100, ((tot - u) / tot) * 100));
            }
          } else if (sepRem) {
            const r = toNum(sepRem[1]);
            creditsRem = Math.round(r);
            if (sepTotal && toNum(sepTotal[1]) > 0) {
              const tot = toNum(sepTotal[1]);
              creditsTot = Math.round(tot);
              remainingPct = Math.max(0, Math.min(100, (r / tot) * 100));
            } else {
              remainingPct = r > 0 ? 100 : 0;
            }
          } else if (sepUsed && sepTotal) {
            const u = toNum(sepUsed[1]), tot = toNum(sepTotal[1]);
            if (tot > 0) {
              creditsRem = Math.max(0, Math.round(tot - u));
              creditsTot = Math.round(tot);
              remainingPct = Math.max(0, Math.min(100, ((tot - u) / tot) * 100));
            }
          }

          if (!planTier && creditsTot !== null) {
            planTier = creditsTot >= 2000 ? 'Pro 套餐' : '基础套餐';
          }

          const dateMatch = text.match(/(20\\d{2})[\\/-](\\d{1,2})[\\/-](\\d{1,2})(?:\\s+(\\d{1,2}):(\\d{2})(?::(\\d{2}))?)?/);
          if (dateMatch) {
            const y = dateMatch[1], m = dateMatch[2].padStart(2, '0'), d = dateMatch[3].padStart(2, '0');
            const hh = (dateMatch[4] || '00').padStart(2, '0');
            const mm = (dateMatch[5] || '00').padStart(2, '0');
            const ss = (dateMatch[6] || '00').padStart(2, '0');
            resetDateStr = `${y}-${m}-${d}T${hh}:${mm}:${ss}+08:00`;
          } else {
            const resetMatch = text.match(/(?:重置|刷新|到期|Reset)[^\\n。]{0,20}/i);
            if (resetMatch) resetText = resetMatch[0].replace(/^刷新时间[：:]\\s*/, '').trim();
          }

          if (creditsRem !== null && creditsTot !== null) {
            subtitle = `总额度 ${creditsTot} 积分`;
          }

          return JSON.stringify({
            loggedIn: remainingPct !== null,
            isLoginRedirect: false,
            remaining: remainingPct,
            creditsRem,
            creditsTot,
            accountLabel,
            planTier,
            subtitle,
            resetDateStr,
            resetText,
            href
          });
        })()
        """

        let outcome = await WebUsageFetcher.shared.evaluatePageOutcome(
            url: url,
            script: script,
            requireExistingCookiesFor: ["codebuddy.cn", "tencent.com", "workbuddy.cn"]
        )

        let localUID = Self.readLocalWorkBuddyUID()

        switch outcome {
        case .missingCookies:
            return QuotaSnapshot(
                agentID: .workbuddy,
                remainingPercent: nil,
                accountEmail: localUID,
                isWorking: isWorking,
                sourceDescription: "WorkBuddy Web",
                requiresWebLogin: true,
                errorMessage: "请点击「登录」同步 CodeBuddy 积分"
            )
        case .transientFailure:
            // CRITICAL: Timeout / slow SPA load is NOT a logout — preserve cached 3177/6068 credits!
            return QuotaSnapshot(
                agentID: .workbuddy,
                remainingPercent: nil,
                accountEmail: localUID,
                isWorking: isWorking,
                sourceDescription: "CodeBuddy 积分",
                requiresWebLogin: false,
                errorMessage: "CodeBuddy 页面响应较慢（已保留上次积分）"
            )
        case .payload(let resultData):
            guard let result = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
                  let loggedIn = result["loggedIn"] as? Bool, loggedIn,
                  let remaining = result["remaining"] as? Double else {
                let isRedirect = ((try? JSONSerialization.jsonObject(with: resultData) as? [String: Any])?["isLoginRedirect"] as? Bool) ?? false
                return QuotaSnapshot(
                    agentID: .workbuddy,
                    remainingPercent: nil,
                    accountEmail: localUID,
                    isWorking: isWorking,
                    sourceDescription: "WorkBuddy",
                    requiresWebLogin: isRedirect,
                    errorMessage: isRedirect ? "登录态已过期，请点击「登录」" : "页面加载未完成（已保留上次积分）"
                )
            }

            let creditsRem = result["creditsRem"] as? Int
            let creditsTot = result["creditsTot"] as? Int
            let acct = (result["accountLabel"] as? String)?.nilIfEmpty ?? localUID
            let plan = (result["planTier"] as? String)?.nilIfEmpty
            let subtitle = result["subtitle"] as? String
            let resetText = result["resetText"] as? String
            var resetsAt: Date? = nil
            if let isoStr = result["resetDateStr"] as? String {
                resetsAt = ISO8601DateFormatter().date(from: isoStr)
            }

            let winLabel: String
            if let c = creditsRem, let t = creditsTot {
                winLabel = "套餐积分 (\(c)/\(t))"
            } else {
                winLabel = "WorkBuddy 积分"
            }

            let snap = QuotaSnapshot(
                agentID: .workbuddy,
                remainingPercent: remaining,
                creditsRemaining: creditsRem,
                creditsTotal: creditsTot,
                accountEmail: acct,
                planTier: plan,
                primaryLabel: "WorkBuddy",
                resetsAt: resetsAt,
                resetText: resetsAt == nil ? resetText : nil,
                windows: [QuotaWindow(label: winLabel, remainingPercent: remaining, resetsAt: resetsAt, resetText: resetText, isPrimary: true)],
                subtitle: subtitle,
                isWorking: isWorking,
                sourceDescription: "CodeBuddy 积分"
            )
            WorkBuddySnapshotCache.shared.store(snap)
            return snap
        }
    }

    private static func readLocalWorkBuddyUID() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let settingsPath = "\(home)/.workbuddy/settings.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let claw = json["claw"] as? [String: Any],
           let uid = (claw["legacyOwnerUid"] as? String)?.nilIfEmpty {
            return "UID:\(uid.prefix(8))"
        }
        return nil
    }

    private static func checkIsWorking() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "\(home)/.workbuddy/app/sessions.json",
            "\(home)/.workbuddy/app/session/DIPS"
        ]
        let now = Date()
        for path in paths {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let mtime = attrs[.modificationDate] as? Date,
               now.timeIntervalSince(mtime) < 8.0 {
                return true
            }
        }
        return false
    }
}
