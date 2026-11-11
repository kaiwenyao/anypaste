import AppKit
import SwiftUI

/// Captures a new global hotkey from real key presses. The current hotkey is
/// unregistered while recording so its own combination can be re-recorded.
final class HotKeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var errorText: String?

    var onBeginRecording: (() -> Void)?
    var onEndRecording: (() -> Void)?
    var onCapture: ((HotKeyConfig) throws -> Void)?

    private var monitor: Any?

    func start() {
        guard !isRecording else { return }
        errorText = nil
        isRecording = true
        onBeginRecording?()

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            self.handle(event)
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        onEndRecording?()
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { // Escape cancels recording
            stop()
            return
        }

        // Ignore bare modifier keys.
        if event.modifierFlags.intersection([.command, .option, .control, .shift, .function]).isEmpty,
           event.charactersIgnoringModifiers == nil {
            return
        }

        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty else {
            errorText = "快捷键至少要包含 ⌘、⌥ 或 ⌃ 之一"
            return
        }

        let config = HotKeyConfig(keyCode: UInt32(event.keyCode), modifiers: CarbonMod.from(flags))
        do {
            try onCapture?(config)
            errorText = nil
            stop()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct HotKeySettingsTab: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controller: AppController
    @StateObject private var recorder = HotKeyRecorder()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Text(settings.hotKey.displayString)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    Spacer()
                    Button(recorder.isRecording ? "请按下新的组合键…" : "录制新快捷键") {
                        if recorder.isRecording {
                            recorder.stop()
                        } else {
                            recorder.start()
                        }
                    }
                }

                if let error = recorder.errorText ?? controller.hotKeyError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("录制时按 Esc 取消。建议保留一个不与系统或常用应用冲突的组合。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Button("恢复默认 ⌃⇧V") {
                        settings.hotKey = .presetControlShiftV
                        controller.applyHotKey()
                    }
                    Spacer()
                    Text("默认组合与原 Windows 版 Ctrl+Shift+V 语义一致")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            recorder.onBeginRecording = { controller.suspendHotKey() }
            recorder.onEndRecording = { controller.resumeHotKey() }
            recorder.onCapture = { config in
                try controller.applyHotKey(config)
            }
        }
    }
}
