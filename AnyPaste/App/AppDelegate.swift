import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var e2eWindow: NSWindow?
    private var e2eTextView: NSTextView?
    private var e2eFinished = false
    private var e2eReceivedEvents = 0
    private var e2eMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppMenu.install()

        let arguments = CommandLine.arguments

        if arguments.contains("--self-test") {
            runSelfTest(requireAccessibility: !arguments.contains("--skip-accessibility-check"))
            return
        }
        if arguments.contains("--e2e-test") {
            runEndToEndTest()
            return
        }

        AppController.shared.start()
        StatusItemController.shared.install()

        if arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                SettingsWindowController.shared.show()
            }
        }

        if !AppSettings.shared.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                OnboardingWindowController.shared.show()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregister()
    }

    // MARK: - Headless self test

    private func runSelfTest(requireAccessibility: Bool) {
        let report = Diagnostics.run(requireAccessibility: requireAccessibility)
        Diagnostics.save(report)
        let text = Diagnostics.encode(report) + "\n"
        FileHandle.standardOutput.write(Data(text.utf8))
        fflush(stdout)
        exit(report.ok ? 0 : 1)
    }

    // MARK: - End to end typing test

    private func runEndToEndTest() {
        NSApp.setActivationPolicy(.regular)

        let expected = "AnyPaste E2E: {}^+! 100%\n\t第二行,你好世界! 👋"

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AnyPaste E2E"

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 620, height: 260))
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 620, height: 260))
        textView.isRichText = false
        textView.isEditable = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = ""
        scrollView.documentView = textView

        window.contentView = scrollView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(textView)

        e2eWindow = window
        e2eTextView = textView
        e2eMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.e2eReceivedEvents += 1
            return event
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(textView)

            guard AXIsProcessTrusted() else {
                self.finishEndToEnd(ok: false, reason: "ax-not-trusted", expected: expected, actual: "")
                return
            }

            let delay = CommandLine.arguments.first { $0.hasPrefix("--delay=") }
                .flatMap { Int($0.dropFirst("--delay=".count)) } ?? 1

            KeystrokeTyper.shared.start(text: expected, delayMs: delay) { result in
                switch result {
                case .success:
                    // The WindowServer delivers events asynchronously; let the
                    // last keystroke land before comparing.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let actual = textView.string
                        self.finishEndToEnd(
                            ok: actual == expected,
                            reason: actual == expected ? "ok" : "mismatch",
                            expected: expected,
                            actual: actual
                        )
                    }
                case .failure(let error):
                    self.finishEndToEnd(
                        ok: false,
                        reason: error.localizedDescription,
                        expected: expected,
                        actual: textView.string
                    )
                }
            }
        }

        // Safety net so a stuck run can never hang the verification script.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            self.finishEndToEnd(
                ok: false,
                reason: "timeout",
                expected: expected,
                actual: self.e2eTextView?.string ?? ""
            )
        }
    }

    private func finishEndToEnd(ok: Bool, reason: String, expected: String, actual: String) {
        guard !e2eFinished else { return }
        e2eFinished = true

        if let monitor = e2eMonitor {
            NSEvent.removeMonitor(monitor)
            e2eMonitor = nil
        }

        Diagnostics.saveEndToEnd(["reason": reason, "expected": expected, "actual": actual], ok: ok)

        let payload: [String: Any] = [
            "ok": ok,
            "reason": reason,
            "expected": expected,
            "actual": actual,
            "expectedLength": expected.count,
            "actualLength": actual.count,
            "receivedEvents": e2eReceivedEvents,
            "frontmost": NSWorkspace.shared.frontmostApplication?.localizedName ?? "?",
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]))
            ?? Data("{\"ok\":false}".utf8)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        fflush(stdout)
        exit(ok ? 0 : 1)
    }
}
