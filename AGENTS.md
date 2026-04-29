# AGENTS.md — Pixelkin macOS Native

> AI coding agent 与开发者共用项目规范。
> 
> **⚠️ 本文件以实际代码为准**，定期同步。如与代码冲突，以代码为真。

## 项目概述

### 产品定位

macOS 原生桌面宠物应用。角色以 2D 动画形式常驻桌面（透明无边框窗口），具备自主行为、可扩展的多动画引擎系统、皮肤管理和控制面板。仅支持 macOS。

### 当前阶段（截至 2026-04-18）

已实现的核心能力：

- ✅ 常驻桌面的宠物运行时（透明窗口 + 状态机 + 拖拽 + 下落）
- ✅ 三引擎动画系统（Sprite Sheet / GIF / SVG），Rive 注册但未接入
- ✅ 皮肤导入、编辑、热切换的控制面板
- ✅ 点击穿透（V2 alpha-based 像素级检测，动态 `ignoresMouseEvents`）
- ✅ 菜单栏入口（MenuBarExtra）
- ✅ SkinManifest 支持 states → variants + selection 策略模型
- ✅ 多变体动画（idle 等状态可定义多个变体随机切换）
- ✅ 情境气泡系统（检测前台应用 + 规则匹配 + 角色语录本 + 漫画尾巴气泡）
- ✅ Sleep 行为（60s 无互动入睡 + 5min 自然醒 + 鼠标/拖拽唤醒）
- ✅ Sit 行为（窗口边缘检测 + 概率坐下 + 窗口跟随 + 窗口消失下落）
- ✅ Cling 行为（下落/窗口边缘挂住窗口侧边 + 窗口跟随 + 随机爬上/下落）
- ✅ 窗口上行走（walk/fall 可落在窗口顶部 + 在窗口上来回走 + 边缘下落）
- ✅ 物理控制器独立拆分（PetPhysicsController + WindowDetector）
- ✅ 控制面板设置页（气泡语气 / LLM 预设 / 开机自启）
- ✅ 基础聊天页（远程 LLM 调用 + Persona 开场白 + 宠物气泡联动）
- ✅ 基础角色页（Persona 本地持久化 + 关联皮肤）
- ✅ 高级皮肤文件编辑器（动画属性 + 语录本 + 气泡规则）

尚未实现 / 待完善：

- ⬚ 内置皮肤（Bundle 内 `Resources/Skins/` 目录无皮肤；皮肤仅来自用户数据目录）
- ⬚ 聊天历史 / 记忆 / Function Calling（当前仅有基础聊天与 Persona 配置）
- ⬚ Rive 引擎实际接入

## 技术栈（严格遵守）

| 层 | 技术 | 硬性要求 |
|---|---|---|
| 语言 | **Swift 5.9+** | MUST 使用现代 Swift 语法 |
| UI 框架 | **SwiftUI** | 业务界面 MUST 用 SwiftUI |
| 桌面窗口 | **AppKit** | 透明窗口、层级、命中测试 MUST 用 AppKit |
| 并发 | **Swift Concurrency** | `async/await`、`Task`、`@MainActor` |
| 状态管理 | **`@Observable`** (Observation framework) | NEVER 使用 `ObservableObject` + `@Published` |
| 持久化 | **Codable + JSON / UserDefaults** | NEVER 引入 SwiftData / Core Data |
| 动画引擎 | **Sprite Sheet** / **GIF** / **SVG (WebKit)** | 通过 `AnimationAdapter` protocol 统一访问 |
| 构建工具 | **XcodeGen** (`project.yml`) | 项目配置通过 `project.yml` 生成 |
| 最低系统 | **macOS 14.0+ (Sonoma)** | NEVER 降到 macOS 13 |
| 平台 | **macOS only** | NEVER 引入 iOS / visionOS target |
| 沙盒 | **非沙盒** | 开发阶段不启用 App Sandbox |

### 禁止引入的技术

- ❌ Objective-C（除非 Apple API 强制要求）
- ❌ `ObservableObject` / `@Published` / `@StateObject`（用 `@Observable` / `@State` 替代）
- ❌ Combine（用 Swift Concurrency 替代）
- ❌ SwiftData / Core Data
- ❌ 任何跨平台框架（Electron、Tauri、React Native 等）
- ❌ CocoaPods / Carthage（MUST 使用 Swift Package Manager）
- ❌ Storyboard / XIB

## 架构约束

### 核心分层

