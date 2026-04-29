import SwiftUI
import UniformTypeIdentifiers

/// 皮肤高级编辑器 — 动画状态配置 + 角色语录编辑 + 气泡规则管理
///
/// 结构概览（按 MARK 导航）：
/// - Types & State: EditorSection 枚举、@State 属性
/// - Body & Header: 主布局、顶栏
/// - Sidebar: 动画/语录的侧边栏导航
/// - Detail Editors: 基础信息、状态编辑、语录编辑的详情区
/// - Cards: 变体卡片、语录行卡片
/// - UI Components: labeledField / numberField / fileSelectorField 等
/// - I/O: load / save / batch import
/// - State Mutation: manifest 和 phraseBook 的增删改
/// - Binding Factories: 为 manifest 字段生成双向绑定
/// - Display Helpers: 排序、显示名、规则分发
struct SkinFilesEditorModal: View {
    private enum EditorSection: String, CaseIterable, Identifiable {
        case animation
        case phrases

        var id: String { rawValue }

        var title: String {
            switch self {
            case .animation:
                return "动画属性"
            case .phrases:
                return "气泡语录"
            }
        }
    }
    
    // MARK: - Types & State
    
    let skin: SkinManifest
    var onPhraseBookSaved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var selectedSection: EditorSection = .animation
    @State private var manifest: SkinManifest?
    @State private var phraseBook: PhraseBook = .init(phrases: [:])
    @State private var bubbleRuleSet: BubbleRuleSet = BubbleRuleSet.builtInDefault

    @State private var errorMessage: String?
    @State private var selectedStateKey: String?
    @State private var selectedPhraseKey: String?

    /// 固定的行为状态列表（与 PetBehaviorState 枚举一致）
    private var allStateKeys: [String] {
        PetBehaviorState.allCases.map(\.rawValue)
    }

    private var sortedPhraseKeys: [String] {
        var keys = Set(commonPhraseKeys)
        keys.formUnion(phraseBook.phrases.keys)
        return Array(keys).sorted { lhs, rhs in
            phraseSortIndex(lhs) < phraseSortIndex(rhs)
        }
    }

    private var addablePhraseKeys: [String] {
        commonPhraseKeys.filter { !phraseBook.phrases.keys.contains($0) }
    }

