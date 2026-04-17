import Foundation

/// 宠物行为状态机 + 计时调度
/// 不知道引擎类型，只通过 AnimationAdapter protocol 交互
@MainActor
final class BehaviorController {
    let state: PetRuntimeState
    var adapter: AnimationAdapter?
    private var randomActionTimer: Timer?
    
    // MARK: - Sleep 计时
    
    /// 无互动计时器（idle 持续一段时间后触发 sleep）
    private var sleepTimer: Timer?
    /// 自然醒计时器（sleep 持续 5 分钟后自动醒来）
    private var wakeTimer: Timer?
    /// sit 结束计时器
    private var sitTimer: Timer?
    
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
        guard let result = SkinService.switchSkin(name: name, oldAdapter: adapter) else {
            return false
        }
        
        self.adapter = result.adapter
        
        // 更新运行时状态
        state.currentSkinID = name
        if let frameSize = result.manifest.frameSize {
            let s = result.manifest.scale ?? 1.0
            state.petSize = CGSize(width: frameSize.width * s, height: frameSize.height * s)
        }
        SettingsStore.update { $0.selectedSkinID = name }
        
        // 同步当前行为和朝向到新引擎
        setBehavior(.idle)
        startRandomActions()
        return true
    }
    
    func setBehavior(_ behavior: PetBehaviorState) {
        let previousState = state.behaviorState
        state.behaviorState = behavior
        
        // 尝试播放对应动画，如果皮肤没有该状态的动画则 fallback 到 idle
        adapter?.play(behavior)
        
        // Sleep 相关计时管理
        handleSleepTimers(from: previousState, to: behavior)
    }
    
    func setDirection(_ direction: FacingDirection) {
        state.facingDirection = direction
        adapter?.setDirection(direction)
    }
    
    func syncBehaviorFromState() {
        adapter?.play(state.behaviorState)
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
        setBehavior(.idle)
        startRandomActions()
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
            startWakeTimer()
            
        case .drag, .fall:
            // 拖拽/下落时暂停所有计时
            sleepTimer?.invalidate()
            wakeTimer?.invalidate()
            sitTimer?.invalidate()
            
        case .sit:
            // 坐着时暂停 sleep 计时（不会睡着）
            sleepTimer?.invalidate()
            wakeTimer?.invalidate()
            randomActionTimer?.invalidate()
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
    
    // MARK: - 随机行为调度
    
    private func startRandomActions() {
        scheduleNextRandomAction()
    }
    
    private func scheduleNextRandomAction() {
        randomActionTimer?.invalidate()
        let interval: TimeInterval = state.behaviorState == .idle ? Double.random(in: 4...8) : Double.random(in: 2...5)
        
        randomActionTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
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
                setBehavior(.walk)
                setDirection(Bool.random() ? .left : .right)
            } else {
                // 重新 resolve 变体：如果 manifest 定义了多个 idle 变体（selection: random），
                // 每次都会随机选一个不同的休闲动画
                setBehavior(.idle)
            }
        } else {
            setBehavior(.idle)
        }
        scheduleNextRandomAction()
    }
}
