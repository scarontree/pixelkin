import SwiftUI

/// 自动换行流式布局 — 子视图按水平排列，超出宽度自动折行
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var width: CGFloat = 0
        var height: CGFloat = 0
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for size in sizes {
            if currentRowWidth + size.width + spacing > maxWidth {
                width = max(width, currentRowWidth)
                height += currentRowHeight + spacing
                currentRowWidth = size.width
                currentRowHeight = size.height
            } else {
                currentRowWidth += currentRowWidth > 0 ? spacing + size.width : size.width
                currentRowHeight = max(currentRowHeight, size.height)
            }
        }
        width = max(width, currentRowWidth)
        height += currentRowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += currentRowHeight + spacing
                currentRowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
    }
}
