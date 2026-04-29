import EventKit
import Foundation
import UserNotifications

@MainActor
/// Function Calling 工具执行服务 — 闹钟 / 计时 / 日历 / 提醒
enum SystemActionService {

    // MARK: - Types

    struct ToolExecutionResult: Codable, Equatable {
        var toolName: String
        var success: Bool
        var summary: String
        var details: [String: String]
    }

    enum ToolError: LocalizedError {
        case unsupportedTool(String)
        case missingArgument(String)
        case invalidArgument(String)
        case accessDenied(String)
        case executionFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedTool(let name):
                return "不支持的工具：\(name)"
            case .missingArgument(let field):
                return "缺少必填参数：\(field)"
            case .invalidArgument(let message):
                return "参数无效：\(message)"
            case .accessDenied(let capability):
                return "没有获得 \(capability) 的系统权限。"
            case .executionFailed(let message):
                return "执行失败：\(message)"
            }
        }
    }

    // MARK: - Dispatcher

    static func execute(
        toolName: String,
        arguments: [String: Any],
        timerManager: TimerManager? = nil
    ) async -> ToolExecutionResult {
        do {
            switch toolName {
            case "create_alarm":
                return try await createAlarm(arguments: arguments, timerManager: timerManager)
            case "create_timer":
                return try await createTimer(arguments: arguments, timerManager: timerManager)
            case "create_calendar_event":
                return try await createCalendarEvent(arguments: arguments)
            case "create_reminder":
                return try await createReminder(arguments: arguments)
            default:
                throw ToolError.unsupportedTool(toolName)
            }
        } catch {
            let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return ToolExecutionResult(
                toolName: toolName,
                success: false,
                summary: description,
                details: [:]
            )
        }
    }

    // MARK: - Tool Implementations

    private static func createAlarm(
        arguments: [String: Any],
        timerManager: TimerManager?
    ) async throws -> ToolExecutionResult {
        let scheduledAt = try requiredDate("scheduledAt", in: arguments)
        let title = optionalString("title", in: arguments) ?? "DesktopPet 闹钟"
        let note = optionalString("note", in: arguments)
        try await requestNotificationAccess()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = note ?? "你设置的闹钟时间到了。"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: scheduledAt
            ),
            repeats: false
        )
        let identifier = notificationIdentifier(prefix: "alarm")
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await addNotificationRequest(request)

        // 注册到应用内闹钟管理器（响铃 + 弹窗）
        timerManager?.addAlarm(id: identifier, title: title, fireDate: scheduledAt)

        return ToolExecutionResult(
            toolName: "create_alarm",
            success: true,
            summary: "已创建闹钟提醒「\(title)」，触发时间 \(formattedDate(scheduledAt))。",
            details: [
                "identifier": identifier,
                "title": title,
                "scheduledAt": iso8601String(from: scheduledAt)
            ]
        )
    }

    private static func createTimer(
        arguments: [String: Any],
        timerManager: TimerManager?
    ) async throws -> ToolExecutionResult {
        let durationSeconds = try requiredPositiveTimeInterval("durationSeconds", in: arguments)
        let title = optionalString("title", in: arguments) ?? "DesktopPet 倒计时"
        let note = optionalString("note", in: arguments)
        try await requestNotificationAccess()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = note ?? "你设置的倒计时结束了。"
        content.sound = .default

        let identifier = notificationIdentifier(prefix: "timer")
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: durationSeconds, repeats: false)
        )
        try await addNotificationRequest(request)

        let fireDate = Date().addingTimeInterval(durationSeconds)

        // 注册到应用内计时器管理器（菜单栏倒计时 + 到时弹窗）
        timerManager?.addTimer(id: identifier, title: title, fireDate: fireDate)

        return ToolExecutionResult(
            toolName: "create_timer",
            success: true,
            summary: "已创建倒计时「\(title)」，将在 \(formattedDate(fireDate)) 提醒你。",
            details: [
                "identifier": identifier,
                "title": title,
                "durationSeconds": String(Int(durationSeconds)),
                "fireAt": iso8601String(from: fireDate)
            ]
        )
    }

    private static func createCalendarEvent(arguments: [String: Any]) async throws -> ToolExecutionResult {
        let title = try requiredString("title", in: arguments)
        let startAt = try requiredDate("startAt", in: arguments)
        let endAt = try resolveEventEndDate(arguments: arguments, startAt: startAt)
        guard endAt > startAt else {
            throw ToolError.invalidArgument("endAt 必须晚于 startAt")
        }

        let notes = optionalString("notes", in: arguments)
        let location = optionalString("location", in: arguments)
        let calendarName = optionalString("calendarName", in: arguments)

        let store = EKEventStore()
        try await requestCalendarAccess(store: store)

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startAt
        event.endDate = endAt
        event.notes = notes
        event.location = location
        event.calendar = try selectEventCalendar(named: calendarName, store: store)

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw ToolError.executionFailed(error.localizedDescription)
        }

        return ToolExecutionResult(
            toolName: "create_calendar_event",
            success: true,
            summary: "已创建日历事件「\(title)」，时间 \(formattedDate(startAt)) - \(formattedDate(endAt))。",
            details: [
                "identifier": event.eventIdentifier ?? "",
                "title": title,
                "startAt": iso8601String(from: startAt),
                "endAt": iso8601String(from: endAt),
                "calendar": event.calendar.title
            ]
        )
    }

    private static func createReminder(arguments: [String: Any]) async throws -> ToolExecutionResult {
        let title = try requiredString("title", in: arguments)
        let dueAt = optionalDate("dueAt", in: arguments)
        let notes = optionalString("notes", in: arguments)
        let listName = optionalString("listName", in: arguments)
        let priority = optionalInt("priority", in: arguments)

        let store = EKEventStore()
        try await requestReminderAccess(store: store)

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = try selectReminderCalendar(named: listName, store: store)

        if let dueAt {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: dueAt
            )
        }
        if let priority {
            reminder.priority = priority
        }

        do {
            try store.save(reminder, commit: true)
        } catch {
            throw ToolError.executionFailed(error.localizedDescription)
        }

        var details: [String: String] = [
            "identifier": reminder.calendarItemIdentifier,
            "title": title,
            "list": reminder.calendar.title
        ]
        if let dueAt {
            details["dueAt"] = iso8601String(from: dueAt)
        }
        if let priority {
            details["priority"] = String(priority)
        }

        let summary: String
        if let dueAt {
            summary = "已创建提醒「\(title)」，到期时间 \(formattedDate(dueAt))。"
        } else {
            summary = "已创建提醒「\(title)」。"
        }

        return ToolExecutionResult(
            toolName: "create_reminder",
            success: true,
            summary: summary,
            details: details
        )
    }

    // MARK: - Permission Helpers

    private static func requestCalendarAccess(store: EKEventStore) async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        if hasCalendarAccess(status) {
            return
        }

        guard status == .notDetermined else {
            throw ToolError.accessDenied("日历")
        }

        let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            store.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }

        guard granted else {
            throw ToolError.accessDenied("日历")
        }
    }

    private static func requestReminderAccess(store: EKEventStore) async throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if hasReminderAccess(status) {
            return
        }

        guard status == .notDetermined else {
            throw ToolError.accessDenied("提醒事项")
        }

        let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            store.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }

        guard granted else {
            throw ToolError.accessDenied("提醒事项")
        }
    }

    private static func requestNotificationAccess() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return
        case .denied:
            throw ToolError.accessDenied("通知")
        case .notDetermined:
            let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
            guard granted else {
                throw ToolError.accessDenied("通知")
            }
        @unknown default:
            throw ToolError.accessDenied("通知")
        }
    }

    private static func addNotificationRequest(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    // MARK: - Calendar / Reminder Helpers

    private static func selectEventCalendar(named name: String?, store: EKEventStore) throws -> EKCalendar {
        if let name, !name.isEmpty,
           let matched = store.calendars(for: .event).first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) {
            return matched
        }

        if let calendar = store.defaultCalendarForNewEvents {
            return calendar
        }
        throw ToolError.executionFailed("没有可用的日历。")
    }

    private static func selectReminderCalendar(named name: String?, store: EKEventStore) throws -> EKCalendar {
        if let name, !name.isEmpty,
           let matched = store.calendars(for: .reminder).first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) {
            return matched
        }

        if let calendar = store.defaultCalendarForNewReminders() {
            return calendar
        }
        if let first = store.calendars(for: .reminder).first {
            return first
        }
        throw ToolError.executionFailed("没有可用的提醒事项列表。")
    }

    private static func resolveEventEndDate(arguments: [String: Any], startAt: Date) throws -> Date {
        if let endAt = optionalDate("endAt", in: arguments) {
            return endAt
        }
        if let durationMinutes = optionalInt("durationMinutes", in: arguments), durationMinutes > 0 {
            return startAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
        }
        throw ToolError.missingArgument("endAt 或 durationMinutes")
    }

    // MARK: - Argument Parsing

    private static func requiredString(_ key: String, in arguments: [String: Any]) throws -> String {
        guard let value = optionalString(key, in: arguments), !value.isEmpty else {
            throw ToolError.missingArgument(key)
        }
        return value
    }

    private static func optionalString(_ key: String, in arguments: [String: Any]) -> String? {
        if let value = arguments[key] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func requiredDate(_ key: String, in arguments: [String: Any]) throws -> Date {
        guard let date = optionalDate(key, in: arguments) else {
            throw ToolError.missingArgument(key)
        }
        return date
    }

    private static func optionalDate(_ key: String, in arguments: [String: Any]) -> Date? {
        guard let raw = optionalString(key, in: arguments) else { return nil }
        if let date = iso8601Formatter.date(from: raw) {
            return date
        }
        return fallbackDateFormatter.date(from: raw)
    }

    private static func optionalInt(_ key: String, in arguments: [String: Any]) -> Int? {
        if let value = arguments[key] as? Int {
            return value
        }
        if let value = arguments[key] as? Double {
            return Int(value)
        }
        if let value = arguments[key] as? String, let parsed = Int(value) {
            return parsed
        }
        return nil
    }

    private static func requiredPositiveTimeInterval(_ key: String, in arguments: [String: Any]) throws -> TimeInterval {
        if let value = arguments[key] as? Double, value > 0 {
            return value
        }
        if let value = arguments[key] as? Int, value > 0 {
            return TimeInterval(value)
        }
        if let value = arguments[key] as? String, let parsed = TimeInterval(value), parsed > 0 {
            return parsed
        }
        throw ToolError.invalidArgument("\(key) 必须是大于 0 的秒数")
    }

    // MARK: - Formatters

    private static func notificationIdentifier(prefix: String) -> String {
        "\(prefix).\(UUID().uuidString)"
    }

    private static func formattedDate(_ date: Date) -> String {
        displayDateFormatter.string(from: date)
    }

    private static func iso8601String(from date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    private static func hasCalendarAccess(_ status: EKAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .fullAccess, .writeOnly:
            return true
        case .notDetermined, .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func hasReminderAccess(_ status: EKAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .fullAccess:
            return true
        case .writeOnly, .notDetermined, .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }()

    private static let fallbackDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
