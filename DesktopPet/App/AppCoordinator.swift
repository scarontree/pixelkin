import AppKit
import SwiftUI

/// 全局状态编排与依赖注入
///
/// 职责：创建核心组件、连接依赖、编排启动流程。
/// 不包含具体业务逻辑 — 业务逻辑分散在 BehaviorController / SkinService / ContextBubbleController 中。
///
/// 由 AppDelegate 持有，生命周期 = 应用生命周期。
@MainActor
final class AppCoordinator {
    
    /// 宠物右键菜单"打开控制面板"通过此通知传递给 AppDelegate
    static let openControlPanelNotification = Notification.Name("com.desktopPet.openControlPanel")
    
    // MARK: - 核心组件
    
    /// 宠物运行时状态（位置、行为、皮肤 ID 等），所有 UI 层监听此对象
    let petState = PetRuntimeState()
    
    /// 行为状态机 + 动画引擎编排
    let behaviorController: BehaviorController
    
    /// 情境气泡控制器（应用监听 + 规则匹配 + 角色语录）
    let contextBubbleController: ContextBubbleController
    
    /// 应用内计时器/闹钟管理器（菜单栏倒计时 + 闹钟响铃）
    let timerManager = TimerManager()
    
    /// 宠物窗口控制器（拖拽 / 下落 / 点击穿透 / 物理）
    private var petWindowController: PetWindowController?
    
    /// 启动时读取的用户设置快照
    private let settings = SettingsStore.load()
    
    init() {
        self.behaviorController = BehaviorController(state: petState)
        self.contextBubbleController = ContextBubbleController(state: petState)
        
        contextBubbleController.applyGlobalTone(settings.globalTone)
        
        // 恢复上次选中的皮肤
        let initialSkinID = settings.selectedSkinID
        if !initialSkinID.isEmpty {
            switchSkin(name: initialSkinID)
        }
    }
    
    // MARK: - 皮肤
    
    /// 统一的皮肤切换入口 — 同时更新动画引擎和角色语录
    @discardableResult
    func switchSkin(name: String) -> Bool {
        let success = behaviorController.loadSkin(name: name)
        if success, let skinDir = SkinService.locateSkin(name: name)?.skinDirectory {
            contextBubbleController.loadPhraseBook(from: skinDir)
        }
        return success
    }
    
    /// 在 Finder 中打开用户皮肤目录
    func openSkinsDirectory() {
        NSWorkspace.shared.open(AppPaths.skinsDir)
    }
    
    /// 皮肤文件编辑后，若编辑的是当前活跃皮肤，重新加载其语录本
    func reloadPhraseBookIfCurrentSkin(_ skin: SkinManifest) {
        guard skin.id == petState.currentSkinID,
              let skinDir = SkinService.locateSkin(name: skin.id)?.skinDirectory else { return }
        contextBubbleController.loadPhraseBook(from: skinDir)
    }
    
    /// 重新加载全局气泡规则
    func reloadRules() {
        contextBubbleController.reloadRules()
    }
    
    // MARK: - 配置（LLM 模型接口等）
    
    /// 加载全局配置（LLM 预设等），由 SettingsView / ChatView 调用
    func loadAppConfig() -> AppConfig {
        ConfigService.load()
    }
    
    /// 保存全局配置
    func saveAppConfig(_ config: AppConfig) {
        ConfigService.save(config)
    }
    
    // MARK: - 运行时设置
    
    /// 加载持久化的运行时设置（当前保留可见性、皮肤和气泡语气）
    func loadStoredSettings() -> SettingsStore.StoredSettings {
        SettingsStore.load()
    }
    
    /// 更新全局气泡语气（"skin" = 跟随皮肤配置）
    func updateGlobalTone(_ value: String) {
        SettingsStore.update { $0.globalTone = value }
        contextBubbleController.applyGlobalTone(value)
    }
    
    // MARK: - 宠物窗口
    
    /// 创建宠物窗口并连接所有回调
    ///
    /// 由 AppDelegate.applicationDidFinishLaunching 调用，MUST 只调用一次。
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
        
        // 绑定点击事件到行为控制器
        windowController.onClick = { [weak self] in
            self?.behaviorController.handleClick()
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
        
        // 绑定 sit 回调（窗口边缘坐下 / 窗口消失下落）
        windowController.onSitStateChanged = { [weak self] isSitting, _ in
            guard let self else { return }
            if isSitting {
                self.behaviorController.setBehavior(.sit)
                self.behaviorController.scheduleSitEnd()   // 坐 10~20 秒后站起来
            } else {
                self.behaviorController.setBehavior(.fall)  // 窗口消失 → 下落
            }
        }
        
        // 绑定 cling 回调（窗口侧边挂住 / 窗口消失下落）
        windowController.onClingStateChanged = { [weak self] isCling, side, _ in
            guard let self else { return }
            if isCling, let side {
                // 面朝窗口方向
                let facing: FacingDirection = side == .left ? .right : .left
                self.behaviorController.setDirection(facing)
                self.behaviorController.setBehavior(.cling)
                self.petState.clingSide = side
                self.behaviorController.scheduleClingEnd()
            } else {
                self.behaviorController.setBehavior(.fall)  // 窗口消失 → 下落
            }
        }
        
        // 绑定 cling 结束回调（爬到顶部 / 松手下落）
        behaviorController.onClingClimbUp = { [weak self] in
            self?.petWindowController?.climbToClungWindowTop()
        }
        behaviorController.onClingFall = { [weak self] in
            self?.petWindowController?.performClingFall()
        }
        
        windowController.showWindow()
        self.petWindowController = windowController
    }
    
    /// 切换宠物窗口显示/隐藏，并持久化设置
    func togglePetVisibility() {
        guard let petWindowController else { return }
        let isVisible = petWindowController.toggleVisibility()
        SettingsStore.update { $0.isPetVisible = isVisible }
    }
    
    // MARK: - 控制面板
    
    /// 激活或聚焦控制面板窗口
    private static func openControlPanel() {
        NotificationCenter.default.post(name: openControlPanelNotification, object: nil)
    }
}
