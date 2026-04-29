import Foundation

/// 气泡规则集持久化服务 — 管理 BubbleRuleSet 的加载与保存
/// 职责从 SkinService 中拆出，保持单一职责
@MainActor
enum BubbleRuleService {
    
    static func load() -> BubbleRuleSet {
        let fileURL = AppPaths.bubbleRulesFile
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                return try JSONDecoder().decode(BubbleRuleSet.self, from: data)
            } catch {
                print("[BubbleRuleService] 加载气泡规则失败，使用内置默认: \(error.localizedDescription)")
            }
        }
        return BubbleRuleSet.builtInDefault
    }
    
    @discardableResult
    static func save(_ ruleSet: BubbleRuleSet) -> String? {
        let fileURL = AppPaths.bubbleRulesFile
        AppPaths.ensureDirectoryExists(AppPaths.appSupport)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(ruleSet)
            try data.write(to: fileURL, options: .atomic)
            return nil
        } catch {
            let message = "保存气泡规则失败: \(error.localizedDescription)"
            print("[BubbleRuleService] \(message)")
            return message
        }
    }
}
