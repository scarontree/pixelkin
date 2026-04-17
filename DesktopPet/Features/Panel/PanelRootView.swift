import SwiftUI

/// 控制面板根视图 — NavigationSplitView 骨架
struct PanelRootView: View {
    @State private var selectedSection: PanelSection = .skins
    let coordinator: AppCoordinator
    
    var body: some View {
        NavigationSplitView {
            List(PanelSection.allCases, id: \.self, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selectedSection {
            case .chat:
                placeholderView("聊天工作区", subtitle: "V2.0")
            case .personas:
                placeholderView("角色管理", subtitle: "V2.0")
            case .skins:
                SkinGalleryView(coordinator: coordinator)
            case .settings:
                placeholderView("设置", subtitle: "V1.0")
            }
        }
    }
    
    private func placeholderView(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - PanelSection

enum PanelSection: String, CaseIterable {
    case chat, personas, skins, settings
    
    var title: String {
        switch self {
        case .chat: return "聊天"
        case .personas: return "角色"
        case .skins: return "皮肤"
        case .settings: return "设置"
        }
    }
    
    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .personas: return "person.2"
        case .skins: return "paintpalette"
        case .settings: return "gear"
        }
    }
}
