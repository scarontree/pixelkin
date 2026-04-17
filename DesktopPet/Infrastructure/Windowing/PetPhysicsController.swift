import AppKit

/// 宠物物理控制器 — 管理移动、下落、窗口边缘检测
/// 从 PetWindowController 拆出，专注物理与空间逻辑
@MainActor
final class PetPhysicsController {
    
    private let state: PetRuntimeState
    
    /// 宠物当前行走的表面
    enum WalkingSurface {
        case ground
        case windowTop(windowID: CGWindowID, minX: CGFloat, maxX: CGFloat)
    }
    private(set) var walkingSurface: WalkingSurface = .ground
    
    /// sit 状态下坐着的窗口 ID
    private(set) var sittingOnWindowID: CGWindowID?
    
    /// 窗口边缘检测计数器（降频扫描）
    private var edgeCheckCounter: Int = 0
    
    /// 宠物窗口编号（用于排除自身）
    var panelWindowNumber: Int = 0
    
    // MARK: - 回调
    
    /// 到达边界
    var onReachBoundary: ((FacingDirection) -> Void)?
    /// 状态变化
    var onBehaviorStateChanged: ((PetBehaviorState) -> Void)?
    /// sit 状态变化
    var onSitStateChanged: ((Bool, CGFloat?) -> Void)?
    /// 请求执行下落动画
    var onFallRequested: (() -> Void)?
    
    init(state: PetRuntimeState) {
        self.state = state
    }
    
    // MARK: - 表面管理
    
    func setWalkingSurface(_ surface: WalkingSurface) {
        walkingSurface = surface
    }
    
    func setSittingOnWindow(_ windowID: CGWindowID?) {
        sittingOnWindowID = windowID
    }
    
    // MARK: - Walk 逻辑（每帧调用）
    
    /// 执行 walk 移动，返回新的窗口原点（nil = 不移动或已触发状态切换）
    func tickWalk(panelFrame: NSRect, screenFrame: NSRect) -> NSPoint? {
        guard state.behaviorState == .walk else { return nil }
        
        let speed: CGFloat = state.facingDirection == .right ? 0.5 : -0.5
        var origin = panelFrame.origin
        origin.x += speed
        
        switch walkingSurface {
        case .ground:
            // 在地面行走 — 边界是屏幕边缘
            if origin.x <= screenFrame.minX - 50 {
                origin.x = screenFrame.minX - 50
                onReachBoundary?(.right)
            } else if origin.x + panelFrame.width - 50 >= screenFrame.maxX {
                origin.x = screenFrame.maxX - panelFrame.width + 50
                onReachBoundary?(.left)
            }
            
        case .windowTop(let windowID, _, _):
            // 在窗口顶部行走
            if let currentTop = WindowDetector.getWindowTop(windowID: windowID) {
                // 窗口移动了 → 跟着调整 Y
                if abs(origin.y - currentTop) > 5 {
                    origin.y = currentTop
                }
                // 边缘检测
                if let bounds = WindowDetector.getWindowBounds(windowID: windowID) {
                    let edgeMargin: CGFloat = 10
                    let petCenterX = origin.x + panelFrame.width / 2
                    
                    if petCenterX <= bounds.minX + edgeMargin {
                        if Bool.random() {
                            onReachBoundary?(.right)
                        } else {
                            walkingSurface = .ground
                            onBehaviorStateChanged?(.fall)
                            onFallRequested?()
                            return nil
                        }
                    } else if petCenterX >= bounds.maxX - edgeMargin {
                        if Bool.random() {
                            onReachBoundary?(.left)
                        } else {
                            walkingSurface = .ground
                            onBehaviorStateChanged?(.fall)
                            onFallRequested?()
                            return nil
                        }
                    }
                }
            } else {
                // 窗口消失了 → 下落
                walkingSurface = .ground
                onBehaviorStateChanged?(.fall)
                onFallRequested?()
                return nil
            }
        }
        
        return origin
    }
    
    // MARK: - 窗口边缘检测（Sit）
    
    /// walk 中检测脚下是否有窗口边缘（每 ~0.5s 执行一次）
    func checkForWindowEdge(panelFrame: NSRect) {
        edgeCheckCounter += 1
        guard edgeCheckCounter >= 30 else { return }
        edgeCheckCounter = 0
        
        guard state.behaviorState == .walk else { return }
        
        let petBottomCenter = NSPoint(x: panelFrame.midX, y: panelFrame.origin.y)
        
        if let (windowTop, windowID) = WindowDetector.findWindowEdgeBelow(
            point: petBottomCenter,
            excludeWindowNumber: panelWindowNumber
        ) {
            // 宠物底部接近窗口顶边（±10pt）→ 概率坐下
            if abs(panelFrame.origin.y - windowTop) < 10 {
                if Double.random(in: 0...1) < 0.4 {
                    sittingOnWindowID = windowID
                    onSitStateChanged?(true, windowTop)
                }
            }
        }
    }
    
    /// 检测 sit 状态下底下的窗口是否还在
    func checkSitStability(panelFrame: NSRect) {
        guard state.behaviorState == .sit, let windowID = sittingOnWindowID else { return }
        
        edgeCheckCounter += 1
        guard edgeCheckCounter >= 15 else { return }
        edgeCheckCounter = 0
        
        if let currentTop = WindowDetector.getWindowTop(windowID: windowID) {
            // 窗口移动了 → 通知跟随
            if abs(panelFrame.origin.y - currentTop) > 5 {
                onSitStateChanged?(true, currentTop)
            }
        } else {
            // 窗口关闭了 → 下落
            sittingOnWindowID = nil
            onSitStateChanged?(false, nil)
            onFallRequested?()
        }
    }
    
    // MARK: - 着陆检测
    
    /// 检测拖拽释放后的着陆点 — 返回着陆类型
    enum LandingResult {
        case ground
        case windowTop(windowID: CGWindowID, adjustedY: CGFloat, bounds: NSRect)
        case midAir
    }
    
    func detectLanding(panelFrame: NSRect, screenFrame: NSRect) -> LandingResult {
        let isOnGround = panelFrame.origin.y <= screenFrame.minY + 5
        
        if isOnGround {
            return .ground
        }
        
        let petMidX = panelFrame.midX
        if let (windowTop, windowID) = WindowDetector.findWindowEdgeBelow(
            point: NSPoint(x: petMidX, y: panelFrame.origin.y),
            excludeWindowNumber: panelWindowNumber
        ) {
            if let bounds = WindowDetector.getWindowBounds(windowID: windowID) {
                return .windowTop(windowID: windowID, adjustedY: windowTop, bounds: bounds)
            }
        }
        
        return .midAir
    }
    
    /// 下落过程中检测是否碰到窗口顶部
    /// 专用于下落着陆 — 只在宠物确实"穿过"窗口顶边时才触发，避免提前吸附
    func detectFallLanding(petMidX: CGFloat, currentY: CGFloat) -> (windowTop: CGFloat, windowID: CGWindowID, bounds: NSRect)? {
        if let result = WindowDetector.findWindowTopBelow(
            x: petMidX,
            y: currentY,
            excludeWindowNumber: panelWindowNumber
        ) {
            if let bounds = WindowDetector.getWindowBounds(windowID: result.windowID) {
                return (result.windowTop, result.windowID, bounds)
            }
        }
        return nil
    }
}
