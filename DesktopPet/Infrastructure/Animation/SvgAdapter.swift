import AppKit
import WebKit

/// SVG 动画适配器 — 使用 WKWebView 原生高质渲染矢量动效序列
@MainActor
final class SvgAdapter: AnimationAdapter {
    private let manifest: SkinManifest
    private let skinDirectory: URL
    private var renderView: SvgRenderView?
    private var currentDirection: FacingDirection = .right
    
    // 渲染尺寸
    private var renderWidth: CGFloat {
        (manifest.frameSize?.width ?? 64) * (manifest.scale ?? 2)
    }
    private var renderHeight: CGFloat {
        (manifest.frameSize?.height ?? 64) * (manifest.scale ?? 2)
    }
    
    init(manifest: SkinManifest, skinDirectory: URL) {
        self.manifest = manifest
        self.skinDirectory = skinDirectory
    }
    
    func play(_ state: PetBehaviorState) {
        // 尝试解析该状态的动画变体，找不到则 fallback 到 idle
        let variant: SkinManifest.AnimationVariant
        if let v = manifest.resolveVariant(for: state.rawValue) {
            variant = v
        } else if let v = manifest.resolveVariant(for: PetBehaviorState.idle.rawValue) {
            variant = v
        } else {
            return
        }
        
        let url = skinDirectory.appendingPathComponent(variant.file)
        renderView?.loadFile(url)
    }
    
    func stop() {}
    
    func setDirection(_ direction: FacingDirection) {
        currentDirection = direction
        renderView?.isHorizontallyFlipped = (direction == .left)
    }
    
    func attach(to container: NSView) {
        let view = SvgRenderView()
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
        renderView?.removeFromSuperview()
        renderView = nil
    }
}

// MARK: - SvgRenderView

/// SVG 渲染视图 — WKWebView 包装，透明背景
final class SvgRenderView: NSView {
    private let webView: WKWebView
    
    var isHorizontallyFlipped: Bool = false {
        didSet {
            let transform = isHorizontallyFlipped ? "scaleX(-1)" : "scaleX(1)"
            webView.evaluateJavaScript("document.body.style.transform = '\(transform)'; document.body.style.transformOrigin = 'center';")
        }
    }
    
    override init(frame frameRect: NSRect) {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        
        super.init(frame: frameRect)
        
        wantsLayer = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // FIXME: 阻断WKWebView的默认滚动与交互
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
    
    func loadFile(_ url: URL) {
        guard let svgContent = try? String(contentsOf: url) else {
            print("Failed to read SVG file at \(url)")
            return
        }
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                body, html {
                    margin: 0; padding: 0; width: 100%; height: 100%;
                    overflow: hidden; background: transparent; pointer-events: none;
                    transform: \(isHorizontallyFlipped ? "scaleX(-1)" : "scaleX(1)");
                    transform-origin: center;
                }
                svg {
                    width: 100% !important; height: 100% !important;
                    pointer-events: none; user-select: none;
                }
            </style>
        </head>
        <body>
            \(svgContent)
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
