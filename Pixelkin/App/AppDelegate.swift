import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    let coordinator = AppCoordinator()
    
    /// 由 SwiftUI 层注入的打开控制面板闭包（持有 openWindow 环境）
    var openControlPanelAction: (() -> Void)?
    
    private var notificationObserver: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 宠物窗口由 AppDelegate 手动创建（不用 SwiftUI Window）
        coordinator.setupPetWindow()
        
        // 监听来自宠物右键菜单的"打开控制面板"请求
        notificationObserver = NotificationCenter.default.addObserver(
            forName: AppCoordinator.openControlPanelNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleOpenControlPanel()
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 关闭控制面板不退出应用，宠物窗口常驻
        return false
    }
    
    private func handleOpenControlPanel() {
        if let action = openControlPanelAction {
            // 使用 SwiftUI openWindow 闭包（最可靠）
            action()
        } else {
            // Fallback：尝试直接查找并激活已有窗口
            if let window = NSApplication.shared.windows.first(where: {
                $0.identifier?.rawValue == "control-panel"
            }) {
                window.makeKeyAndOrderFront(nil)
                window.deminiaturize(nil)
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    
    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
