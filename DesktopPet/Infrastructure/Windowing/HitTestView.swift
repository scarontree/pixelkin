import AppKit
import SwiftUI

/// 命中测试 NSHostingView 子类 — 处理拖拽与右键菜单
/// 使用 alpha-based 像素检测：透明像素穿透，不透明像素响应
/// SwiftUI DragGesture 在 nonactivatingPanel 下不可靠，改用 AppKit 原生鼠标事件
final class HitTestView<Content: View>: NSHostingView<Content> {
    
    /// 拖拽回调
    var onDragBegan: ((NSPoint) -> Void)?
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    
    /// 右键菜单构建
    var contextMenuProvider: (() -> NSMenu)?
    
    private var isDragging = false
    
    /// Alpha 阈值：像素 alpha 大于此值时视为"可点击"（0-255）
    private let alphaThreshold: UInt8 = 20
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    // MARK: - Alpha-based 命中测试
    
    /// 检测屏幕坐标处的像素是否不透明（供 PetWindowController 调用）
    /// 使用 NSView.cacheDisplay 捕获实际渲染内容
    func isScreenPointOpaque(_ screenPoint: NSPoint) -> Bool {
        guard let window = window else { return false }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let viewPoint = convert(windowPoint, from: nil)
        guard bounds.contains(viewPoint) else { return false }
        return isPixelOpaque(at: viewPoint)
    }
    
    /// 核心方法：捕获指定位置的 1x1 像素并检查 alpha
    private func isPixelOpaque(at viewPoint: NSPoint) -> Bool {
        let sampleRect = NSRect(
            x: floor(viewPoint.x),
            y: floor(viewPoint.y),
            width: 1,
            height: 1
        )
        
        guard bounds.intersects(sampleRect) else { return false }
        
        // 使用 macOS 原生 API 捕获渲染内容
        guard let bitmap = bitmapImageRepForCachingDisplay(in: sampleRect) else { return false }
        cacheDisplay(in: sampleRect, to: bitmap)
        
        guard let data = bitmap.bitmapData else { return false }
        
        // 检查 alpha 通道
        if bitmap.samplesPerPixel >= 4 {
            return data[3] > alphaThreshold
        }
        // 无 alpha 通道但有颜色 → 视为不透明
        if bitmap.samplesPerPixel >= 3 {
            return data[0] > 0 || data[1] > 0 || data[2] > 0
        }
        return false
    }
    
    // MARK: - 鼠标事件
    
    override func mouseDown(with event: NSEvent) {
        isDragging = true
        let screenPoint = NSEvent.mouseLocation
        onDragBegan?(screenPoint)
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let screenPoint = NSEvent.mouseLocation
        onDragMoved?(screenPoint)
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        onDragEnded?()
    }
    
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenuProvider?() else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
