import CoreGraphics
import Foundation

/// One atomic keyboard action the typer should perform.
///
/// When `keyCode` is present the event carries a real virtual key so apps that
/// ignore Unicode payloads still receive something meaningful; otherwise the
/// event is a pure Unicode injection.
struct Stroke {
    let keyCode: CGKeyCode?
    let flags: CGEventFlags
    let text: String
}

/// Pure translation of clipboard text into the keystroke sequence. Kept free of
/// side effects so it can be covered by the built-in self test.
enum KeystrokePlanner {
    static let returnKey: CGKeyCode = 36
    static let tabKey: CGKeyCode = 48
    static let spaceKey: CGKeyCode = 49
    static let deleteKey: CGKeyCode = 51

    static func strokes(for text: String, layout: KeyboardLayout = .shared) -> [Stroke] {
        let useKeyCodes = layout.hasPhysicalLayout
        var strokes: [Stroke] = []
        strokes.reserveCapacity(text.count)

        for character in text {
            switch character {
            case "\n", "\r":
                strokes.append(Stroke(keyCode: returnKey, flags: [], text: "\r"))
            case "\t":
                strokes.append(Stroke(keyCode: tabKey, flags: [], text: "\t"))
            case " ":
                strokes.append(Stroke(keyCode: spaceKey, flags: [], text: " "))
            case "\u{8}":
                strokes.append(Stroke(keyCode: deleteKey, flags: [], text: ""))
            case "\u{0}", "\u{7}", "\u{1B}":
                // NUL / bell are meaningless here; ESC would cancel the target UI.
                continue
            default:
                if useKeyCodes, let entry = layout.mapping(for: character) {
                    strokes.append(
                        Stroke(
                            keyCode: entry.keyCode,
                            flags: entry.shift ? .maskShift : [],
                            text: String(character)
                        )
                    )
                } else {
                    strokes.append(Stroke(keyCode: nil, flags: [], text: String(character)))
                }
            }
        }
        return strokes
    }
}
