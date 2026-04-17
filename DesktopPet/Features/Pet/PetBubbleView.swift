import SwiftUI

/// 漫画风对话气泡（带小尾巴，整体一个 Shape 统一毛玻璃）
struct PetBubbleView: View {
    let text: String
    
    private let tailHeight: CGFloat = 8
    private let cornerRadius: CGFloat = 12
    
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .padding(.bottom, tailHeight) // 为尾巴留空间
            .background {
                BubbleShape(cornerRadius: cornerRadius, tailHeight: tailHeight)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }
            .frame(maxWidth: 180)
    }
}

/// 带尾巴的气泡形状 — 圆角矩形 + 底部平滑三角，作为整体路径
struct BubbleShape: Shape {
    let cornerRadius: CGFloat
    let tailHeight: CGFloat
    
    func path(in rect: CGRect) -> Path {
        // 气泡主体区域（不含尾巴）
        let bodyRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height - tailHeight
        )
        
        // 尾巴参数
        let tailWidth: CGFloat = 14
        let tailCenterX = rect.midX + 4 // 稍偏右
        let tailTop = bodyRect.maxY
        let tailBottom = rect.maxY
        
        var path = Path()
        
        // 画圆角矩形（顺时针，从左上开始）
        path.addRoundedRect(in: bodyRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .continuous)
        
        // 画尾巴三角（从主体底边向下延伸）
        let tailLeft = tailCenterX - tailWidth / 2
        let tailRight = tailCenterX + tailWidth / 2
        
        path.move(to: CGPoint(x: tailLeft, y: tailTop))
        path.addQuadCurve(
            to: CGPoint(x: tailCenterX, y: tailBottom),
            control: CGPoint(x: tailCenterX - 3, y: tailTop + tailHeight * 0.5)
        )
        path.addQuadCurve(
            to: CGPoint(x: tailRight, y: tailTop),
            control: CGPoint(x: tailCenterX + 3, y: tailTop + tailHeight * 0.5)
        )
        path.closeSubpath()
        
        return path
    }
}
