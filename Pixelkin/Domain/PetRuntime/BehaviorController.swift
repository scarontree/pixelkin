import AppKit
import Foundation

/// 宠物行为状态机 + 计时调度
/// 不知道引擎类型，只通过 AnimationAdapter protocol 交互
@MainActor
final class BehaviorController {
    private static let defaultPetBaseSize = CGSize(width: 128, height: 128)

    let state: PetRuntimeState
    var adapter: AnimationAdapter?
    private var currentManifest: SkinManifest?
    private var randomActionTimer: Timer?
    
    // MARK: - Sleep 计时
    
    /// 无互动计时器（idle 持续一段时间后触发 sleep）
    private var sleepTimer: Timer?
    /// 自然醒计时器（sleep 持续 5 分钟后自动醒来）
    private var wakeTimer: Timer?
    /// sit 结束计时器
    private var sitTimer: Timer?
    /// cling 结束计时器
    private var clingTimer: Timer?
    
    // MARK: - Click 计时
    private var consecutiveClicks: Int = 0
    private var variantLastPlayedAt: [String: Date] = [:]
    private var clickResetTimer: Timer?
    
    /// cling 结束后爬到窗口顶部的回调（由 AppCoordinator 注入）
    var onClingClimbUp: (() -> Void)?
    /// cling 结束后下落的回调（由 AppCoordinator 注入）
    var onClingFall: (() -> Void)?
    
    /// 进入 sleep 前需要保持 idle/walk 的秒数
    private let sleepDelay: TimeInterval = 60
    /// sleep 最长持续时间（自然醒）
    private let maxSleepDuration: TimeInterval = 300 // 5 分钟
    
    init(state: PetRuntimeState) {
        self.state = state
    }
    
    /// 使用 SkinService 加载皮肤并切换引擎
    @discardableResult
    func loadSkin(name: String) -> Bool {
        // 如果已经是当前皮肤，不重复销毁-重建引擎
        if name == state.currentSkinID && adapter != nil {
            return true
        }

        guard let result = SkinService.switchSkin(name: name, oldAdapter: adapter) else {
            return false
        }
        
        self.adapter = result.adapter
        self.currentManifest = result.manifest
        
        // 更新运行时状态
        state.currentSkinID = name
        recomputePetSize()
        SettingsStore.update { $0.selectedSkinID = name }
        
        // 同步当前行为和朝向到新引擎
        setBehavior(.idle)
        setDirection(state.facingDirection)
        startRandomActions()
        return true
    }
    
    @discardableResult
    func setBehavior(_ behavior: PetBehaviorState) -> SkinManifest.AnimationVariant? {
        let previousState = state.behaviorState
        state.behaviorState = behavior
        
        // 尝试播放对应动画，如果皮肤没有该状态的动画则 fallback 到 idle
        let variant = adapter?.play(behavior, context: currentAnimationContext)
        if let v = variant {
            variantLastPlayedAt[v.id] = Date()
        }
        
        // Sleep 相关计时管理
        handleSleepTimers(from: previousState, to: behavior)
        
        return variant
    }
    
    func setDirection(_ direction: FacingDirection) {
        state.facingDirection = direction
        adapter?.setDirection(direction)
    }
    
    func syncBehaviorFromState() {
        let variant = adapter?.play(state.behaviorState, context: currentAnimationContext)
        if let v = variant {
            variantLastPlayedAt[v.id] = Date()
        }
    }

    private var currentAnimationContext: SkinManifest.AnimationContext {
        var conditions = Set<String>()
        
        // 时间相关条件
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<12: conditions.insert("morning")
        case 12..<18: conditions.insert("afternoon")
        case 18..<24: conditions.insert("evening")
        default: conditions.insert("night") // 0..<6
        }
        
        // 应用相关条件
        if let app = NSWorkspace.shared.frontmostApplication {
            if let bundleID = app.bundleIdentifier {
                conditions.insert(bundleID)
            }
            if let name = app.localizedName?.lowercased() {
                conditions.insert(name)
            }
        }
        
        // 连击条件
        if state.behaviorState == .click && consecutiveClicks > 0 {
            conditions.insert("click_\(consecutiveClicks)")
            if consecutiveClicks >= 3 {
                conditions.insert("multi_click")
            }
        }
        
