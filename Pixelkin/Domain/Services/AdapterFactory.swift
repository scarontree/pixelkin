import AppKit

/// 根据 SkinManifest 创建对应的 AnimationAdapter
/// 新增引擎只需在这里注册一个 case，业务层不用改
@MainActor
enum AdapterFactory {
    static func create(manifest: SkinManifest, skinDirectory: URL) -> AnimationAdapter {
        switch manifest.skinType {
        case .gif:     return GifAdapter(manifest: manifest, skinDirectory: skinDirectory)
        case .svg:     return SvgAdapter(manifest: manifest, skinDirectory: skinDirectory)
        // case .rive: return RiveAdapter(manifest: manifest, skinDirectory: skinDirectory)
        case .sprite, .rive, .unknown:
            return SpriteAdapter(manifest: manifest, skinDirectory: skinDirectory)
        }
    }
}
