import AppKit

/// 宠物窗口 — NSPanel 子类，透明无边框悬浮面板
final class PetPanel: NSPanel {
    
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        
        // ignoresMouseEvents 由 PetWindowController 动态控制
        // 初始为 true：透明区域默认穿透
        ignoresMouseEvents = true
    }
    
    // MARK: - 禁用系统默认的窗口位置限制
    
    /// 系统默认会将窗口限制在屏幕可视区域内（约上方 1/3 位置封顶），
    /// 宠物窗口需要自由移动到屏幕任意位置，故直接返回原始 rect 不做任何限制。
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
    
    // MARK: - 允许面板接收鼠标事件
    
    override var canBecomeKey: Bool { true }
}
