import AppKit
import ApplicationServices
import Carbon

/// Posts synthetic keystrokes that replay clipboard text into the focused app.
final class KeystrokeTyper {
    static let shared = KeystrokeTyper()

    enum TypingError: LocalizedError {
        case notTrusted
        case secureInput
        case cancelled
        case busy

        var errorDescription: String? {
            switch self {
            case .notTrusted:
                return "需要「辅助功能」权限才能向其它应用输入文字"
            case .secureInput:
                return "当前应用处于安全输入状态(例如密码框),系统会忽略模拟按键"
            case .cancelled:
                return "已停止输入"
            case .busy:
                return "正在输入中"
            }
        }
    }

    private let queue = DispatchQueue(label: "com.anypaste.keystroke", qos: .userInitiated)
    private let stateLock = NSLock()
    private var running = false
    private var cancelRequested = false

    private init() {}

    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running
    }

    /// Starts a typing session. Returns false when another session is active.
    @discardableResult
    func start(
        text: String,
        delayMs: Int,
        layout: KeyboardLayout = .shared,
        progress: ((Int, Int) -> Void)? = nil,
        completion: @escaping (Result<Int, Error>) -> Void
    ) -> Bool {
        stateLock.lock()
        if running {
            stateLock.unlock()
            completion(.failure(TypingError.busy))
            return false
        }
        running = true
        cancelRequested = false
        stateLock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            let result = self.perform(text: text, delayMs: delayMs, layout: layout, progress: progress)
            self.stateLock.lock()
            self.running = false
            self.cancelRequested = false
            self.stateLock.unlock()
            DispatchQueue.main.async { completion(result) }
        }
        return true
    }

    func cancel() {
        stateLock.lock()
        cancelRequested = true
        stateLock.unlock()
    }

    // MARK: - Private

    private func isCancelRequested() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancelRequested
    }

    private func perform(
        text: String,
        delayMs: Int,
        layout: KeyboardLayout,
        progress: ((Int, Int) -> Void)?
    ) -> Result<Int, Error> {
        guard AXIsProcessTrusted() else { return .failure(TypingError.notTrusted) }
        guard !IsSecureEventInputEnabled() else { return .failure(TypingError.secureInput) }

        let strokes = KeystrokePlanner.strokes(for: text, layout: layout)
        guard !strokes.isEmpty else { return .success(0) }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return .failure(TypingError.notTrusted)
        }

        // Wait out a held Escape so a leftover key press cannot abort instantly.
        var waited = 0
        while escapeIsDown() && waited < 40 {
            usleep(25_000)
            waited += 1
        }

        let delayMicroseconds = useconds_t(max(0, min(delayMs, 200)) * 1000)
        var sent = 0

        for stroke in strokes {
            if isCancelRequested() { return .failure(TypingError.cancelled) }
            if escapeIsDown() { return .failure(TypingError.cancelled) }

            post(stroke: stroke, source: source)
            sent += 1

            if let progress, sent % 8 == 0 || sent == strokes.count {
                DispatchQueue.main.async { progress(sent, strokes.count) }
            }
            if delayMicroseconds > 0 && sent < strokes.count {
                usleep(delayMicroseconds)
            }
        }

        if let progress {
            DispatchQueue.main.async { progress(strokes.count, strokes.count) }
        }
        return .success(sent)
    }

    private func post(stroke: Stroke, source: CGEventSource) {
        let virtualKey = stroke.keyCode ?? 0
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        else { return }

        down.flags = stroke.flags
        up.flags = stroke.flags

        if stroke.text.isEmpty {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            return
        }

        // CGEvent carries at most 20 UTF-16 units per keyboard event.
        let units = Array(stroke.text.utf16)
        var offset = 0
        while offset < units.count {
            let end = min(offset + 20, units.count)
            let chunk = Array(units[offset..<end])
            chunk.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: buffer.baseAddress)
                up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: buffer.baseAddress)
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            offset = end
        }
    }

    private func escapeIsDown() -> Bool {
        CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(53))
    }
}
