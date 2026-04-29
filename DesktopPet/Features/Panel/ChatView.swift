import SwiftUI

/// 聊天工作区视图
struct ChatView: View {
    let coordinator: AppCoordinator

    @State private var messages: [LLMService.ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    // 角色
    @State private var personas: [Persona] = []
    @State private var selectedPersonaID: String? = nil

    private var selectedPersona: Persona? {
        personas.first(where: { $0.id == selectedPersonaID })
    }

    private var activePreset: LLMPreset? {
        let config = coordinator.loadAppConfig()
        if let activeID = config.llm.activePresetID {
            return config.llm.presets.first(where: { $0.id == activeID })
        }
        return config.llm.presets.first
    }

    private var isConfigured: Bool {
        guard let preset = activePreset else { return false }
        return !preset.apiKey.isEmpty && !preset.model.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isConfigured {
                unconfiguredView
            } else {
                chatContent
            }
        }
        .navigationTitle("聊天")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // 角色选择器
                Menu {
                    ForEach(personas) { persona in
                        Button(action: { switchPersona(persona) }) {
                            HStack {
                                Text(persona.name)
                                if persona.id == selectedPersonaID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "theatermasks")
                        Text(selectedPersona?.name ?? "选择角色")
                            .font(.callout)
                    }
                }

                Button(action: clearChat) {
                    Label("清空对话", systemImage: "trash")
                }
                .disabled(messages.isEmpty)
            }
        }
        .onAppear {
            loadPersonas()
        }
    }

    // MARK: - 加载角色

    private func loadPersonas() {
        personas = PersonaService.loadAll()
        if selectedPersonaID == nil {
            selectedPersonaID = personas.first?.id
        }
        // 首次进入且无消息，自动添加角色的开场白
        if messages.isEmpty, let persona = selectedPersona, !persona.greeting.isEmpty {
            messages.append(LLMService.ChatMessage(role: "assistant", content: persona.greeting))
        }
    }

    private func switchPersona(_ persona: Persona) {
        selectedPersonaID = persona.id
        // 清空对话，用新角色的开场白
        messages.removeAll()
        errorMessage = nil
        if !persona.skinID.isEmpty {
            coordinator.switchSkin(name: persona.skinID)
        }
        if !persona.greeting.isEmpty {
            messages.append(LLMService.ChatMessage(role: "assistant", content: persona.greeting))
        }
    }

    // MARK: - 未配置状态

    private var unconfiguredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("尚未配置 LLM 接口")
                .font(.title3.weight(.semibold))
            Text("请在「设置 → 模型接口」中添加预设并保存")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 聊天主体

    private var chatContent: some View {
        VStack(spacing: 0) {
            // 角色信息条
            if let persona = selectedPersona {
                personaBar(persona)
            }

            // 消息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            switch message.kind {
                            case .text:
                                MessageBubble(
                                    message: message,
                                    personaName: selectedPersona?.name
                                )
                            case .toolCall, .toolResult:
                                ToolEventCard(message: message)
                            }
                        }

                        if isLoading {
                            loadingIndicator
                                .id("loading")
                        }
                    }
                    .padding(.vertical, 16)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(messages.last?.id ?? "loading", anchor: .bottom)
                    }
                }
                .onChange(of: isLoading) { _, newValue in
                    if newValue {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("loading", anchor: .bottom)
                        }
                    }
                }
            }

            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button("关闭") { errorMessage = nil }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
            }

            Divider()

            // 输入栏
            inputBar
        }
    }

    // MARK: - Loading 指示器

    private var loadingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("\(selectedPersona?.name ?? "宠物")正在思考…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    // MARK: - 角色信息条

    private func personaBar(_ persona: Persona) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(LinearGradient(
                    colors: [.purple.opacity(0.5), .pink.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                )

            Text(persona.name)
                .font(.system(.caption, design: .rounded).weight(.semibold))

            if let preset = activePreset {
                Text("·")
                    .foregroundStyle(.quaternary)
                Text(preset.model)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)

                if preset.toolCallingEnabled {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Label("工具已开", systemImage: "wand.and.stars")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - 输入栏

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("输入消息…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .onSubmit {
                    if !NSEvent.modifierFlags.contains(.shift) {
                        sendMessage()
                    }
                }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    // MARK: - 发送

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let preset = activePreset else { return }

        let userMessage = LLMService.ChatMessage(role: "user", content: text)
        messages.append(userMessage)
        inputText = ""
        errorMessage = nil
        isLoading = true

        // 只发送 user/assistant 消息给 API
        let historyForAPI = messages.filter { $0.role == "user" || $0.role == "assistant" }

        Task {
            do {
                let chatResult = try await LLMService.sendChat(
                    messages: historyForAPI,
                    systemPrompt: selectedPersona?.systemPrompt,
                    preset: preset,
                    timerManager: coordinator.timerManager
                )

                // 插入工具调用/结果事件（卡片）
                if !chatResult.toolEvents.isEmpty {
                    messages.append(contentsOf: chatResult.toolEvents)
                }

                let assistantMessage = LLMService.ChatMessage(role: "assistant", content: chatResult.reply)
                messages.append(assistantMessage)

                // 桌面宠物弹气泡
                coordinator.contextBubbleController.showBubble(
                    text: String(chatResult.reply.prefix(60)),
                    duration: 5
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func clearChat() {
        messages.removeAll()
        errorMessage = nil
        // 重新加入开场白
        if let persona = selectedPersona, !persona.greeting.isEmpty {
            messages.append(LLMService.ChatMessage(role: "assistant", content: persona.greeting))
        }
    }
}

// MARK: - 工具事件卡片

private struct ToolEventCard: View {
    let message: LLMService.ChatMessage

    private var isCall: Bool { message.kind == .toolCall }
    private var info: LLMService.ToolInfo? { message.toolInfo }

    var body: some View {
        HStack {
            card
            Spacer(minLength: 80)
        }
        .padding(.horizontal, 16)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部标题栏
            HStack(spacing: 6) {
                icon
                    .font(.system(size: 12, weight: .semibold))

                Text(headerText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))

                Spacer()

                if isCall {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(headerBackground)

            // 内容区域
            VStack(alignment: .leading, spacing: 6) {
                if isCall, let args = info?.arguments, !args.isEmpty {
                    // 工具调用 — 显示参数
                    ForEach(Array(args.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                        HStack(alignment: .top, spacing: 6) {
                            Text(key)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 50, alignment: .trailing)
                            Text(value)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }
                } else if !isCall {
                    // 工具结果 — 显示摘要
                    Text(message.content)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    // 详情
                    if let details = info?.details, !details.isEmpty {
                        Divider()
                            .padding(.vertical, 2)
                        ForEach(Array(details.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                            HStack(alignment: .top, spacing: 6) {
                                Text(key)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(.tertiary)
                                Text(value)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var icon: some View {
        if isCall {
            Image(systemName: "hammer.fill")
                .foregroundStyle(.blue)
        } else if info?.success == true {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var headerText: String {
        if isCall {
            return "调用工具：\(info?.displayName ?? "未知")"
        }
        if info?.success == true {
            return "✓ \(info?.displayName ?? "工具")执行成功"
        }
        return "✗ \(info?.displayName ?? "工具")执行失败"
    }

    private var headerBackground: Color {
        if isCall {
            return Color.blue.opacity(0.08)
        }
        if info?.success == true {
            return Color.green.opacity(0.08)
        }
        return Color.red.opacity(0.08)
    }

    private var cardBackground: Color {
        Color(NSColor.controlBackgroundColor).opacity(0.6)
    }

    private var borderColor: Color {
        if isCall {
            return Color.blue.opacity(0.2)
        }
        if info?.success == true {
            return Color.green.opacity(0.2)
        }
        return Color.red.opacity(0.2)
    }
}

// MARK: - 消息气泡

private struct MessageBubble: View {
    let message: LLMService.ChatMessage
    var personaName: String? = nil

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                Circle()
                    .fill(LinearGradient(
                        colors: [.purple.opacity(0.6), .blue.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                    )
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser, let name = personaName {
                    Text(name)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isUser
                                  ? Color.accentColor.opacity(0.15)
                                  : Color(NSColor.controlBackgroundColor))
                    )

                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if isUser {
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue.opacity(0.5), .cyan.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                    )
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
    }
}
