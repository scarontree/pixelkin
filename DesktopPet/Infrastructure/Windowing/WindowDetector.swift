import AppKit

/// 窗口探测工具 — 封装 CGWindowList API，检测屏幕上的窗口位置
/// 用于 sit/walk-on-window 等行为的窗口边缘发现
///
/// 关键设计：CGWindowListCopyWindowInfo 返回窗口按 **前到后**（z-order）排列。
/// 所有检测方法会追踪"已被前方窗口覆盖的区域"，被遮挡的后台窗口不会被选为着陆面。
///
/// 性能优化：同一物理帧内多次调用会复用缓存的窗口列表（50ms TTL）。
@MainActor
enum WindowDetector {
    
    // MARK: - 窗口列表缓存（同一帧内复用）
    
    private static var cachedWindowList: [[String: Any]]?
    private static var cacheTimestamp: Date = .distantPast
    private static let cacheTTL: TimeInterval = 0.05  // 50ms ≈ 3 帧 @60fps
    
    /// 获取当前屏幕上的窗口列表（带缓存）
    private static func getOnScreenWindowList() -> [[String: Any]]? {
        let now = Date()
        if let cached = cachedWindowList,
           now.timeIntervalSince(cacheTimestamp) < cacheTTL {
            return cached
        }
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]]
        cachedWindowList = list
        cacheTimestamp = now
        return list
    }
    
    // MARK: - 窗口信息解析
    
    /// 从 CGWindowList 条目中提取窗口信息（CG→NS 坐标转换）
    private struct WindowInfo {
        let windowID: CGWindowID
        let nsTop: CGFloat      // NS 坐标系中窗口顶边 Y
        let nsBottom: CGFloat   // NS 坐标系中窗口底边 Y
        let nsRect: NSRect      // NS 坐标系中完整矩形
    }
    
    /// 解析一个 CGWindowList 条目，返回 WindowInfo（nil = 不符合条件，跳过）
    private static func parseWindowInfo(
        _ info: [String: Any],
        excludeID: CGWindowID,
        screenHeight: CGFloat
    ) -> WindowInfo? {
        guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
              windowID != excludeID,
              let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
              let cgX = boundsDict["X"],
              let cgY = boundsDict["Y"],
              let cgW = boundsDict["Width"],
              let cgH = boundsDict["Height"],
              let layer = info[kCGWindowLayer as String] as? Int,
              layer == 0,                   // 只检测普通窗口层（排除菜单栏、Dock 等）
              cgW > 1, cgH > 1             // 排除零尺寸窗口
        else { return nil }
        
        let nsTop = screenHeight - cgY
        let nsBottom = screenHeight - cgY - cgH
        let nsRect = NSRect(x: cgX, y: nsBottom, width: cgW, height: cgH)
        return WindowInfo(windowID: windowID, nsTop: nsTop, nsBottom: nsBottom, nsRect: nsRect)
    }
    
    /// 检查指定 Y 坐标是否被"已覆盖区间"遮挡
    /// coveredIntervals: 前方窗口在该 X 位置上覆盖的 Y 区间列表
    private static func isOccluded(y: CGFloat, by coveredIntervals: [(bottom: CGFloat, top: CGFloat)]) -> Bool {
        for interval in coveredIntervals {
            if y >= interval.bottom && y <= interval.top {
                return true
            }
        }
        return false
    }
    
    // MARK: - Sit / 拖拽释放 用的边缘检测
    
    /// 查找指定点附近的 **可见** 窗口顶边（用于 sit 检测和拖拽释放着陆）
    /// - Parameters:
    ///   - point: NS 坐标系中的检测点
    ///   - excludeWindowNumber: 排除的窗口编号（通常是宠物自身窗口）
    /// - Returns: 窗口顶边 Y 坐标 + 窗口 ID（仅返回视觉上可见、未被遮挡的窗口）
    static func findWindowEdgeBelow(
        point: NSPoint,
        excludeWindowNumber: Int
    ) -> (windowTop: CGFloat, windowID: CGWindowID)? {
        guard let windowList = getOnScreenWindowList() else { return nil }
        
        let excludeID = CGWindowID(excludeWindowNumber)
        let screenHeight = NSScreen.main?.frame.height ?? 0
        
        // 追踪前方窗口在 point.x 位置上覆盖的 Y 区间
        var coveredIntervals: [(bottom: CGFloat, top: CGFloat)] = []
        var bestMatch: (windowTop: CGFloat, windowID: CGWindowID)?
        var bestDistance: CGFloat = .infinity
        
        for info in windowList {
            guard let w = parseWindowInfo(info, excludeID: excludeID, screenHeight: screenHeight) else { continue }
            
            // 检测点必须在窗口水平范围内
            guard point.x >= w.nsRect.minX && point.x <= w.nsRect.maxX else { continue }
            
            // 检查窗口顶边是否被前方窗口遮挡
            let topIsExposed = !isOccluded(y: w.nsTop, by: coveredIntervals)
            
            // 无论是否遮挡，该窗口都会覆盖一段区间（阻挡后面的窗口）
            coveredIntervals.append((bottom: w.nsBottom, top: w.nsTop))
            
            guard topIsExposed else { continue }
            
            // 检测点在窗口顶边附近（上方 10pt ~ 下方 20pt）
            let distance = point.y - w.nsTop
            if distance >= -10 && distance < 20 && abs(distance) < bestDistance {
                bestDistance = abs(distance)
                bestMatch = (w.nsTop, w.windowID)
            }
        }
        
        return bestMatch
    }
    
    // MARK: - 下落着陆检测
    
    /// 下落着陆专用 — 查找 x 正下方、且顶边 ≤ y 的最高 **可见** 窗口
    ///
    /// 与 findWindowEdgeBelow 不同：
    /// - 只在宠物真正到达或穿过窗口顶边时才匹配（避免提前"吸附"）
    /// - 排除被前方窗口遮挡的后台窗口（避免落在看不见的窗口上）
    static func findWindowTopBelow(
        x: CGFloat,
        y: CGFloat,
        excludeWindowNumber: Int
    ) -> (windowTop: CGFloat, windowID: CGWindowID)? {
        guard let windowList = getOnScreenWindowList() else { return nil }
        
        let excludeID = CGWindowID(excludeWindowNumber)
        let screenHeight = NSScreen.main?.frame.height ?? 0
        
        // 追踪前方窗口在 x 位置上覆盖的 Y 区间
        var coveredIntervals: [(bottom: CGFloat, top: CGFloat)] = []
        var bestMatch: (windowTop: CGFloat, windowID: CGWindowID)?
        
        for info in windowList {
            guard let w = parseWindowInfo(info, excludeID: excludeID, screenHeight: screenHeight) else { continue }
            
            // 宠物水平位置必须在窗口范围内
            guard x >= w.nsRect.minX && x <= w.nsRect.maxX else { continue }
            
            // 检查窗口顶边是否被前方窗口遮挡
            let topIsExposed = !isOccluded(y: w.nsTop, by: coveredIntervals)
            
            // 无论是否遮挡，该窗口都会覆盖一段区间
            coveredIntervals.append((bottom: w.nsBottom, top: w.nsTop))
            
            guard topIsExposed else { continue }
            
            // 窗口顶边必须 ≤ 宠物当前 Y（宠物已经到达或穿过）
            guard w.nsTop <= y + 2 else { continue }
            
            // 选离宠物最近的（最高的）可见窗口顶边
            if bestMatch == nil || w.nsTop > bestMatch!.windowTop {
                bestMatch = (w.nsTop, w.windowID)
            }
        }
        
        return bestMatch
    }
    
    // MARK: - 单窗口查询
    
    /// 获取指定窗口的顶边 Y 坐标
    static func getWindowTop(windowID: CGWindowID) -> CGFloat? {
        guard let bounds = getWindowBounds(windowID: windowID) else { return nil }
        return bounds.maxY
    }
    
    /// 获取指定窗口的 NS 坐标矩形
    static func getWindowBounds(windowID: CGWindowID) -> NSRect? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            windowID
        ) as? [[String: Any]],
              let info = windowList.first,
              let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
              let cgX = boundsDict["X"],
              let cgY = boundsDict["Y"],
              let cgW = boundsDict["Width"],
              let cgH = boundsDict["Height"] else { return nil }
        
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let nsY = screenHeight - cgY - cgH
        return NSRect(x: cgX, y: nsY, width: cgW, height: cgH)
    }
    
    // MARK: - Cling 侧边检测
    
    /// 下落过程中检测是否经过窗口侧边（用于 cling 抓住）
    ///
    /// 检测逻辑：宠物中心 X 距离窗口左/右边缘 ≤ sideMargin，且宠物 Y 在窗口垂直范围内。
    /// 同样排除被前方窗口遮挡的边缘。
    static func findWindowSideDuringFall(
        x: CGFloat,
        y: CGFloat,
        petWidth: CGFloat,
        excludeWindowNumber: Int
    ) -> (side: FacingDirection, windowID: CGWindowID, edgeX: CGFloat, bounds: NSRect)? {
        guard let windowList = getOnScreenWindowList() else { return nil }
        
        let excludeID = CGWindowID(excludeWindowNumber)
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let sideMargin: CGFloat = 25  // 距离窗口边缘的检测范围
        
        for info in windowList {
            guard let w = parseWindowInfo(info, excludeID: excludeID, screenHeight: screenHeight) else { continue }
            
            // 宠物 Y 必须在窗口垂直范围内（上方 5pt 到底部）
            guard y >= w.nsBottom && y <= w.nsTop + 5 else { continue }
            
            // 窗口高度太小的跳过（< 80pt）
            guard w.nsRect.height >= 80 else { continue }
            
            // 检查左侧：宠物在窗口左边缘附近
            let distToLeft = abs(x - w.nsRect.minX)
            if distToLeft <= sideMargin && x <= w.nsRect.minX {
                return (.left, w.windowID, w.nsRect.minX, w.nsRect)
            }
            
            // 检查右侧：宠物在窗口右边缘附近
            let distToRight = abs(x - w.nsRect.maxX)
            if distToRight <= sideMargin && x >= w.nsRect.maxX {
                return (.right, w.windowID, w.nsRect.maxX, w.nsRect)
            }
        }
        
        return nil
    }
}
