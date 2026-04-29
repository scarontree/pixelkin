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
    
    /// 点击事件回调
    var onClick: (() -> Void)?
    
    /// 互动回调（鼠标靠近、拖拽等），用于唤醒 sleep
    var onInteraction: (() -> Void)?
    
    /// 宠物坐下/站起回调
    var onSitStateChanged: ((Bool, CGFloat?) -> Void)? {
        didSet { physics.onSitStateChanged = onSitStateChanged }
    }
    
    /// 宠物 cling 状态变化回调
    var onClingStateChanged: ((Bool, FacingDirection?, CGFloat?) -> Void)? {
        didSet { physics.onClingStateChanged = onClingStateChanged }
    }
    
    /// 物理循环计时器
    private var physicsTimer: Timer?
    private var displayLink: CADisplayLink?
    
    /// 全局鼠标监听器（点击穿透用）
    private var mouseMonitor: Any?
    /// 本地鼠标监听器（点击穿透用）
    private var localMouseMonitor: Any?
    
    /// 点击穿透降频计数器（避免每帧 cacheDisplay）
    private var clickThroughCounter: Int = 0
    
    /// hover 交互节流时间戳（避免鼠标路过不断重置 sleep 计时器）
    private var lastHoverInteractionTime: Date = .distantPast
    
    /// 拖拽开始时窗口的位置
    private var dragStartWindowOrigin: NSPoint = .zero
    
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
        hitView.onDragEnded = { [weak self] isClick in self?.endDrag(isClick: isClick) }
        
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
        if let monitor = localMouseMonitor {
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
        let deltaWidth = newSize.width - frame.size.width
        frame.size = newSize
        frame.origin.x -= deltaWidth / 2
        panel.setFrame(frame, display: true)
        hostingView?.frame = NSRect(origin: .zero, size: newSize)
        state.position = CGPoint(x: panel.frame.origin.x, y: panel.frame.origin.y)
    }
    
    // MARK: - 点击穿透
    
    private func startClickThroughMonitor() {
        // 全局鼠标移动监听
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                self?.updateClickThrough()
            }
        }
        
        // 本地事件补充 — 保存返回值以便清理
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
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
        
        // 鼠标靠近宠物时触发互动（唤醒 sleep 等）— 10s 节流避免频繁重置
        if isOverPet {
            let now = Date()
            if now.timeIntervalSince(lastHoverInteractionTime) > 10 {
                lastHoverInteractionTime = now
                onInteraction?()
            }
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
        dragStartWindowOrigin = windowOrigin
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
    
    private func endDrag(isClick: Bool) {
        state.isDragging = false
        
        if isClick {
            // 如果是点击，恢复初始位置（消除微小拖动的偏移）
            applyPosition(dragStartWindowOrigin)
        }
        
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let landing = physics.detectLanding(panelFrame: panel.frame, screenFrame: screenFrame)
        
        switch landing {
        case .ground:
            physics.setWalkingSurface(.ground)
            if isClick {
                onClick?()
            } else {
                state.behaviorState = .idle
                onBehaviorStateChanged?(.idle)
            }
            
        case .windowTop(let windowID, let adjustedY, let bounds):
            physics.setWalkingSurface(.windowTop(
                windowID: windowID,
                minX: bounds.minX,
                maxX: bounds.maxX
            ))
            applyPosition(NSPoint(x: panel.frame.origin.x, y: adjustedY))
            if isClick {
                onClick?()
            } else {
                state.behaviorState = .idle
                onBehaviorStateChanged?(.idle)
            }
            
        case .windowSide(let windowID, let side, let edgeX, _):
            // 拖拽释放在窗口侧边 → cling (如果不是点击)
            if isClick {
                // 如果是点击且在窗口边缘，触发点击
                physics.setClingingOnWindow(windowID)
                state.clingSide = side
                onClick?()
            } else {
                let petX = side == .left ? edgeX - panel.frame.width : edgeX
                applyPosition(NSPoint(x: petX, y: panel.frame.origin.y))
                physics.setClingingOnWindow(windowID)
                state.clingSide = side
                onClingStateChanged?(true, side, edgeX)
            }
            
        case .midAir:
            if isClick {
                onClick?() // 点击依然可以响应，但会继续下落
            }
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
        
        while currentY > groundY {
            velocity += 0.3  // 重力加速
            currentY -= velocity
            
            let petMidX = panel.frame.origin.x + panel.frame.width / 2
            
            // 检查是否碰到可见窗口顶部（被遮挡的后台窗口会被跳过）
            if let landing = physics.detectFallLanding(petMidX: petMidX, currentY: currentY) {
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
            
            // 检查是否经过窗口侧边（40% 概率 cling）
            if Double.random(in: 0...1) < 0.4 {
                if let cling = physics.detectFallCling(
                    petMidX: petMidX,
                    currentY: currentY,
                    petWidth: panel.frame.width
                ) {
                    let petX = cling.side == .left
                        ? cling.edgeX - panel.frame.width
                        : cling.edgeX
                    applyPosition(NSPoint(x: petX, y: currentY))
                    physics.setClingingOnWindow(cling.windowID)
                    state.clingSide = cling.side
                    onClingStateChanged?(true, cling.side, cling.edgeX)
                    return
                }
            }
            
            applyPosition(NSPoint(x: panel.frame.origin.x, y: max(currentY, groundY)))
            try? await Task.sleep(for: .milliseconds(16))
        }
        
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
        // 降频点击穿透检测（每 4 帧一次，避免每帧 cacheDisplay）
        clickThroughCounter += 1
        if clickThroughCounter >= 4 {
            clickThroughCounter = 0
            updateClickThrough()
        }
        
        // sit 稳定性检测
        if state.behaviorState == .sit {
            physics.checkSitStability(panelFrame: panel.frame)
            if let windowID = physics.sittingOnWindowID,
               let top = WindowDetector.getWindowTop(windowID: windowID) {
                if abs(panel.frame.origin.y - top) > 5 {
                    applyPosition(NSPoint(x: panel.frame.origin.x, y: top))
                }
            }
            return
        }
        
        // cling 稳定性检测
        if state.behaviorState == .cling {
            physics.checkClingStability(panelFrame: panel.frame)
            // 窗口移动时跟随
            if let windowID = physics.clingingOnWindowID,
               let bounds = WindowDetector.getWindowBounds(windowID: windowID) {
                let side = state.clingSide
                let targetX = side == .left
                    ? bounds.minX - panel.frame.width
                    : bounds.maxX
                if abs(panel.frame.origin.x - targetX) > 3 {
                    applyPosition(NSPoint(x: targetX, y: panel.frame.origin.y))
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
    
    // MARK: - Cling 结束动作
    
    /// cling 结束后爬到窗口顶部
    func climbToClungWindowTop() {
        guard let windowID = physics.clingingOnWindowID,
              let bounds = WindowDetector.getWindowBounds(windowID: windowID) else {
            // 窗口已消失，直接下落
            triggerFall()
            return
        }
        
        let topY = bounds.maxY
        let centerX = bounds.midX - panel.frame.width / 2
        applyPosition(NSPoint(x: centerX, y: topY))
        physics.setWalkingSurface(.windowTop(
            windowID: windowID,
            minX: bounds.minX,
            maxX: bounds.maxX
        ))
        physics.setClingingOnWindow(nil)
        state.clingSide = nil
    }
    
    /// cling 结束后松手下落
    func performClingFall() {
        physics.setClingingOnWindow(nil)
        state.clingSide = nil
        triggerFall()
    }
    
    // MARK: - 位置工具
    
    /// 将窗口移动到指定位置并同步状态
    private func applyPosition(_ origin: NSPoint) {
        panel.setFrameOrigin(origin)
        state.position = CGPoint(x: origin.x, y: origin.y)
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
