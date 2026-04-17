import AppKit

/// 窗口探测工具 — 封装 CGWindowList API，检测屏幕上的窗口位置
/// 用于 sit/walk-on-window 等行为的窗口边缘发现
@MainActor
enum WindowDetector {
    
    /// 查找指定点下方最近的窗口顶边
    /// - Parameters:
    ///   - point: NS 坐标系中的检测点
    ///   - excludeWindowNumber: 排除的窗口编号（通常是宠物自身窗口）
    /// - Returns: 窗口顶边 Y 坐标 + 窗口 ID
    static func findWindowEdgeBelow(
        point: NSPoint,
        excludeWindowNumber: Int
    ) -> (windowTop: CGFloat, windowID: CGWindowID)? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        
        let excludeID = CGWindowID(excludeWindowNumber)
        let screenHeight = NSScreen.main?.frame.height ?? 0
        
        var bestMatch: (windowTop: CGFloat, windowID: CGWindowID)?
        var bestDistance: CGFloat = .infinity
        
        for info in windowList {
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  windowID != excludeID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let cgX = boundsDict["X"],
                  let cgY = boundsDict["Y"],
                  let cgW = boundsDict["Width"],
                  let cgH = boundsDict["Height"],
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0  // 只检测普通窗口
            else { continue }
            
            // CG 坐标转 NS 坐标（y 翻转）
            let nsTop = screenHeight - cgY
            let nsBottom = screenHeight - cgY - cgH
            let nsRect = NSRect(x: cgX, y: nsBottom, width: cgW, height: cgH)
            
            // 检测点是否在窗口水平范围内
            guard point.x >= nsRect.minX && point.x <= nsRect.maxX else { continue }
            
            // 窗口顶边在检测点附近
            let distance = point.y - nsTop
            if distance >= -10 && distance < 20 && abs(distance) < bestDistance {
                bestDistance = abs(distance)
                bestMatch = (nsTop, windowID)
            }
        }
        
        return bestMatch
    }
    
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
    
    /// 下落着陆专用 — 查找 x 正下方、且顶边 ≤ y 的最高窗口
    /// 与 findWindowEdgeBelow 不同：只在宠物真正到达或穿过窗口顶边时才匹配，
    /// 避免宠物还在窗口上方就被提前"吸附"。
    static func findWindowTopBelow(
        x: CGFloat,
        y: CGFloat,
        excludeWindowNumber: Int
    ) -> (windowTop: CGFloat, windowID: CGWindowID)? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        
        let excludeID = CGWindowID(excludeWindowNumber)
        let screenHeight = NSScreen.main?.frame.height ?? 0
        
        var bestMatch: (windowTop: CGFloat, windowID: CGWindowID)?
        
        for info in windowList {
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  windowID != excludeID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let cgX = boundsDict["X"],
                  let cgY = boundsDict["Y"],
                  let cgW = boundsDict["Width"],
                  let cgH = boundsDict["Height"],
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0
            else { continue }
            
            let nsTop = screenHeight - cgY
            let nsRect = NSRect(x: cgX, y: screenHeight - cgY - cgH, width: cgW, height: cgH)
            
            // 宠物水平位置必须在窗口范围内
            guard x >= nsRect.minX && x <= nsRect.maxX else { continue }
            
            // 关键：窗口顶边必须 ≤ 宠物当前 Y（宠物已经到达或穿过）
            guard nsTop <= y + 2 else { continue }
            
            // 选离宠物最近的（最高的）窗口顶边
            if bestMatch == nil || nsTop > bestMatch!.windowTop {
                bestMatch = (nsTop, windowID)
            }
        }
        
        return bestMatch
    }
}