```
App 层           — 入口、AppDelegate、AppCoordinator（编排依赖注入）
Data 层          — 未来数据存储占位（Persona / Chat / Memory / Config）
Domain 层        — 模型、运行时控制器、服务接口（纯业务逻辑，不依赖 UI/AppKit）
Infrastructure 层 — 窗口桥接、动画引擎实现、文件存储（系统能力封装）
Features 层      — SwiftUI View（只消费状态，不包含业务逻辑和 I/O）
```

### App 生命周期

- MUST 使用 SwiftUI `@main App` + `@NSApplicationDelegateAdaptor`
- 宠物窗口 MUST 由 `AppDelegate.applicationDidFinishLaunching` 手动创建
- 控制面板窗口 MUST 用 SwiftUI `Window` 声明
- NEVER 把宠物窗口用 SwiftUI `Window` 声明
- 应用设置为 `LSUIElement = YES`（不在 Dock 显示图标，纯菜单栏应用）

### 双窗口模式

- 宠物窗口 MUST 保持极度轻量：只有动画渲染 + 气泡 + 交互
- 聊天、设置、皮肤管理等 MUST 放在独立的控制面板窗口
- 两个窗口是独立协作关系，NEVER 做成主从页面跳转

### 宠物窗口（PetPanel）

- MUST 使用 `NSPanel` 子类，NEVER 使用 `NSWindow`
- MUST 设置以下属性：

```swift
styleMask = [.borderless, .nonactivatingPanel]
isOpaque = false
backgroundColor = .clear
hasShadow = false
level = .floating
collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
isMovableByWindowBackground = false
ignoresMouseEvents = true  // 初始穿透，由 PetWindowController 动态控制
```

- 窗口内容 MUST 通过 `HitTestView`（`NSHostingView` 子类）嵌入 SwiftUI View

### 点击穿透（已实现 V2）

**目标行为**：宠物实体区域可交互，透明背景区域让点击事件到达底层应用。

**当前实现**：动态 `ignoresMouseEvents` + 全局/本地鼠标位置监听 + `HitTestView` alpha-based 像素检测。

1. `NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged])` 持续追踪光标
2. `NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved])` 补充本地事件
3. 光标进入窗口后，通过 `HitTestView.isScreenPointOpaque(_:)` 对当前像素做透明度采样
4. 采样命中宠物实体像素 → `panel.ignoresMouseEvents = false`
5. 采样到透明背景 → `panel.ignoresMouseEvents = true`
6. 拖拽过程中强制 `ignoresMouseEvents = false`

- NEVER 只靠 `hitTest` 返回 `nil` 当作穿透方案
- NEVER 把 `ignoresMouseEvents` 写死为 `true` 或 `false`

### 运行时内核（Pet Runtime Kernel）

皮肤加载、引擎创建/销毁、状态同步的当前结构：

```
SkinService          — 扫描可用皮肤（用户目录）、加载 manifest、管理导入/删除/元数据编辑
AdapterFactory       — 给定 manifest + 目录，创建对应 AnimationAdapter
BehaviorController   — 状态机 + 计时调度，通过 adapter 驱动引擎，调用 SkinService 完成皮肤加载
```

- `SkinService.switchSkin()` 封装了完整的皮肤切换流程（定位 → 加载 → 销毁旧引擎 → 创建新引擎）
- `BehaviorController` MUST 对引擎类型无感知，只通过 `AnimationAdapter` protocol 交互
- 新增引擎 MUST 通过 `AdapterFactory` 注册，NEVER 在 BehaviorController 中增加 if/else

### 引擎生命周期

切换皮肤的实际流程（`SkinService.switchSkin`）：

```
1. 定位皮肤目录（用户数据目录）
2. 加载 manifest.json → SkinManifest
3. 旧 adapter.stop()
4. 旧 adapter.detach()
5. AdapterFactory.create() 创建新 adapter
6. 返回 (adapter, manifest) 给 BehaviorController
7. BehaviorController 调用 adapter.play(state) 和 setDirection()
```

- MUST 在创建新 adapter 之前完成旧 adapter 的清理
- NEVER 让旧 adapter 的 timer/displayLink 在后台继续运行

## 目录结构（实际）

