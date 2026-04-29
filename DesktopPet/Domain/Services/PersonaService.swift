import Foundation

/// 角色人设持久化服务
@MainActor
enum PersonaService {
    private static var fileURL: URL {
        AppPaths.personasFile
    }

    static func loadAll() -> [Persona] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            let defaults = Persona.makeDefault()
            saveAll(defaults)
            return defaults
        }
        do {
            let data = try Data(contentsOf: url)
            let personas = try JSONDecoder().decode([Persona].self, from: data)
            if personas.isEmpty {
                let defaults = Persona.makeDefault()
                saveAll(defaults)
                return defaults
            }
            return personas
        } catch {
            print("[PersonaService] 加载角色失败，使用默认: \(error.localizedDescription)")
            let defaults = Persona.makeDefault()
            saveAll(defaults)
            return defaults
        }
    }

    static func saveAll(_ personas: [Persona]) {
        AppPaths.ensureDirectoryExists(AppPaths.appSupport)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(personas)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[PersonaService] 保存角色失败: \(error.localizedDescription)")
        }
    }

    static func add(_ persona: Persona) {
        var list = loadAll()
        list.append(persona)
        saveAll(list)
    }

    static func update(_ persona: Persona) {
        var list = loadAll()
        if let index = list.firstIndex(where: { $0.id == persona.id }) {
            list[index] = persona
            saveAll(list)
        }
    }

    static func delete(id: String) {
        var list = loadAll()
        list.removeAll { $0.id == id }
        saveAll(list)
    }
}
