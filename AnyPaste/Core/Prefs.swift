import AppKit
import Carbon.HIToolbox

/// Carbon modifier bits as understood by `RegisterEventHotKey`.
enum CarbonMod {
    static let command: UInt32 = 0x0100
    static let shift: UInt32 = 0x0200
    static let option: UInt32 = 0x0800
    static let control: UInt32 = 0x1000

    static func from(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= command }
        if flags.contains(.shift) { result |= shift }
        if flags.contains(.option) { result |= option }
        if flags.contains(.control) { result |= control }
        return result
    }

    static func toNSEventFlags(_ carbon: UInt32) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if carbon & command != 0 { result.insert(.command) }
        if carbon & shift != 0 { result.insert(.shift) }
        if carbon & option != 0 { result.insert(.option) }
        if carbon & control != 0 { result.insert(.control) }
        return result
    }
}

/// A global hotkey expressed in Carbon terms so it can be handed to
/// `RegisterEventHotKey` without any lossy conversion.
struct HotKeyConfig: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let presetControlShiftV = HotKeyConfig(keyCode: 9, modifiers: CarbonMod.control | CarbonMod.shift)

    var displayString: String {
        var text = ""
        if modifiers & CarbonMod.control != 0 { text += "⌃" }
        if modifiers & CarbonMod.option != 0 { text += "⌥" }
        if modifiers & CarbonMod.shift != 0 { text += "⇧" }
        if modifiers & CarbonMod.command != 0 { text += "⌘" }
        return text + KeyboardLayout.keyName(forKeyCode: keyCode)
    }

    /// A hotkey is only useful when it carries at least one "real" modifier.
    var isUsable: Bool {
        modifiers & (CarbonMod.command | CarbonMod.option | CarbonMod.control) != 0
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Factory default for the per-character delay. 5 ms keeps up with fast
    /// targets (terminals, remote desktops, Electron apps) better than 1 ms.
    static let defaultDelayMs = 5

    private enum Keys {
        static let enabled = "anypaste.enabled"
        static let hotKeyCode = "anypaste.hotKeyCode"
        static let hotKeyModifiers = "anypaste.hotKeyModifiers"
        static let delayMs = "anypaste.delayMs"
        static let showProgress = "anypaste.showProgress"
        static let completedOnboarding = "anypaste.completedOnboarding"
        static let menuTriggerDelayMs = "anypaste.menuTriggerDelayMs"
        static let showInDock = "anypaste.showInDock"
    }

    private let defaults: UserDefaults

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }

    @Published var hotKey: HotKeyConfig {
        didSet {
            guard hotKey != oldValue else { return }
            defaults.set(Int(hotKey.keyCode), forKey: Keys.hotKeyCode)
            defaults.set(Int(hotKey.modifiers), forKey: Keys.hotKeyModifiers)
            NotificationCenter.default.post(name: AppSettings.hotKeyDidChange, object: nil)
        }
    }

    @Published var delayMs: Int {
        didSet { defaults.set(delayMs, forKey: Keys.delayMs) }
    }

    @Published var showProgress: Bool {
        didSet { defaults.set(showProgress, forKey: Keys.showProgress) }
    }

    /// Whether the app is also reachable from the Dock. On by default: the
    /// status item alone is not reliable on every macOS build, and a Dock icon
    /// gives the app a second, always-visible entry point.
    @Published var showInDock: Bool {
        didSet {
            guard showInDock != oldValue else { return }
            defaults.set(showInDock, forKey: Keys.showInDock)
            NotificationCenter.default.post(name: AppSettings.showInDockDidChange, object: nil)
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.completedOnboarding) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                try LaunchAtLogin.setEnabled(launchAtLogin)
                launchAtLoginError = nil
            } catch {
                launchAtLoginError = error.localizedDescription
                launchAtLogin = !launchAtLogin
            }
        }
    }

    @Published var launchAtLoginError: String?

    static let hotKeyDidChange = Notification.Name("anypaste.hotKeyDidChange")
    static let showInDockDidChange = Notification.Name("anypaste.showInDockDidChange")

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Registered defaults: everything is on out of the box, mirroring the
        // original script which needed no configuration at all.
        defaults.register(defaults: [
            Keys.enabled: true,
            Keys.hotKeyCode: Int(HotKeyConfig.presetControlShiftV.keyCode),
            Keys.hotKeyModifiers: Int(HotKeyConfig.presetControlShiftV.modifiers),
            Keys.delayMs: Self.defaultDelayMs,
            Keys.showProgress: true,
            Keys.completedOnboarding: false,
            Keys.showInDock: true,
        ])

        isEnabled = defaults.bool(forKey: Keys.enabled)

        let storedKeyCode = UInt32(defaults.integer(forKey: Keys.hotKeyCode))
        let storedModifiers = UInt32(defaults.integer(forKey: Keys.hotKeyModifiers))
        let stored = HotKeyConfig(keyCode: storedKeyCode, modifiers: storedModifiers)
        hotKey = stored.isUsable ? stored : HotKeyConfig.presetControlShiftV

        delayMs = min(max(defaults.integer(forKey: Keys.delayMs), 0), 50)
        showProgress = defaults.bool(forKey: Keys.showProgress)
        showInDock = defaults.bool(forKey: Keys.showInDock)
        hasCompletedOnboarding = defaults.bool(forKey: Keys.completedOnboarding)

        // Keep the launch-at-login switch honest about the real system state.
        launchAtLogin = LaunchAtLogin.isEnabled
        launchAtLoginError = nil
    }

    func resetToDefaults() {
        hotKey = .presetControlShiftV
        delayMs = Self.defaultDelayMs
        showProgress = true
        isEnabled = true
        showInDock = true
    }

    /// Delay used when typing is triggered from the menu bar: the menu needs a
    /// moment to dismiss before keystrokes reach the previously focused app.
    var menuTriggerDelayMs: Int {
        let value = defaults.integer(forKey: Keys.menuTriggerDelayMs)
        return value > 0 ? value : 320
    }
}
