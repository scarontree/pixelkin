import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    let coordinator = AppCoordinator()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 宠物窗口由 AppDelegate 手动创建（不用 SwiftUI Window）
        coordinator.setupPetWindow()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 关闭控制面板不退出应用，宠物窗口常驻
        return false
    }
}
