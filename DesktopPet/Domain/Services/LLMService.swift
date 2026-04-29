import Foundation

/// LLM 聊天服务 — 统一支持 OpenAI / OpenAI Compatible / Anthropic / Gemini
/// 纯业务逻辑，不依赖 UI
@MainActor
final class LLMService {

    struct ChatMessage: Codable, Identifiable, Equatable {
        let id: String
        var role: String        // "system" | "user" | "assistant" | "tool"
        var content: String
        var timestamp: Date
        var kind: MessageKind
        var toolInfo: ToolInfo?

        init(role: String, content: String, kind: MessageKind = .text, toolInfo: ToolInfo? = nil) {
            self.id = UUID().uuidString
            self.role = role
            self.content = content
            self.timestamp = Date()
            self.kind = kind
            self.toolInfo = toolInfo
        }
    }

    /// 消息类型：纯文本 / 工具调用 / 工具执行结果
    enum MessageKind: String, Codable, Equatable {
        case text
        case toolCall
        case toolResult
    }

    /// 工具调用/执行的可视化信息
    struct ToolInfo: Codable, Equatable {
        var toolName: String
        var displayName: String
        var arguments: [String: String]?
        var success: Bool?
        var details: [String: String]?
    }

    // MARK: - 工具显示名称

    static let toolDisplayNames: [String: String] = [
        "create_alarm": "创建闹钟",
        "create_timer": "创建计时器",
        "create_calendar_event": "创建日历事件",
        "create_reminder": "创建提醒事项"
    ]

    static let argDisplayNames: [String: String] = [
        "title": "标题",
        "scheduledAt": "触发时间",
        "durationSeconds": "时长(秒)",
        "note": "备注",
        "notes": "备注",
        "startAt": "开始时间",
        "endAt": "结束时间",
        "durationMinutes": "时长(分钟)",
        "location": "地点",
        "calendarName": "日历",
        "dueAt": "到期时间",
        "listName": "列表",
        "priority": "优先级"
    ]

