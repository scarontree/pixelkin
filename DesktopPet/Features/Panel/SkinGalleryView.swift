import SwiftUI

/// 皮肤画廊 — 扫描文件系统展示所有可用皮肤，支持热切换
struct SkinGalleryView: View {
    let coordinator: AppCoordinator
    
    @State private var groupedSkins: [String: [SkinManifest]] = [:]
    @State private var isShowingEditor = false
    @State private var skinToEdit: SkinManifest? = nil
    @State private var manifestSkinToEdit: SkinManifest? = nil
    
    private func iconFor(group: String) -> String {
        if group == "Beta Legacy" { return "flask.fill" }
        return "folder.fill"
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                
                // 顶部说明区
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("实时热切换引擎。当前挂载：")
                        .foregroundStyle(.secondary)
                    Text(coordinator.petState.currentSkinID)
                        .font(.system(.body, design: .monospaced).weight(.bold))
                        .foregroundStyle(.primary)
                }
                .font(.subheadline)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                if groupedSkins.isEmpty {
                    // 空状态提示
                    VStack(spacing: 16) {
                        Image(systemName: "tray.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("当前没有任何角色皮肤\n请点击右上角导入新皮肤")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    let sortedKeys = groupedSkins.keys.sorted()
                    
                    ForEach(sortedKeys, id: \.self) { groupName in
                        SkinSectionView(
                            title: groupName,
                            icon: iconFor(group: groupName),
                            skins: groupedSkins[groupName]!,
                            coordinator: coordinator,
                            isDisabled: false,
                            onEditSkin: { skin in
                                skinToEdit = skin
                                isShowingEditor = true
                            },
                            onEditManifestSkin: { skin in
                                manifestSkinToEdit = skin
                            },
                            onRefresh: { refreshSkins() }
                        )
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .navigationTitle("主题皮肤与角色")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    skinToEdit = nil
                    isShowingEditor = true
                }) {
                    Label("导入新皮肤", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { refreshSkins() }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .sheet(isPresented: $isShowingEditor, onDismiss: { refreshSkins() }) {
            SkinEditorModal(isPresented: $isShowingEditor, skinToEdit: skinToEdit)
        }
        .sheet(item: $manifestSkinToEdit, onDismiss: { refreshSkins() }) { skin in
            ManifestEditorModal(skin: skin)
        }
        .onAppear {
            refreshSkins()
        }
        .background(Color.clear)
    }
    
    private func refreshSkins() {
        groupedSkins = SkinService.discoverAllSkins()
    }
}

// MARK: - SkinSectionView

struct SkinSectionView: View {
    let title: String
    let icon: String
    let skins: [SkinManifest]
    let coordinator: AppCoordinator
    let isDisabled: Bool
    var onEditSkin: ((SkinManifest) -> Void)? = nil
    var onEditManifestSkin: ((SkinManifest) -> Void)? = nil
    var onRefresh: (() -> Void)? = nil
    
    let columns = [GridItem(.adaptive(minimum: 140, maximum: 160), spacing: 20)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(isDisabled ? Color.secondary : Color.accentColor)
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
            }
            .padding(.horizontal, 24)
            .opacity(isDisabled ? 0.6 : 1.0)
            
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(skins) { skin in
                    SkinCard(
                        skin: skin,
                        isSelected: coordinator.petState.currentSkinID == skin.id,
                        isDisabled: isDisabled,
                        action: {
                            if !isDisabled {
                                coordinator.switchSkin(name: skin.id)
                            }
                        },
                        onDelete: {
                            deleteSkin(skin)
                        },
                        onEdit: onEditSkin != nil ? { onEditSkin?(skin) } : nil,
                        onEditManifest: onEditManifestSkin != nil ? { onEditManifestSkin?(skin) } : nil
                    )
                }
            }
            .padding(.horizontal, 24)
        }
    }
    
    private func deleteSkin(_ skin: SkinManifest) {
        SkinService.deleteImportedSkin(skin)
        onRefresh?()
    }
}
