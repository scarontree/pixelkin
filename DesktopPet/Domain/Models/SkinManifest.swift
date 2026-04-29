import Foundation

/// 动画包 manifest 模型，对应 Skins/{skinID}/manifest.json
/// 统一描述所有引擎类型（sprite / gif / svg / rive）
/// 状态配置采用“state -> variants[] + selection”模型
struct SkinManifest: Codable, Identifiable, Equatable {
    // MARK: - 基础标识
    
    var id: String    // 皮肤唯一标识（= 文件夹名）
    var name: String  // 显示名称
    var type: String  // "原始字符串，保留 JSON 兼容，业务逻辑用 skinType
    
    /// 类型安全的引擎类型枚举
    enum SkinType: String, Codable, CaseIterable {
        case sprite
        case gif
        case svg
        case rive
        case unknown
        
        var displayName: String {
            switch self {
            case .sprite: return "Sprite"
            case .gif: return "GIF"
            case .svg: return "SVG"
            case .rive: return "Rive"
            case .unknown: return "Unknown"
            }
        }
    }
    
    /// 类型安全的引擎类型（从原始字符串解析）
    var skinType: SkinType {
        SkinType(rawValue: type.lowercased()) ?? .unknown
    }
    
    // MARK: - 渲染尺寸（sprite / gif / svg 通用）
    
    var frameSize: FrameSize?
    var scale: Double?
    
    // MARK: - 状态动画定义（sprite / gif / svg 使用）
    
    var states: [String: StateConfig]?
    
    // MARK: - Rive 专用
    
    let file: String?
    let stateMachine: String?
    let canvasSize: Int?
    
    // MARK: - UI 元数据（直接存在 manifest.json 中）
    
    var group: String?    // 分组标签（"Beta Legacy"、"自定义" 等）
    var tag: String?      // 特征标签（"v2"、"WIP" 等）
    var preview: String?  // 预览图文件名
    
    // MARK: - 加载时注入（不序列化）
    
    /// 皮肤资源目录的绝对路径（运行时注入，不写入 JSON）
    var directoryURL: URL?
    /// 是否为内置只读皮肤
    var isBuiltIn: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case id, name, type
        case frameSize, scale
        case states
        case file, stateMachine, canvasSize
        case group, tag, preview
    }

    init(
        id: String,
        name: String,
        type: String,
        frameSize: FrameSize?,
        scale: Double?,
        states: [String: StateConfig]?,
        file: String?,
        stateMachine: String?,
        canvasSize: Int?,
        group: String?,
        tag: String?,
        preview: String?
    ) {
        self.id = id
        self.name = name
        self.type = type.lowercased()
        self.frameSize = frameSize
        self.scale = scale
        self.states = states
        self.file = file
        self.stateMachine = stateMachine
        self.canvasSize = canvasSize
        self.group = group
        self.tag = tag
        self.preview = preview
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        self.name = try container.decode(String.self, forKey: .name)
        self.type = (try container.decode(String.self, forKey: .type)).lowercased()
        self.frameSize = try container.decodeIfPresent(FrameSize.self, forKey: .frameSize)
        self.scale = try container.decodeIfPresent(Double.self, forKey: .scale)
        self.states = try container.decodeIfPresent([String: StateConfig].self, forKey: .states)
        self.file = try container.decodeIfPresent(String.self, forKey: .file)
        self.stateMachine = try container.decodeIfPresent(String.self, forKey: .stateMachine)
        self.canvasSize = try container.decodeIfPresent(Int.self, forKey: .canvasSize)
        self.group = try container.decodeIfPresent(String.self, forKey: .group)
        self.tag = try container.decodeIfPresent(String.self, forKey: .tag)
        self.preview = try container.decodeIfPresent(String.self, forKey: .preview)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type.lowercased(), forKey: .type)
        try container.encodeIfPresent(frameSize, forKey: .frameSize)
        try container.encodeIfPresent(scale, forKey: .scale)
        try container.encodeIfPresent(states, forKey: .states)
        try container.encodeIfPresent(file, forKey: .file)
        try container.encodeIfPresent(stateMachine, forKey: .stateMachine)
        try container.encodeIfPresent(canvasSize, forKey: .canvasSize)
        try container.encodeIfPresent(group, forKey: .group)
        try container.encodeIfPresent(tag, forKey: .tag)
        try container.encodeIfPresent(preview, forKey: .preview)
    }
    
    struct FrameSize: Codable, Equatable {
        var width: Double
        var height: Double
    }
    
    struct StateConfig: Codable, Equatable {
        var selection: SelectionStrategy
        var variants: [AnimationVariant]
    }

    enum SelectionStrategy: String, Codable, CaseIterable, Equatable {
        case single
        case random
        case weightedRandom
        case firstMatch
    }

    /// 单个动画变体
    struct AnimationVariant: Codable, Equatable, Identifiable {
        var id: String
        var file: String
        var frames: Int?     // sprite 必填，gif/svg 不需要
        var fps: Int?        // sprite 必填，gif 由文件自带延迟
        var loop: Bool?      // sprite 必填，gif 始终循环
        var weight: Int?
        var conditions: [String]?
        var priority: Int?
        var duration: Double? // 播放时长（覆盖默认调度）
        var cooldown: Double? // 冷却时间（秒）
    }

    struct AnimationContext: Equatable {
        var activeConditions: Set<String> = []
        var variantLastPlayedAt: [String: Date] = [:]
    }

    func resolveVariant(
        for state: String,
        context: AnimationContext = .init()
    ) -> AnimationVariant? {
        guard let config = states?[state], !config.variants.isEmpty else {
            return nil
        }

        let matched = config.variants
            .filter { variant in
                // 条件检查
                let required = Set(variant.conditions ?? [])
                guard required.isSubset(of: context.activeConditions) else { return false }
                
                // 冷却检查
                if let cooldown = variant.cooldown, cooldown > 0 {
                    if let lastPlayed = context.variantLastPlayedAt[variant.id] {
                        if Date().timeIntervalSince(lastPlayed) < cooldown {
                            return false
                        }
                    }
                }
                return true
            }
            .sorted { lhs, rhs in
                (lhs.priority ?? 0) > (rhs.priority ?? 0)
            }

        guard !matched.isEmpty else { return nil }

        switch config.selection {
        case .single:
            return matched.first
        case .firstMatch:
            return matched.first
        case .random:
            return matched.randomElement()
        case .weightedRandom:
            let weighted = matched.map { max($0.weight ?? 1, 1) }
            let total = weighted.reduce(0, +)
            guard total > 0 else { return matched.first }

            var cursor = Int.random(in: 0..<total)
            for (index, weight) in weighted.enumerated() {
                cursor -= weight
                if cursor < 0 {
                    return matched[index]
                }
            }
            return matched.last
        }
    }
}