```
pixelkin/
├── Pixelkin/
│   ├── App/
│   │   ├── PixelkinApp.swift           # @main 入口 + MenuBarExtra + Window
│   │   ├── AppDelegate.swift             # 创建宠物窗口
│   │   └── AppCoordinator.swift          # 依赖注入与全局编排
│   ├── Data/                             # 🔮 未来数据层占位（均为空目录）
│   │   ├── Config/
│   │   ├── Memory/
│   │   ├── Persona/
│   │   │   └── Chats/
│   │   └── UserPersona/
│   ├── Domain/
│   │   ├── Models/
│   │   │   ├── AppConfig.swift           # 全局配置（LLM provider / preset）
│   │   │   ├── BubbleRuleSet.swift       # 情境气泡规则 + PhraseBook 角色语录本
│   │   │   ├── Persona.swift             # Persona 人设模型
│   │   │   ├── PetBehaviorState.swift    # 行为状态 + 朝向枚举
│   │   │   └── SkinManifest.swift        # 皮肤 manifest 模型（含 states/variants/selection）
│   │   ├── PetRuntime/
│   │   │   ├── PetRuntimeState.swift     # 宠物运行时状态聚合
│   │   │   ├── BehaviorController.swift  # 状态机 + 计时调度 + 皮肤加载
│   │   │   └── ContextBubbleController.swift # 情境气泡控制器（应用监听 + 规则匹配）
│   │   └── Services/
│   │       ├── AdapterFactory.swift      # 根据 manifest 创建 adapter
│   │       ├── ConfigService.swift       # AppConfig JSON 持久化
│   │       ├── LaunchAtLoginService.swift # 开机自启注册
│   │       ├── LLMService.swift          # OpenAI / Anthropic / Gemini 调用封装
│   │       ├── PersonaService.swift      # Persona JSON 持久化
│   │       ├── SettingsStore.swift       # UserDefaults 封装（皮肤 / 可见性 / 运行时参数）
│   │       └── SkinService.swift         # 皮肤发现 + 加载 + 导入 + 编辑 + 删除
│   ├── Infrastructure/
│   │   ├── Windowing/
│   │   │   ├── PetPanel.swift            # NSPanel 子类
│   │   │   ├── PetWindowController.swift # 窗口创建 + 拖拽 + 点击穿透 + 右键菜单
│   │   │   ├── PetPhysicsController.swift # 移动 + 下落 + 窗口边缘检测 + walking surface
│   │   │   ├── WindowDetector.swift      # CGWindowList API 封装（窗口位置探测）
│   │   │   └── HitTestView.swift         # NSHostingView 子类（alpha 像素检测 + 鼠标事件）
│   │   ├── Animation/
│   │   │   ├── AnimationAdapter.swift    # protocol 定义
│   │   │   ├── SpriteAdapter.swift       # Sprite Sheet 帧动画
│   │   │   ├── GifAdapter.swift          # GIF 帧动画
│   │   │   ├── SvgAdapter.swift          # SVG + WKWebView（含内嵌 SvgRenderView）
│   │   │   └── SpriteRenderView.swift    # CALayer 渲染视图（Sprite + GIF 共用）
│   │   └── Persistence/
│   │       └── AppPaths.swift            # Application Support 路径管理 + 未来路径占位
│   ├── Features/
│   │   ├── Pet/
│   │   │   ├── PetView.swift             # 宠物窗口根 View
│   │   │   ├── PetBubbleView.swift       # 对话气泡
│   │   │   └── PetRenderView.swift       # 动画渲染容器（NSViewRepresentable 桥接）
│   │   ├── Panel/
│   │   │   ├── ChatView.swift            # 聊天工作区（LLM + Persona）
│   │   │   ├── PanelRootView.swift       # 控制面板根 View（NavigationSplitView + PanelSection 枚举）
│   │   │   ├── PersonasView.swift        # Persona 管理
│   │   │   ├── SettingsView.swift        # 运行时设置 + LLM 预设
│   │   │   ├── SkinCard.swift            # 皮肤卡片组件（含内嵌 SkinCardContent）
│   │   │   ├── SkinEditorModal.swift     # 皮肤导入/编辑弹窗（基础属性）
│   │   │   ├── SkinFilesEditorModal.swift # 动画属性 / 语录 / 规则高级编辑
│   │   │   └── SkinGalleryView.swift     # 皮肤画廊（含内嵌 SkinSectionView）
│   │   └── Shared/
│   │       └── Components/               # 空目录，共享组件占位
│   ├── Resources/
│   │   └── Assets.xcassets               # 应用图标等
│   └── Pixelkin.entitlements           # 非沙盒配置
├── project.yml                           # XcodeGen 项目配置
├── AGENTS.md                             # 本文件
└── SPEC_NATIVE.md                        # 人类可读开发文档
```

