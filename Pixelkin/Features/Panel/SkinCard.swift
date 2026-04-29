import SwiftUI

/// 皮肤卡片组件 — Gacha 风格细长卡片
struct SkinCard: View {
    let skin: SkinManifest
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void
    var onDelete: (() -> Void)? = nil
    var onEditFiles: (() -> Void)? = nil
    @State private var hover = false
    @State private var showDeleteConfirmation = false
    
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
                    Button("编辑属性") {
                        onEditFiles?()
                    }
                    Divider()
                    Button("删除此皮肤", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .confirmationDialog(
            "确定要删除皮肤「\(skin.name)」吗？",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                onDelete?()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作将永久删除皮肤文件，不可恢复。")
        }
    }
}

// MARK: - SkinCardContent

private struct SkinCardContent: View {
    let skin: SkinManifest
    let isSelected: Bool
    let isDisabled: Bool

    private var engineLabel: String {
        skin.skinType.displayName
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

    /// 尝试加载预览图：优先 manifest.preview → 自动发现 idle 资源 → nil
    private var previewImage: NSImage? {
        guard let dir = skin.directoryURL else { return nil }
        let fm = FileManager.default

        // 1. manifest 中指定的 preview 文件
        if let previewName = skin.preview, !previewName.isEmpty {
            let url = dir.appendingPathComponent(previewName)
            if let img = NSImage(contentsOf: url) {
                return extractFirstFrame(from: img, manifest: skin)
            }
        }

        // 2. 自动发现：idle 资源（最常见的预览来源）
        if let idleVariant = skin.states?["idle"]?.variants.first {
            let url = dir.appendingPathComponent(idleVariant.file)
            if let img = NSImage(contentsOf: url) {
                return extractFirstFrame(from: img, manifest: skin, variant: idleVariant)
            }
        }

        // 3. 目录中任意图片文件
        let imageExtensions: Set<String> = ["png", "gif", "jpg", "jpeg", "webp"]
        if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files where imageExtensions.contains(file.pathExtension.lowercased()) {
                if let img = NSImage(contentsOf: file) {
                    return extractFirstFrame(from: img, manifest: skin)
                }
            }
        }

        return nil
    }

    /// 对 sprite sheet 提取第一帧；GIF/普通图片直接返回
    private func extractFirstFrame(
        from image: NSImage,
        manifest: SkinManifest,
        variant: SkinManifest.AnimationVariant? = nil
    ) -> NSImage {
        // 如果是 sprite sheet 且有 frameSize，裁剪第一帧
        if manifest.skinType == .sprite,
           let frameSize = manifest.frameSize,
           frameSize.width > 0, frameSize.height > 0 {
            let fw = CGFloat(frameSize.width)
            let fh = CGFloat(frameSize.height)
            let pixelSize = image.pixelSize
            // 只在图片宽度确实大于一帧时裁剪
            if pixelSize.width > fw * 1.5 {
                let cropRect = CGRect(x: 0, y: pixelSize.height - fh, width: fw, height: fh)
                if let cgRef = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                   let cropped = cgRef.cropping(to: cropRect) {
                    return NSImage(cgImage: cropped, size: NSSize(width: fw, height: fh))
                }
            }
        }
        return image
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

                if let preview = previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(12)
                } else {
                    Image(systemName: isDisabled ? "lock.fill" : (isSelected ? "sparkles" : "pawprint.fill"))
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(isDisabled ? Color.secondary.opacity(0.3) : (isSelected ? Color.white : Color.secondary.opacity(0.5)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
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

// MARK: - NSImage 像素尺寸辅助

private extension NSImage {
    /// 获取图片的实际像素尺寸（而非 point 尺寸）
    var pixelSize: CGSize {
        guard let rep = representations.first else { return size }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
}
