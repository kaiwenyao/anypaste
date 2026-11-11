import AppKit
import Carbon

/// Global hotkey registration through Carbon. Carbon hotkeys need no
/// Accessibility permission, only the keystroke injection does.
final class HotKeyManager {
    static let shared = HotKeyManager()

    enum RegistrationError: LocalizedError {
        case alreadyInUse(String)
        case failed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .alreadyInUse(let combo):
                return "快捷键 \(combo) 已被其它应用占用,请换一个组合"
            case .failed(let status):
                return "无法注册快捷键(系统错误码 \(status))"
            }
        }
    }

    var onPressed: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var registeredConfig: HotKeyConfig?

    private init() {}

    var isRegistered: Bool { hotKeyRef != nil }

    func register(_ config: HotKeyConfig) throws {
        unregister()

        let hotKeyID = EventHotKeyID(signature: OSType(0x414E_5950), id: 1) // 'ANYP'
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            config.keyCode,
            config.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        if status == OSStatus(-9878) { // eventHotKeyExistsErr
            throw RegistrationError.alreadyInUse(config.displayString)
        }
        guard status == noErr, let reference else {
            throw RegistrationError.failed(status)
        }

        hotKeyRef = reference
        registeredConfig = config
        installHandlerIfNeeded()
        AppLog.info("热键已注册: \(config.displayString)")
    }

    func unregister() {
        if let reference = hotKeyRef {
            UnregisterEventHotKey(reference)
            hotKeyRef = nil
        }
        if let handler = handlerRef {
            RemoveEventHandler(handler)
            handlerRef = nil
        }
        registeredConfig = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) -> OSStatus in
                DispatchQueue.main.async {
                    HotKeyManager.shared.onPressed?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
        if status != noErr {
            AppLog.error("安装热键事件处理器失败: \(status)")
        }
    }
}
