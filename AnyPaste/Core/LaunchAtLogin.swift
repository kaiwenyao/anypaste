import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService` so failures can be surfaced in Settings
/// instead of silently doing nothing.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "已开启"
        case .notRegistered: return "未开启"
        case .notFound: return "未找到登录项(请把应用放到 /Applications)"
        case .requiresApproval: return "等待用户在系统设置中允许"
        @unknown default: return "未知状态"
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled {
                try service.register()
            }
        } else {
            if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        }
    }
}
