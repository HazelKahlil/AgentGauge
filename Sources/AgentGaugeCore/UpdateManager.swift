import AppKit
import CryptoKit
import Darwin
import Foundation

public struct ReleaseManifest: Codable, Sendable, Equatable {
    public let version: String
    public let build: Int
    public let publishedAt: String?
    public let urgency: String?
    public let title: String?
    public let notes: [String]
    public let zipUrl: String
    public let fallbackZipUrl: String?
    public let dmgUrl: String?
    public let sha256: String?
    public let signature: String?
    public let isFromSignedFeed: Bool

    public init(
        version: String,
        build: Int,
        publishedAt: String? = nil,
        urgency: String? = nil,
        title: String? = nil,
        notes: [String] = [],
        zipUrl: String,
        fallbackZipUrl: String? = nil,
        dmgUrl: String? = nil,
        sha256: String? = nil,
        signature: String? = nil,
        isFromSignedFeed: Bool = true
    ) {
        self.version = version
        self.build = build
        self.publishedAt = publishedAt
        self.urgency = urgency
        self.title = title
        self.notes = notes
        self.zipUrl = zipUrl
        self.fallbackZipUrl = fallbackZipUrl
        self.dmgUrl = dmgUrl
        self.sha256 = sha256
        self.signature = signature
        self.isFromSignedFeed = isFromSignedFeed
    }
}

public enum UpdateState: Sendable, Equatable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case available(ReleaseManifest)
    case downloading(ReleaseManifest, progress: Double)
    case installing(ReleaseManifest)
    case failed(String, retryable: ReleaseManifest?)

    public var availableManifest: ReleaseManifest? {
        switch self {
        case .available(let m), .downloading(let m, _), .installing(let m):
            return m
        case .failed(_, let m):
            return m
        default:
            return nil
        }
    }

    public var hasUnreadUpdate: Bool {
        switch self {
        case .available, .downloading, .installing:
            return true
        case .failed(_, let retryable):
            return retryable != nil
        default:
            return false
        }
    }
}

@MainActor
public final class UpdateManager: ObservableObject {
    public static let shared = UpdateManager()

    /// Embedded Ed25519 Release Signing Public Key (private key lives exclusively outside git at `~/.config/agentgauge/release_ed25519.key`).
    public nonisolated static let releasePublicKeyBase64 = "5OsV5hFo010d6lSMn3XGJRQOAznpoZ7SFXINupTk+GA="

    /// Primary global + China fast CDN manifest endpoint & GitHub Releases fallback.
    private nonisolated static let primaryFeedURL = URL(string: "https://usage.komorebi.date/updates/latest.json")!
    private nonisolated static let githubLatestAPIURL = URL(string: "https://api.github.com/repos/HazelKahlil/AgentGauge/releases/latest")!
    private nonisolated static let allowedDownloadHosts: Set<String> = [
        "usage.komorebi.date",
        "github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com"
    ]

    @Published public private(set) var state: UpdateState = .idle

