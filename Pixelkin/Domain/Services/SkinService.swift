import Foundation
import AppKit

/// 皮肤发现、加载、导入与引擎生命周期管理
/// 统一入口：面板和运行时都通过 SkinService 访问皮肤
@MainActor
final class SkinService {
    
    // MARK: - 皮肤发现（扫描文件系统）
    
    /// 扫描所有可用皮肤（用户目录 + Bundle 内置），按分组返回
    static func discoverAllSkins() -> [String: [SkinManifest]] {
        let allSkins = discoverUserSkins()
        return Dictionary(grouping: allSkins, by: { $0.group ?? "默认" })
    }
    
    /// 扫描所有可用皮肤，平铺返回
    static func discoverAllSkinsFlat() -> [SkinManifest] {
        return discoverUserSkins()
    }
    
    /// 扫描用户数据目录的皮肤
    private static func discoverUserSkins() -> [SkinManifest] {
        let skinsDir = AppPaths.skinsDir
        let fm = FileManager.default
        
        guard let entries = try? fm.contentsOfDirectory(at: skinsDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        
        return entries.compactMap { dir -> SkinManifest? in
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { return nil }
            
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestURL.path),
                  var manifest = loadManifest(from: manifestURL) else {
                return nil
            }
            
            // 用文件夹名作为 ID（覆盖 manifest 中可能不一致的 id）
            manifest.id = dir.lastPathComponent
            manifest.directoryURL = dir
            manifest.isBuiltIn = false
            return manifest
        }
    }
    
    // MARK: - 单皮肤定位与加载
    
    /// 定位皮肤目录：仅认用户数据目录
    static func locateSkin(name: String) -> (manifestURL: URL, skinDirectory: URL)? {
        let fm = FileManager.default

        let skinDir = AppPaths.skinsDir.appendingPathComponent(name)
        let manifestURL = skinDir.appendingPathComponent("manifest.json")
        if fm.fileExists(atPath: manifestURL.path) {
            return (manifestURL, skinDir)
        }

        return nil
    }
    
    /// 加载皮肤的 manifest
    static func loadManifest(from url: URL) -> SkinManifest? {
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(SkinManifest.self, from: data) else {
            print("[SkinService] Failed to decode manifest at \(url)")
            return nil
        }
        return manifest
    }
    
    // MARK: - 引擎切换
    
    /// 完整的皮肤切换流程：定位 → 加载 → 销毁旧引擎 → 创建新引擎
    static func switchSkin(
        name: String,
        oldAdapter: AnimationAdapter?
    ) -> (adapter: AnimationAdapter, manifest: SkinManifest)? {
        guard let (manifestURL, skinDir) = locateSkin(name: name) else {
            print("[SkinService] Skin not found: \(name)")
            return nil
        }
        
        guard var manifest = loadManifest(from: manifestURL) else {
            return nil
        }
        
        manifest.directoryURL = skinDir
        
        // 销毁旧引擎
        oldAdapter?.stop()
        oldAdapter?.detach()
        
        // 通过工厂创建新引擎
        let newAdapter = AdapterFactory.create(manifest: manifest, skinDirectory: skinDir)
        
        return (newAdapter, manifest)
    }
    
    // MARK: - 皮肤导入
    
    /// 从外部文件夹导入皮肤到用户数据目录
    static func importSkin(
        from sourceURL: URL,
        skinID: String,
        displayName: String,
        engineType: String,
        group: String?,
        tag: String?
    ) {
        let fm = FileManager.default
        let destFolder = AppPaths.skinsDir.appendingPathComponent(skinID)
        AppPaths.ensureDirectoryExists(destFolder)
        
        // 拷贝资源文件
        if sourceURL.startAccessingSecurityScopedResource() {
            defer { sourceURL.stopAccessingSecurityScopedResource() }
            if let contents = try? fm.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil) {
                for item in contents {
                    let destItem = destFolder.appendingPathComponent(item.lastPathComponent)
                    if fm.fileExists(atPath: destItem.path) {
                        try? fm.removeItem(at: destItem)
                    }
                    try? fm.copyItem(at: item, to: destItem)
                }
            }
        }
        
