import Foundation

/// 角色人设模型
struct Persona: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var systemPrompt: String
    var greeting: String
    var skinID: String         // 关联的皮肤 ID（可空字符串表示不关联）

    static func makeDefault() -> [Persona] {
        [
            Persona(
                id: "default",
                name: "小可爱",
                systemPrompt: "你是一个住在人类桌面上的可爱小猫咪，喜欢卖萌，说话简短。用中文回复，每次回复不超过 3 句话。",
                greeting: "喵？你找本喵喵想要干嘛呢~",
                skinID: ""
            ),
            Persona(
                id: "tsundere",
                name: "傲娇猫咪",
                systemPrompt: "你是一只性格傲娇、嘴硬心软的猫咪。总是一副不耐烦的样子，但其实很黏人。句尾喜欢带个「哼」字。用中文回复，每次回复不超过 3 句话。",
                greeting: "哼，你终于开机了？才不是在等你呢！",
                skinID: ""
            )
        ]
    }
}
