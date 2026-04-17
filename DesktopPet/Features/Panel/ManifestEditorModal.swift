import SwiftUI

/// Manifest 编辑弹窗 — 结构化编辑为主，原始 JSON 退到高级模式
struct ManifestEditorModal: View {
    let skin: SkinManifest
    @Environment(\.dismiss) private var dismiss

    @State private var manifest: SkinManifest?
    @State private var errorMessage: String? = nil
    @State private var selectedStateKey: String? = nil

    private var sortedStateKeys: [String] {
        manifest?.states?.keys.sorted() ?? []
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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("动画状态配置 - \(skin.name)")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            if let manifest {
                HStack(spacing: 0) {
                    stateSidebar
                        .frame(width: 220)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            basicInfoEditor(manifest: manifest)
                            Divider()
                            stateEditor(manifest: manifest)
                        }
                        .padding(20)
                    }
                    .frame(minWidth: 620, minHeight: 460)
                }
            } else if errorMessage == nil {
                ContentUnavailableView("未找到配置文件", systemImage: "xmark.doc", description: Text("该皮肤文件夹下不存在 manifest.json 或者尚未导入到本地空间。"))
            }

            if let err = errorMessage {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存改动") {
                    saveManifest()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(manifest == nil)
            }
            .padding()
        }
        .onAppear(perform: loadManifest)
    }

    private var stateSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("状态")
                    .font(.headline)
                Spacer()
                Button(action: addState) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top)

            List(selection: $selectedStateKey) {
                ForEach(sortedStateKeys, id: \.self) { key in
                    HStack {
                        Image(systemName: "sparkles.rectangle.stack")
                            .foregroundStyle(.secondary)
                        Text(key)
                    }
                    .tag(Optional(key))
                }
                .onDelete(perform: deleteStates)
            }
        }
    }

    @ViewBuilder
    private func basicInfoEditor(manifest: SkinManifest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("基础信息")
                .font(.title3.weight(.semibold))

            HStack {
                infoField("ID", text: .constant(manifest.id), editable: false)
                infoField("名称", text: bindingForManifestName(fallback: manifest.name), editable: true)
            }

            HStack {
                infoField("类型", text: .constant(manifest.type), editable: false)
                infoField("分组", text: bindingForManifestGroup(fallback: manifest.group ?? ""), editable: true)
                infoField("标签", text: bindingForManifestTag(fallback: manifest.tag ?? ""), editable: true)
            }

            HStack {
                infoField("预览图", text: bindingForManifestPreview(fallback: manifest.preview ?? ""), editable: true)
                numberField("宽度", value: bindingForFrameWidth(fallback: Int(manifest.frameSize?.width ?? 64)))
                numberField("高度", value: bindingForFrameHeight(fallback: Int(manifest.frameSize?.height ?? 64)))
                decimalField("缩放", value: bindingForScale(fallback: manifest.scale ?? 1))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    @ViewBuilder
    private func stateEditor(manifest: SkinManifest) -> some View {
        if let stateKey = selectedStateKey,
           let config = manifest.states?[stateKey] {
            VStack(alignment: .leading, spacing: 20) {
                Text("状态配置")
                    .font(.title3.weight(.semibold))

                HStack {
                    infoField("状态名", text: bindingForStateName(currentKey: stateKey), editable: true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("选择策略")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("选择策略", selection: bindingForSelection(stateKey: stateKey, fallback: config.selection)) {
                            ForEach(SkinManifest.SelectionStrategy.allCases, id: \.self) { strategy in
                                Text(selectionStrategyLabel(strategy)).tag(strategy)
                            }
                        }
                        .labelsHidden()
                    }
                }

                Divider()

                HStack {
                    Text("动画变体")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button("新增变体") {
                        addVariant(to: stateKey)
                    }
                }

                ForEach(Array(config.variants.enumerated()), id: \.element.id) { index, variant in
                    variantCard(stateKey: stateKey, index: index, variant: variant)
                }
            }
        } else {
            ContentUnavailableView("未选择状态", systemImage: "square.stack", description: Text("从左侧选择一个状态，或新建一个状态。"))
        }
    }

    private func variantCard(
        stateKey: String,
        index: Int,
        variant: SkinManifest.AnimationVariant
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("变体 \(index + 1)")
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    deleteVariant(at: index, from: stateKey)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }

            TextField("变体 ID", text: bindingForVariantID(stateKey: stateKey, index: index))
                .textFieldStyle(.roundedBorder)

            TextField("文件名", text: bindingForVariantFile(stateKey: stateKey, index: index))
                .textFieldStyle(.roundedBorder)

            HStack {
                numberField("帧数", value: bindingForFrames(stateKey: stateKey, index: index, fallback: variant.frames ?? 1))
                numberField("FPS", value: bindingForFPS(stateKey: stateKey, index: index, fallback: variant.fps ?? 8))
                numberField("权重", value: bindingForWeight(stateKey: stateKey, index: index, fallback: variant.weight ?? 1))
                numberField("优先级", value: bindingForPriority(stateKey: stateKey, index: index, fallback: variant.priority ?? 0))
            }

            Toggle("循环播放", isOn: bindingForLoop(stateKey: stateKey, index: index, fallback: variant.loop ?? true))

            TextField("条件，逗号分隔", text: bindingForConditions(stateKey: stateKey, index: index, fallback: variant.conditions ?? []))
                .textFieldStyle(.roundedBorder)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private func numberField(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func decimalField(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func infoField(_ title: String, text: Binding<String>, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .disabled(!editable)
        }
    }

    private func loadManifest() {
        manifest = skin
        selectedStateKey = skin.states?.keys.sorted().first
        errorMessage = nil
    }

    private func saveManifest() {
        guard let manifest,
              let data = try? JSONEncoder.prettyPrinted.encode(manifest),
              let text = String(data: data, encoding: .utf8) else {
            errorMessage = "当前配置无法编码为 manifest.json。"
            return
        }

        if let message = SkinService.saveManifestText(text, for: skin) {
            errorMessage = message
        } else {
            dismiss()
        }
    }

    private func addState() {
        guard var manifest else { return }

        var states = manifest.states ?? [:]
        let base = "new_state"
        var key = base
        var suffix = 1
        while states[key] != nil {
            suffix += 1
            key = "\(base)_\(suffix)"
        }

        states[key] = .init(selection: .single, variants: [
            .init(id: "\(key)_default", file: "", frames: 1, fps: 8, loop: true, weight: 1, conditions: nil, priority: 0)
        ])
        manifest.states = states
        self.manifest = manifest
        selectedStateKey = key
    }

    private func deleteStates(at offsets: IndexSet) {
        guard var manifest else { return }

        let keys = sortedStateKeys
        for offset in offsets {
            manifest.states?.removeValue(forKey: keys[offset])
        }
        self.manifest = manifest
        selectedStateKey = manifest.states?.keys.sorted().first
    }

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

    private func bindingForStateName(currentKey: String) -> Binding<String> {
        Binding(
            get: { currentKey },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != currentKey, var manifest else { return }
                guard let config = manifest.states?.removeValue(forKey: currentKey) else { return }
                manifest.states?[trimmed] = config
                self.manifest = manifest
                selectedStateKey = trimmed
            }
        )
    }

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

    private func bindingForLoop(stateKey: String, index: Int, fallback: Bool) -> Binding<Bool> {
        Binding(
            get: { manifest?.states?[stateKey]?.variants[index].loop ?? fallback },
            set: { newValue in
                updateVariant(stateKey, index: index) { $0.loop = newValue }
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
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
