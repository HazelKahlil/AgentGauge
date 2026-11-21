import Darwin
import Foundation

public struct LogEntry: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let timestamp: Date
    public let timeString: String
    public let category: String
    public let message: String
}

@MainActor
public final class AppLogger: ObservableObject {
    public static let shared = AppLogger()

    @Published public private(set) var entries: [LogEntry] = []
    private let maxEntries = 160
    private let logFileURL: URL
    private let ioQueue = DispatchQueue(label: "com.kahlil.AgentGauge.logger", qos: .utility)

    nonisolated private static func fastShortTime(_ date: Date) -> String {
        var secs = time_t(date.timeIntervalSince1970)
        var tmVal = tm()
        localtime_r(&secs, &tmVal)
        return String(format: "%02d:%02d:%02d", tmVal.tm_hour, tmVal.tm_min, tmVal.tm_sec)
    }

    nonisolated private static func formatTimestamp(_ date: Date) -> String {
        var secs = time_t(date.timeIntervalSince1970)
        var tmVal = tm()
        localtime_r(&secs, &tmVal)
        let ms = Int((date.timeIntervalSince1970 - floor(date.timeIntervalSince1970)) * 1000.0)
        return String(
            format: "%04d-%02d-%02d %02d:%02d:%02d.%03d",
            tmVal.tm_year + 1900, tmVal.tm_mon + 1, tmVal.tm_mday,
            tmVal.tm_hour, tmVal.tm_min, tmVal.tm_sec, max(0, min(999, ms))
        )
    }

    private init() {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.logFileURL = logsDir.appendingPathComponent("AgentGauge.log")
    }

    public func log(_ category: String, _ message: String) {
        let now = Date()
        let entry = LogEntry(
            timestamp: now,
            timeString: Self.fastShortTime(now),
            category: category,
            message: message
        )
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        let targetURL = logFileURL
        ioQueue.async {
            let line = "\(Self.formatTimestamp(now)) [\(category)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: targetURL.path) {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: targetURL.path),
                   let size = attrs[.size] as? UInt64, size > 256_000 {
                    try? data.write(to: targetURL, options: .atomic)
                } else if let fh = try? FileHandle(forWritingTo: targetURL) {
                    _ = try? fh.seekToEnd()
                    try? fh.write(contentsOf: data)
                    try? fh.close()
                }
            } else {
                try? data.write(to: targetURL, options: .atomic)
            }
        }
    }

    public func clear() {
        entries.removeAll()
        let targetURL = logFileURL
        ioQueue.async {
            try? Data().write(to: targetURL, options: .atomic)
        }
    }
}
