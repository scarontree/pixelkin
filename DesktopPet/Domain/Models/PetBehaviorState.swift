import Foundation

/// 宠物行为状态
enum PetBehaviorState: String, Codable {
    case idle
    case walk
    case drag
    case fall
    case sleep  // 长时间无互动后打瞌睡
    case sit    // 坐在窗口边缘
}

/// 宠物朝向
enum FacingDirection: String, Codable {
    case left
    case right
}