    // MARK: - Body & Header

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 240)
                
                detail
                    .frame(minWidth: 760, minHeight: 560)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存改动") {
                    saveAll()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .onAppear(perform: loadEditorState)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("编辑属性 - \(skin.name)")
                .font(.headline)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .overlay {
            Picker("", selection: $selectedSection) {
                ForEach(EditorSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        switch selectedSection {
        case .animation:
            animationSidebar
        case .phrases:
            phrasesSidebar
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedSection {
        case .animation:
            animationEditor
        case .phrases:
            phrasesEditor
        }
    }

    private var animationSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("动画状态")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)

            List(selection: $selectedStateKey) {
                Section("全局设置") {
                    ForEach(["global"], id: \.self) { _ in
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(selectedStateKey == "global" ? .blue : .secondary)
                            Text("基础信息")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .tag("global" as String?)
                    }
                }
                
                Section("行为状态") {
                    ForEach(allStateKeys, id: \.self) { key in
                        HStack {
                            Image(systemName: stateHasConfig(key) ? "sparkles.rectangle.stack.fill" : "sparkles.rectangle.stack")
                                .foregroundStyle(stateHasConfig(key) ? .blue : .secondary)
                            Text(stateDisplayName(key))
                            Spacer()
                            if stateHasConfig(key) {
                                Text("\(manifest?.states?[key]?.variants.count ?? 0)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .tag(key as String?)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }
    
    private func stateHasConfig(_ key: String) -> Bool {
        guard let variants = manifest?.states?[key]?.variants else { return false }
        return !variants.isEmpty
    }
    
    private func stateDisplayName(_ key: String) -> String {
        switch key {
        case "idle": return "待机"
        case "walk": return "行走"
        case "drag": return "拖拽"
        case "fall": return "下落"
        case "sleep": return "睡觉"
        case "sit": return "坐下"
        case "cling": return "挂住"
        case "click": return "点击"
        default: return key
        }
    }

    private var phrasesSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("语录场景")
                    .font(.headline)
                Spacer()
                
                Menu {
                    Button("覆盖为：傲娇性格") {
                        phraseBook = PhraseBook.exampleTsundere
                        selectedPhraseKey = phraseBook.phrases.keys.sorted().first
                    }
                    Button("覆盖为：温柔性格") {
                        phraseBook = PhraseBook.exampleGentle
                        selectedPhraseKey = phraseBook.phrases.keys.sorted().first
                    }
                    Button("覆盖为：默认性格") {
                        phraseBook = PhraseBook(phrases: BubbleRuleSet.builtInDefault.fallbackPhrases)
                        selectedPhraseKey = phraseBook.phrases.keys.sorted().first
                    }
                } label: {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("导入内置性格模板（会覆盖当前所有语录）")
                
                Button {
                    addCustomPhraseCategory()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("新增自定义场景")
            }
            .padding(.horizontal)
            .padding(.top)

            List(selection: $selectedPhraseKey) {
                ForEach(sortedPhraseKeys, id: \.self) { key in
                    HStack {
                        Text(phraseTitle(for: key))
                        Spacer()
                        Button {
                            deletePhraseCategory(key)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .tag(Optional(key))
                }
                .onDelete(perform: deletePhraseCategories)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Detail Editors

    @ViewBuilder
    private var animationEditor: some View {
        if let manifest {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if selectedStateKey == "global" {
                        basicInfoEditor(manifest: manifest)
                    } else {
                        stateEditor(manifest: manifest)
                    }
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView(
                "未找到动画配置",
                systemImage: "xmark.doc",
                description: Text("该皮肤没有可编辑的动画属性。")
            )
        }
    }

    @ViewBuilder
    private var phrasesEditor: some View {
        if let selectedPhraseKey {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(phraseTitle(for: selectedPhraseKey))
                            .font(.title3.weight(.semibold))
                    }
                    
                    ruleEditorCard(for: selectedPhraseKey)

                    HStack {
                        Text("台词列表")
                            .font(.headline)
                        Spacer()
                        Button("新增台词") {
                            addPhraseLine(to: selectedPhraseKey)
                        }
                    }

                    ForEach(Array(phrases(for: selectedPhraseKey).enumerated()), id: \.offset) { index, _ in
                        phraseCard(key: selectedPhraseKey, index: index)
                    }
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView(
                "未选择语录场景",
                systemImage: "text.bubble",
                description: Text("从左侧选择一个场景，或新增一个语录场景。")
            )
        }
    }

    @ViewBuilder
    private func basicInfoEditor(manifest: SkinManifest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("基础信息")
                .font(.title3.weight(.semibold))

            HStack(spacing: 16) {
                infoField("ID (对应文件夹名，只读)", text: bindingForManifestID(), editable: false)
                infoField("名称", text: bindingForManifestName(fallback: manifest.name), editable: true)
            }

            HStack(spacing: 16) {
                infoField("类型", text: bindingForManifestType(), editable: true)
                infoField("分组", text: bindingForManifestGroup(fallback: manifest.group ?? ""), editable: true)
                infoField("标签", text: bindingForManifestTag(fallback: manifest.tag ?? ""), editable: true)
            }

            HStack(spacing: 16) {
                fileSelectorField("预览图", fileNameBinding: bindingForManifestPreview(fallback: manifest.preview ?? ""), allowedFileTypes: ["png", "jpg", "jpeg", "gif"])
                numberField("宽度", value: bindingForFrameWidth(fallback: Int(manifest.frameSize?.width ?? 64)))
                numberField("高度", value: bindingForFrameHeight(fallback: Int(manifest.frameSize?.height ?? 64)))
                decimalField("缩放", value: bindingForScale(fallback: manifest.scale ?? 1))
            }
        }
        .padding(16)
        .background(editorCardBackground)
    }

    @ViewBuilder
    private func stateEditor(manifest: SkinManifest) -> some View {
        if let stateKey = selectedStateKey {
            let config = manifest.states?[stateKey]
            VStack(alignment: .leading, spacing: 20) {
                
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("\(stateDisplayName(stateKey))")
                            .font(.title3.weight(.semibold))
                        Spacer()
                    }
                    
                    if let config {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 16) {
                                labeledField(title: "状态标识") {
                                    Text(stateKey)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                labeledField(title: "片段选择策略") {
                                    Picker("", selection: bindingForSelection(stateKey: stateKey, fallback: config.selection)) {
                                        ForEach(SkinManifest.SelectionStrategy.allCases, id: \.self) { strategy in
                                            Text(selectionStrategyLabel(strategy)).tag(strategy)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(16)
                        .background(editorCardBackground)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("动作片段")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        HStack(spacing: 8) {
                            Button(action: { batchImportVariants(stateKey) }) {
                                Label("批量导入", systemImage: "photo.badge.plus")
                            }
                            Button(action: { ensureStateAndAddVariant(stateKey) }) {
                                Label("新增片段", systemImage: "plus")
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    if let config, !config.variants.isEmpty {
                        ForEach(Array(config.variants.enumerated()), id: \.offset) { index, variant in
                            variantCard(stateKey: stateKey, index: index, variant: variant)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "film.stack")
                                .font(.largeTitle)
                                .foregroundStyle(.quaternary)
                            Text("该状态尚未配置动画")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("点击「新增片段」添加动画变体，或留空使用 idle 动画作为 fallback。")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "未选择状态",
                systemImage: "square.stack",
                description: Text("从左侧选择一个行为状态来配置动画。")
            )
        }
    }
    
    /// 确保 state config 存在后再添加 variant
    private func ensureStateAndAddVariant(_ stateKey: String) {
        guard var manifest else { return }
        if manifest.states == nil {
            manifest.states = [:]
        }
        if manifest.states?[stateKey] == nil {
            manifest.states?[stateKey] = .init(selection: .single, variants: [])
        }
        self.manifest = manifest
        addVariant(to: stateKey)
    }

    // MARK: - Cards

    private func variantCard(
        stateKey: String,
        index: Int,
        variant: SkinManifest.AnimationVariant
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("片段 \(index + 1)", systemImage: "photo.stack")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                
                Toggle("循环播放", isOn: bindingForLoop(stateKey: stateKey, index: index, fallback: variant.loop ?? true))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                
                Button(role: .destructive) {
                    deleteVariant(at: index, from: stateKey)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 16) {
                infoField("片段 ID", text: bindingForVariantID(stateKey: stateKey, index: index), editable: true)
                fileSelectorField("源文件名", fileNameBinding: bindingForVariantFile(stateKey: stateKey, index: index), allowedFileTypes: ["png", "gif", "svg"])
            }

            HStack(spacing: 16) {
                numberField("帧数", value: bindingForFrames(stateKey: stateKey, index: index, fallback: variant.frames ?? 1))
                numberField("帧率 (FPS)", value: bindingForFPS(stateKey: stateKey, index: index, fallback: variant.fps ?? 8))
                numberField("权重", value: bindingForWeight(stateKey: stateKey, index: index, fallback: variant.weight ?? 1))
                numberField("优先级", value: bindingForPriority(stateKey: stateKey, index: index, fallback: variant.priority ?? 0))
            }
            
            HStack(spacing: 16) {
                decimalField("持续时间(秒)", value: bindingForDuration(stateKey: stateKey, index: index, fallback: variant.duration ?? 0))
                decimalField("冷却时间(秒)", value: bindingForCooldown(stateKey: stateKey, index: index, fallback: variant.cooldown ?? 0))
            }

            VariantConditionEditor(stateKey: stateKey, conditions: bindingForConditionsArray(stateKey: stateKey, index: index, fallback: variant.conditions ?? []), ruleSet: bubbleRuleSet)
        }
        .padding(16)
        .background(editorCardBackground)
    }

    private func phraseCard(key: String, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("台词 \(index + 1)", systemImage: "text.bubble")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button(role: .destructive) {
                    deletePhraseLine(key: key, index: index)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            TextField("输入这条语录", text: bindingForPhraseLine(key: key, index: index))
                .textFieldStyle(.roundedBorder)
        }
        .padding(16)
        .background(editorCardBackground)
    }

    // MARK: - Shared UI Components

    private var editorCardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(NSColor.controlBackgroundColor))
            .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
            )
    }

    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func numberField(_ title: String, value: Binding<Int>) -> some View {
        labeledField(title: title) {
            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func decimalField(_ title: String, value: Binding<Double>) -> some View {
        labeledField(title: title) {
            TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func infoField(_ title: String, text: Binding<String>, editable: Bool) -> some View {
        labeledField(title: title) {
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .disabled(!editable)
        }
    }

    private func fileSelectorField(
        _ title: String,
        fileNameBinding: Binding<String>,
        allowedFileTypes: [String]? = nil
    ) -> some View {
        labeledField(title: title) {
            Button {
                selectFile(for: fileNameBinding, allowedFileTypes: allowedFileTypes)
            } label: {
                Text(fileNameBinding.wrappedValue.isEmpty ? "点击选取..." : fileNameBinding.wrappedValue)
                    .foregroundStyle(fileNameBinding.wrappedValue.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
    }

    private func selectFile(for binding: Binding<String>, allowedFileTypes: [String]?) {
        guard let skinDir = skin.directoryURL else { return }
        
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        if let allowed = allowedFileTypes {
            openPanel.allowedContentTypes = allowed.compactMap { UTType(filenameExtension: $0) }
        }
        openPanel.directoryURL = skinDir
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            let selectedPath = url.standardizedFileURL.path
            let skinDirPath = skinDir.standardizedFileURL.path
            
            if selectedPath.hasPrefix(skinDirPath) {
                binding.wrappedValue = url.lastPathComponent
            } else {
                let destURL = skinDir.appendingPathComponent(url.lastPathComponent)
                do {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: url, to: destURL)
                    binding.wrappedValue = destURL.lastPathComponent
                } catch {
                    print("Failed to copy file: \(error)")
                }
            }
        }
    }

    // MARK: - I/O (Load / Save / Import)

    private func loadEditorState() {
        manifest = skin
        phraseBook = SkinService.loadPhraseBook(for: skin)
        bubbleRuleSet = BubbleRuleService.load()
        // 默认选中基础信息
        selectedStateKey = "global"
        selectedPhraseKey = sortedPhraseKeys.first
        errorMessage = nil
    }

    private func saveAll() {
        guard let manifest,
              let manifestText = encodedJSONString(from: manifest) else {
            errorMessage = "当前动画属性无法保存。"
            selectedSection = .animation
            return
        }

        if let message = SkinService.saveManifestText(manifestText, for: skin) {
            errorMessage = message
            selectedSection = .animation
            return
        }

        let normalizedBook = normalizedPhraseBook()
        if let message = SkinService.savePhraseBook(normalizedBook, for: skin) {
            errorMessage = message
            selectedSection = .phrases
            return
        }

        if let message = BubbleRuleService.save(bubbleRuleSet) {
            errorMessage = message
            selectedSection = .phrases
            return
        }

        onPhraseBookSaved?()
        dismiss()
    }

    // State 的增删已移除 — 行为状态由 PetBehaviorState 枚举固定定义，
    // 用户只需为每个 state 配置动画变体。

    private func batchImportVariants(_ stateKey: String) {
        guard var currentManifest = manifest else { return }
        if currentManifest.states == nil {
            currentManifest.states = [:]
        }
        if currentManifest.states?[stateKey] == nil {
            currentManifest.states?[stateKey] = .init(selection: .single, variants: [])
        }
        self.manifest = currentManifest
        
        guard let skinDir = skin.directoryURL else { return }
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = true
        openPanel.allowedContentTypes = [
            UTType.png,
            UTType.gif,
            UTType.svg
        ]
        openPanel.directoryURL = skinDir
        
        if openPanel.runModal() == .OK {
            updateState(stateKey) { config in
                for url in openPanel.urls {
                    let destURL = skinDir.appendingPathComponent(url.lastPathComponent)
                    do {
                        if url.standardizedFileURL.path != destURL.standardizedFileURL.path {
                            if FileManager.default.fileExists(atPath: destURL.path) {
                                try FileManager.default.removeItem(at: destURL)
                            }
                            try FileManager.default.copyItem(at: url, to: destURL)
                        }
                    } catch {
                        print("Failed to copy file: \(error)")
                    }
                    
                    let nextIndex = config.variants.count + 1
                    config.variants.append(
                        .init(
                            id: "\(stateKey)_variant_\(nextIndex)",
                            file: url.lastPathComponent,
                            frames: 1,
                            fps: 8,
                            loop: true,
                            weight: 1,
                            conditions: nil,
                            priority: 0
                        )
                    )
                }
            }
        }
    }

    // MARK: - State Mutation (Variant CRUD)

    private func addVariant(to stateKey: String) {
        updateState(stateKey) { config in
            let nextIndex = config.variants.count + 1
            config.variants.append(
                .init(
                    id: "\(stateKey)_variant_\(nextIndex)",
                    file: "",
                    frames: 1,
                    fps: 8,
                    loop: true,
                    weight: 1,
                    conditions: nil,
                    priority: 0
                )
            )
        }
    }

    private func deleteVariant(at index: Int, from stateKey: String) {
        updateState(stateKey) { config in
            guard config.variants.indices.contains(index) else { return }
            config.variants.remove(at: index)
        }
    }

    private func updateState(_ stateKey: String, mutate: (inout SkinManifest.StateConfig) -> Void) {
        guard var manifest, var config = manifest.states?[stateKey] else { return }
        mutate(&config)
        manifest.states?[stateKey] = config
        self.manifest = manifest
    }

    private func updateVariant(_ stateKey: String, index: Int, mutate: (inout SkinManifest.AnimationVariant) -> Void) {
        updateState(stateKey) { config in
            guard config.variants.indices.contains(index) else { return }
            mutate(&config.variants[index])
        }
    }

    // MARK: - Phrase CRUD

    private func addPhraseCategory(key: String) {
        phraseBook.phrases[key] = phraseBook.phrases[key] ?? [""]
        selectedPhraseKey = key
    }

    private func addCustomPhraseCategory() {
        var index = 1
        var key = "custom_\(index)"
        while phraseBook.phrases[key] != nil {
            index += 1
            key = "custom_\(index)"
        }
        addPhraseCategory(key: key)
    }

    private var canAddCustomPhraseCategory: Bool {
        true
    }

    private func deletePhraseCategories(at offsets: IndexSet) {
        let keys = sortedPhraseKeys
        for offset in offsets {
            phraseBook.phrases.removeValue(forKey: keys[offset])
        }
        selectedPhraseKey = sortedPhraseKeys.first
    }

    private func deletePhraseCategory(_ key: String) {
        phraseBook.phrases.removeValue(forKey: key)
        if selectedPhraseKey == key {
            selectedPhraseKey = sortedPhraseKeys.first
        }
    }

    private func phrases(for key: String) -> [String] {
        phraseBook.phrases[key] ?? []
    }

    private func addPhraseLine(to key: String) {
        var lines = phraseBook.phrases[key] ?? []
        lines.append("")
        phraseBook.phrases[key] = lines
    }

    private func deletePhraseLine(key: String, index: Int) {
        guard var lines = phraseBook.phrases[key], lines.indices.contains(index) else { return }
        lines.remove(at: index)
        phraseBook.phrases[key] = lines.isEmpty ? [""] : lines
    }

    private func normalizedPhraseBook() -> PhraseBook {
        var normalized: [String: [String]] = [:]

        for (key, values) in phraseBook.phrases {
            let cleaned = values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if !cleaned.isEmpty {
                normalized[key] = cleaned
            }
        }

        if normalized.isEmpty {
            normalized["default"] = ["今天也辛苦啦~"]
        }

        return PhraseBook(phrases: normalized)
    }

    private func selectionStrategyLabel(_ strategy: SkinManifest.SelectionStrategy) -> String {
        switch strategy {
        case .single:
            return "固定单个"
        case .random:
            return "随机"
        case .weightedRandom:
            return "按权重随机"
        case .firstMatch:
            return "首个匹配"
        }
    }

    // MARK: - Binding Factories

    private func bindingForSelection(
        stateKey: String,
        fallback: SkinManifest.SelectionStrategy
    ) -> Binding<SkinManifest.SelectionStrategy> {
        Binding(
            get: { manifest?.states?[stateKey]?.selection ?? fallback },
            set: { newValue in
                updateState(stateKey) { $0.selection = newValue }
            }
        )
    }

    private func bindingForManifestID() -> Binding<String> {
        Binding(
            get: { manifest?.id ?? "" },
            set: { newValue in manifest?.id = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    private func bindingForManifestType() -> Binding<String> {
        Binding(
            get: { manifest?.type ?? "" },
            set: { newValue in manifest?.type = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    private func bindingForManifestName(fallback: String) -> Binding<String> {
        Binding(
            get: { manifest?.name ?? fallback },
            set: { newValue in manifest?.name = newValue }
        )
    }

    private func bindingForManifestGroup(fallback: String) -> Binding<String> {
        Binding(
            get: { manifest?.group ?? fallback },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                manifest?.group = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private func bindingForManifestTag(fallback: String) -> Binding<String> {
        Binding(
            get: { manifest?.tag ?? fallback },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                manifest?.tag = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private func bindingForManifestPreview(fallback: String) -> Binding<String> {
        Binding(
            get: { manifest?.preview ?? fallback },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                manifest?.preview = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private func bindingForFrameWidth(fallback: Int) -> Binding<Int> {
        Binding(
            get: { Int(manifest?.frameSize?.width ?? Double(fallback)) },
            set: { newValue in
                let height = manifest?.frameSize?.height ?? 64
                manifest?.frameSize = .init(width: Double(max(newValue, 1)), height: height)
            }
        )
    }

    private func bindingForFrameHeight(fallback: Int) -> Binding<Int> {
        Binding(
            get: { Int(manifest?.frameSize?.height ?? Double(fallback)) },
            set: { newValue in
                let width = manifest?.frameSize?.width ?? 64
                manifest?.frameSize = .init(width: width, height: Double(max(newValue, 1)))
            }
        )
    }

    private func bindingForScale(fallback: Double) -> Binding<Double> {
        Binding(
            get: { manifest?.scale ?? fallback },
            set: { newValue in
                manifest?.scale = max(newValue, 0.1)
            }
        )
    }

    private func bindingForVariantID(stateKey: String, index: Int) -> Binding<String> {
        Binding(
            get: { manifest?.states?[stateKey]?.variants[index].id ?? "" },
            set: { newValue in
                updateVariant(stateKey, index: index) { $0.id = newValue }
            }
        )
    }

    private func bindingForVariantFile(stateKey: String, index: Int) -> Binding<String> {
        Binding(
            get: { manifest?.states?[stateKey]?.variants[index].file ?? "" },
            set: { newValue in
                updateVariant(stateKey, index: index) { $0.file = newValue }
            }
        )
    }

    private func bindingForFrames(stateKey: String, index: Int, fallback: Int) -> Binding<Int> {
        Binding(
            get: { manifest?.states?[stateKey]?.variants[index].frames ?? fallback },
            set: { newValue in
                updateVariant(stateKey, index: index) { $0.frames = newValue }
            }
        )
    }

    private func bindingForFPS(stateKey: String, index: Int, fallback: Int) -> Binding<Int> {
        Binding(
            get: { manifest?.states?[stateKey]?.variants[index].fps ?? fallback },
            set: { newValue in
                updateVariant(stateKey, index: index) { $0.fps = newValue }
            }
        )
    }

    private func bindingForWeight(stateKey: String, index: Int, fallback: Int) -> Binding<Int> {
        Binding(
            get: { manifest?.states?[stateKey]?.variants[index].weight ?? fallback },
            set: { newValue in
                updateVariant(stateKey, index: index) { $0.weight = newValue }
            }
        )
    }

    private func bindingForPriority(stateKey: String, index: Int, fallback: Int) -> Binding<Int> {
        Binding(
            get: { manifest?.states?[stateKey]?.variants[index].priority ?? fallback },
            set: { newValue in
                updateVariant(stateKey, index: index) { $0.priority = newValue }
            }
        )
    }

    private func bindingForDuration(stateKey: String, index: Int, fallback: Double) -> Binding<Double> {
        Binding(
            get: { manifest?.states?[stateKey]?.variants[index].duration ?? fallback },
            set: { newValue in
                updateVariant(stateKey, index: index) { $0.duration = newValue > 0 ? newValue : nil }
            }
        )
    }

    private func bindingForCooldown(stateKey: String, index: Int, fallback: Double) -> Binding<Double> {
        Binding(
            get: { manifest?.states?[stateKey]?.variants[index].cooldown ?? fallback },
            set: { newValue in
                updateVariant(stateKey, index: index) { $0.cooldown = newValue > 0 ? newValue : nil }
            }
        )
    }

    private func bindingForLoop(stateKey: String, index: Int, fallback: Bool) -> Binding<Bool> {
        Binding(
            get: { manifest?.states?[stateKey]?.variants[index].loop ?? fallback },
            set: { newValue in
                updateVariant(stateKey, index: index) { $0.loop = newValue }
            }
        )
    }

    private func bindingForConditionsArray(stateKey: String, index: Int, fallback: [String]) -> Binding<[String]> {
        Binding(
            get: { manifest?.states?[stateKey]?.variants[index].conditions ?? fallback },
            set: { newValue in
                updateVariant(stateKey, index: index) { $0.conditions = newValue.isEmpty ? nil : newValue }
            }
        )
    }

    private func bindingForConditions(stateKey: String, index: Int, fallback: [String]) -> Binding<String> {
        Binding(
            get: { (manifest?.states?[stateKey]?.variants[index].conditions ?? fallback).joined(separator: ", ") },
            set: { newValue in
                let parsed = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                updateVariant(stateKey, index: index) {
                    $0.conditions = parsed.isEmpty ? nil : parsed
                }
            }
        )
    }

    private func bindingForPhraseLine(key: String, index: Int) -> Binding<String> {
        Binding(
            get: { phraseBook.phrases[key]?[index] ?? "" },
            set: { newValue in
                guard var lines = phraseBook.phrases[key], lines.indices.contains(index) else { return }
                lines[index] = newValue
                phraseBook.phrases[key] = lines
            }
        )
    }

    // MARK: - Display Helpers

    private var commonPhraseKeys: [String] {
        bubbleRuleSet.allCategoryKeys
    }

    private func phraseSortIndex(_ key: String) -> String {
        BubbleRuleSet.sortIndex(for: key)
    }

    private func phraseTitle(for key: String) -> String {
        BubbleRuleSet.displayName(for: key)
    }

    @ViewBuilder
    private func ruleEditorCard(for key: String) -> some View {
        BubbleRuleEditorView(key: key, ruleSet: $bubbleRuleSet)
    }

    private func encodedJSONString<T: Encodable>(from value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

