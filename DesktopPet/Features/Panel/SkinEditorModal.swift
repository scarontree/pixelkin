import SwiftUI

/// 皮肤导入/编辑弹窗 — 创建新皮肤或编辑已有皮肤的基础属性
struct SkinEditorModal: View {
    @Binding var isPresented: Bool
    
    /// 编辑模式传入已有 manifest，新建模式传 nil
    var skinToEdit: SkinManifest?
    
    @State private var selectedSourceURL: URL? = nil
    
    @State private var skinName: String = ""
    @State private var diskID: String = ""
    @State private var engine: String = "sprite"
    @State private var tag: String = ""
    @State private var groupLabel: String = ""
    
    let engineOptions = ["sprite", "gif", "svg", "rive"]

    private func engineLabel(_ engine: String) -> String {
        switch engine.lowercased() {
        case "gif":
            return "GIF"
        case "svg":
            return "SVG"
        case "sprite":
            return "Sprite"
        case "rive":
            return "Rive"
        default:
            return engine.capitalized
        }
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
                    HStack {
                        TextField("本地资源文件夹名", text: $diskID)
                            .disabled(skinToEdit != nil) // 编辑模式不允许改 ID
                        Button(action: {
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
                        }) {
                            Image(systemName: "folder.badge.magnifyingglass")
                        }
                        .help("点击在文件系统中选择")
                    }
                    TextField("界面展示名称", text: $skinName)
                } footer: {
                    Text("提示: 你也可以点击右侧图标直接从电脑里选择文件夹的名字。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section {
                    Picker("渲染引擎类型", selection: $engine) {
                        ForEach(engineOptions, id: \.self) { e in
                            Text(engineLabel(e)).tag(e)
                        }
                    }
                }
                
                Section {
                    TextField("所属分组大类", text: $groupLabel)
                    TextField("特征识别小标签", text: $tag)
                }
            }
            .formStyle(.grouped)
            .frame(width: 380, height: 380)
            
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
                engine = skin.type
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
                engineType: engine,
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
