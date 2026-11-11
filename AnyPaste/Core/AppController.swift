import AppKit
import SwiftUI

/// Central coordinator: owns the hotkey, the menu bar state and the typing flow.
final class AppController: ObservableObject {
    static let shared = AppController()

    let settings = AppSettings.shared

    @Published private(set) var isTyping = false
    @Published private(set) var sent = 0
    @Published private(set) var total = 0
    @Published private(set) var permissionGranted = PermissionService.isAccessibilityTrusted
    @Published private(set) var hotKeyError: String?
    @Published private(set) var menuBarItemVisible = true
    @Published private(set) var lastMessage: String?

    private var permissionTimer: Timer?
    private var hotKeySuspended = false

    private init() {}

    // MARK: - Lifecycle

    func start() {
        AppInfo.ensureDirectories()

        HotKeyManager.shared.onPressed = { [weak self] in
            self?.typeClipboardNow(fromMenu: false)
        }

        NotificationCenter.default.addObserver(
            forName: AppSettings.hotKeyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyHotKey()
        }

        applyHotKey()
        startPermissionPolling()

        AppLog.info(
            "AnyPaste \(AppInfo.version) 已启动;热键=\(settings.hotKey.displayString);"
                + "键盘布局=\(KeyboardLayout.shared.displayName);辅助功能=\(permissionGranted)"
        )
    }

    /// Keeps the app reachable: a normal menu bar agent when the status item is
    /// presented, a Dock-icon app when the system fails to present status items.
    func setMenuBarItemVisible(_ visible: Bool) {
        guard menuBarItemVisible != visible else { return }
        menuBarItemVisible = visible
        NSApp.setActivationPolicy(visible ? .accessory : .regular)
        AppLog.info("激活策略切换为 \(visible ? "accessory(仅菜单栏)" : "regular(Dock 备用入口)")")
        if !visible {
            HUDWindow.show("菜单栏图标未显示,已启用 Dock 图标作为入口")
        }
    }

    func startPermissionPolling() {
        permissionTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshPermission()
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    func refreshPermission() {
        let granted = PermissionService.isAccessibilityTrusted
        if granted != permissionGranted {
            permissionGranted = granted
            AppLog.info("辅助功能授权状态变更为 \(granted)")
        }
    }

    // MARK: - Hotkey

    func applyHotKey() {
        guard settings.isEnabled, !hotKeySuspended else {
            HotKeyManager.shared.unregister()
            return
        }
        do {
            try HotKeyManager.shared.register(settings.hotKey)
            hotKeyError = nil
        } catch {
            hotKeyError = error.localizedDescription
            AppLog.error("热键注册失败: \(error.localizedDescription)")
        }
    }

    func suspendHotKey() {
        hotKeySuspended = true
        HotKeyManager.shared.unregister()
    }

    func resumeHotKey() {
        hotKeySuspended = false
        applyHotKey()
    }

    func applyHotKey(_ config: HotKeyConfig) throws {
        guard config.isUsable else {
            throw HotKeyManager.RegistrationError.failed(OSStatus(-1))
        }
        try HotKeyManager.shared.register(config)
        settings.hotKey = config
        hotKeyError = nil
    }

    // MARK: - Typing

    func typeClipboardNow(fromMenu: Bool) {
        AppLog.info("触发输入(fromMenu=\(fromMenu))")
        guard !isTyping else { return }
        guard settings.isEnabled else {
            HUDWindow.show("AnyPaste 已暂停")
            return
        }

        refreshPermission()
        guard permissionGranted else {
            HUDWindow.show("请先在系统设置的「辅助功能」中允许 AnyPaste")
            PermissionService.requestAccessibilityPrompt()
            PermissionService.openAccessibilitySettings()
            return
        }

        guard !PermissionService.isSecureInputEnabled else {
            HUDWindow.show("当前应用处于安全输入状态,无法模拟按键")
            return
        }

        guard let text = ClipboardService.text(), !text.isEmpty else {
            HUDWindow.show("剪贴板中没有可输入的文本")
            return
        }

        // A menu item needs the menu to dismiss before keystrokes land in the
        // previously focused app; the hotkey path can start almost immediately.
        let delay = fromMenu ? settings.menuTriggerDelayMs : 60
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) { [weak self] in
            self?.beginTyping(text)
        }
    }

    func stopTyping() {
        KeystrokeTyper.shared.cancel()
    }

    private func beginTyping(_ text: String) {
        guard !isTyping else { return }
        isTyping = true
        sent = 0
        total = text.count
        lastMessage = nil

        KeystrokeTyper.shared.start(
            text: text,
            delayMs: settings.delayMs,
            progress: { [weak self] sent, total in
                self?.sent = sent
                self?.total = total
            },
            completion: { [weak self] result in
                guard let self else { return }
                self.isTyping = false
                switch result {
                case .success(let count):
                    AppLog.info("输入完成,共 \(count) 个字符")
                    self.lastMessage = "已输入 \(count) 个字符"
                case .failure(let error):
                    AppLog.error("输入失败: \(error.localizedDescription)")
                    self.lastMessage = error.localizedDescription
                    HUDWindow.show(error.localizedDescription)
                }
            }
        )
    }

    // MARK: - Menu bar presentation

    var menuBarTitle: String {
        if isTyping && settings.showProgress {
            return "\(sent)/\(total)"
        }
        return ""
    }

    var menuBarSymbol: String {
        if isTyping { return "keyboard.badge.ellipsis" }
        if !settings.isEnabled { return "pause.circle" }
        return permissionGranted ? "keyboard.badge.ellipsis" : "exclamationmark.triangle"
    }

    var statusText: String {
        if isTyping { return "正在输入 \(sent)/\(total)" }
        if !settings.isEnabled { return "已暂停(热键未启用)" }
        if !permissionGranted { return "缺少辅助功能权限" }
        return "就绪 · \(settings.hotKey.displayString)"
    }
}
