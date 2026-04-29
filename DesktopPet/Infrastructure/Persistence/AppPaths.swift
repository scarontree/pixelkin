import Foundation

/// 应用数据目录统一管理
/// 所有 Service 通过此枚举获取路径，NEVER 在代码中硬编码路径
enum AppPaths {
    /// ~/Library/Application Support/DesktopPet/
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("DesktopPet")
    }
    
    /// 用户皮肤目录（唯一真数据源）
    static var skinsDir: URL {
        let preferred = appSupport.appendingPathComponent("Skins")
        let legacy = appSupport.appendingPathComponent("skins")
        migrateDirectoryIfNeeded(from: legacy, to: preferred)
        return preferred
    }
    
    /// Persona 角色配置 (V2.0)
    static var personasDir: URL { appSupport.appendingPathComponent("personas") }
    
    /// Persona 角色配置数据文件
    static var personasFile: URL { appSupport.appendingPathComponent("personas.json") }
    
    /// 聊天历史 (V2.0)
    static var chatDir: URL { appSupport.appendingPathComponent("chat") }
    
    /// 记忆 (V2.5)
    static var memoryDir: URL { appSupport.appendingPathComponent("memory") }
    
    /// 全局配置文件
    static var configFile: URL { appSupport.appendingPathComponent("config.json") }
    
    /// 情境气泡规则文件
    static var bubbleRulesFile: URL { appSupport.appendingPathComponent("bubble_rules.json") }
    
    /// 确保目录存在
    static func ensureDirectoryExists(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func migrateDirectoryIfNeeded(from legacy: URL, to preferred: URL) {
        let fm = FileManager.default
        guard legacy.path != preferred.path else { return }
        guard fm.fileExists(atPath: legacy.path) else { return }
        guard !fm.fileExists(atPath: preferred.path) else { return }
        try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try? fm.moveItem(at: legacy, to: preferred)
    }
}
