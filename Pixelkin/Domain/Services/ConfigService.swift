import Foundation

@MainActor
enum ConfigService {
    static func load() -> AppConfig {
        let fileURL = AppPaths.configFile
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .default
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            print("[ConfigService] 加载配置失败，使用默认值: \(error.localizedDescription)")
            return .default
        }
    }

    static func save(_ config: AppConfig) {
        AppPaths.ensureDirectoryExists(AppPaths.appSupport)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: AppPaths.configFile, options: .atomic)
        } catch {
            print("[ConfigService] 保存配置失败: \(error.localizedDescription)")
        }
    }
}
