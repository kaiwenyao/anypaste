import AppKit

/// Menu bar entry point. AnyPaste is an agent app (LSUIElement) whose status
/// item — not a window — is the main UI surface. The default Dock icon is a
/// runtime activation-policy change applied in AppController.start() from the
/// saved preference, so this initial policy only matters for headless launches.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