    @Published public var autoCheckUpdates: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckUpdates, forKey: "AgentGauge.autoCheckUpdates")
        }
    }

    private var periodicTimer: Timer?
    private var diskWatchTimer: Timer?
    private let launchedExecutableInode: ino_t
    private let launchedTeamIdentifier: String?
    private var isPerformingInstall = false
    private var checkGeneration: UInt64 = 0

    public var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.3.5"
    }

    public var currentBuild: Int {
        if let raw = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, let n = Int(raw) {
            return n
        }
        return 135
    }

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "AgentGauge.autoCheckUpdates") != nil {
            self.autoCheckUpdates = defaults.bool(forKey: "AgentGauge.autoCheckUpdates")
        } else {
            self.autoCheckUpdates = true
        }

        if let execPath = Bundle.main.executablePath {
            var st = stat()
            self.launchedExecutableInode = (stat(execPath, &st) == 0) ? st.st_ino : 0
        } else {
            self.launchedExecutableInode = 0
        }
        self.launchedTeamIdentifier = Self.signingTeamIdentifier(for: Bundle.main.bundleURL)
    }

    /// Terminates any older lingering `com.kahlil.AgentGauge` background instance (e.g. `v1.1.0–v1.2.1`) when a newer bundle is opened.
    public static func terminateOlderRunningInstancesIfNeeded() {
        let myPID = getpid()
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.kahlil.AgentGauge")
            .filter { $0.processIdentifier != myPID }
        guard !others.isEmpty else { return }

        for old in others {
            old.terminate()
        }
        let deadline = Date().addingTimeInterval(0.65)
        while Date() < deadline {
            if others.allSatisfy(\.isTerminated) { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        for old in others where !old.isTerminated {
            old.forceTerminate()
        }
    }

    public func start() {
        periodicTimer?.invalidate()
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 4 * 3600.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.autoCheckUpdates else { return }
                await self.checkForUpdates(userInitiated: false)
            }
        }

        // Watch on-disk executable inode every 8s (0.001ms stat syscall):
        // If user manually drags a newer DMG app over `/Applications/AgentGauge.app`, hot-relaunch into the new binary automatically!
        diskWatchTimer?.invalidate()
        if launchedExecutableInode != 0 {
            diskWatchTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.checkIfBundleReplacedOnDisk()
                }
            }
        }

        if autoCheckUpdates {
            Task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                await checkForUpdates(userInitiated: false)
            }
        }
    }

    public func stop() {
        periodicTimer?.invalidate()
        periodicTimer = nil
        diskWatchTimer?.invalidate()
        diskWatchTimer = nil
    }

    private func checkIfBundleReplacedOnDisk() {
        guard !isPerformingInstall,
              launchedExecutableInode != 0,
              let execPath = Bundle.main.executablePath else { return }

        var st = stat()
        guard stat(execPath, &st) == 0, st.st_ino != 0, st.st_ino != launchedExecutableInode else {
            return
        }

        let bundlePath = Bundle.main.bundleURL.path
        guard bundlePath.hasSuffix(".app"),
              Self.verifyExtractedBundle(
                  at: Bundle.main.bundleURL,
                  expectedTeamIdentifier: launchedTeamIdentifier
              ) else {
            return
        }

        isPerformingInstall = true
        AppLogger.shared.log("Update", "检测到磁盘上的 AgentGauge.app 已更新，正在自动无缝重启至新版本…")
        AgentGaugeStore.shared.shutdown()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = [
            "-c",
            "sleep 0.35; /usr/bin/open -n -g \"$1\"",
            "--",
            bundlePath
        ]
        try? proc.run()
        NSApp.terminate(nil)
    }

    // MARK: - Remote Update Check (Cloudflare Signed Feed -> GitHub Releases API Fallback)

    public func checkForUpdates(userInitiated: Bool = true) async {
        guard !isPerformingInstall else { return }
        switch state {
        case .checking, .downloading, .installing:
            return
        default:
            break
        }

        checkGeneration &+= 1
        let myGen = checkGeneration

        if userInitiated {
            state = .checking
        }

        let curVer = currentVersion
        let curBuild = currentBuild

        func canCommitCheckResult() -> Bool {
            guard !isPerformingInstall, myGen == checkGeneration else { return false }
            switch state {
            case .downloading, .installing:
                return false
            default:
                return true
            }
        }

        // 1. Primary: Cloudflare Global/China CDN Signed `latest.json`
        if let manifest = await Self.fetchPrimarySignedFeed() {
            guard canCommitCheckResult() else { return }
            if Self.isRemoteNewer(
                remoteVersion: manifest.version,
                remoteBuild: manifest.build,
                currentVersion: curVer,
                currentBuild: curBuild
            ) {
                state = .available(manifest)
                AppLogger.shared.log("Update", "发现远程新版本 v\(manifest.version) (\(manifest.build))")
            } else if userInitiated || state.availableManifest != nil {
                state = .upToDate(checkedAt: Date())
            }
            return
        }

        // 2. Fallback: Official GitHub Releases signed `latest.json` (same Ed25519 + SHA-256 trust anchor)
        if let ghManifest = await Self.fetchGitHubLatestRelease() {
            guard canCommitCheckResult() else { return }
            if Self.isRemoteNewer(
                remoteVersion: ghManifest.version,
                remoteBuild: ghManifest.build,
                currentVersion: curVer,
                currentBuild: curBuild
            ) {
                state = .available(ghManifest)
                AppLogger.shared.log("Update", "发现 GitHub 已签名新版本 v\(ghManifest.version)")
            } else if userInitiated || state.availableManifest != nil {
                state = .upToDate(checkedAt: Date())
            }
            return
        }

        if userInitiated, canCommitCheckResult() {
            state = .failed("暂时无法连接更新服务器，请稍后重试", retryable: nil)
        }
    }

    // MARK: - One-Click Verified Download, Atomic Overwrite & Auto-Relaunch

    public func installUpdate(_ manifest: ReleaseManifest) async {
        guard !isPerformingInstall else { return }
        isPerformingInstall = true
        checkGeneration &+= 1
        state = .downloading(manifest, progress: 0.02)
        AppLogger.shared.log("Update", "开始下载更新包 v\(manifest.version)…")

        let stageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentgauge-ota-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)
        } catch {
            isPerformingInstall = false
            state = .failed("无法创建临时更新目录", retryable: manifest)
            return
        }

        let archiveURL = stageDir.appendingPathComponent("AgentGauge-update.zip")
        var candidateURLs: [URL] = []
        if let u1 = URL(string: manifest.zipUrl), Self.isAllowedDownloadURL(u1) {
            candidateURLs.append(u1)
        }
        if let fb = manifest.fallbackZipUrl, let u2 = URL(string: fb), Self.isAllowedDownloadURL(u2), !candidateURLs.contains(u2) {
            candidateURLs.append(u2)
        }

        guard !candidateURLs.isEmpty else {
            try? FileManager.default.removeItem(at: stageDir)
            isPerformingInstall = false
            state = .failed("更新包地址不受信任，已拦截", retryable: manifest)
            return
        }

        var downloadSucceeded = false
        for url in candidateURLs {
            if await downloadFileWithProgress(from: url, to: archiveURL, manifest: manifest) {
                downloadSucceeded = true
                break
            }
        }

        guard downloadSucceeded else {
            try? FileManager.default.removeItem(at: stageDir)
            isPerformingInstall = false
            state = .failed("更新包下载失败，可重试或前往官网下载", retryable: manifest)
            return
        }

        state = .installing(manifest)

        let verificationResult = await Task.detached(priority: .userInitiated) { () -> Result<URL, NSError> in
            do {
                try Self.verifyArchiveCryptographically(at: archiveURL, manifest: manifest)
                let extractDir = stageDir.appendingPathComponent("extracted", isDirectory: true)
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

                guard Self.extractZipArchive(at: archiveURL, into: extractDir) else {
                    throw NSError(domain: "UpdateManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "解压更新包失败"])
                }

                let appURL = extractDir.appendingPathComponent("AgentGauge.app", isDirectory: true)
                guard FileManager.default.fileExists(atPath: appURL.path) else {
                    throw NSError(domain: "UpdateManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "更新包内未找到 AgentGauge.app"])
                }

                // Clear any extended quarantine attributes so relaunch is 100% seamless without Gatekeeper prompts
                Self.clearQuarantineAttributes(at: appURL)

                guard Self.verifyExtractedBundle(
                    at: appURL,
                    expectedVersion: manifest.version,
                    expectedBuild: manifest.build
                ) else {
                    throw NSError(domain: "UpdateManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "应用签名、版本或包结构校验未通过"])
                }
                return .success(appURL)
            } catch let err as NSError {
                return .failure(err)
            }
        }.value

        let stagedAppURL: URL
        switch verificationResult {
        case .success(let url):
            stagedAppURL = url
        case .failure(let err):
            try? FileManager.default.removeItem(at: stageDir)
            isPerformingInstall = false
            AppLogger.shared.log("Update", "校验未通过: \(err.localizedDescription)")
            state = .failed(err.localizedDescription, retryable: manifest)
            return
        }

        let currentBundlePath = Bundle.main.bundleURL.path
        let targetAppPath: String = if currentBundlePath.hasSuffix(".app") && !currentBundlePath.hasPrefix("/Volumes/") {
            currentBundlePath
        } else {
            "/Applications/AgentGauge.app"
        }

        let parentDir = (targetAppPath as NSString).deletingLastPathComponent
        guard FileManager.default.isWritableFile(atPath: parentDir) else {
            isPerformingInstall = false
            NSWorkspace.shared.activateFileViewerSelecting([stagedAppURL])
            state = .failed("当前目录无写入权限，已为你打开新版应用所在文件夹，拖入应用程序即可", retryable: manifest)
            return
        }

        // Stage candidate bundle directly inside target parent directory so kernel-atomic RENAME_SWAP stays on the same volume!
        let sameVolStageURL = URL(fileURLWithPath: parentDir)
            .appendingPathComponent(".AgentGauge.ota-stage-\(getpid()).app", isDirectory: true)
        do {
            try? FileManager.default.removeItem(at: sameVolStageURL)
            try FileManager.default.moveItem(at: stagedAppURL, to: sameVolStageURL)
            try? FileManager.default.removeItem(at: stageDir)
        } catch {
            try? FileManager.default.removeItem(at: sameVolStageURL)
            try? FileManager.default.removeItem(at: stageDir)
            isPerformingInstall = false
            state = .failed("准备同卷原子替换目录失败: \(error.localizedDescription)", retryable: manifest)
            return
        }

        AppLogger.shared.log("Update", "校验通过，正在原子交换 \(targetAppPath) 并验证重启至 v\(manifest.version)…")

        let myPID = "\(getpid())"
        let swapScript = """
        OLD_PID="$1"
        STAGED_APP="$2"
        TARGET_APP="$3"
        SWAP_HELPER="$STAGED_APP/Contents/MacOS/AgentGaugeCleanup"
        INSTALLED_HELPER="$TARGET_APP/Contents/MacOS/AgentGaugeCleanup"

        i=0
        while kill -0 "$OLD_PID" 2>/dev/null && [ $i -lt 30 ]; do
          sleep 0.1
          i=$((i + 1))
        done
        if kill -0 "$OLD_PID" 2>/dev/null; then
          kill -TERM "$OLD_PID" 2>/dev/null || true
          sleep 0.2
        fi

        SWAPPED=0
        if [ -d "$TARGET_APP" ]; then
          if [ -x "$SWAP_HELPER" ] && "$SWAP_HELPER" --atomic-swap "$STAGED_APP" "$TARGET_APP"; then
            SWAPPED=1
          else
            # Fallback if swap helper missing: move existing to backup before moving staged in
            BACKUP_APP="${TARGET_APP}.backup.$$"
            rm -rf "$BACKUP_APP" 2>/dev/null || true
            if mv "$TARGET_APP" "$BACKUP_APP" && mv "$STAGED_APP" "$TARGET_APP"; then
              STAGED_APP="$BACKUP_APP"
              SWAPPED=1
            else
              [ -d "$BACKUP_APP" ] && [ ! -d "$TARGET_APP" ] && mv "$BACKUP_APP" "$TARGET_APP" 2>/dev/null || true
              rm -rf "$STAGED_APP" 2>/dev/null || true
              exit 1
            fi
          fi
        else
          if ! mv "$STAGED_APP" "$TARGET_APP"; then
            rm -rf "$STAGED_APP" 2>/dev/null || true
            exit 1
          fi
        fi

        /usr/bin/xattr -cr "$TARGET_APP" 2>/dev/null || true
        touch "$TARGET_APP" 2>/dev/null || true

        # Verify new app actually launches and stays alive BEFORE deleting previous backup; rollback automatically on failure!
        LAUNCH_OK=0
        if /usr/bin/open -n "$TARGET_APP"; then
          j=0
          while [ $j -lt 25 ]; do
            sleep 0.15
            if pgrep -f "$TARGET_APP/Contents/MacOS/AgentGauge" >/dev/null 2>&1; then
              LAUNCH_OK=1
              break
            fi
            j=$((j + 1))
          done
        fi

        if [ "$LAUNCH_OK" -eq 1 ]; then
          rm -rf "$STAGED_APP" 2>/dev/null || true
          exit 0
        fi

        # Launch failed -> atomically roll back to the previous working bundle!
        if [ "$SWAPPED" -eq 1 ] && [ -d "$STAGED_APP" ]; then
          if [ -x "$INSTALLED_HELPER" ] && "$INSTALLED_HELPER" --atomic-swap "$STAGED_APP" "$TARGET_APP"; then
            rm -rf "$STAGED_APP" 2>/dev/null || true
          else
            FAILED_APP="${TARGET_APP}.failed.$$"
            mv "$TARGET_APP" "$FAILED_APP" 2>/dev/null || true
            mv "$STAGED_APP" "$TARGET_APP" 2>/dev/null || true
            rm -rf "$FAILED_APP" 2>/dev/null || true
          fi
          /usr/bin/open -n "$TARGET_APP" 2>/dev/null || true
        fi
        exit 1
        """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        proc.arguments = [
            "/bin/sh",
            "-c",
            swapScript,
            "--",
            myPID,
            sameVolStageURL.path,
            targetAppPath
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            AgentGaugeStore.shared.shutdown()
            try proc.run()
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: sameVolStageURL)
            isPerformingInstall = false
            state = .failed("启动更新替换进程失败: \(error.localizedDescription)", retryable: manifest)
        }
    }

    private func downloadFileWithProgress(from url: URL, to destination: URL, manifest: ReleaseManifest) async -> Bool {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45.0)
        req.setValue("AgentGauge/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            try? FileManager.default.removeItem(at: destination)
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            let fh = try FileHandle(forWritingTo: destination)
            defer { try? fh.close() }

            let (bytes, response) = try await URLSession.shared.bytes(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let finalURL = http.url,
                  Self.isAllowedDownloadURL(finalURL) else {
                return false
            }

            let expectedLen = max(response.expectedContentLength, 2_400_000)
            var buffer = Data()
            buffer.reserveCapacity(65_536)
            var totalWritten: Int64 = 0
            var lastUIUpdate = CACurrentMediaTime()

            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 65_536 {
                    try fh.write(contentsOf: buffer)
                    totalWritten += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)

                    let now = CACurrentMediaTime()
                    if now - lastUIUpdate >= 0.08 {
                        lastUIUpdate = now
                        let prog = min(0.98, max(0.04, Double(totalWritten) / Double(expectedLen)))
                        self.state = .downloading(manifest, progress: prog)
                    }
                }
            }
            if !buffer.isEmpty {
                try fh.write(contentsOf: buffer)
                totalWritten += Int64(buffer.count)
            }
            guard totalWritten > 100_000 else { return false }
            self.state = .downloading(manifest, progress: 1.0)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Feed Parsers & Cryptographic Primitives (Testable & Pure)

    private static func parseSignedManifestJSON(_ data: Data, overrideZipURL: String? = nil) -> ReleaseManifest? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = (json["version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty,
              let feedZipUrl = (json["zipUrl"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !feedZipUrl.isEmpty,
              let sha256 = (json["sha256"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sha256.isEmpty,
              let sig = (json["signature"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sig.isEmpty else {
            return nil
        }

        let cleanVer = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let build = (json["build"] as? Int) ?? inferredBuildNumber(from: cleanVer)
        guard verifyManifestSignature(version: cleanVer, build: build, sha256: sha256, signatureBase64: sig) else {
            return nil
        }

        let notes = (json["notes"] as? [String]) ?? []
        let primaryZip = overrideZipURL ?? feedZipUrl
        let fallbackZip = (overrideZipURL != nil) ? feedZipUrl : (json["fallbackZipUrl"] as? String)
        return ReleaseManifest(
            version: cleanVer,
            build: build,
            publishedAt: json["publishedAt"] as? String,
            urgency: json["urgency"] as? String,
            title: json["title"] as? String,
            notes: notes,
            zipUrl: primaryZip,
            fallbackZipUrl: fallbackZip,
            dmgUrl: json["dmgUrl"] as? String,
            sha256: sha256.lowercased(),
            signature: sig,
            isFromSignedFeed: true
        )
    }

    private static func fetchPrimarySignedFeed() async -> ReleaseManifest? {
        guard var comps = URLComponents(url: primaryFeedURL, resolvingAgainstBaseURL: false) else { return nil }
        comps.queryItems = [URLQueryItem(name: "t", value: "\(Int(Date().timeIntervalSince1970 / 60))")]
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6.0)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        return parseSignedManifestJSON(data)
    }

    /// GitHub Releases fallback ALWAYS fetches and Ed25519-verifies the uploaded `latest.json` manifest asset
    /// — unsigned releases or missing signatures are strictly rejected!
    private static func fetchGitHubLatestRelease() async -> ReleaseManifest? {
        var req = URLRequest(url: githubLatestAPIURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6.5)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("AgentGauge", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else {
            return nil
        }

        guard let manifestAsset = assets.first(where: { ($0["name"] as? String)?.lowercased() == "latest.json" }),
              let manifestURLStr = manifestAsset["browser_download_url"] as? String,
              let manifestURL = URL(string: manifestURLStr),
              isAllowedDownloadURL(manifestURL) else {
            return nil
        }

        let zipAsset = assets.first {
            guard let name = ($0["name"] as? String)?.lowercased() else { return false }
            return name.hasSuffix(".zip") && name.contains("agentgauge")
        }
        let ghZipURL = (zipAsset?["browser_download_url"] as? String)
            .flatMap { URL(string: $0).flatMap { isAllowedDownloadURL($0) ? $0.absoluteString : nil } }

        var mReq = URLRequest(url: manifestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6.5)
        mReq.setValue("application/json", forHTTPHeaderField: "Accept")
        mReq.setValue("AgentGauge", forHTTPHeaderField: "User-Agent")

        guard let (mData, mResp) = try? await URLSession.shared.data(for: mReq),
              let mHTTP = mResp as? HTTPURLResponse, mHTTP.statusCode == 200,
              let finalURL = mHTTP.url, isAllowedDownloadURL(finalURL) else {
            return nil
        }

        return parseSignedManifestJSON(mData, overrideZipURL: ghZipURL)
    }

    public nonisolated static func canonicalSignedPayload(version: String, build: Int, sha256: String) -> Data {
        let cleanVer = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return Data("AgentGauge-Update-v1|\(cleanVer)|\(build)|\(sha256.lowercased())".utf8)
    }

    public nonisolated static func verifyManifestSignature(
        version: String,
        build: Int,
        sha256: String,
        signatureBase64: String,
        publicKeyBase64: String = releasePublicKeyBase64
    ) -> Bool {
        guard let pubData = Data(base64Encoded: publicKeyBase64),
              let sigData = Data(base64Encoded: signatureBase64),
              let pubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData) else {
            return false
        }
        let message = canonicalSignedPayload(version: version, build: build, sha256: sha256)
        return pubKey.isValidSignature(sigData, for: message)
    }

    public nonisolated static func verifyArchiveCryptographically(
        at archiveURL: URL,
        manifest: ReleaseManifest,
        publicKeyBase64: String = releasePublicKeyBase64
    ) throws {
        let data = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
        let computedHex = digest.map { String(format: "%02x", $0) }.joined()

        // Fail closed for ALL update sources: both SHA-256 and Ed25519 release signature are strictly mandatory!
        guard let expectedHex = manifest.sha256?.lowercased(), !expectedHex.isEmpty else {
            throw NSError(domain: "UpdateManager", code: 11, userInfo: [NSLocalizedDescriptionKey: "更新清单缺少哈希摘要，已拦截安装"])
        }
        guard computedHex == expectedHex else {
            throw NSError(domain: "UpdateManager", code: 10, userInfo: [NSLocalizedDescriptionKey: "更新包 SHA-256 校验不匹配，已拦截安装"])
        }
        guard let sig = manifest.signature, !sig.isEmpty,
              verifyManifestSignature(
                  version: manifest.version,
                  build: manifest.build,
                  sha256: computedHex,
                  signatureBase64: sig,
                  publicKeyBase64: publicKeyBase64
              ) else {
            throw NSError(domain: "UpdateManager", code: 12, userInfo: [NSLocalizedDescriptionKey: "更新包 Ed25519 数字签名校验未通过"])
        }
    }

    public nonisolated static func isRemoteNewer(
        remoteVersion: String,
        remoteBuild: Int,
        currentVersion: String,
        currentBuild: Int
    ) -> Bool {
        let rParts = parseSemVer(remoteVersion)
        let cParts = parseSemVer(currentVersion)
        if rParts != cParts {
            return rParts.lexicographicallyPrecedes(cParts) == false
        }
        return remoteBuild > currentBuild
    }

    private nonisolated static func parseSemVer(_ raw: String) -> [Int] {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: "-").first.map(String.init) ?? raw
        var nums = clean.split(separator: ".").map { Int($0) ?? 0 }
        while nums.count < 3 { nums.append(0) }
        return Array(nums.prefix(3))
    }

    private nonisolated static func inferredBuildNumber(from version: String) -> Int {
        let parts = parseSemVer(version)
        return parts[0] * 100 + parts[1] * 10 + parts[2]
    }

    private nonisolated static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return allowedDownloadHosts.contains(host)
    }

    private nonisolated static func extractZipArchive(at zipURL: URL, into destDir: URL) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-x", "-k", zipURL.path, destDir.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    private nonisolated static func clearQuarantineAttributes(at appURL: URL) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        proc.arguments = ["-cr", appURL.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
    }

    private nonisolated static func signingTeamIdentifier(for appURL: URL) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        proc.arguments = ["-dv", "--verbose=2", appURL.path]
        let errPipe = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = errPipe
        do {
            try proc.run()
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(separator: "\n") {
                if line.hasPrefix("TeamIdentifier=") {
                    let team = String(line.dropFirst("TeamIdentifier=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (team.isEmpty || team == "not set") ? nil : team
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    private nonisolated static func verifyExtractedBundle(
        at appURL: URL,
        expectedVersion: String? = nil,
        expectedBuild: Int? = nil,
        expectedTeamIdentifier: String? = nil
    ) -> Bool {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plistURL),
              (dict["CFBundleIdentifier"] as? String) == "com.kahlil.AgentGauge" else {
            return false
        }
        if let expectedVersion {
            let cleanExp = expectedVersion.hasPrefix("v") ? String(expectedVersion.dropFirst()) : expectedVersion
            guard (dict["CFBundleShortVersionString"] as? String) == cleanExp else {
                return false
            }
        }
        if let expectedBuild {
            guard let rawBuild = dict["CFBundleVersion"] as? String, Int(rawBuild) == expectedBuild else {
                return false
            }
        }
        let mainExec = appURL.appendingPathComponent("Contents/MacOS/AgentGauge").path
        let helperExec = appURL.appendingPathComponent("Contents/MacOS/AgentGaugeCleanup").path
        guard FileManager.default.isExecutableFile(atPath: mainExec),
              FileManager.default.isExecutableFile(atPath: helperExec) else {
            return false
        }

        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--deep", "--strict", appURL.path]
        verify.standardOutput = FileHandle.nullDevice
        verify.standardError = FileHandle.nullDevice
        do {
            try verify.run()
            verify.waitUntilExit()
            guard verify.terminationStatus == 0 else { return false }
        } catch {
            return false
        }

        if let expectedTeam = expectedTeamIdentifier {
            guard signingTeamIdentifier(for: appURL) == expectedTeam else {
                return false
            }
        }
        return true
    }
}
