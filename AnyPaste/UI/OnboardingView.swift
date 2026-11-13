import AppKit
import Combine
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controller: AppController

    var onFinish: () -> Void

    private let refreshTimer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("AnyPaste")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("把剪贴板里的文字逐字“敲”进任意应用")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                stepRow(index: 1, title: "复制文字", detail: "用 ⌘C 把要“粘贴”的内容放进剪贴板。")
                stepRow(index: 2, title: "按下 \(settings.hotKey.displayString)", detail: "在任意应用里按这个组合键。")
                stepRow(index: 3, title: "文字被逐字输入", detail: "不经过系统粘贴,所以远程桌面、终端、禁止粘贴的输入框都能用。")
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: controller.permissionGranted
                          ? "checkmark.circle.fill"
                          : "exclamationmark.triangle.fill")
                        .foregroundStyle(controller.permissionGranted ? Color.green : Color.orange)
                    Text(controller.permissionGranted
                         ? "辅助功能权限已就绪"
                         : "还需要一次「辅助功能」授权")
                        .fontWeight(.medium)
                    Spacer()
                    Button(controller.permissionGranted ? "打开系统设置" : "去允许") {
                        PermissionService.requestAccessibilityPrompt()
                        PermissionService.openAccessibilitySettings()
                    }
                }

                Text("在「隐私与安全性 → 辅助功能」中勾选 AnyPaste,然后回到这里 —— 状态会自动刷新。"
                     + "若已勾选仍显示未授权,请退出并重新打开 AnyPaste(部分 macOS 版本需要重启应用或重新登录后才生效)。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let message = controller.hotKeyError {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            Spacer(minLength: 0)

            HStack {
                Text("关闭此窗口后,AnyPaste 会常驻菜单栏并默认显示 Dock 图标(可在设置里关闭)。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("稍后再说") {
                    onFinish()
                }
                Button(controller.permissionGranted ? "开始使用" : "完成") {
                    settings.hasCompletedOnboarding = true
                    onFinish()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 540, height: 500)
        .onReceive(refreshTimer) { _ in
            controller.refreshPermission()
        }
    }

    private func stepRow(index: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
