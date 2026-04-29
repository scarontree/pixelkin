import SwiftUI

@main
struct PixelkinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    
    var body: some Scene {
        // 控制面板窗口
        Window("Pixelkin 控制面板", id: "control-panel") {
            PanelRootView(coordinator: appDelegate.coordinator)
                .frame(minWidth: 600, minHeight: 400)
                .background(
                    ControlPanelActionBinder {
                        appDelegate.openControlPanelAction = { [openWindow] in
                            Self.bringControlPanelToFront(openWindow: openWindow)
                        }
                    }
                )
        }
        
        // 菜单栏入口
        MenuBarExtra {
            // 活跃的计时器/闹钟列表
            if !appDelegate.coordinator.timerManager.items.isEmpty {
                ForEach(appDelegate.coordinator.timerManager.items) { item in
                    Label("\(item.title) — \(item.menuBarDisplay)", systemImage: item.sfSymbolName)
                }
                
                Button("清除所有计时") {
                    appDelegate.coordinator.timerManager.removeAll()
                }
                
                Divider()
            }
            
            Button("打开控制面板") {
                Self.bringControlPanelToFront(openWindow: openWindow)
            }
            Divider()
            Button("显示/隐藏宠物") {
                appDelegate.coordinator.togglePetVisibility()
            }
            Divider()
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            MenuBarLabel(timerManager: appDelegate.coordinator.timerManager)
                .background(
                    ControlPanelActionBinder {
                        appDelegate.openControlPanelAction = { [openWindow] in
                            Self.bringControlPanelToFront(openWindow: openWindow)
                        }
                    }
                )
        }
    }
    
    /// 统一的控制面板打开逻辑 — 查找已有窗口或通过 openWindow 创建新窗口
    private static func bringControlPanelToFront(openWindow: OpenWindowAction) {
        if let window = NSApplication.shared.windows.first(where: {
            $0.identifier?.rawValue == "control-panel"
        }) {
            window.makeKeyAndOrderFront(nil)
            window.deminiaturize(nil)
        } else {
            openWindow(id: "control-panel")
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

/// 菜单栏标签 — 有活跃计时时显示图标+倒计时，否则显示默认图标
private struct MenuBarLabel: View {
    let timerManager: TimerManager
    
    var body: some View {
        if let nearest = timerManager.nearestPendingItem {
            Label(nearest.menuBarDisplay, systemImage: nearest.sfSymbolName)
        } else {
            Label("Pixelkin", systemImage: "pawprint.fill")
        }
    }
}

private struct ControlPanelActionBinder: View {
    let bind: () -> Void
    
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear(perform: bind)
    }
}
