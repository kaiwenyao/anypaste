import AppKit

/// Menu bar entry point. AnyPaste is a pure agent app (LSUIElement), so the
/// status item — not a window — is its main UI surface.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
