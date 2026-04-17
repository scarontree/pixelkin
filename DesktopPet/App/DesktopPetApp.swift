import SwiftUI

@main
struct DesktopPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // 控制面板窗口（V1.0 骨架）
        Window("DesktopPet 控制面板", id: "control-panel") {
            PanelRootView(coordinator: appDelegate.coordinator)
                .frame(minWidth: 600, minHeight: 400)
        }
        
        // 菜单栏入口
        MenuBarExtra("DesktopPet", systemImage: "pawprint.fill") {
            Button("打开控制面板") {
                openControlPanel()
            }
            Divider()
            Button("显示/隐藏宠物") {
                appDelegate.coordinator.togglePetVisibility()
            }
            Divider()
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    private func openControlPanel() {
        if let window = NSApplication.shared.windows.first(where: {
            $0.identifier?.rawValue == "control-panel"
        }) {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            NSWorkspace.shared.open(URL(string: "desktoppet://control-panel")!)
        }
    }
}