## 接口契约

### AnimationAdapter（所有引擎 MUST 实现）

```swift
@MainActor
protocol AnimationAdapter: AnyObject {
    @discardableResult
    func play(_ state: PetBehaviorState, context: SkinManifest.AnimationContext) -> SkinManifest.AnimationVariant?
    func stop()
    func setDirection(_ direction: FacingDirection)
    func attach(to container: NSView)
    func detach()
}
```

### 行为状态枚举

```swift
enum PetBehaviorState: String, Codable {
    case idle, walk, drag, fall, sleep, sit, cling, click
}

enum FacingDirection: String, Codable {
    case left, right
}
```

### SkinManifest（实际模型）

```swift
struct SkinManifest: Codable, Identifiable, Equatable {
    var id: String        // 皮肤唯一标识（= 文件夹名，运行时注入覆盖）
    var name: String
    let type: String      // "sprite" | "gif" | "svg" | "rive"

    // 渲染尺寸（sprite / gif / svg 通用）
    var frameSize: FrameSize?
    var scale: Double?

    // 状态动画配置（sprite / gif / svg 使用）
    var states: [String: StateConfig]?

    // Rive 专用
    let file: String?
    let stateMachine: String?
    let canvasSize: Int?

    // UI 元数据
    var group: String?       // 分组标签
    var tag: String?         // 特征标签
    var preview: String?     // 预览图文件名

    // 运行时注入（不序列化）
    var directoryURL: URL?
    var isBuiltIn: Bool = false

    struct FrameSize: Codable, Equatable {
        var width: Double
        var height: Double
    }

    struct StateConfig: Codable, Equatable {
        var selection: SelectionStrategy
        var variants: [AnimationVariant]
    }

    enum SelectionStrategy: String, Codable, CaseIterable, Equatable {
        case single, random, weightedRandom, firstMatch
    }

    struct AnimationVariant: Codable, Equatable, Identifiable {
        var id: String
        var file: String
        var frames: Int?       // sprite 必填
        var fps: Int?          // sprite 必填
        var loop: Bool?        // sprite 必填
        var weight: Int?       // weightedRandom 策略用
        var conditions: [String]?
        var priority: Int?
        var duration: Double?  // 覆盖默认调度时长
        var cooldown: Double?  // 变体冷却（秒）
    }

    struct AnimationContext: Equatable {
        var activeConditions: Set<String> = []
        var variantLastPlayedAt: [String: Date] = [:]
    }

    // 变体选择算法
    func resolveVariant(for state: String, context: AnimationContext = .init()) -> AnimationVariant?
}
```

### PetRuntimeState

```swift
@Observable
@MainActor
final class PetRuntimeState {
    var behaviorState: PetBehaviorState = .idle
    var facingDirection: FacingDirection = .right
    var position: CGPoint = .zero
    var currentSkinID: String = ""
    var isBubbleVisible: Bool = false
    var bubbleText: String = ""
    var isDragging: Bool = false
    var clingSide: FacingDirection? = nil  // cling 状态下趴在窗口哪一侧
    var petSize: CGSize = CGSize(width: 128, height: 128)
}
```

### AdapterFactory

```swift
@MainActor
enum AdapterFactory {
    static func create(manifest: SkinManifest, skinDirectory: URL) -> AnimationAdapter {
        switch manifest.type {
        case "gif":    return GifAdapter(manifest: manifest, skinDirectory: skinDirectory)
        case "svg":    return SvgAdapter(manifest: manifest, skinDirectory: skinDirectory)
        // case "rive": return RiveAdapter(...)  // 待接入
        default:       return SpriteAdapter(manifest: manifest, skinDirectory: skinDirectory)
        }
    }
}
```

### SettingsStore

```swift
@MainActor
enum SettingsStore {
    struct StoredSettings: Codable {
        var selectedSkinID: String       // 上次选中的皮肤 ID
        var isPetVisible: Bool           // 宠物是否可见
        var globalTone: String           // "skin" | "tsundere" | "gentle" | "default"
    }

    static func load() -> StoredSettings
    static func save(_ settings: StoredSettings)
    static func update(_ mutate: (inout StoredSettings) -> Void)
}
```

## 数据格式

### Sprite 动画包 manifest.json（states/variants 模型）

