import AppKit

/// Sprite Sheet 动画适配器 — 逐帧播放像素风动画
@MainActor
final class SpriteAdapter: AnimationAdapter {
    
    private let manifest: SkinManifest
    private let skinDirectory: URL
    private var renderView: SpriteRenderView?
    
    private var currentState: PetBehaviorState = .idle
    private var currentDirection: FacingDirection = .right
    
    // 帧动画状态
    private var cachedFrames: [CGImage] = []
    private var currentFrame: Int = 0
    private var totalFrames: Int = 0
    private var isLooping: Bool = true
    private var frameTimer: Timer?
    private var frameFps: Int = 0
    
    init(manifest: SkinManifest, skinDirectory: URL) {
        self.manifest = manifest
        self.skinDirectory = skinDirectory
    }
    
    deinit {
        // 保险：CADisplayLink/Timer 强持有 target，确保它们不会阻止释放
        displayLink?.invalidate()
        frameTimer?.invalidate()
    }
    
    @discardableResult
    func play(_ state: PetBehaviorState, context: SkinManifest.AnimationContext) -> SkinManifest.AnimationVariant? {
        // 尝试解析该状态的动画变体，找不到则 fallback 到 idle
        let stateName = state.rawValue
        let variant: SkinManifest.AnimationVariant
        if let v = manifest.resolveVariant(for: stateName, context: context) {
            variant = v
        } else if let v = manifest.resolveVariant(for: PetBehaviorState.idle.rawValue, context: context) {
            variant = v
        } else {
            return nil
        }
        
        guard let frames = variant.frames,
              let fps = variant.fps else { return nil }
        
        currentState = state
        currentFrame = 0
        totalFrames = frames
        isLooping = variant.loop ?? true
        frameFps = fps
        lastFrameTime = 0
        
        // 切状态时预裁切所有帧，后续每帧只做清屏 + 绘制
        cachedFrames = loadFrames(from: variant.file, frameCount: frames)
        
        updateFrame()
        startTimer()
        
        return variant
    }
    
    func stop() {
        stopTimer()
    }
    
    func setDirection(_ direction: FacingDirection) {
        currentDirection = direction
        renderView?.isHorizontallyFlipped = (direction == .left)
    }
    
    func attach(to container: NSView) {
        let view = SpriteRenderView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            view.widthAnchor.constraint(equalToConstant: renderWidth),
            view.heightAnchor.constraint(equalToConstant: renderHeight)
        ])
        
        self.renderView = view
        self.renderView?.isHorizontallyFlipped = (currentDirection == .left)
    }
    
    func detach() {
        stopTimer()
        renderView?.removeFromSuperview()
        renderView = nil
    }
    
    // MARK: - Private
    
    private var renderWidth: CGFloat {
        (manifest.frameSize?.width ?? 64) * (manifest.scale ?? 2)
    }
    
    private var renderHeight: CGFloat {
        (manifest.frameSize?.height ?? 64) * (manifest.scale ?? 2)
    }
    
    private var displayLink: CADisplayLink?
    
    private func startTimer() {
        stopTimer()
        lastFrameTime = CACurrentMediaTime()
        if #available(macOS 14.0, *) {
            if let link = renderView?.displayLink(target: self, selector: #selector(advanceFrame)) {
                link.add(to: .main, forMode: .common)
                displayLink = link
                return
            }
        }
        
        let timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(advanceFrame), userInfo: nil, repeats: true)
        timer.tolerance = 0.001
        RunLoop.current.add(timer, forMode: .common)
        frameTimer = timer
    }
    
    private func stopTimer() {
        displayLink?.invalidate()
        displayLink = nil
        frameTimer?.invalidate()
        frameTimer = nil
    }
    
    private var lastFrameTime: CFTimeInterval = 0
    
    @objc private func advanceFrame() {
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - lastFrameTime
        let targetInterval = 1.0 / Double(frameFps)
        
        if elapsed >= targetInterval {
            lastFrameTime = currentTime
            
            if isLooping {
                currentFrame = (currentFrame + 1) % totalFrames
            } else if currentFrame < totalFrames - 1 {
                currentFrame += 1
            }
            
            updateFrame()
        }
    }
    
    private func updateFrame() {
        guard currentFrame >= 0, currentFrame < cachedFrames.count else { return }
        renderView?.setFrame(image: cachedFrames[currentFrame])
    }
    
    private func loadFrames(from fileName: String, frameCount: Int) -> [CGImage] {
        guard let frameSize = manifest.frameSize else { return [] }
        
        let imageURL = skinDirectory.appendingPathComponent(fileName)
        guard let sheet = NSImage(contentsOf: imageURL),
              let cgImage = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }
        
        let fw = CGFloat(frameSize.width)
        let fh = CGFloat(frameSize.height)
        
        return (0..<frameCount).compactMap { frameIndex in
            let sourceRect = CGRect(
                x: CGFloat(frameIndex) * fw,
                y: 0,
                width: fw,
                height: fh
            )
            
            let flippedY = CGFloat(cgImage.height) - sourceRect.origin.y - sourceRect.height
            let cropRect = CGRect(
                x: sourceRect.origin.x,
                y: flippedY,
                width: sourceRect.width,
                height: sourceRect.height
            )
            
            return cgImage.cropping(to: cropRect)
        }
    }
}
