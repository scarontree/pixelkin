import AppKit
import Foundation

/// 情境气泡控制器
///
/// 三种触发模式：
/// 1. 应用切换：监听 NSWorkspace.didActivateApplicationNotification，通过 bundle ID / 应用名匹配规则
/// 2. 时间段：每分钟轮询，匹配当前小时是否在规则时间窗口内
/// 3. 特殊日期：每分钟轮询，匹配节日或星期几（优先级高于时间段）
///
/// 语录查找链：
/// 1. 当前皮肤 phrases.json（PhraseBook）
/// 2. BubbleRuleSet.fallbackPhrases
///
/// 外部接口：
/// - showBubble(text:duration:) — LLM / 其他模块直接弹气泡
/// - loadPhraseBook(from:) — 切换皮肤时加载新角色的语录
@MainActor
final class ContextBubbleController {
    
    private let state: PetRuntimeState
    private var ruleSet: BubbleRuleSet
    
    /// 当前皮肤的角色语录本（可能为 nil）
    private var phraseBook: PhraseBook?
    
    /// 反向索引：bundleID → ruleID
    private var bundleIDIndex: [String: String] = [:]
    
    /// 每条规则的上次触发时间
    private var lastTriggerTimes: [String: Date] = [:]
    /// 全局上次触发时间
    private var lastGlobalTriggerTime: Date = .distantPast
    
    /// 气泡自动隐藏的计时器
    private var hideTimer: Timer?
    
    /// 定时检查时间规则的计时器
    private var timeCheckTimer: Timer?
    
    /// NSWorkspace 通知观察者
    private var workspaceObserver: NSObjectProtocol?
    
    init(state: PetRuntimeState) {
        self.state = state
        self.ruleSet = Self.loadOrCreateRuleSet()
        buildIndex()
        startMonitoring()
    }
    
    deinit {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        timeCheckTimer?.invalidate()
    }
    
    // MARK: - 公开接口
    
