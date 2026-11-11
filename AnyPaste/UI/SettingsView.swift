import AppKit
import Combine
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controller: AppController
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(0)

            HotKeySettingsTab()
                .tabItem { Label("快捷键", systemImage: "command") }
                .tag(1)

            PermissionSettingsTab()
                .tabItem { Label("权限与诊断", systemImage: "checkmark.shield") }
                .tag(2)
        }
        .frame(width: 520, height: 460)
    }
}

struct GeneralSettingsTab: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controller: AppController

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: controller.permissionGranted
                          ? "checkmark.circle.fill"
                          : "exclamationmark.triangle.fill")
                        .foregroundStyle(controller.permissionGranted ? Color.green : Color.orange)
                    Text(controller.statusText)
                    Spacer()
                    Text("v\(AppInfo.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if !controller.permissionGranted {
                    HStack {
                        Text("缺少「辅助功能」权限,无法向其它应用输入文字。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("去授权") {
                            PermissionService.requestAccessibilityPrompt()
                            PermissionService.openAccessibilitySettings()
                        }
                    }
                }

                if !controller.menuBarItemVisible {
                    Text("当前系统未能显示菜单栏图标,已自动在 Dock 显示入口;热键与输入均不受影响。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("启用全局热键", isOn: Binding(
                    get: { settings.isEnabled },
                    set: { newValue in
                        settings.isEnabled = newValue
                        controller.applyHotKey()
                    }
                ))

                LabeledContent("当前热键") {
                    Text(settings.hotKey.displayString)
                        .fontWeight(.medium)
                }
            }

            Section("输入速度") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("每字延迟")
                        Slider(
                            value: Binding(
                                get: { Double(settings.delayMs) },
                                set: { settings.delayMs = Int($0.rounded()) }
                            ),
                            in: 0...20,
                            step: 1
                        )
                        Text("\(settings.delayMs) ms")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                    Text("远端桌面或 Electron 应用偶尔丢字时,把延迟调大(例如 5–10 ms)。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("在菜单栏显示输入进度", isOn: $settings.showProgress)
            }

            Section("启动") {
                Toggle("开机自动启动", isOn: $settings.launchAtLogin)

                HStack {
                    Text("登录项状态")
                    Spacer()
                    Text(LaunchAtLogin.statusDescription)
                        .foregroundStyle(.secondary)
                }

                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                HStack {
                    Button("恢复默认设置") {
                        settings.resetToDefaults()
                        controller.applyHotKey()
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct PermissionSettingsTab: View {
    @EnvironmentObject private var controller: AppController
    @State private var reportText = ""
    @State private var isRunning = false

    private let refreshTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: controller.permissionGranted
                          ? "checkmark.circle.fill"
                          : "exclamationmark.triangle.fill")
                        .foregroundStyle(controller.permissionGranted ? Color.green : Color.orange)
                    Text(controller.permissionGranted ? "辅助功能权限已授予" : "尚未授予辅助功能权限")
                    Spacer()
                    Button("请求授权") {
                        PermissionService.requestAccessibilityPrompt()
                    }
                    Button("打开系统设置") {
                        PermissionService.openAccessibilitySettings()
                    }
                }

                Text("macOS 要求应用在「系统设置 → 隐私与安全性 → 辅助功能」中被允许后,"
                     + "才能向其它应用模拟按键。授权或撤销后无需重启。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("安全输入")
                    Spacer()
                    Text(PermissionService.isSecureInputEnabled ? "开启(密码框等)" : "正常")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("键盘布局")
                    Spacer()
                    Text(KeyboardLayout.shared.displayName)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("版本")
                    Spacer()
                    Text("v\(AppInfo.version) (\(AppInfo.build))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Section("诊断") {
                HStack {
                    Button(isRunning ? "自检中…" : "运行自检") { runSelfTest() }
                        .disabled(isRunning)
                    Button("复制诊断信息") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(reportText, forType: .string)
                    }
                    .disabled(reportText.isEmpty)
                    Spacer()
                }

                if !reportText.isEmpty {
                    ScrollView {
                        Text(reportText)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                    .frame(height: 150)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(refreshTimer) { _ in
            controller.refreshPermission()
        }
    }

    private func runSelfTest() {
        isRunning = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let report = Diagnostics.run()
            reportText = Diagnostics.encode(report)
            Diagnostics.save(report)
            isRunning = false
        }
    }
}
