import AppKit

/// The application menu bar. AnyPaste is a menu bar agent (optionally showing a
/// Dock icon), but while one of its windows is frontmost it still gets a standard
/// menu bar. Installing an explicit main menu is what makes ⌘W and ⌘Q work:
/// without one AppKit has nowhere to dispatch those key equivalents.
enum AppMenu {
    static let closeWindowKeyEquivalent = "w"
    static let quitKeyEquivalent = "q"

    static func install() {
        NSApp.mainMenu = build()
    }

    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(fileMenuItem())
        return mainMenu
    }

    /// Finds a key-equivalent item in the main menu or any of its submenus.
    static func item(in menu: NSMenu, keyEquivalent: String) -> NSMenuItem? {
        for item in menu.items {
            if item.keyEquivalent == keyEquivalent {
                return item
            }
            if let submenu = item.submenu,
               let match = self.item(in: submenu, keyEquivalent: keyEquivalent) {
                return match
            }
        }
        return nil
    }

    private static func appMenuItem() -> NSMenuItem {
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: AppInfo.name)

        let aboutItem = NSMenuItem(
            title: "关于 AnyPaste",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = NSApp
        appMenu.addItem(aboutItem)

        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 AnyPaste",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: quitKeyEquivalent
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = NSApp
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        return appMenuItem
    }

    private static func fileMenuItem() -> NSMenuItem {
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")

        // A nil target sends `performClose:` down the responder chain, so it
        // always closes the key window and leaves the app running.
        let closeItem = NSMenuItem(
            title: "关闭窗口",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: closeWindowKeyEquivalent
        )
        closeItem.keyEquivalentModifierMask = .command
        closeItem.target = nil
        fileMenu.addItem(closeItem)

        fileMenuItem.submenu = fileMenu
        return fileMenuItem
    }
}
