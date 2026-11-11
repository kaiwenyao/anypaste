import Foundation

struct DiagnosticsCheck: Codable {
    let name: String
    let ok: Bool
    let detail: String
}

struct DiagnosticsReport: Codable {
    let ok: Bool
    let version: String
    let build: String
    let axTrusted: Bool
    let checks: [DiagnosticsCheck]

    var failed: [DiagnosticsCheck] { checks.filter { !$0.ok } }
}

/// Headless verification channel: `AnyPaste --self-test` prints this report as
/// JSON so installation can be validated without any UI interaction.
enum Diagnostics {
    static func run() -> DiagnosticsReport {
        var checks: [DiagnosticsCheck] = []

        func add(_ name: String, _ ok: Bool, _ detail: String) {
            checks.append(DiagnosticsCheck(name: name, ok: ok, detail: detail))
        }

        // Keystroke planning: these cover every translation rule in the planner.
        let layout = KeyboardLayout.shared
        add("layout.active", true, "\(layout.displayName),物理布局=\(layout.hasPhysicalLayout)")

        let newlineStrokes = KeystrokePlanner.strokes(for: "a\nb", layout: layout)
        add(
            "mapping.return",
            newlineStrokes.contains { $0.keyCode == KeystrokePlanner.returnKey },
            "换行→Return(\(KeystrokePlanner.returnKey)),共 \(newlineStrokes.count) 个事件"
        )

        let tabStrokes = KeystrokePlanner.strokes(for: "a\tb", layout: layout)
        add(
            "mapping.tab",
            tabStrokes.contains { $0.keyCode == KeystrokePlanner.tabKey },
            "Tab→\(KeystrokePlanner.tabKey),共 \(tabStrokes.count) 个事件"
        )

        let asciiText = "AnyPaste 123 !@#;'[]"
        let asciiStrokes = KeystrokePlanner.strokes(for: asciiText, layout: layout)
        add(
            "mapping.ascii",
            asciiStrokes.count == asciiText.count,
            "\(asciiStrokes.count)/\(asciiText.count) 个事件,键码事件 \(asciiStrokes.filter { $0.keyCode != nil }.count) 个"
        )

        // Raw semantics: braces, carets and bangs must survive untouched.
        let rawText = "{}^+!#%~`"
        let rawStrokes = KeystrokePlanner.strokes(for: rawText, layout: layout)
        let rawRoundTrip = rawStrokes.map(\.text).joined()
        add(
            "mapping.raw",
            rawRoundTrip == rawText && rawStrokes.count == rawText.count,
            "原文=\(rawText) 还原=\(rawRoundTrip)"
        )

        let cjkText = "中文测试👍"
        let cjkStrokes = KeystrokePlanner.strokes(for: cjkText, layout: layout)
        add(
            "mapping.unicode",
            cjkStrokes.count == cjkText.count && cjkStrokes.map(\.text).joined() == cjkText,
            "\(cjkStrokes.count) 个事件,全部为 Unicode 注入=\(cjkStrokes.allSatisfy { $0.keyCode == nil })"
        )

        // Preferences round trip.
        let probeKey = "anypaste.selftest.probe"
        UserDefaults.standard.set("ok", forKey: probeKey)
        let roundTrip = UserDefaults.standard.string(forKey: probeKey) == "ok"
        UserDefaults.standard.removeObject(forKey: probeKey)
        add("prefs.roundtrip", roundTrip, "UserDefaults 读写")

        let settings = AppSettings.shared
        add("prefs.hotkey", settings.hotKey.isUsable, "当前热键=\(settings.hotKey.displayString)")

        // Hotkey registration. A registration failure caused by another running
        // instance is expected and reported as a passing skip.
        do {
            try HotKeyManager.shared.register(settings.hotKey)
            add("hotkey.register", true, "已注册 \(settings.hotKey.displayString)")
            HotKeyManager.shared.unregister()
            add("hotkey.unregister", HotKeyManager.shared.isRegistered == false, "已注销")
        } catch {
            let description = error.localizedDescription
            let occupied = description.contains("占用")
            add("hotkey.register", occupied, occupied ? "跳过:\(description)" : description)
            add("hotkey.unregister", true, "未注册")
        }

        let clipboardText = ClipboardService.text()
        add(
            "clipboard.read",
            true,
            "类型=\(ClipboardService.types().joined(separator: ",")),文本长度=\(clipboardText?.count ?? 0)"
        )

        let trusted = PermissionService.isAccessibilityTrusted
        add("permission.accessibility", trusted, trusted ? "已授权" : "未授权(无法向其它应用输入文字)")
        add(
            "permission.secureInput",
            true,
            PermissionService.isSecureInputEnabled ? "当前处于安全输入状态" : "正常"
        )

        add("launchAtLogin", true, LaunchAtLogin.statusDescription)

        return DiagnosticsReport(
            ok: checks.allSatisfy(\.ok),
            version: AppInfo.version,
            build: AppInfo.build,
            axTrusted: trusted,
            checks: checks
        )
    }

    static func encode(_ report: DiagnosticsReport) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(report), let text = String(data: data, encoding: .utf8) else {
            return "{\"ok\":false,\"error\":\"encode-failed\"}"
        }
        return text
    }

    static func save(_ report: DiagnosticsReport) {
        AppInfo.ensureDirectories()
        let url = AppInfo.logDirectory.appendingPathComponent("selftest-last.json")
        try? encode(report).data(using: .utf8)?.write(to: url)
    }

    static func saveEndToEnd(_ payload: [String: String], ok: Bool) {
        AppInfo.ensureDirectories()
        var merged: [String: Any] = payload
        merged["ok"] = ok
        let data = (try? JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys]))
            ?? Data("{\"ok\":false}".utf8)
        try? data.write(to: AppInfo.logDirectory.appendingPathComponent("e2e-last.json"))
    }
}