        // 如果没有 manifest.json，自动生成
        let manifestURL = destFolder.appendingPathComponent("manifest.json")
        if !fm.fileExists(atPath: manifestURL.path) {
            let manifest = generateDefaultManifest(
                id: skinID,
                name: displayName,
                type: engineType.lowercased(),
                group: group,
                tag: tag
            )
            if let data = try? JSONEncoder.prettyPrinting.encode(manifest) {
                try? data.write(to: manifestURL)
            }
        } else {
            // manifest 存在但可能缺少 group/tag，补上
            if var existing = loadManifest(from: manifestURL) {
                var needsUpdate = false
                if existing.group == nil, let g = group, !g.isEmpty {
                    existing.group = g
                    needsUpdate = true
                }
                if existing.tag == nil, let t = tag, !t.isEmpty {
                    existing.tag = t
                    needsUpdate = true
                }
                if needsUpdate, let data = try? JSONEncoder.prettyPrinting.encode(existing) {
                    try? data.write(to: manifestURL)
                }
            }
        }
        
        NSWorkspace.shared.open(destFolder)
    }

    static func updateSkinMetadata(
        for skin: SkinManifest,
        displayName: String,
        group: String?,
        tag: String?
    ) {
        guard let manifestURL = manifestURL(for: skin),
              var manifest = loadManifest(from: manifestURL) else { return }

        manifest.name = displayName
        manifest.group = group
        manifest.tag = tag

        guard let data = try? JSONEncoder.prettyPrinting.encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    static func manifestText(for skin: SkinManifest) -> String? {
        guard let fileURL = manifestURL(for: skin) else { return nil }
        return try? String(contentsOf: fileURL)
    }

    static func saveManifestText(_ text: String, for skin: SkinManifest) -> String? {
        guard let fileURL = manifestURL(for: skin) else {
            return "未找到 manifest.json。"
        }
        guard let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data, options: [])) != nil else {
            return "JSON 格式校验失败！请检查是否有语法错误（多余逗号或括号不匹配）。"
        }
        guard (try? JSONDecoder().decode(SkinManifest.self, from: data)) != nil else {
            return "manifest.json 与当前模型不兼容，请检查必填字段和字段类型。"
        }

        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "保存失败: \(error.localizedDescription)"
        }
    }

    static func phraseBookText(for skin: SkinManifest) -> String? {
        let fileURL = phrasesURL(for: skin)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            createDefaultPhraseBookIfNeeded(for: skin)
        }
        return try? String(contentsOf: fileURL)
    }

    static func loadPhraseBook(for skin: SkinManifest) -> PhraseBook {
        let fileURL = phrasesURL(for: skin)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            createDefaultPhraseBookIfNeeded(for: skin)
        }

        guard let data = try? Data(contentsOf: fileURL),
              let phraseBook = try? JSONDecoder().decode(PhraseBook.self, from: data) else {
            return defaultPhraseBook()
        }

        return phraseBook
    }

    static func savePhraseBookText(_ text: String, for skin: SkinManifest) -> String? {
        let fileURL = phrasesURL(for: skin)
        guard let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data, options: [])) != nil else {
            return "JSON 格式校验失败！请检查是否有语法错误（多余逗号或括号不匹配）。"
        }
        guard (try? JSONDecoder().decode(PhraseBook.self, from: data)) != nil else {
            return "phrases.json 结构无效，必须是 { \"phrases\": { ... } } 形式。"
        }

        do {
            try data.write(to: fileURL, options: .atomic)
            return nil
        } catch {
            return "保存失败: \(error.localizedDescription)"
        }
    }

    static func savePhraseBook(_ phraseBook: PhraseBook, for skin: SkinManifest) -> String? {
        guard let data = try? JSONEncoder.prettyPrinting.encode(phraseBook),
              let text = String(data: data, encoding: .utf8) else {
            return "当前语录内容无法保存。"
        }
        return savePhraseBookText(text, for: skin)
    }

    static func openSkinsDirectory() {
        AppPaths.ensureDirectoryExists(AppPaths.skinsDir)
        NSWorkspace.shared.open(AppPaths.skinsDir)
    }

    static func deleteImportedSkin(_ skin: SkinManifest) {
        guard let dir = skin.directoryURL else { return }
        try? FileManager.default.removeItem(at: dir)
    }
    
    // MARK: - Bubble Rule Set Management (已迁移到 BubbleRuleService)
    
    @available(*, deprecated, message: "使用 BubbleRuleService.load() 替代")
    static func loadBubbleRuleSet() -> BubbleRuleSet {
        BubbleRuleService.load()
    }
    
    @available(*, deprecated, message: "使用 BubbleRuleService.save() 替代")
    static func saveBubbleRuleSet(_ ruleSet: BubbleRuleSet) -> String? {
        BubbleRuleService.save(ruleSet)
    }
    
    /// 生成默认 manifest
    private static func generateDefaultManifest(
        id: String,
        name: String,
        type: String,
        group: String?,
        tag: String?
    ) -> SkinManifest {
        switch type {
        case "sprite":
            return SkinManifest(
                id: id, name: name, type: "sprite",
                frameSize: .init(width: 64, height: 64), scale: 3,
                states: [
                    "idle": .init(selection: .single, variants: [
                        .init(id: "idle_default", file: "idle.png", frames: 4, fps: 4, loop: true, weight: 1, conditions: nil, priority: nil)
                    ]),
                    "walk": .init(selection: .single, variants: [
                        .init(id: "walk_default", file: "walk.png", frames: 8, fps: 10, loop: true, weight: 1, conditions: nil, priority: nil)
                    ]),
                    "drag": .init(selection: .single, variants: [
                        .init(id: "drag_default", file: "drag.png", frames: 2, fps: 6, loop: true, weight: 1, conditions: nil, priority: nil)
                    ]),
                    "fall": .init(selection: .single, variants: [
                        .init(id: "fall_default", file: "fall.png", frames: 3, fps: 8, loop: false, weight: 1, conditions: nil, priority: nil)
                    ])
                ],
                file: nil, stateMachine: nil, canvasSize: nil,
                group: group, tag: tag, preview: nil
            )
        case "rive":
            return SkinManifest(
                id: id, name: name, type: "rive",
                frameSize: nil, scale: nil, states: nil,
                file: "pet.riv", stateMachine: "PetBehavior", canvasSize: 192,
                group: group, tag: tag, preview: nil
            )
        default:
            return SkinManifest(
                id: id, name: name, type: type,
                frameSize: nil, scale: nil, states: nil,
                file: nil, stateMachine: nil, canvasSize: nil,
                group: group, tag: tag, preview: nil
            )
        }
    }

    private static func manifestURL(for skin: SkinManifest) -> URL? {
        if let dir = skin.directoryURL {
            return dir.appendingPathComponent("manifest.json")
        }
        let projectPath = AppPaths.skinsDir.appendingPathComponent(skin.id).appendingPathComponent("manifest.json")
        return FileManager.default.fileExists(atPath: projectPath.path) ? projectPath : nil
    }

    private static func phrasesURL(for skin: SkinManifest) -> URL {
        if let dir = skin.directoryURL {
            return dir.appendingPathComponent("phrases.json")
        }
        return AppPaths.skinsDir.appendingPathComponent(skin.id).appendingPathComponent("phrases.json")
    }

    private static func createDefaultPhraseBookIfNeeded(for skin: SkinManifest) {
        let fileURL = phrasesURL(for: skin)
        let directory = fileURL.deletingLastPathComponent()
        AppPaths.ensureDirectoryExists(directory)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let template = defaultPhraseBook()
        guard let data = try? JSONEncoder.prettyPrinting.encode(template) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func defaultPhraseBook() -> PhraseBook {
        PhraseBook(phrases: [
            "default": ["今天也辛苦啦~"]
        ])
    }
}

// MARK: - JSONEncoder extension

private extension JSONEncoder {
    /// 共享 encoder 实例 — 所有调用在 @MainActor 上，线程安全
    static let prettyPrinting: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
