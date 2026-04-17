import Foundation
import SwiftUI

/// 宠物运行时状态聚合
@Observable
@MainActor
final class PetRuntimeState {
    var behaviorState: PetBehaviorState = .idle
    var facingDirection: FacingDirection = .right
    var position: CGPoint = .zero
    var currentSkinID: String = ""
    var isBubbleVisible: Bool = false
    var bubbleText: String = ""
    var isDragging: Bool = false
    
    /// 宠物渲染尺寸（由动画包决定）
    var petSize: CGSize = CGSize(width: 128, height: 128)
}
