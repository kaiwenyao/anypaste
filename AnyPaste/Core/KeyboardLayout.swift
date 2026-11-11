import AppKit
import Carbon

/// Resolves characters to physical key codes for the *current* keyboard layout.
///
/// Typing through real key codes keeps synthetic input compatible with apps that
/// only look at `virtualKey` (many Electron/Java/remote clients do). Characters a
/// layout cannot produce (CJK, emoji, …) fall back to pure Unicode events, which
/// is the only way to inject them at all.
final class KeyboardLayout {
    static let shared = KeyboardLayout()

    struct Entry {
        let keyCode: CGKeyCode
        let shift: Bool
    }

    private let lock = NSLock()
    private var table: [Character: Entry] = [:]
    private var usesLayoutData = false
    private var localizedName = "Unknown"

    private init() {
        reload()
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil
        )
    }

    @objc private func inputSourceChanged() {
        DispatchQueue.main.async { [weak self] in self?.reload() }
    }

    /// True when the active input source exposes a Unicode key layout. When an
    /// IME is active instead, every character is injected as Unicode text.
    var hasPhysicalLayout: Bool {
        lock.lock()
        defer { lock.unlock() }
        return usesLayoutData
    }

    var displayName: String {
        lock.lock()
        defer { lock.unlock() }
        return localizedName
    }

    func mapping(for character: Character) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return table[character]
    }

    func reload() {
        var newTable: [Character: Entry] = [:]
        var hasData = false
        var name = "Unknown"

        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() {
            if let rawName = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                name = Unmanaged<CFString>.fromOpaque(rawName).takeUnretainedValue() as String
            }

            if let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
                let data = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue() as Data
                if let parsed = KeyboardLayout.translateLayout(data) {
                    newTable = parsed
                    hasData = !parsed.isEmpty
                }
            }
        }

        if newTable.isEmpty {
            newTable = KeyboardLayout.fallbackUS
            name = name == "Unknown" ? "US (fallback)" : name + " (fallback)"
        }

        lock.lock()
        table = newTable
        usesLayoutData = hasData
        localizedName = name
        lock.unlock()
    }

    private static func translateLayout(_ data: Data) -> [Character: Entry]? {
        var result: [Character: Entry] = [:]
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            let keyboardType = UInt32(LMGetKbdType())
            for keyCode in 0..<128 {
                for shift in [false, true] {
                    var deadKeyState: UInt32 = 0
                    var characters = [UniChar](repeating: 0, count: 8)
                    var length = 0
                    let modifiers: UInt32 = shift ? 0x0002 : 0
                    let status = UCKeyTranslate(
                        layout,
                        UInt16(keyCode),
                        UInt16(kUCKeyActionDisplay),
                        modifiers,
                        keyboardType,
                        OptionBits(kUCKeyTranslateNoDeadKeysMask),
                        &deadKeyState,
                        characters.count,
                        &length,
                        &characters
                    )
                    guard status == noErr, length > 0 else { continue }
                    let text = String(utf16CodeUnits: characters, count: length)
                    guard text.count == 1, let character = text.first else { continue }
                    if result[character] == nil {
                        result[character] = Entry(keyCode: CGKeyCode(keyCode), shift: shift)
                    }
                }
            }
        }
        return result
    }

    /// Minimal US QWERTY map used when the active input source has no layout data.
    private static let fallbackUS: [Character: Entry] = {
        let plain: [(Character, CGKeyCode)] = [
            ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5),
            ("z", 6), ("x", 7), ("c", 8), ("v", 9), ("b", 11), ("q", 12),
            ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("1", 18),
            ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("=", 24),
            ("9", 25), ("7", 26), ("-", 27), ("8", 28), ("0", 29), ("]", 30),
            ("o", 31), ("u", 32), ("[", 33), ("i", 34), ("p", 35), ("l", 37),
            ("j", 38), ("'", 39), ("k", 40), (";", 41), ("\\", 42), (",", 43),
            ("/", 44), ("n", 45), ("m", 46), (".", 47), (" ", 49), ("`", 50),
        ]
        let shifted: [(Character, CGKeyCode)] = [
            ("!", 18), ("@", 19), ("#", 20), ("$", 21), ("%", 23), ("^", 22),
            ("&", 26), ("*", 28), ("(", 25), (")", 29), ("_", 27), ("+", 24),
            ("{", 33), ("}", 30), ("|", 42), (":", 41), ("\"", 39), ("<", 43),
            (">", 47), ("?", 44), ("~", 50),
        ]
        var map: [Character: Entry] = [:]
        for (character, keyCode) in plain {
            map[character] = Entry(keyCode: keyCode, shift: false)
        }
        for (character, keyCode) in shifted {
            map[character] = Entry(keyCode: keyCode, shift: true)
        }
        // Upper-case letters share the key code of their lower-case partner,
        // with Shift added.
        for (character, keyCode) in plain where character.isLetter {
            guard let upper = character.uppercased().first, map[upper] == nil else { continue }
            map[upper] = Entry(keyCode: keyCode, shift: true)
        }
        return map
    }()

    /// Human readable key name for the hotkey recorder and menu labels.
    static func keyName(forKeyCode code: UInt32) -> String {
        switch Int(code) {
        case 0: return "A"; case 1: return "S"; case 2: return "D"; case 3: return "F"
        case 4: return "H"; case 5: return "G"; case 6: return "Z"; case 7: return "X"
        case 8: return "C"; case 9: return "V"; case 10: return "§"; case 11: return "B"
        case 12: return "Q"; case 13: return "W"; case 14: return "E"; case 15: return "R"
        case 16: return "Y"; case 17: return "T"; case 18: return "1"; case 19: return "2"
        case 20: return "3"; case 21: return "4"; case 22: return "6"; case 23: return "5"
        case 24: return "="; case 25: return "9"; case 26: return "7"; case 27: return "-"
        case 28: return "8"; case 29: return "0"; case 30: return "]"; case 31: return "O"
        case 32: return "U"; case 33: return "["; case 34: return "I"; case 35: return "P"
        case 36: return "↩"; case 37: return "L"; case 38: return "J"; case 39: return "'"
        case 40: return "K"; case 41: return ";"; case 42: return "\\"; case 43: return ","
        case 44: return "/"; case 45: return "N"; case 46: return "M"; case 47: return "."
        case 48: return "⇥"; case 49: return "Space"; case 50: return "`"
        case 51: return "⌫"; case 53: return "Esc"; case 117: return "⌦"
        case 115: return "↖"; case 116: return "⇞"; case 119: return "↘"; case 121: return "⇟"
        case 123: return "←"; case 124: return "→"; case 125: return "↓"; case 126: return "↑"
        case 122: return "F1"; case 120: return "F2"; case 99: return "F3"; case 118: return "F4"
        case 96: return "F5"; case 97: return "F6"; case 98: return "F7"; case 100: return "F8"
        case 101: return "F9"; case 109: return "F10"; case 103: return "F11"; case 111: return "F12"
        default: return "Key\(code)"
        }
    }
}
