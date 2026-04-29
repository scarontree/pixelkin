import CoreGraphics
import Foundation

/// 轻量配置持久化
/// 当前只负责运行时恢复所需的用户设置，不存放皮肤资源本体
@MainActor
enum SettingsStore {
    private static let defaults = UserDefaults.standard
    private static let settingsKey = "desktop_pet.settings"

    struct StoredSettings: Codable {
        var selectedSkinID: String
        var isPetVisible: Bool
        var globalTone: String

        static let `default` = StoredSettings(
            selectedSkinID: "",
            isPetVisible: true,
            globalTone: "skin"
        )

        init(
            selectedSkinID: String,
            isPetVisible: Bool,
            globalTone: String
        ) {
            self.selectedSkinID = selectedSkinID
            self.isPetVisible = isPetVisible
            self.globalTone = globalTone
        }

        private enum CodingKeys: String, CodingKey {
            case selectedSkinID
            case isPetVisible
            case globalTone
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            selectedSkinID = try container.decodeIfPresent(String.self, forKey: .selectedSkinID) ?? ""
            isPetVisible = try container.decodeIfPresent(Bool.self, forKey: .isPetVisible) ?? true
            globalTone = try container.decodeIfPresent(String.self, forKey: .globalTone) ?? "skin"
        }
    }

    static func load() -> StoredSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(StoredSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    static func save(_ settings: StoredSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
    }

    static func update(_ mutate: (inout StoredSettings) -> Void) {
        var settings = load()
        mutate(&settings)
        save(settings)
    }
}
