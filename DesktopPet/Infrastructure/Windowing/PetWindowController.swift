import AppKit
import SwiftUI

/// 宠物窗口控制器 — 管理窗口创建、拖拽、点击穿透、右键菜单
/// 物理/移动逻辑已拆到 PetPhysicsController
@MainActor
final class PetWindowController {
    private static let bubbleReservedHeight: CGFloat = 36
    
    private let panel: PetPanel
    private let state: PetRuntimeState
    private var hostingView: HitTestView<PetView>?
    private let physics: PetPhysicsController
    
    /// 拖拽时记录鼠标在窗口内的初始偏移
    private var dragOffset: CGPoint = .zero
    
    /// 打开控制面板的回调（由 AppCoordinator 注入）
    var onOpenControlPanel: (() -> Void)?
    
    /// 状态变化回调，用于同步播放动画
    var onBehaviorStateChanged: ((PetBehaviorState) -> Void)? {
        didSet { physics.onBehaviorStateChanged = onBehaviorStateChanged }
    }
    
    /// 当宠物走到屏幕边缘时的回调
    var onReachBoundary: ((FacingDirection) -> Void)? {
        didSet { physics.onReachBoundary = onReachBoundary }
    }
    
    /// 互动回调（鼠标靠近、拖拽等），用于唤醒 sleep
    var onInteraction: (() -> Void)?
    
    /// 宠物坐下/站起回调
    var onSitStateChanged: ((Bool, CGFloat?) -> Void)? {
        didSet { physics.onSitStateChanged = onSitStateChanged }
    }
    
    /// 物理循环计时器
    private var physicsTimer: Timer?
    private var displayLink: CADisplayLink?
    
    /// 全局鼠标监听器（点击穿透用）
    private var mouseMonitor: Any?
    
    private var windowSize: NSSize {
        NSSize(
            width: state.petSize.width,
            height: state.petSize.height + Self.bubbleReservedHeight
        )
    }
    
    init(
        petView: PetView,
        state: PetRuntimeState,
        initialPosition: CGPoint?,
        isInitiallyVisible: Bool
    ) {
        self.state = state
        self.physics = PetPhysicsController(state: state)
        
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let windowSize = NSSize(
            width: state.petSize.width,
            height: state.petSize.height + Self.bubbleReservedHeight
        )
        let initialOrigin = Self.resolvedInitialOrigin(
            savedPosition: initialPosition,
            screenFrame: screenFrame,
            windowSize: windowSize
        )
        
        self.panel = PetPanel(contentRect: NSRect(origin: initialOrigin, size: windowSize))
        
        // 用 HitTestView（NSHostingView 子类）嵌入 SwiftUI View
        let hitView = HitTestView(rootView: petView)
        hitView.frame = NSRect(origin: .zero, size: windowSize)
        panel.contentView = hitView
        self.hostingView = hitView
        
        // 配置物理控制器
        physics.panelWindowNumber = panel.windowNumber
        physics.onFallRequested = { [weak self] in
            self?.triggerFall()
        }
        
        // 更新初始位置到 state
        state.position = CGPoint(x: initialOrigin.x, y: initialOrigin.y)
        
        // 绑定拖拽回调
        hitView.onDragBegan = { [weak self] point in self?.beginDrag(at: point) }
        hitView.onDragMoved = { [weak self] point in self?.updateDrag(to: point) }
        hitView.onDragEnded = { [weak self] in self?.endDrag() }
        
        // 绑定右键菜单
        hitView.contextMenuProvider = { [weak self] in
            return self?.buildContextMenu() ?? NSMenu()
        }
        
        startPhysicsLoop()
        startClickThroughMonitor()

        if !isInitiallyVisible {
            panel.orderOut(nil)
        }
    }
    
    deinit {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    func showWindow() {
        panel.orderFront(nil)
    }
    
    @discardableResult
    func toggleVisibility() -> Bool {
        if panel.isVisible {
            panel.orderOut(nil)
            return false
        } else {
            panel.orderFront(nil)
            return true
        }
    }
    
    func updateWindowSize() {
        let newSize = windowSize
        var frame = panel.frame
        frame.size = newSize
        panel.setFrame(frame, display: true)
        hostingView?.frame = NSRect(origin: .zero, size: newSize)
    }
    
    // MARK: - 点击穿透
    
    private func startClickThroughMonitor() {
        // 全局鼠标移动监听
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                self?.updateClickThrough()
            }
        }
        