    enum LLMError: LocalizedError {
        case noPreset
        case noAPIKey
        case noModel
        case networkError(String)
        case apiError(Int, String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .noPreset: return "未配置 LLM 预设，请在设置中添加。"
            case .noAPIKey: return "API Key 未填写。"
            case .noModel: return "未选择模型。"
            case .networkError(let msg): return "网络错误：\(msg)"
            case .apiError(let code, let msg): return "API 错误 (\(code))：\(msg)"
            case .parseError(let msg): return "解析失败：\(msg)"
            }
        }
    }

    private struct PendingToolCall {
        var name: String
        var arguments: [String: Any]
    }

    private enum ToolDirective {
        case assistantMessage(String)
        case toolCalls([PendingToolCall])
    }

    /// 工具调用的聊天结果，包含回复文本和工具事件
    struct ChatResult {
        var reply: String
        var toolEvents: [ChatMessage]
    }

    /// 发送聊天消息，返回助手回复文本和工具调用事件
    static func sendChat(
        messages: [ChatMessage],
        systemPrompt: String?,
        preset: LLMPreset,
        timerManager: TimerManager? = nil
    ) async throws -> ChatResult {
        guard !preset.apiKey.isEmpty else { throw LLMError.noAPIKey }
        guard !preset.model.isEmpty else { throw LLMError.noModel }

        if preset.toolCallingEnabled {
            return try await sendChatWithToolCalling(
                messages: messages,
                systemPrompt: systemPrompt,
                preset: preset,
                timerManager: timerManager
            )
        }

        let reply = try await sendPlainTextChat(
            messages: messages,
            systemPrompt: systemPrompt,
            preset: preset
        )
        return ChatResult(reply: reply, toolEvents: [])
    }

    private static func sendChatWithToolCalling(
        messages: [ChatMessage],
        systemPrompt: String?,
        preset: LLMPreset,
        timerManager: TimerManager? = nil
    ) async throws -> ChatResult {
        var orchestrationMessages = messages.filter { $0.role == "user" || $0.role == "assistant" }
        let toolSystemPrompt = buildToolSystemPrompt(baseSystemPrompt: systemPrompt)
        var remainingRounds = 4
        var collectedToolEvents: [ChatMessage] = []

        while remainingRounds > 0 {
            let rawReply = try await sendPlainTextChat(
                messages: orchestrationMessages,
                systemPrompt: toolSystemPrompt,
                preset: preset
            )

            switch parseToolDirective(from: rawReply) {
            case .assistantMessage(let text):
                return ChatResult(reply: text, toolEvents: collectedToolEvents)

            case .toolCalls(let calls):
                guard !calls.isEmpty else {
                    return ChatResult(
                        reply: rawReply.trimmingCharacters(in: .whitespacesAndNewlines),
                        toolEvents: collectedToolEvents
                    )
                }

                // 1. 收集「正在调用」事件
                for call in calls {
                    let displayName = toolDisplayNames[call.name] ?? call.name
                    let displayArgs = stringifyArguments(call.arguments)
                    collectedToolEvents.append(ChatMessage(
                        role: "tool",
                        content: "正在执行：\(displayName)",
                        kind: .toolCall,
                        toolInfo: ToolInfo(
                            toolName: call.name,
                            displayName: displayName,
                            arguments: displayArgs.isEmpty ? nil : displayArgs
                        )
                    ))
                }

                // 2. 实际执行工具
                let results = await executeToolCalls(calls, timerManager: timerManager)

                // 3. 收集「执行结果」事件
                for result in results {
                    let displayName = toolDisplayNames[result.toolName] ?? result.toolName
                    collectedToolEvents.append(ChatMessage(
                        role: "tool",
                        content: result.summary,
                        kind: .toolResult,
                        toolInfo: ToolInfo(
                            toolName: result.toolName,
                            displayName: displayName,
                            success: result.success,
                            details: result.details.isEmpty ? nil : result.details
                        )
                    ))
                }

                orchestrationMessages.append(ChatMessage(role: "assistant", content: rawReply))
                orchestrationMessages.append(
                    ChatMessage(role: "user", content: toolResultsFollowUpPrompt(results: results))
                )
                remainingRounds -= 1
            }
        }

        throw LLMError.parseError("工具调用轮次超过上限，请简化请求后重试。")
    }

    private static func executeToolCalls(
        _ calls: [PendingToolCall],
        timerManager: TimerManager? = nil
    ) async -> [SystemActionService.ToolExecutionResult] {
        var results: [SystemActionService.ToolExecutionResult] = []
        for call in calls {
            let result = await SystemActionService.execute(
                toolName: call.name,
                arguments: call.arguments,
                timerManager: timerManager
            )
            results.append(result)
        }
        return results
    }

    private static func sendPlainTextChat(
        messages: [ChatMessage],
        systemPrompt: String?,
        preset: LLMPreset
    ) async throws -> String {
        switch preset.provider {
        case .openAI, .openAICompatible:
            return try await sendOpenAI(messages: messages, systemPrompt: systemPrompt, preset: preset)
        case .anthropic:
            return try await sendAnthropic(messages: messages, systemPrompt: systemPrompt, preset: preset)
        case .gemini:
            return try await sendGemini(messages: messages, systemPrompt: systemPrompt, preset: preset)
        }
    }

    // MARK: - OpenAI / OpenAI Compatible

    private static func sendOpenAI(
        messages: [ChatMessage],
        systemPrompt: String?,
        preset: LLMPreset
    ) async throws -> String {
        var apiBase = preset.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !apiBase.contains("/chat/completions") {
            apiBase += "/chat/completions"
        }

        guard let url = URL(string: apiBase) else { throw LLMError.networkError("无效的接口地址") }

        var body: [[String: Any]] = []
        if let sys = systemPrompt, !sys.isEmpty {
            body.append(["role": "system", "content": sys])
        }
        for msg in messages {
            body.append(["role": msg.role, "content": msg.content])
        }

        let payload: [String: Any] = [
            "model": preset.model,
            "messages": body,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(preset.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        let json = try parseJSON(data)

        if let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        throw LLMError.parseError("无法从 OpenAI 响应中提取文本")
    }

    // MARK: - Anthropic

    private static func sendAnthropic(
        messages: [ChatMessage],
        systemPrompt: String?,
        preset: LLMPreset
    ) async throws -> String {
        var apiBase = preset.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !apiBase.contains("/messages") {
            if !apiBase.contains("/v1") {
                apiBase += "/v1"
            }
            apiBase += "/messages"
        }

        guard let url = URL(string: apiBase) else { throw LLMError.networkError("无效的接口地址") }

        var body: [[String: Any]] = []
        for msg in messages where msg.role == "user" || msg.role == "assistant" {
            body.append(["role": msg.role, "content": msg.content])
        }

        var payload: [String: Any] = [
            "model": preset.model,
            "messages": body,
            "max_tokens": 2048,
            "stream": false
        ]
        if let sys = systemPrompt, !sys.isEmpty {
            payload["system"] = sys
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(preset.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        let json = try parseJSON(data)

        if let contentBlocks = json["content"] as? [[String: Any]] {
            let texts = contentBlocks.compactMap { $0["text"] as? String }
            if !texts.isEmpty {
                return texts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        throw LLMError.parseError("无法从 Anthropic 响应中提取文本")
    }

    // MARK: - Gemini

    private static func sendGemini(
        messages: [ChatMessage],
        systemPrompt: String?,
        preset: LLMPreset
    ) async throws -> String {
        var apiBase = preset.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let range = apiBase.range(of: "/models", options: .backwards) {
            apiBase = String(apiBase[..<range.lowerBound])
        }
        if !apiBase.contains("/v1beta") && !apiBase.contains("/v1/") {
            apiBase += "/v1beta"
        }

        let urlString = "\(apiBase)/models/\(preset.model):generateContent?key=\(preset.apiKey)"
        guard let url = URL(string: urlString) else { throw LLMError.networkError("无效的接口地址") }

        var contents: [[String: Any]] = []
        for msg in messages {
            let role = msg.role == "assistant" ? "model" : "user"
            contents.append([
                "role": role,
                "parts": [["text": msg.content]]
            ])
        }

        var payload: [String: Any] = ["contents": contents]
        if let sys = systemPrompt, !sys.isEmpty {
            payload["systemInstruction"] = [
                "role": "user",
                "parts": [["text": sys]]
            ]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        let json = try parseJSON(data)

        if let candidates = json["candidates"] as? [[String: Any]],
           let first = candidates.first,
           let content = first["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]] {
            let texts = parts.compactMap { $0["text"] as? String }
            if !texts.isEmpty {
                return texts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw LLMError.apiError(0, message)
        }

        throw LLMError.parseError("无法从 Gemini 响应中提取文本")
    }

    // MARK: - Tool Prompting

    private static func buildToolSystemPrompt(baseSystemPrompt: String?) -> String {
        var sections: [String] = []

        if let baseSystemPrompt, !baseSystemPrompt.isEmpty {
            sections.append(baseSystemPrompt)
        }

        sections.append("""
你运行在 DesktopPet 的受限工具调用层中，负责决定是否调用系统工具。

当前本地时间：\(localizedNowString())
当前时区：\(TimeZone.current.identifier)
当前 ISO 时间：\(toolExampleISODate())

可用工具（只能调用下面这些）：
1. create_alarm
   参数：title(String，可选), scheduledAt(String，ISO 8601，必填), note(String，可选)
   作用：创建一次性的系统通知闹钟。
2. create_timer
   参数：title(String，可选), durationSeconds(Number，必填), note(String，可选)
   作用：创建一次性的系统通知倒计时。
3. create_calendar_event
   参数：title(String，必填), startAt(String，ISO 8601，必填), endAt(String，ISO 8601，可选), durationMinutes(Number，可选), location(String，可选), notes(String，可选), calendarName(String，可选)
   作用：创建日历事件。endAt 与 durationMinutes 至少提供一个。
4. create_reminder
   参数：title(String，必填), dueAt(String，ISO 8601，可选), notes(String，可选), listName(String，可选), priority(Number，可选)
   作用：创建提醒事项。没有 dueAt 时代表普通待办。

输出规则：
- 你必须只输出一个 JSON 对象，不要输出 Markdown，不要输出代码块。
- 如果需要调用工具，输出：
  {"tool_calls":[{"name":"工具名","arguments":{...}}]}
- 如果不需要调用工具，或你需要继续向用户追问澄清，输出：
  {"assistant_message":"写给用户的中文回复"}
- 所有时间参数必须是完整的 ISO 8601 字符串，带时区偏移，例如 \(toolExampleISODate())。
- 如果用户的时间、日期、时长或目标过于模糊，先提问，不要擅自创建错误的提醒或日历。
- 闹钟和倒计时只支持单次提醒，不支持重复规则。
- 在收到工具执行结果后，用 assistant_message 给出最终回复；除非还缺一步必要工具，否则不要重复发起相同工具调用。
""")

        return sections.joined(separator: "\n\n")
    }

    private static func toolResultsFollowUpPrompt(
        results: [SystemActionService.ToolExecutionResult]
    ) -> String {
        let encodedResults: String
        if let data = try? JSONEncoder().encode(results),
           let json = String(data: data, encoding: .utf8) {
            encodedResults = json
        } else {
            encodedResults = "[]"
        }

        return """
以下是刚刚执行过的工具结果，请基于这些已执行结果继续回复用户。

tool_results:
\(encodedResults)

现在请只输出一个 JSON 对象：
{"assistant_message":"写给用户的中文回复"}
"""
    }

    private static func parseToolDirective(from rawReply: String) -> ToolDirective {
        let trimmed = rawReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonText = extractJSONObject(from: trimmed),
              let object = parseJSONObject(from: jsonText) else {
            return .assistantMessage(trimmed)
        }

        if let assistantMessage = object["assistant_message"] as? String {
            let text = assistantMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            return .assistantMessage(text.isEmpty ? trimmed : text)
        }

        if let toolCallObjects = object["tool_calls"] as? [[String: Any]] {
            let calls = toolCallObjects.compactMap(parseToolCall)
            if !calls.isEmpty {
                return .toolCalls(calls)
            }
        }

        return .assistantMessage(trimmed)
    }

    private static func parseToolCall(from object: [String: Any]) -> PendingToolCall? {
        guard let name = object["name"] as? String else { return nil }

        if let arguments = object["arguments"] as? [String: Any] {
            return PendingToolCall(name: name, arguments: arguments)
        }

        if let rawArguments = object["arguments"] as? String,
           let jsonText = extractJSONObject(from: rawArguments),
           let parsedArguments = parseJSONObject(from: jsonText) {
            return PendingToolCall(name: name, arguments: parsedArguments)
        }

        return PendingToolCall(name: name, arguments: [:])
    }

    private static func extractJSONObject(from text: String) -> String? {
        let sanitized = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```JSON", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitized.first == "{", sanitized.last == "}" {
            return sanitized
        }

        guard let start = sanitized.firstIndex(of: "{"),
              let end = sanitized.lastIndex(of: "}") else {
            return nil
        }

        return String(sanitized[start...end])
    }

    private static func parseJSONObject(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func localizedNowString() -> String {
        nowDisplayFormatter.string(from: Date())
    }

    private static func toolExampleISODate() -> String {
        toolDateFormatter.string(from: Date())
    }

    /// 将 [String: Any] 转为 [String: String] 用于 UI 展示
    private static func stringifyArguments(_ args: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in args {
            let displayKey = argDisplayNames[key] ?? key
            if let str = value as? String {
                // 尝试美化 ISO 日期
                if let date = iso8601DateFromString(str) {
                    result[displayKey] = displayDateFormatter.string(from: date)
                } else {
                    result[displayKey] = str
                }
            } else if let num = value as? NSNumber {
                result[displayKey] = num.stringValue
            } else {
                result[displayKey] = "\(value)"
            }
        }
        return result
    }

    private static func iso8601DateFromString(_ str: String) -> Date? {
        iso8601ParseFormatter.date(from: str)
    }

    private static let iso8601ParseFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // MARK: - 工具方法

    private static func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError("非 HTTP 响应")
        }
        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw LLMError.apiError(httpResponse.statusCode, message)
            }
            throw LLMError.apiError(httpResponse.statusCode, String(body.prefix(300)))
        }
    }

    private static func parseJSON(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.parseError("响应不是有效的 JSON 对象")
        }
        return json
    }

    private static let nowDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        return formatter
    }()

    private static let toolDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }()
}
