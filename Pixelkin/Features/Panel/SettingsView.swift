import SwiftUI

/// 控制面板设置页 — 运行时参数 + LLM 预设管理
struct SettingsView: View {
    let coordinator: AppCoordinator

    // MARK: - State

    @State private var globalTone: String = "skin"
    @State private var appConfig: AppConfig = .default
    @State private var selectedPresetID: String? = nil
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginMessage: String? = nil
    @State private var inlineMessage: String? = nil
    @State private var availableModels: [String] = []
    @State private var isScanningModels = false
    @State private var scanError: String? = nil

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                runtimeSection
                modelAPISection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("设置")
        .onAppear(perform: loadState)
        .onChange(of: globalTone) { _, newValue in
            coordinator.updateGlobalTone(newValue)
        }
    }

    // MARK: - Runtime Section

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("运行时")
                .font(.system(.title3, design: .rounded).weight(.semibold))

            VStack(alignment: .leading, spacing: 14) {
                Toggle("开机自启", isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { newValue in
                        setLaunchAtLogin(newValue)
                    }
                ))
                .toggleStyle(.switch)
                
                HStack {
                    Text("气泡语气")
                    Spacer()
                    Picker("", selection: $globalTone) {
                        Text("跟随皮肤配置").tag("skin")
                        Text("傲娇").tag("tsundere")
                        Text("温柔").tag("gentle")
                        Text("默认").tag("default")
                    }
                    .frame(width: 150)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - LLM Config Section

    private var modelAPISection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("模型接口")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 18) {
                if let preset = selectedPreset {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .bottom, spacing: 12) {
                            editorField("预设名称", text: bindingForName())
                            
                            Menu {
                                Picker("切换预设", selection: Binding(
                                    get: { selectedPresetID ?? "" },
                                    set: { selectedPresetID = $0 }
                                )) {
                                    ForEach(appConfig.llm.presets) { preset in
                                        Text(preset.name.isEmpty ? "未命名预设" : preset.name)
                                            .tag(preset.id)
                                    }
                                }
                                .pickerStyle(.inline)
                                
                                Divider()
                                
                                Button("新建预设") { addPreset() }
                                Button("复制当前预设") { duplicateSelectedPreset() }
                                Button("删除当前预设", role: .destructive) {
                                    if let selectedPreset { deletePreset(selectedPreset) }
                                }
                                .disabled(appConfig.llm.presets.count <= 1)
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .padding(.bottom, 4)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("提供方")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("提供方", selection: bindingForProvider()) {
                                ForEach(LLMProvider.allCases) { provider in
                                    Text(provider.title).tag(provider)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        editorField("接口地址", text: bindingForBaseURL())
                        VStack(alignment: .leading, spacing: 6) {
                            Text("模型名称")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(alignment: .center, spacing: 8) {
                                if availableModels.isEmpty {
                                    TextField("未选择模型", text: bindingForModel())
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(true)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Picker("", selection: bindingForModel()) {
                                        ForEach(availableModels, id: \.self) { model in
                                            Text(model).tag(model)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                }
                                
                                Button(action: scanModels) {
                                    HStack(spacing: 4) {
                                        if isScanningModels {
                                            ProgressView().controlSize(.small).scaleEffect(0.7)
                                        }
                                        Text("扫描")
                                    }
                                }
                                .disabled(isScanningModels)
                            }
                            if let scanError {
                                Text(scanError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        secureEditorField("API 密钥", placeholder: "api-key", text: bindingForAPIKey())

                        Toggle("启用系统工具调用", isOn: bindingForToolCallingEnabled())
                            .toggleStyle(.switch)

                        Text("允许聊天创建提醒事项、日历事件，以及单次闹钟/倒计时通知。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("保存预设") {
                            appConfig.llm.activePresetID = preset.id
                            persistConfig(message: "预设已保存并启用")
                        }
                        .padding(.top, 4)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                }

                if let inlineMessage {
                    Text(inlineMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
    }

    private var selectedPreset: LLMPreset? {
        appConfig.llm.presets.first(where: { $0.id == selectedPresetID })
    }

    // MARK: - Lifecycle

    private func loadState() {
        let settings = coordinator.loadStoredSettings()
        globalTone = settings.globalTone
        appConfig = coordinator.loadAppConfig()
        ensurePresetExistsIfNeeded()
        selectedPresetID = appConfig.llm.activePresetID ?? appConfig.llm.presets.first?.id
        launchAtLoginEnabled = LaunchAtLoginService.isEnabled()
        launchAtLoginMessage = LaunchAtLoginService.statusMessage()
    }

    private func ensurePresetExistsIfNeeded() {
        guard appConfig.llm.presets.isEmpty else { return }
        let preset = LLMPreset.makeDefault(named: "默认预设")
        appConfig.llm.presets = [preset]
        appConfig.llm.activePresetID = preset.id
        coordinator.saveAppConfig(appConfig)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            launchAtLoginEnabled = enabled
            launchAtLoginMessage = LaunchAtLoginService.statusMessage()
        } catch {
            launchAtLoginEnabled = LaunchAtLoginService.isEnabled()
            launchAtLoginMessage = "操作失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Preset CRUD

    private func addPreset() {
        let name = "预设 \(appConfig.llm.presets.count + 1)"
        let preset = LLMPreset.makeDefault(named: name)
        appConfig.llm.presets.append(preset)
        selectedPresetID = preset.id
        if appConfig.llm.activePresetID == nil {
            appConfig.llm.activePresetID = preset.id
        }
        persistConfig(message: "已新增预设")
    }

    private func duplicateSelectedPreset() {
        guard let preset = selectedPreset else { return }
        duplicatePreset(preset)
    }

    private func duplicatePreset(_ preset: LLMPreset) {
        var copied = preset
        copied.id = UUID().uuidString
        copied.name = "\(preset.name) 副本"
        appConfig.llm.presets.append(copied)
        selectedPresetID = copied.id
        persistConfig(message: "已复制预设")
    }

    private func deletePreset(_ preset: LLMPreset) {
        appConfig.llm.presets.removeAll { $0.id == preset.id }
        if appConfig.llm.activePresetID == preset.id {
            appConfig.llm.activePresetID = appConfig.llm.presets.first?.id
        }
        if selectedPresetID == preset.id {
            selectedPresetID = appConfig.llm.presets.first?.id
        }
        persistConfig(message: "已删除预设")
    }

    private func updateSelectedPreset(
        _ mutate: (inout LLMPreset) -> Void,
        message: String? = nil
    ) {
        guard let selectedPresetID,
              let index = appConfig.llm.presets.firstIndex(where: { $0.id == selectedPresetID }) else { return }
        mutate(&appConfig.llm.presets[index])
        persistConfig(message: message)
    }

    // MARK: - Binding Factories

    private func bindingForName() -> Binding<String> {
        Binding(
            get: { selectedPreset?.name ?? "" },
            set: { newValue in
                updateSelectedPreset({ $0.name = newValue }, message: nil)
            }
        )
    }

    private func bindingForProvider() -> Binding<LLMProvider> {
        Binding(
            get: { selectedPreset?.provider ?? .openAICompatible },
            set: { newValue in
                updateSelectedPreset { preset in
                    let oldDefault = preset.provider.defaultBaseURL
                    let shouldReplaceBaseURL = preset.baseURL.isEmpty || preset.baseURL == oldDefault
                    preset.provider = newValue
                    if shouldReplaceBaseURL {
                        preset.baseURL = newValue.defaultBaseURL
                    }
                }
            }
        )
    }

    private func bindingForBaseURL() -> Binding<String> {
        Binding(
            get: { selectedPreset?.baseURL ?? "" },
            set: { newValue in
                updateSelectedPreset({ $0.baseURL = newValue }, message: nil)
            }
        )
    }

    private func bindingForModel() -> Binding<String> {
        Binding(
            get: { selectedPreset?.model ?? "" },
            set: { newValue in
                updateSelectedPreset({ $0.model = newValue }, message: nil)
            }
        )
    }

    private func bindingForAPIKey() -> Binding<String> {
        Binding(
            get: { selectedPreset?.apiKey ?? "" },
            set: { newValue in
                updateSelectedPreset({ $0.apiKey = newValue }, message: nil)
            }
        )
    }

    private func bindingForToolCallingEnabled() -> Binding<Bool> {
        Binding(
            get: { selectedPreset?.toolCallingEnabled ?? true },
            set: { newValue in
                updateSelectedPreset({ $0.toolCallingEnabled = newValue }, message: nil)
            }
        )
    }

    private func persistConfig(message: String?) {
        coordinator.saveAppConfig(appConfig)
        inlineMessage = message
    }

    // MARK: - Network

    private func scanModels() {
        guard let preset = selectedPreset, !preset.apiKey.isEmpty, !preset.baseURL.isEmpty else {
            scanError = "请先输入接口地址和 api-key"
            return
        }
        
        isScanningModels = true
        scanError = nil
        
        Task {
            do {
                let models = try await fetchModels(baseURL: preset.baseURL, apiKey: preset.apiKey, provider: preset.provider)
                await MainActor.run {
                    self.availableModels = models
                    self.isScanningModels = false
                    if preset.model.isEmpty, let first = models.first {
                        updateSelectedPreset({ $0.model = first }, message: nil)
                    }
                }
            } catch {
                await MainActor.run {
                    self.scanError = "获取失败: \(error.localizedDescription)"
                    self.isScanningModels = false
                }
            }
        }
    }

    private func fetchModels(baseURL: String, apiKey: String, provider: LLMProvider) async throws -> [String] {
        let url: URL
        var request: URLRequest

        switch provider {
        case .gemini:
            // Gemini API: https://generativelanguage.googleapis.com/v1beta/models?key=xxx
            // baseURL 可能是根域名或已包含版本路径
            var apiBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            // 移除尾部的 /models 或 /models/xxx:generateContent 等
            if let range = apiBase.range(of: "/models", options: .backwards) {
                apiBase = String(apiBase[..<range.lowerBound])
            }
            // 如果没有版本路径段，补上 /v1beta
            if !apiBase.contains("/v1beta") && !apiBase.contains("/v1/") {
                apiBase += "/v1beta"
            }
            guard let parsedURL = URL(string: "\(apiBase)/models?key=\(apiKey)") else {
                throw URLError(.badURL)
            }
            url = parsedURL
            request = URLRequest(url: url)
            request.httpMethod = "GET"

        case .openAI, .openAICompatible:
            // OpenAI: https://api.openai.com/v1/models
            var apiBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            // 移除 /chat/completions 后缀
            if apiBase.hasSuffix("/chat/completions") {
                apiBase = String(apiBase.dropLast("/chat/completions".count))
            }
            // 移除已有的 /models 后缀
            if apiBase.hasSuffix("/models") {
                apiBase = String(apiBase.dropLast("/models".count))
            }
            guard let parsedURL = URL(string: "\(apiBase)/models") else {
                throw URLError(.badURL)
            }
            url = parsedURL
            request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        case .anthropic:
            // Anthropic: https://api.anthropic.com/v1/models
            var apiBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if apiBase.hasSuffix("/messages") {
                apiBase = String(apiBase.dropLast("/messages".count))
            }
            if apiBase.hasSuffix("/models") {
                apiBase = String(apiBase.dropLast("/models".count))
            }
            // 如果没有版本路径段，补上 /v1
            if !apiBase.contains("/v1") {
                apiBase += "/v1"
            }
            guard let parsedURL = URL(string: "\(apiBase)/models") else {
                throw URLError(.badURL)
            }
            url = parsedURL
            request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            let preview = String(body.prefix(300))
            throw NSError(
                domain: "LLM",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(preview)"]
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        // OpenAI 格式: { "data": [{ "id": "gpt-4o" }, ...] }
        if let dataArray = json["data"] as? [[String: Any]] {
            return dataArray
                .compactMap { $0["id"] as? String }
                .filter { !$0.isEmpty }
                .sorted()
        }

        // Gemini 格式: { "models": [{ "name": "models/gemini-2.0-flash" }, ...] }
        if let modelsArray = json["models"] as? [[String: Any]] {
            return modelsArray
                .compactMap { item -> String? in
                    guard let name = item["name"] as? String else { return nil }
                    // 去掉 "models/" 前缀
                    return name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
                }
                .filter { !$0.isEmpty }
                .sorted()
        }

        return []
    }

    // MARK: - UI Helpers

    private func editorField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func secureEditorField(_ title: String, placeholder: String? = nil, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField(placeholder ?? title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(20)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(NSColor.windowBackgroundColor))
            )
    }
}
