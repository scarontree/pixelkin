import SwiftUI

/// 宠物窗口根视图
/// 交互（拖拽、右键菜单）由 HitTestView 在 AppKit 层处理，
/// 这里只负责渲染布局
struct PetView: View {
    let state: PetRuntimeState
    let behaviorController: BehaviorController
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear // 占满 NSHostingView 提供的全部可用空间
            
            // 宠物渲染区域
            PetRenderView(state: state, adapterProvider: { behaviorController.adapter })
                .frame(width: state.petSize.width, height: state.petSize.height)
                .overlay(alignment: .bottom) {
                    // 对话气泡 — 锚定在宠物帧底部，往上偏移到角色头顶
                    if state.isBubbleVisible {
                        PetBubbleView(text: state.bubbleText)
                            .fixedSize()
                            .offset(y: -state.petSize.height * 0.38) // 从底部往上偏移约 38%
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: state.isBubbleVisible)
        }
        // 彻底撑满并确保对齐底部
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
    }
}