```json
{
  "id": "pixel-cat",
  "name": "像素猫咪",
  "type": "sprite",
  "frameSize": { "width": 64, "height": 64 },
  "scale": 3,
  "states": {
    "idle": {
      "selection": "single",
      "variants": [
        { "id": "idle_default", "file": "idle.png", "frames": 4, "fps": 4, "loop": true }
      ]
    },
    "walk": {
      "selection": "single",
      "variants": [
        { "id": "walk_default", "file": "walk.png", "frames": 8, "fps": 10, "loop": true }
      ]
    },
    "drag": {
      "selection": "single",
      "variants": [
        { "id": "drag_default", "file": "drag.png", "frames": 2, "fps": 6, "loop": true }
      ]
    },
    "fall": {
      "selection": "single",
      "variants": [
        { "id": "fall_default", "file": "fall.png", "frames": 3, "fps": 8, "loop": false }
      ]
    }
  }
}
```

### GIF 动画包 manifest.json

```json
{
  "id": "clawd",
  "name": "Clawd",
  "type": "gif",
  "frameSize": { "width": 64, "height": 64 },
  "scale": 1.5,
  "group": "Beta Legacy",
  "states": {
    "idle": {
      "selection": "single",
      "variants": [{ "id": "idle_default", "file": "clawd-idle.gif" }]
    },
    "walk": {
      "selection": "single",
      "variants": [{ "id": "walk_default", "file": "clawd-carrying.gif" }]
    }
  }
}
```

### Rive 动画包 manifest.json（待实现）

```json
{
  "id": "genki-girl",
  "name": "元气少女",
  "type": "rive",
  "file": "pet.riv",
  "stateMachine": "PetBehavior",
  "canvasSize": 192
}
```

## 行为状态机

```
States: idle, walk, drag, fall, sleep, sit, cling

idle → walk       (随机计时器 4~8s)
walk → idle       (计时器 2~5s 或撞到边界)
idle/walk → drag  (mouseDown)
drag → idle       (mouseUp 且在地面或窗口顶部)
drag → fall       (mouseUp 且悬空)
drag → cling      (mouseUp 且在窗口侧边)
fall → idle       (落到地面或窗口顶部)
fall → cling      (下落经过窗口侧边，40% 概率抓住)
idle/walk → sleep (60s 无互动)
sleep → idle      (鼠标靠近 / 拖拽 / 5min 自然醒)
walk → sit        (经过窗口顶部边缘，40% 概率)
sit → idle        (10~20s 后站起)
sit → fall        (底下的窗口被关闭)
walk → cling      (走到窗口边缘，30% 概率翻身挂住)
walk → fall       (走到窗口边缘且没转向，30% 概率掉下去)
cling → idle      (8~15s 后，50% 爬到窗口顶部)
cling → fall      (8~15s 后，50% 松手下落；或窗口被关闭)

Walking surfaces: ground（屏幕底部）/ windowTop（其他窗口顶部）
宠物可在窗口顶部来回行走，到达窗口边缘时 40% 转向 / 30% 掉落 / 30% 挂住侧边
```

## 情境气泡系统

### 架构：规则和语录分离

```
BubbleRuleSet (bubble_rules.json)         PhraseBook (phrases.json, 在皮肤目录中)
┌──────────────────────────────┐           ┌────────────────────────────────┐
│ appGroups:                   │           │ phrases:                       │
│   "browsers": [Safari, ...]  │           │   "browsers": ["才不是在偷看…"] │
│   "code_editors": [Xcode, …] │           │   "code_editors": ["Bug又来了"]│
│                              │           │   "default": ["哼…随便你"]     │
│ rules:                       │           └────────────────────────────────┘
│   - id: "browsers"           │                       ▲
│     appGroup: "browsers"     │                       │
│     probability: 0.35        │           ContextBubbleController
│     cooldown: 45             │           loadPhraseBook(from: skinDir)
│                              │                       │
│ fallbackPhrases:             │           查找链：PhraseBook → fallbackPhrases
│   "browsers": ["又在摸鱼！"]  │
└──────────────────────────────┘
```

**设计原则**：
- `BubbleRuleSet` 定义 **"什么时候触发"**（app 分组 + 概率 + 冷却），全局共享
- `PhraseBook` 定义 **"说什么"**（角色语录），跟着皮肤走
- 新增角色 = 在皮肤目录里放一个 `phrases.json`，规则文件不用动
- LLM 通过 `showBubble(text:)` 直接弹气泡，绕过规则系统

### 触发流程