        // 本地事件补充
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in
                self?.updateClickThrough()
            }
            return event
        }
    }
    
    private func updateClickThrough() {
        guard !state.isDragging else {
            panel.ignoresMouseEvents = false
            return
        }
        
        let mouseLocation = NSEvent.mouseLocation
        let isOverPet = isPetHitArea(mouseLocation)
        panel.ignoresMouseEvents = !isOverPet
        
        // 鼠标靠近宠物时触发互动（唤醒 sleep 等）
        if isOverPet {
            onInteraction?()
        }
    }
    
    /// Alpha-based 像素级命中检测
    private func isPetHitArea(_ screenPoint: NSPoint) -> Bool {
        guard panel.frame.contains(screenPoint) else { return false }
        return hostingView?.isScreenPointOpaque(screenPoint) ?? false
    }
    
    // MARK: - 右键菜单
    
    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu(title: "DesktopPet")
        
        menu.addItem(withTitle: "打开控制面板", action: #selector(menuOpenPanel), keyEquivalent: "")
            .target = self
        
        menu.addItem(.separator())
        
        let visibilityTitle = panel.isVisible ? "隐藏宠物" : "显示宠物"
        menu.addItem(withTitle: visibilityTitle, action: #selector(menuToggleVisibility), keyEquivalent: "")
            .target = self
        
        menu.addItem(.separator())
        
        menu.addItem(withTitle: "退出 DesktopPet", action: #selector(menuQuit), keyEquivalent: "")
            .target = self
        
        return menu
    }
    
    @objc private func menuOpenPanel() { onOpenControlPanel?() }
    @objc private func menuToggleVisibility() { toggleVisibility() }
    @objc private func menuQuit() { NSApplication.shared.terminate(nil) }
    
    // MARK: - 拖拽
    
    private func beginDrag(at screenPoint: NSPoint) {
        let windowOrigin = panel.frame.origin
        dragOffset = CGPoint(
            x: screenPoint.x - windowOrigin.x,
            y: screenPoint.y - windowOrigin.y
        )
        state.isDragging = true
        onInteraction?()
        state.behaviorState = .drag
        onBehaviorStateChanged?(.drag)
    }
    
    private func updateDrag(to screenPoint: NSPoint) {
        let newOrigin = NSPoint(
            x: round(screenPoint.x - dragOffset.x),
            y: round(screenPoint.y - dragOffset.y)
        )
        applyPosition(newOrigin)
    }
    
    private func endDrag() {
        state.isDragging = false
        
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let landing = physics.detectLanding(panelFrame: panel.frame, screenFrame: screenFrame)
        
        // 🔍 DEBUG: 拖拽释放诊断
        print("[DEBUG endDrag] panel.frame=\(panel.frame) screenFrame=\(screenFrame)")
        
        switch landing {
        case .ground:
            print("[DEBUG endDrag] → landing = GROUND")
            physics.setWalkingSurface(.ground)
            state.behaviorState = .idle
            onBehaviorStateChanged?(.idle)
            
        case .windowTop(let windowID, let adjustedY, let bounds):
            print("[DEBUG endDrag] → landing = WINDOW_TOP windowID=\(windowID) adjustedY=\(adjustedY) bounds=\(bounds)")
            physics.setWalkingSurface(.windowTop(
                windowID: windowID,
                minX: bounds.minX,
                maxX: bounds.maxX
            ))
            applyPosition(NSPoint(x: panel.frame.origin.x, y: adjustedY))
            state.behaviorState = .idle
            onBehaviorStateChanged?(.idle)
            
        case .midAir:
            print("[DEBUG endDrag] → landing = MID_AIR, triggering fall")
            state.behaviorState = .fall
            onBehaviorStateChanged?(.fall)
            triggerFall()
        }
    }
    
    // MARK: - 下落动画
    
    private func triggerFall() {
        state.behaviorState = .fall
        let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        Task {
            await animateFallToGround(screenFrame: screenFrame)
        }
    }
    
    private func animateFallToGround(screenFrame: NSRect) async {
        let groundY = screenFrame.minY
        var currentY = panel.frame.origin.y
        var velocity: CGFloat = 0
        
        print("[DEBUG fall] START groundY=\(groundY) currentY=\(currentY)")
        
        while currentY > groundY {
            velocity += 0.3  // 重力加速
            currentY -= velocity
            
            let petMidX = panel.frame.origin.x + panel.frame.width / 2
            
            // 检查是否碰到窗口顶部
            if let landing = physics.detectFallLanding(petMidX: petMidX, currentY: currentY) {
                print("[DEBUG fall] LANDED ON WINDOW at y=\(currentY) → windowTop=\(landing.windowTop) windowID=\(landing.windowID)")
                applyPosition(NSPoint(x: panel.frame.origin.x, y: landing.windowTop))
                physics.setWalkingSurface(.windowTop(
                    windowID: landing.windowID,
                    minX: landing.bounds.minX,
                    maxX: landing.bounds.maxX
                ))
                state.behaviorState = .idle
                onBehaviorStateChanged?(.idle)
                return
            }
            
            applyPosition(NSPoint(x: panel.frame.origin.x, y: max(currentY, groundY)))
            try? await Task.sleep(for: .milliseconds(16))
        }
        
        print("[DEBUG fall] REACHED GROUND at y=\(groundY)")
        // 落到地面
        physics.setWalkingSurface(.ground)
        state.behaviorState = .idle
        onBehaviorStateChanged?(.idle)
    }
    
    // MARK: - 物理循环
    
    private func startPhysicsLoop() {
        displayLink?.invalidate()
        if #available(macOS 14.0, *) {
            if let link = hostingView?.displayLink(target: self, selector: #selector(physicsTick)) {
                link.add(to: .main, forMode: .common)
                displayLink = link
                return
            }
        }
        
        // Fallback
        let timer = Timer(timeInterval: 0.016, target: self, selector: #selector(physicsTick), userInfo: nil, repeats: true)
        timer.tolerance = 0.001
        RunLoop.current.add(timer, forMode: .common)
        physicsTimer = timer
    }
    
    @objc private func physicsTick() {
        // 每帧更新点击穿透
        updateClickThrough()
        
        // sit 稳定性检测
        if state.behaviorState == .sit {
            physics.checkSitStability(panelFrame: panel.frame)
            // sit 回调可能更新了位置
            if let windowID = physics.sittingOnWindowID,
               let top = WindowDetector.getWindowTop(windowID: windowID) {
                if abs(panel.frame.origin.y - top) > 5 {
                    applyPosition(NSPoint(x: panel.frame.origin.x, y: top))
                }
            }
            return
        }
        
        // walk 移动
        let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        if let newOrigin = physics.tickWalk(panelFrame: panel.frame, screenFrame: screenFrame) {
            applyPosition(newOrigin)
            // walk 中检测窗口边缘
            physics.checkForWindowEdge(panelFrame: panel.frame)
        }
    }
    
    // MARK: - 位置工具
    
    private func applyPosition(_ origin: NSPoint) {
        panel.setFrameOrigin(origin)
        let actual = panel.frame.origin
        if abs(actual.x - origin.x) > 1 || abs(actual.y - origin.y) > 1 {
            print("[DEBUG applyPosition] ⚠️ MISMATCH! requested=\(origin) actual=\(actual)")
        }
        state.position = CGPoint(x: actual.x, y: actual.y)
    }
    
    /// 临时调试：自动测试下落（3 秒后触发）
    func debugAutoFallTest() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            let screenFrame = NSScreen.main?.visibleFrame ?? .zero
            let testY = screenFrame.maxY - 50 // 接近屏幕顶部
            let testOrigin = NSPoint(x: screenFrame.midX - panel.frame.width/2, y: testY)
            print("[DEBUG autoTest] Moving pet to \(testOrigin)")
            applyPosition(testOrigin)
            print("[DEBUG autoTest] Actual position after move: \(panel.frame.origin)")
            
            try? await Task.sleep(for: .seconds(1))
            print("[DEBUG autoTest] Triggering fall from \(panel.frame.origin)")
            triggerFall()
        }
    }

    private static func resolvedInitialOrigin(
        savedPosition: CGPoint?,
        screenFrame: NSRect,
        windowSize: NSSize
    ) -> NSPoint {
        let defaultOrigin = NSPoint(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.minY
        )

        guard let savedPosition else { return defaultOrigin }

        let minX = screenFrame.minX - 50
        let maxX = screenFrame.maxX - windowSize.width + 50
        let minY = screenFrame.minY
        let maxY = screenFrame.maxY - windowSize.height

        return NSPoint(
            x: min(max(savedPosition.x, minX), maxX),
            y: min(max(savedPosition.y, minY), maxY)
        )
    }
}
