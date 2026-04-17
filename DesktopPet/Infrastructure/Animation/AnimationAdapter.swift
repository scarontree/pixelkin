import AppKit

/// 动画适配器协议 — 所有动画引擎 MUST 实现
@MainActor
protocol AnimationAdapter: AnyObject {
    func play(_ state: PetBehaviorState)
    func stop()
    func setDirection(_ direction: FacingDirection)
    func attach(to container: NSView)
    func detach()
}