1. `NSWorkspace.didActivateApplicationNotification` 检测前台应用切换
2. 获取 `bundleIdentifier` → 通过反向索引匹配规则
3. 检查全局冷却（15s）+ 规则冷却（40-60s）
4. 按 `probability` 随机判定
5. 从当前 PhraseBook 查找语录 → fallback 到 `fallbackPhrases`
6. 设置 `PetRuntimeState.bubbleText` + `isBubbleVisible = true`
7. `defaultDuration`（4s）后自动隐藏

### 皮肤语录本（PhraseBook）

```json
// ~/Library/Application Support/Pixelkin/Skins/{skinID}/phrases.json
{
  "browsers": ["才不是在偷看你上网呢！", "又在摸鱼…哼"],
  "code_editors": ["这种 Bug 怎么还犯", "变量名太随意了吧…"],
  "default": ["才不是在意你呢！", "哼，随便你做什么"]
}
```

- key 对应 `BubbleRule.id`
- 皮肤切换时通过 `AppCoordinator.switchSkin()` 自动加载对应 PhraseBook

### 持久化

| 数据 | 位置 |
|---|---|
| 气泡触发规则 | `~/Library/Application Support/Pixelkin/bubble_rules.json` |
| 角色语录本 | `~/Library/Application Support/Pixelkin/Skins/{skinID}/phrases.json` |

### 外部触发接口（供 LLM 使用）

```swift
// 直接弹气泡，不走规则匹配
contextBubbleController.showBubble(text: "你好！", duration: 5)
```

## 代码规范

### MUST

- 界面 MUST 使用 SwiftUI
- 窗口外壳 MUST 使用 AppKit（NSPanel / NSHostingView）
- 状态对象 MUST 使用 `@Observable` + `@MainActor`
- 业务逻辑 MUST 放在 Controller / Service 中，NEVER 在 View body 里写
- 文件 I/O MUST 通过 Service 层，NEVER 在 View 中直接操作文件系统
- AppKit 调用 MUST 通过 Infrastructure 层封装
- Sprite 渲染 MUST 设 `magnificationFilter = .nearest`
- 帧推进 MUST 优先使用 `CADisplayLink`（macOS 14+），不可用时回退 Timer
- 每个引擎 Adapter MUST 独立一个文件
- 每个有实质功能的 View MUST 独立一个文件
- 数据模型 MUST 放在 Domain/Models，NEVER 内联在 View 文件中

### NEVER

- NEVER 在 View body 中直接调用 `NSPanel` / `NSWindow` API
- NEVER 用 `ObservableObject` / `@Published`
- NEVER 用 Combine
- NEVER 引入 SwiftData / Core Data
- NEVER 在 `BehaviorController` 中硬编码引擎类型判断
- NEVER 把多个无关的 class/struct 塞进同一个文件

### 命名规则

| 类型 | 模式 | 示例 |
|---|---|---|
| 状态对象 | `SomethingState` | `PetRuntimeState` |
| 控制器 | `SomethingController` | `BehaviorController` |
| 服务 | `SomethingService` | `SkinService` |
| 工厂 | `SomethingFactory` | `AdapterFactory` |
| 存储 | `SomethingStore` | `SettingsStore` |
| 窗口桥接 | `SomethingPanel` / `SomethingWindowController` | `PetPanel` |
| 动画适配器 | `SomethingAdapter` | `SpriteAdapter`, `GifAdapter` |
| SwiftUI View | `SomethingView` | `PetView`, `SkinGalleryView` |

## 持久化位置

| 数据 | 位置 | 格式 |
|---|---|---|
| 轻量配置 | `UserDefaults` (key: `desktop_pet.settings`) | JSON (StoredSettings) |
| 用户导入皮肤 | `~/Library/Application Support/Pixelkin/Skins/{skinID}/` | manifest.json + 资源文件 |

**当前状态**：皮肤仅从用户数据目录加载，Bundle 内置皮肤机制未启用。

## 菜单栏

- MUST 使用 SwiftUI `MenuBarExtra` 作为全局入口
- 当前包含：打开控制面板、显示/隐藏宠物、退出

## 控制面板侧栏

当前 `PanelSection` 枚举定义了四个 tab：

| Section | 名称 | 状态 |
|---|---|---|
| `.chat` | 聊天 | ✅ 基础聊天已实现（LLM + Persona + 气泡联动） |
| `.personas` | 角色 | ✅ 基础编辑已实现（本地持久化 + 关联皮肤） |
| `.skins` | 皮肤 | ✅ 已实现（SkinGalleryView） |
| `.settings` | 设置 | ✅ 基础设置已实现（气泡语气 + LLM 预设 + 开机自启） |
