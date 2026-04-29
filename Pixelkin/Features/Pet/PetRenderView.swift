import SwiftUI
import AppKit

/// 将 AppKit 原生 NSView（动画容器）桥接到 SwiftUI
struct AnimationContainerView: NSViewRepresentable {
    let state: PetRuntimeState
    let adapterProvider: () -> AnimationAdapter?
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        
        if let adapter = adapterProvider() {
            adapter.attach(to: view)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        let currentSkin = state.currentSkinID
        if context.coordinator.lastSkin != currentSkin {
            context.coordinator.lastSkin = currentSkin
            
            // 卸载老的视图
            nsView.subviews.forEach { $0.removeFromSuperview() }
            
            // 挂载新的引擎试图
            if let adapter = adapterProvider() {
                adapter.attach(to: nsView)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(lastSkin: state.currentSkinID) }
    
    class Coordinator {
        var lastSkin: String
        init(lastSkin: String) { self.lastSkin = lastSkin }
    }
}

/// 宠物动画渲染容器
struct PetRenderView: View {
    let state: PetRuntimeState
    let adapterProvider: () -> AnimationAdapter?
    
    @State private var trackingSkinID: String = ""
    
    var body: some View {
        AnimationContainerView(state: state, adapterProvider: adapterProvider)
            .animation(.easeInOut(duration: 0.2), value: state.behaviorState)
            .onChange(of: state.currentSkinID) { _, newValue in
                // 显式追踪 skinID 变化以触发 AnimationContainerView 更新
                trackingSkinID = newValue
            }
    }
}
