import SwiftUI

/// 皮肤导入/编辑弹窗 — 创建新皮肤或编辑已有皮肤的基础属性
struct SkinEditorModal: View {
    @Binding var isPresented: Bool
    
    /// 编辑模式传入已有 manifest，新建模式传 nil
    var skinToEdit: SkinManifest?
    
    @State private var selectedSourceURL: URL? = nil
    
    @State private var skinName: String = ""
    @State private var diskID: String = ""
    @State private var engine: SkinManifest.SkinType = .sprite
    @State private var tag: String = ""
    @State private var groupLabel: String = ""
    
    private let engineOptions = SkinManifest.SkinType.allCases.filter { $0 != .unknown }

    private func engineLabel(_ engine: SkinManifest.SkinType) -> String {
        engine.displayName
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(skinToEdit != nil ? "编辑皮肤属性" : "配置新皮肤")
                    .font(.headline)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            Form {
                Section {
                    LabeledContent("本地资源文件夹名") {
                        Button(action: {
                            if skinToEdit != nil {
                                if let url = skinToEdit?.directoryURL {
                                    NSWorkspace.shared.open(url)
                                }
                            } else {
                                let openPanel = NSOpenPanel()
                                openPanel.canChooseFiles = false
                                openPanel.canChooseDirectories = true
                                openPanel.allowsMultipleSelection = false
                                openPanel.prompt = "选为本地源"
                                openPanel.message = "请选择任意包含你资源的文件夹"
                                if openPanel.runModal() == .OK, let url = openPanel.url {
                                    selectedSourceURL = url
                                    diskID = url.lastPathComponent
                                }
                            }
                        }) {
                            Text(diskID.isEmpty ? "点击选择" : diskID)
                                .foregroundStyle(diskID.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                    TextField("界面展示名称", text: $skinName)
                }
                .padding(.bottom, 6)
                
                Section {
                    Picker("渲染引擎类型", selection: $engine) {
                        ForEach(engineOptions, id: \.self) { e in
                            Text(engineLabel(e)).tag(e)
                        }
                    }
                }
                .padding(.bottom, 6)
                
                Section {
                    TextField("所属分组大类", text: $groupLabel)
                    TextField("特征识别小标签", text: $tag)
                }
            }
            .formStyle(.grouped)
            .frame(width: 380, height: 380)
            
            if skinToEdit == nil {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("导入成功后，请右键点击生成的卡片，进入「编辑属性」配置具体动画片段与角色语录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(skinToEdit != nil ? "保存修改" : "导入并保存") {
                    performSave()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(skinName.isEmpty || diskID.isEmpty)
            }
            .padding()
        }
        .onAppear {
            if let skin = skinToEdit {
                diskID = skin.id
                skinName = skin.name
                engine = skin.skinType
                tag = skin.tag ?? ""
                groupLabel = skin.group ?? ""
            }
        }
    }
    
    private func performSave() {
        if skinToEdit != nil {
            // 编辑模式：更新已有 manifest 的 UI 字段
            updateExistingManifest()
        } else {
            // 新建模式：导入资源并生成 manifest
            SkinService.importSkin(
                from: selectedSourceURL ?? URL(fileURLWithPath: "/dev/null"),
                skinID: diskID,
                displayName: skinName,
                engineType: engine.rawValue,
                group: groupLabel.isEmpty ? nil : groupLabel,
                tag: tag.isEmpty ? nil : tag
            )
        }
    }
    
    private func updateExistingManifest() {
        guard let skin = skinToEdit else { return }
        SkinService.updateSkinMetadata(
            for: skin,
            displayName: skinName,
            group: groupLabel.isEmpty ? nil : groupLabel,
            tag: tag.isEmpty ? nil : tag
        )
    }
}
