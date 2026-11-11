import AppKit
import Combine

/// Owns the menu bar status item and its menu. An explicit `NSStatusItem` is
/// used instead of SwiftUI's `MenuBarExtra` so the item can be verified, updated
/// with live progress and rebuilt deterministically.
final class StatusItemController: NSObject, NSMenuDelegate {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    private let controller = AppController.shared
    private let settings = AppSettings.shared

    private override init() { super.init() }

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = symbolImage("keyboard.badge.ellipsis")
            button.imagePosition = .imageOnly
            button.toolTip = "AnyPaste · \(settings.hotKey.displayString)"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu

        statusItem = item
        observe()
        refresh()
        AppLog.info("菜单栏图标已就绪")

        scheduleAvailabilityChecks()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard let button = item.button else {
                AppLog.error("状态项没有 button")
                return
            }
            let window = button.window
            AppLog.info(
                "状态项诊断:visible=\(item.isVisible) hasWindow=\(window != nil) "
                    + "buttonFrame=\(button.frame) windowFrame=\(String(describing: window?.frame)) "
                    + "screen=\(String(describing: NSScreen.main?.frame)) "
                    + "buttonVisible=\(!button.isHidden) alpha=\(button.alphaValue)"
            )
        }
    }

    /// macOS writes `NSStatusItem Preferred Position …` into the app's own
    /// preferences once it lays the item out. If that never happens the menu bar
    /// is not presenting items (seen on some macOS builds), so the app falls back
    /// to a Dock icon instead of becoming unreachable.
    private func scheduleAvailabilityChecks() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.evaluateMenuBarAvailability()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            self?.evaluateMenuBarAvailability()
        }
    }

    private func evaluateMenuBarAvailability() {
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        let bundleID = Bundle.main.bundleIdentifier ?? AppInfo.bundleIdentifier
        let domain = UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]
        let laidOut = domain.keys.contains { $0.hasPrefix("NSStatusItem Preferred Position") }

        if laidOut {
            AppController.shared.setMenuBarItemVisible(true)
            return
        }
        AppLog.info("菜单栏布局检测:状态项未排布,启用 Dock 图标备用入口")
        AppController.shared.setMenuBarItemVisible(false)
    }

    private func observe() {
        controller.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func symbolImage(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "AnyPaste")
        image?.isTemplate = true
        return image
    }

    func refresh() {
        guard let item = statusItem, let button = item.button else { return }

        button.image = symbolImage(controller.menuBarSymbol)
        let title = controller.menuBarTitle
        button.title = title
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        button.toolTip = "AnyPaste · \(controller.statusText)"
        item.length = NSStatusItem.variableLength
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        build(menu)
    }

    private func build(_ menu: NSMenu) {
        menu.removeAllItems()

        let statusLine = NSMenuItem(title: controller.statusText, action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        menu.addItem(.separator())

        let typeItem = NSMenuItem(
            title: "立即输入剪贴板",
            action: #selector(typeClipboardNow(_:)),
            keyEquivalent: ""
        )
        typeItem.target = self
        typeItem.isEnabled = settings.isEnabled && !controller.isTyping
        menu.addItem(typeItem)

        if controller.isTyping {
            let stopItem = NSMenuItem(title: "停止输入 (Esc)", action: #selector(stopTyping(_:)), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
        }

        menu.addItem(.separator())

        let enabledItem = NSMenuItem(title: "启用热键", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = settings.isEnabled ? .on : .off
        menu.addItem(enabledItem)

        if let error = controller.hotKeyError {
            let errorItem = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        } else if !controller.permissionGranted {
            let permissionItem = NSMenuItem(
                title: "缺少辅助功能权限 — 点此查看",
                action: #selector(openOnboarding(_:)),
                keyEquivalent: ""
            )
            permissionItem.target = self
            menu.addItem(permissionItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let onboardingItem = NSMenuItem(
            title: "权限与引导…",
            action: #selector(openOnboarding(_:)),
            keyEquivalent: ""
        )
        onboardingItem.target = self
        menu.addItem(onboardingItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "关于 AnyPaste", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "退出 AnyPaste", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func typeClipboardNow(_ sender: Any?) {
        controller.typeClipboardNow(fromMenu: true)
    }

    @objc private func stopTyping(_ sender: Any?) {
        controller.stopTyping()
    }

    @objc private func toggleEnabled(_ sender: Any?) {
        settings.isEnabled.toggle()
        controller.applyHotKey()
    }

    @objc private func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    @objc private func openOnboarding(_ sender: Any?) {
        OnboardingWindowController.shared.show()
    }

    @objc private func showAbout(_ sender: Any?) {
        AboutPanel.show()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
