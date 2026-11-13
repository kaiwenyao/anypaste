import AppKit
import SwiftUI

/// Standalone `NSWindow` based windows keep the app a menu bar agent while
/// still letting Settings and onboarding come to the front predictably.
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if window == nil { buildWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildWindow() {
        let root = SettingsView()
            .environmentObject(AppSettings.shared)
            .environmentObject(AppController.shared)
        let hosting = NSHostingView(rootView: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AnyPaste 设置"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("AnyPasteSettingsWindow")
        self.window = window
    }
}

final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if window == nil { buildWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }

    private func buildWindow() {
        let root = OnboardingView(onFinish: { [weak self] in self?.close() })
            .environmentObject(AppSettings.shared)
            .environmentObject(AppController.shared)
        let hosting = NSHostingView(rootView: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "欢迎使用 AnyPaste"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
    }
}

enum AboutPanel {
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "把剪贴板里的文字逐字“敲”进当前应用,用于远程桌面、终端、"
                + "禁止粘贴的输入框等场景。\n根据对 AnyPaste.exe 的逆向结果,用 SwiftUI 原生重写。",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
