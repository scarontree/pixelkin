import Foundation

struct AppConfig: Codable, Equatable {
    var llm: LLMSettings

    static let `default` = AppConfig(llm: .default)
}

struct LLMSettings: Codable, Equatable {
    var presets: [LLMPreset]
    var activePresetID: String?

    static let `default` = LLMSettings(presets: [], activePresetID: nil)
}

struct LLMPreset: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var provider: LLMProvider
    var baseURL: String
    var model: String
    var apiKey: String
    var toolCallingEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case provider
        case baseURL
        case model
        case apiKey
        case toolCallingEnabled
    }

    init(
        id: String,
        name: String,
        provider: LLMProvider,
        baseURL: String,
        model: String,
        apiKey: String,
        toolCallingEnabled: Bool
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.toolCallingEnabled = toolCallingEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        provider = try container.decode(LLMProvider.self, forKey: .provider)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        model = try container.decode(String.self, forKey: .model)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        toolCallingEnabled = try container.decodeIfPresent(Bool.self, forKey: .toolCallingEnabled) ?? true
    }

    static func makeDefault(named name: String = "新预设") -> LLMPreset {
        let provider: LLMProvider = .openAICompatible
        return LLMPreset(
            id: UUID().uuidString,
            name: name,
            provider: provider,
            baseURL: provider.defaultBaseURL,
            model: "",
            apiKey: "",
            toolCallingEnabled: true
        )
    }
}

enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case openAI
    case openAICompatible
    case anthropic
    case gemini

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .openAICompatible:
            return "OpenAI 兼容"
        case .anthropic:
            return "Anthropic"
        case .gemini:
            return "Gemini"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI:
            return "https://api.openai.com/v1"
        case .openAICompatible:
            return "https://api.openai.com/v1"
        case .anthropic:
            return "https://api.anthropic.com"
        case .gemini:
            return "https://generativelanguage.googleapis.com"
        }
    }
}
