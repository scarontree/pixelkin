import SwiftUI

/// 皮肤卡片组件 — Gacha 风格细长卡片
struct SkinCard: View {
    let skin: SkinManifest
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void
    var onDelete: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onEditManifest: (() -> Void)? = nil
    @State private var hover = false
    
    var body: some View {
        Button(action: action) {
            SkinCardContent(skin: skin, isSelected: isSelected, isDisabled: isDisabled)
                .scaleEffect(hover && !isDisabled ? 1.02 : 1.0)
                .offset(y: hover && !isDisabled ? -2 : 0)
                .shadow(color: isSelected ? Color.accentColor.opacity(hover ? 0.3 : 0.1) : Color.black.opacity(hover && !isDisabled ? 0.1 : 0.0),
                        radius: hover && !isDisabled ? 12 : 8, y: hover && !isDisabled ? 6 : 2)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
                .onHover { isHovered in
                    if !isDisabled {
                        withAnimation { hover = isHovered }
                    }
                }
                .contextMenu {
                    Button("编辑皮肤设置") {
                        onEdit?()
                    }
                    Button("高级: 编辑属性") {
                        onEditManifest?()
                    }
                    Divider()
                    Button("删除此皮肤", role: .destructive) {
                        onDelete?()
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - SkinCardContent

private struct SkinCardContent: View {
    let skin: SkinManifest
    let isSelected: Bool
    let isDisabled: Bool

    private var engineLabel: String {
        switch skin.type.lowercased() {
        case "gif":
            return "GIF"
        case "svg":
            return "SVG"
        case "sprite":
            return "Sprite"
        case "rive":
            return "Rive"
        default:
            return skin.type.capitalized
        }
    }
    
    private var gradientColors: [Color] {
        if isSelected {
            return [Color.accentColor.opacity(0.5), Color.accentColor.opacity(0.1)]
        } else if isDisabled {
            return [Color.gray.opacity(0.1), Color.gray.opacity(0.05)]
        } else {
            return [Color.gray.opacity(0.2), Color.gray.opacity(0.02)]
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 图鉴区域 (瘦长)
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    gradient: Gradient(colors: gradientColors),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                Image(systemName: isDisabled ? "lock.fill" : (isSelected ? "sparkles" : "pawprint.fill"))
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(isDisabled ? Color.secondary.opacity(0.3) : (isSelected ? Color.white : Color.secondary.opacity(0.5)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                if isSelected {
                    Circle()
                        .fill(RadialGradient(gradient: Gradient(colors: [Color.white.opacity(0.5), Color.clear]), center: .center, startRadius: 0, endRadius: 50))
                        .blendMode(.screen)
                }
                
                if let tag = skin.tag {
                    Text(tag)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isDisabled ? Color.gray.opacity(0.5) : (isSelected ? Color.white : Color.secondary.opacity(0.2)))
                        .foregroundColor(isDisabled ? Color.white : (isSelected ? Color.accentColor : Color.primary))
                        .clipShape(Capsule())
                        .padding([.top, .trailing], 8)
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(8)
            
            // 文本信息区
            VStack(spacing: 4) {
                Text(skin.name)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundColor(isDisabled ? Color.secondary : (isSelected ? Color.accentColor : Color.primary))
                    .lineLimit(1)
                
                Text(engineLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(isDisabled ? Color.secondary.opacity(0.5) : Color.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
        )
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}
