import AppKit

enum ClipboardService {
    /// Text currently on the general pasteboard, or nil when it holds no text.
    static func text() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    static func hasText() -> Bool {
        NSPasteboard.general.string(forType: .string)?.isEmpty == false
    }

    static func types() -> [String] {
        (NSPasteboard.general.types ?? []).map(\.rawValue)
    }
}
