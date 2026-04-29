import AppKit

/// Sprite 渲染视图 — 使用 CALayer 硬件加速，并强制使用 nearest 采样，解决像素画移动过程中的模糊问题
final class SpriteRenderView: NSView {
    
    private let spriteLayer = CALayer()
    
    /// 是否水平翻转（用于朝向切换）
    var isHorizontallyFlipped: Bool = false {
        didSet {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            spriteLayer.transform = isHorizontallyFlipped ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
            CATransaction.commit()
        }
    }
    
    override var isOpaque: Bool { false }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        // 非常关键：强制关闭图层放大的抗锯齿（避免边缘模糊）
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
        
        spriteLayer.contentsGravity = .resizeAspect
        spriteLayer.magnificationFilter = .nearest
        spriteLayer.minificationFilter = .nearest
        
        layer?.addSublayer(spriteLayer)
    }
    
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spriteLayer.frame = bounds
        CATransaction.commit()
    }
    
    /// 设置当前帧图片
    func setFrame(image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true) // 避免系统默认的隐式过渡动画引起叠加和模糊
        spriteLayer.contents = image
        CATransaction.commit()
    }
}
