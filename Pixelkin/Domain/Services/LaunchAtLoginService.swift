import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLoginService {
    static func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func statusMessage() -> String? {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "已开启，登录后会自动启动。"
        case .requiresApproval:
            return "系统需要你在“系统设置 > 登录项”中批准该登录项。"
        case .notFound:
            return "当前应用未找到可注册的登录项。"
        case .notRegistered:
            return "当前未开启开机自启。"
        @unknown default:
            return "开机自启状态未知。"
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