        return SkinManifest.AnimationContext(activeConditions: conditions, variantLastPlayedAt: variantLastPlayedAt)
    }

    // MARK: - 点击处理
    
    /// 处理点击事件
    func handleClick() {
        recordInteraction() // 唤醒等基础互动处理
        
        consecutiveClicks += 1
        
        // 重置连击重置定时器（0.8秒内没有新的点击则重置次数）
        clickResetTimer?.invalidate()
        clickResetTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.consecutiveClicks = 0
            }
        }
        
        let variant = setBehavior(.click)
        let delay = variant?.duration ?? 1.5
        
        // 如果没有点击动画或动画是非循环的，过段时间后回到 idle
        // 如果连续快速点击，这会覆盖之前的 scheduledIdle
        randomActionTimer?.invalidate()
        randomActionTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state.behaviorState == .click else { return }
                let v = self.setBehavior(.idle)
                self.scheduleNextRandomAction(interval: v?.duration)
            }
        }
    }
    
    // MARK: - Sleep 逻辑
    
    /// 记录互动（被拖拽、鼠标靠近等），重置 sleep 计时器
    func recordInteraction() {
        // 如果正在睡觉，唤醒
        if state.behaviorState == .sleep {
            wakeUp()
            return
        }
        
        // 重置无互动计时器
        resetSleepTimer()
    }
    
    /// 唤醒宠物
    private func wakeUp() {
        wakeTimer?.invalidate()
        wakeTimer = nil
        let variant = setBehavior(.idle)
        scheduleNextRandomAction(interval: variant?.duration)
    }
    
    /// 处理 sleep 相关计时器
    private func handleSleepTimers(from previousState: PetBehaviorState, to newState: PetBehaviorState) {
        switch newState {
        case .idle, .walk:
            // 在 idle/walk 时启动 sleep 倒计时
            resetSleepTimer()
            wakeTimer?.invalidate()
            
        case .sleep:
            // 进入 sleep，取消 sleep 倒计时，启动自然醒计时器
            sleepTimer?.invalidate()
            randomActionTimer?.invalidate()
            sitTimer?.invalidate()
            clingTimer?.invalidate()
            startWakeTimer()
            
        case .drag, .fall:
            // 拖拽/下落时暂停所有计时
            sleepTimer?.invalidate()
            wakeTimer?.invalidate()
            sitTimer?.invalidate()
            clingTimer?.invalidate()
            
        case .sit:
            // 坐着时暂停 sleep 计时（不会睡着）
            sleepTimer?.invalidate()
            wakeTimer?.invalidate()
            randomActionTimer?.invalidate()
            clingTimer?.invalidate()
            
        case .cling:
            // 趴着时暂停所有计时
            sleepTimer?.invalidate()
            wakeTimer?.invalidate()
            randomActionTimer?.invalidate()
            sitTimer?.invalidate()
            
        case .click:
            // 点击时暂停所有计时
            sleepTimer?.invalidate()
            wakeTimer?.invalidate()
            sitTimer?.invalidate()
            clingTimer?.invalidate()
        }
    }
    
    /// 重置无互动计时器
    private func resetSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = Timer.scheduledTimer(withTimeInterval: sleepDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.fallAsleep()
            }
        }
    }
    
    /// 进入睡眠
    private func fallAsleep() {
        guard state.behaviorState == .idle || state.behaviorState == .walk else { return }
        setBehavior(.sleep)
    }
    
    /// 启动自然醒计时器
    private func startWakeTimer() {
        wakeTimer?.invalidate()
        wakeTimer = Timer.scheduledTimer(withTimeInterval: maxSleepDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.wakeUp()
            }
        }
    }
    
    // MARK: - Sit 逻辑
    
    /// 安排 sit 结束（10~20 秒后站起来）
    func scheduleSitEnd() {
        sitTimer?.invalidate()
        let duration = Double.random(in: 10...20)
        sitTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state.behaviorState == .sit else { return }
                self.setBehavior(.idle)
                self.startRandomActions()
            }
        }
    }
    
    // MARK: - Cling 逻辑
    
    /// 安排 cling 结束（8~15 秒后松手）
    /// 50% 爬到窗口顶部，50% 松手下落
    func scheduleClingEnd() {
        clingTimer?.invalidate()
        let duration = Double.random(in: 8...15)
        clingTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state.behaviorState == .cling else { return }
                self.state.clingSide = nil
                if Bool.random() {
                    // 50% 爬到窗口顶部
                    self.onClingClimbUp?()
                    self.setBehavior(.idle)
                    self.startRandomActions()
                } else {
                    // 50% 松手下落
                    self.setBehavior(.fall)
                    self.onClingFall?()
                }
            }
        }
    }
    
    // MARK: - 随机行为调度
    
    private func startRandomActions() {
        // 由调用方负责传递 duration，如果这里需要则直接 fallback 为普通调度
        scheduleNextRandomAction()
    }
    
    func scheduleNextRandomAction(interval: TimeInterval? = nil) {
        randomActionTimer?.invalidate()
        let defaultInterval: TimeInterval = state.behaviorState == .idle ? Double.random(in: 4...8) : Double.random(in: 2...5)
        let finalInterval = interval ?? defaultInterval
        
        randomActionTimer = Timer.scheduledTimer(withTimeInterval: finalInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performRandomAction()
            }
        }
    }
    
    private func performRandomAction() {
        guard state.behaviorState == .idle || state.behaviorState == .walk else {
            scheduleNextRandomAction()
            return
        }
        
        if state.behaviorState == .idle {
            // 30% 概率切换到 walk，70% 概率留在 idle 并重新选择变体动画
            if Double.random(in: 0...1) < 0.3 {
                let variant = setBehavior(.walk)
                setDirection(Bool.random() ? .left : .right)
                scheduleNextRandomAction(interval: variant?.duration)
            } else {
                // 重新 resolve 变体：如果 manifest 定义了多个 idle 变体（selection: random），
                // 每次都会随机选一个不同的休闲动画
                let variant = setBehavior(.idle)
                scheduleNextRandomAction(interval: variant?.duration)
            }
        } else {
            let variant = setBehavior(.idle)
            scheduleNextRandomAction(interval: variant?.duration)
        }
    }

    private func recomputePetSize() {
        if let frameSize = currentManifest?.frameSize {
            let manifestScale = currentManifest?.scale ?? 1.0
            let width = frameSize.width * manifestScale
            let height = frameSize.height * manifestScale
            state.petSize = CGSize(width: width, height: height)
            return
        }

        state.petSize = CGSize(
            width: Self.defaultPetBaseSize.width,
            height: Self.defaultPetBaseSize.height
        )
    }
}
