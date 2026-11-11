import AppKit
import ApplicationServices
import Carbon

enum PermissionService {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks macOS to show the Accessibility prompt and to list the app in
    /// System Settings. The key is spelled literally so the call works with
    /// every ApplicationServices import flavour.
    static func requestAccessibilityPrompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static var isSecureInputEnabled: Bool {
        IsSecureEventInputEnabled()
    }

    static func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }
}
