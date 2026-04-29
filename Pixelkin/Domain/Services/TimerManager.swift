import AppKit
import Foundation
import UserNotifications

/// 应用内计时器/闹钟管理器 — 菜单栏倒计时显示 + 闹钟到时响铃
///
/// 职责：
/// - 管理所有由 Function Calling 创建的计时器和闹钟
/// - 每秒刷新倒计时文本供菜单栏展示
/// - 闹钟到时播放系统提示音并弹出警告窗口
/// - 计时器结束后播放提示音并弹出通知
@Observable
@MainActor
final class TimerManager {

    // MARK: - Models

    struct ActiveTimer: Identifiable, Equatable {
        let id: String
        var title: String
        var fireDate: Date
        var kind: Kind       // alarm 还是 timer
        var isFired: Bool = false

        enum Kind: String, Equatable {
            case alarm
            case timer
        }

        /// 剩余秒数（可能为负）
        var remainingSeconds: TimeInterval {
            fireDate.timeIntervalSinceNow
        }

        /// 格式化的倒计时文本（计时器用）
        var formattedCountdown: String {
            let remaining = max(0, remainingSeconds)
            let hours = Int(remaining) / 3600
            let minutes = (Int(remaining) % 3600) / 60
            let seconds = Int(remaining) % 60
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            }
            return String(format: "%02d:%02d", minutes, seconds)
        }

        /// 格式化的目标时间（闹钟用，如 "23:46"）
        var formattedTargetTime: String {
            Self.targetTimeFormatter.string(from: fireDate)
        }

        /// 菜单栏显示文本
        var menuBarDisplay: String {
            switch kind {
            case .alarm:
                return formattedTargetTime
            case .timer:
                return formattedCountdown
            }
        }

        /// SF Symbol 图标名
        var sfSymbolName: String {
            switch kind {
            case .alarm: return "alarm.fill"
            case .timer: return "hourglass"
            }
        }

        private static let targetTimeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = .current
            f.timeZone = .current
            f.dateFormat = "HH:mm"
            return f
        }()
    }

    // MARK: - State

    /// 所有活跃的计时器/闹钟（未触发 + 最近触发的）
    private(set) var items: [ActiveTimer] = []

    /// 最近的未触发项（供菜单栏标签使用）
    private(set) var nearestPendingItem: ActiveTimer? = nil

    /// 是否有闹钟正在响
    private(set) var isAlarmRinging = false

    /// 正在响的闹钟标题（用于弹窗）
    private(set) var ringingAlarmTitle: String? = nil

    private var tickTimer: Timer?
    private var alarmSound: NSSound?

    // MARK: - Public API

    /// 添加一个闹钟（到时会响铃 + 弹窗）
    func addAlarm(id: String, title: String, fireDate: Date) {
        let item = ActiveTimer(id: id, title: title, fireDate: fireDate, kind: .alarm)
        items.append(item)
        ensureTickTimer()
    }

    /// 添加一个倒计时器（到时通知 + 短提示音）
    func addTimer(id: String, title: String, fireDate: Date) {
        let item = ActiveTimer(id: id, title: title, fireDate: fireDate, kind: .timer)
        items.append(item)
        ensureTickTimer()
    }

    /// 停止闹钟响铃
    func dismissAlarm() {
        alarmSound?.stop()
        alarmSound = nil
        isAlarmRinging = false
        ringingAlarmTitle = nil
        // 移除已触发的闹钟
        items.removeAll(where: { $0.kind == .alarm && $0.isFired })
    }

    /// 移除指定计时器
    func remove(id: String) {
        items.removeAll(where: { $0.id == id })
        if items.isEmpty {
            stopTickTimer()
        }
    }

    /// 清空全部
    func removeAll() {
        items.removeAll()
        stopTickTimer()
        dismissAlarm()
    }

    // MARK: - Tick Loop

    private func ensureTickTimer() {
        guard tickTimer == nil else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func stopTickTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
        nearestPendingItem = nil
    }

    private func tick() {
        var hadFire = false

        for i in items.indices {
            guard !items[i].isFired else { continue }
            if items[i].remainingSeconds <= 0 {
                items[i].isFired = true
                hadFire = true
                handleFire(items[i])
            }
        }

        // 清理已触发的 timer（闹钟由 dismiss 清理）
        if hadFire {
            items.removeAll(where: { $0.kind == .timer && $0.isFired })
        }

        // 更新菜单栏：优先显示最近的计时器，其次闹钟
        let pending = items.filter { !$0.isFired }.sorted { a, b in
            if a.kind == .timer && b.kind != .timer { return true }
            if a.kind != .timer && b.kind == .timer { return false }
            return a.fireDate < b.fireDate
        }
        nearestPendingItem = pending.first

        // 没有活跃项了，停止 tick
        if items.isEmpty || items.allSatisfy({ $0.isFired }) {
            if !isAlarmRinging {
                stopTickTimer()
            }
        }
    }

    // MARK: - Fire Handlers

    private func handleFire(_ item: ActiveTimer) {
        switch item.kind {
        case .alarm:
            startAlarmRinging(title: item.title)
        case .timer:
            playTimerEndSound()
            showTimerEndAlert(title: item.title)
        }
    }

    /// 闹钟：循环播放提示音 + 弹出系统对话框
    private func startAlarmRinging(title: String) {
        isAlarmRinging = true
        ringingAlarmTitle = title

        // 播放系统提示音（循环）
        if let sound = NSSound(named: "Purr") ?? NSSound(named: "Glass") ?? NSSound(named: "Ping") {
            sound.loops = true
            sound.play()
            alarmSound = sound
        }

        // 弹出模态警告
        let alert = NSAlert()
        alert.messageText = "闹钟 — \(title)"
        alert.informativeText = "你设置的闹钟时间到了！"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "关闭闹钟")
        alert.icon = NSImage(systemSymbolName: "alarm.fill", accessibilityDescription: "闹钟")?  
            .withSymbolConfiguration(.init(pointSize: 32, weight: .medium))

        // 在主线程弹窗（异步，避免阻塞 tick）
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            self.dismissAlarm()
        }
    }

    /// 计时器：播放一次提示音 + 系统通知
    private func playTimerEndSound() {
        if let sound = NSSound(named: "Glass") ?? NSSound(named: "Ping") {
            sound.play()
        }
    }

    private func showTimerEndAlert(title: String) {
        let alert = NSAlert()
        alert.messageText = "计时结束 — \(title)"
        alert.informativeText = "你设置的倒计时结束了！"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好的")
        alert.icon = NSImage(systemSymbolName: "timer", accessibilityDescription: "计时器")?
            .withSymbolConfiguration(.init(pointSize: 32, weight: .medium))

        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
