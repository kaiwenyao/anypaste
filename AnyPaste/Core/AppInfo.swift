import Foundation

/// Bundle level constants and small helpers shared across the app.
enum AppInfo {
    static let bundleIdentifier = "com.anypaste.mac"
    static let name = "AnyPaste"

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AnyPaste", isDirectory: true)
    }

    static var logDirectory: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return base.appendingPathComponent("Logs/AnyPaste", isDirectory: true)
    }

    static func ensureDirectories() {
        for directory in [supportDirectory, logDirectory] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}

/// A deliberately tiny file logger. Logging must never affect typing behavior.
enum AppLog {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func info(_ message: String) {
        write("INFO  \(message)")
    }

    static func error(_ message: String) {
        write("ERROR \(message)")
    }

    private static func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
        do {
            try FileManager.default.createDirectory(at: AppInfo.logDirectory, withIntermediateDirectories: true)
            let url = AppInfo.logDirectory.appendingPathComponent("anypaste.log")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            // Intentionally ignored: stderr already received the line.
        }
    }
}
