import AppKit
import SwiftUI

/// 全局状态编排与依赖注入
/// 不包含业务逻辑，只负责创建组件、连接依赖、编排启动流程
@MainActor
final class AppCoordinator {
    
    let petState = PetRuntimeState()
    let behaviorController: BehaviorController
    let contextBubbleController: ContextBubbleController
    private var petWindowController: PetWindowController?
    private let settings = SettingsStore.load()
    
    init() {
        self.behaviorController = BehaviorController(state: petState)
        self.contextBubbleController = ContextBubbleController(state: petState)
        let initialSkinID = settings.selectedSkinID
        if !initialSkinID.isEmpty {
            switchSkin(name: initialSkinID)
        }
    }
    
    /// 统一的皮肤切换入口 — 同时更新动画引擎和角色语录
    @discardableResult
    func switchSkin(name: String) -> Bool {
        let success = behaviorController.loadSkin(name: name)
        if success, let skinDir = SkinService.locateSkin(name: name)?.skinDirectory {
            contextBubbleController.loadPhraseBook(from: skinDir)
        }
        return success
    }
    
    func setupPetWindow() {
        let petView = PetView(state: petState, behaviorController: behaviorController)
        let windowController = PetWindowController(
            petView: petView,
            state: petState,
            initialPosition: nil,
            isInitiallyVisible: settings.isPetVisible
        )
        
        // 绑定拖拽状态到行为控制器以播放正确的动画
        windowController.onBehaviorStateChanged = { [weak self] state in
            self?.behaviorController.setBehavior(state)
        }
        
        // 绑定撞墙转向逻辑
        windowController.onReachBoundary = { [weak self] dir in
            self?.behaviorController.setDirection(dir)
        }
        
        // 注入"打开控制面板"的回调
        windowController.onOpenControlPanel = {
            Self.openControlPanel()
        }
        
        // 绑定互动回调（唤醒 sleep、重置计时器等）
        windowController.onInteraction = { [weak self] in
            self?.behaviorController.recordInteraction()
        }
        
        // 绑定 sit 回调
        windowController.onSitStateChanged = { [weak self] isSitting, _ in
            guard let self else { return }
            if isSitting {
                self.behaviorController.setBehavior(.sit)
                // 坐 10~20 秒后站起来
                self.behaviorController.scheduleSitEnd()
            } else {
                // 窗口消失了 → 下落
                self.behaviorController.setBehavior(.fall)
            }
        }
        
        windowController.showWindow()
        self.petWindowController = windowController
        
        // 🔍 临时调试：自动测试下落
        windowController.debugAutoFallTest()
    }
    
    func togglePetVisibility() {
        guard let petWindowController else { return }
        let isVisible = petWindowController.toggleVisibility()
        SettingsStore.update { $0.isPetVisible = isVisible }
    }
    
    /// 打开控制面板窗口
    private static func openControlPanel() {
        if let window = NSApplication.shared.windows.first(where: {
            $0.title.contains("控制面板")
        }) {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