    /// 外部直接触发气泡（供 LLM / 其他模块使用）
    func showBubble(text: String, duration: TimeInterval? = nil) {
        state.bubbleText = text
        state.isBubbleVisible = true
        
        let dur = duration ?? ruleSet.defaultDuration
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: dur, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hideBubble()
            }
        }
        lastGlobalTriggerTime = Date()
    }
    
    /// 加载皮肤的语录本（切换皮肤时由 BehaviorController/SkinService 调用）
    func loadPhraseBook(from skinDirectory: URL) {
        let phrasesURL = skinDirectory.appendingPathComponent("phrases.json")
        guard FileManager.default.fileExists(atPath: phrasesURL.path),
              let data = try? Data(contentsOf: phrasesURL),
              let book = try? JSONDecoder().decode(PhraseBook.self, from: data) else {
            phraseBook = nil  // 该皮肤没有语录 → 使用 fallback
            return
        }
        phraseBook = book
    }
    
    /// 清除当前语录本
    func clearPhraseBook() {
        phraseBook = nil
    }
    
    /// 重新加载规则文件
    func reloadRules() {
        ruleSet = Self.loadOrCreateRuleSet()
        buildIndex()
    }
    
    // MARK: - 索引构建
    
    private func buildIndex() {
        bundleIDIndex = [:]
        
        for rule in ruleSet.rules {
            var bundleIDs: [String] = []
            
            if let groupName = rule.appGroup,
               let groupIDs = ruleSet.appGroups[groupName] {
                bundleIDs.append(contentsOf: groupIDs)
            }
            
            if let directIDs = rule.appBundleIDs {
                bundleIDs.append(contentsOf: directIDs)
            }
            
            for bid in bundleIDs {
                // 第一个匹配的规则优先
                if bundleIDIndex[bid] == nil {
                    bundleIDIndex[bid] = rule.id
                }
            }
        }
    }
    
    // MARK: - 应用切换监听
    
    private func startMonitoring() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAppActivation(notification)
            }
        }
        
        // 每分钟检查一次时间规则
        timeCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateTimeRules()
            }
        }
    }
    
    private func handleAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        evaluateAndTrigger(bundleID: app.bundleIdentifier, appName: app.localizedName)
    }
    
    // MARK: - 应用规则匹配与触发
    
    private func evaluateAndTrigger(bundleID: String?, appName: String?) {
        let now = Date()
        
        // 全局冷却
        guard now.timeIntervalSince(lastGlobalTriggerTime) >= ruleSet.globalCooldown else { return }
        
        // 非正常状态不触发
        guard state.behaviorState == .idle || state.behaviorState == .walk else { return }
        
        // 查找规则
        guard let rule = findMatchingRule(bundleID: bundleID, appName: appName) else { return }
        
        // 规则冷却
        if let lastTime = lastTriggerTimes[rule.id],
           now.timeIntervalSince(lastTime) < rule.cooldown { return }
        
        // 概率判定
        guard Double.random(in: 0...1) < rule.probability else { return }
        
        // 查找语录并触发
        triggerBubble(rule: rule)
    }
    
    private func findMatchingRule(bundleID: String?, appName: String?) -> BubbleRule? {
        // 1. bundleID 索引精确匹配
        if let bid = bundleID, let ruleID = bundleIDIndex[bid],
           let rule = ruleSet.rules.first(where: { $0.id == ruleID }) {
            return rule
        }
        
        // 2. appName 模糊匹配
        if let name = appName {
            if let rule = ruleSet.rules.first(where: {
                guard let pattern = $0.appNameContains, !pattern.isEmpty else { return false }
                return name.localizedCaseInsensitiveContains(pattern)
            }) {
                return rule
            }
        }
        
        // 3. default 规则
        return ruleSet.rules.first(where: { $0.appGroup == nil && $0.appBundleIDs == nil })
    }
    
    // MARK: - 时间/日期规则评估（每分钟轮询）
    
    private func evaluateTimeRules() {
        let now = Date()
        
        // 全局冷却
        guard now.timeIntervalSince(lastGlobalTriggerTime) >= ruleSet.globalCooldown else { return }
        
        // 非正常状态不触发
        guard state.behaviorState == .idle || state.behaviorState == .walk else { return }
        
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let currentMonth = calendar.component(.month, from: now)
        let currentDay = calendar.component(.day, from: now)
        let currentWeekday = calendar.component(.weekday, from: now)
        
        var triggered = false
        
        // 1. 优先评估日期规则（节日/周末等）
        //    触发后跳过时间段规则；概率未命中则继续评估时间段规则
        if let dateRules = ruleSet.dateRules {
            for rule in dateRules {
                // 检查今天是否已经触发过
                if let lastTime = lastTriggerTimes[rule.id], calendar.isDateInToday(lastTime) {
                    continue
                }
                
                var isMatch = false
                if let rm = rule.month, let rd = rule.day {
                    isMatch = (rm == currentMonth && rd == currentDay)
                } else if let wds = rule.weekdays {
                    isMatch = wds.contains(currentWeekday)
                }
                
                guard isMatch else { continue }
                guard Double.random(in: 0...1) < rule.probability else { continue }
                
                triggerBubble(ruleID: rule.id, duration: nil)
                triggered = true
                break
            }
        }
        
        // 如果已经触发了节假日气泡，当前轮次就不再触发普通时间气泡
        guard !triggered else { return }
        
        // 2. 评估日常时间规则（早中晚）
        guard let timeRules = ruleSet.timeRules else { return }
        
        for rule in timeRules {
            // 检查今天是否已经触发过该时间规则
            if let lastTime = lastTriggerTimes[rule.id], calendar.isDateInToday(lastTime) {
                continue
            }
            
            // 检查是否在时间窗口内
            let isWithinWindow: Bool
            if rule.startHour <= rule.endHour {
                isWithinWindow = currentHour >= rule.startHour && currentHour < rule.endHour
            } else {
                // 跨午夜的情况（如 23~2，表示 23点以后 或 2点以前）
                isWithinWindow = currentHour >= rule.startHour || currentHour < rule.endHour
            }
            
            guard isWithinWindow else { continue }
            
            // 概率判定（因为每分钟轮询一次，这里的概率可以设低一点让触发更自然）
            guard Double.random(in: 0...1) < rule.probability else { continue }
            
            // 触发气泡
            triggerBubble(ruleID: rule.id, duration: nil)
            break // 每次轮询最多只触发一条时间规则
        }
    }
    
    // MARK: - 气泡显示/隐藏
    
    private func triggerBubble(rule: BubbleRule) {
        triggerBubble(ruleID: rule.id, duration: rule.displayDuration)
    }
    
    private func triggerBubble(ruleID: String, duration: TimeInterval?) {
        // 语录查找链：皮肤 PhraseBook → 规则 fallbackPhrases
        let phrases: [String]? =
            phraseBook?.phrasesForRule(ruleID) ??
            ruleSet.fallbackPhrases[ruleID]
        
        guard let pool = phrases, let phrase = pool.randomElement() else { return }
        
        lastTriggerTimes[ruleID] = Date()
        showBubble(text: phrase, duration: duration)
    }
    
    private func hideBubble() {
        state.isBubbleVisible = false
        state.bubbleText = ""
    }
    
    // MARK: - 规则加载
    
    private static func loadOrCreateRuleSet() -> BubbleRuleSet {
        let fileURL = AppPaths.bubbleRulesFile
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let data = try? Data(contentsOf: fileURL),
               let ruleSet = try? JSONDecoder().decode(BubbleRuleSet.self, from: data) {
                return ruleSet
            }
            print("[ContextBubbleController] 规则文件解码失败，使用默认规则")
        }
        
        let defaultRuleSet = BubbleRuleSet.builtInDefault
        AppPaths.ensureDirectoryExists(AppPaths.appSupport)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(defaultRuleSet) {
            try? data.write(to: fileURL, options: .atomic)
        }
        
        return defaultRuleSet
    }
}
