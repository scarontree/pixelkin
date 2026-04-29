import AppKit

/// GIF 动画适配器 — 播放直接由 .gif 组成的动画包
@MainActor
final class GifAdapter: AnimationAdapter {
    
    private let manifest: SkinManifest
    private let skinDirectory: URL
    private var renderView: SpriteRenderView?
    
    private var currentState: PetBehaviorState = .idle
    private var currentDirection: FacingDirection = .right
    
    // 渲染尺寸
    private var renderWidth: CGFloat {
        (manifest.frameSize?.width ?? 64) * (manifest.scale ?? 2)
    }
    private var renderHeight: CGFloat {
        (manifest.frameSize?.height ?? 64) * (manifest.scale ?? 2)
    }
    
    // 动画状态
    private var cachedFrames: [CGImage] = []
    private var frameDelays: [Double] = []
    private var currentFrame: Int = 0
    private var displayLink: CADisplayLink?
    private var frameTimer: Timer?
    private var lastFrameTime: CFTimeInterval = 0
    
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
        let variant: SkinManifest.AnimationVariant
        if let v = manifest.resolveVariant(for: state.rawValue, context: context) {
            variant = v
        } else if let v = manifest.resolveVariant(for: PetBehaviorState.idle.rawValue, context: context) {
            variant = v
        } else {
            return nil
        }
        
        currentState = state
        currentFrame = 0
        lastFrameTime = 0
        
        loadGif(fileName: variant.file)
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
    
    private func loadGif(fileName: String) {
        cachedFrames.removeAll()
        frameDelays.removeAll()
        
        let url = skinDirectory.appendingPathComponent(fileName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
        
        let count = CGImageSourceGetCount(source)
        for i in 0..<count {
            if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                cachedFrames.append(cgImage)
                
                var delay = 0.1
                if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
                   let gifInfo = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                    if let unclamped = gifInfo[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double, unclamped > 0 {
                        delay = unclamped
                    } else if let clamped = gifInfo[kCGImagePropertyGIFDelayTime as String] as? Double, clamped > 0 {
                        delay = clamped
                    }
                }
                frameDelays.append(delay)
            }
        }
    }
    
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
    
    @objc private func advanceFrame() {
        guard !cachedFrames.isEmpty else { return }
        
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - lastFrameTime
        let targetDelay = frameDelays[currentFrame]
        
        if elapsed >= targetDelay {
            lastFrameTime = currentTime - (elapsed - targetDelay) // 保留余数防止轻微丢帧
            currentFrame = (currentFrame + 1) % cachedFrames.count
            updateFrame()
        }
    }
    
    private func updateFrame() {
        guard currentFrame >= 0, currentFrame < cachedFrames.count else { return }
        renderView?.setFrame(image: cachedFrames[currentFrame])
    }
}
