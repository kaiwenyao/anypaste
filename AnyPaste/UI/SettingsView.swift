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
                    Text("v\(AppInfo.version) (\(AppInfo.build))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .help("v\(AppInfo.version) 是发布版本号;括号里的 \(AppInfo.build) 是构建号,详见「权限与诊断」。")
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
                    Text("默认 5 ms;远端桌面或 Electron 应用仍丢字时,可调到 10 ms 左右。")
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
    @ObservedObject private var updater = UpdateChecker.shared
    @State private var reportText = ""
    @State private var isRunning = false
    @State private var copiedInstallCommand = false

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
            }

            Section("版本与更新") {
                LabeledContent("版本") {
                    HStack(spacing: 8) {
                        Text("v\(AppInfo.version) (\(AppInfo.build))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button(updater.isChecking ? "检查中…" : "检查更新") {
                            updater.check()
                        }
                        .disabled(updater.isChecking)
                    }
                }

                Text("\(AppInfo.version) 是发布版本号(主版本.次版本.修订号),与 GitHub Release 的 tag 对应;"
                     + "括号里的 \(AppInfo.build) 是构建号(build),每次打包递增,"
                     + "用于区分同一发布版本的不同构建。检查更新只比较发布版本号。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                updateStatus
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

    @ViewBuilder
    private var updateStatus: some View {
        switch updater.phase {
        case .idle:
            EmptyView()

        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在从 GitHub 查询最新版本…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

        case .upToDate(let latest):
            Label("已是最新版本(GitHub 最新 v\(latest))。", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)

        case .updateAvailable(let latest, let pageURL):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                    Text("发现新版本 v\(latest) (当前 v\(AppInfo.version))")
                        .fontWeight(.medium)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button("打开 GitHub") {
                        openReleasePage(pageURL)
                    }
                    Button(copiedInstallCommand ? "已复制" : "复制安装命令") {
                        copyInstallCommand()
                    }
                    Spacer()
                }

                Text("在 GitHub 页面复制安装命令,或点「复制安装命令」后粘贴到终端运行;"
                     + "升级会复用本地签名身份,辅助功能授权保持不变。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .failed(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        }
    }

    private func openReleasePage(_ url: URL) {
        if NSWorkspace.shared.open(url) {
            AppLog.info("打开更新页面:\(url.absoluteString)")
        } else {
            AppLog.error("无法打开更新页面:\(url.absoluteString)")
            HUDWindow.show("无法打开浏览器,请手动访问 GitHub Releases")
        }
    }

    private func copyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(UpdateChecker.installCommand, forType: .string)
        copiedInstallCommand = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedInstallCommand = false
        }
        AppLog.info("已复制更新安装命令")
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
