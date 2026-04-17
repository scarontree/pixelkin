# DesktopPet macOS Native — 开发文档

> **版本**: V1 Revised (sync with codebase)
> **最后更新**: 2026-04-17
> **平台**: macOS 14.0+ (Sonoma)
> **定位**: 给人看的完整开发文档。AI agent 专用硬性规范见 `AGENTS.md`

---

## 1. 项目现状

### 1.1 当前形态

项目已经从最初的 V1.0 骨架演进为一个可运行的桌面宠物产品：

| 能力 | 状态 | 说明 |
|---|---|---|
| 桌面宠物运行时 | ✅ 完成 | 透明窗口 + 状态机 + 拖拽 + 下落 |
| 多引擎动画系统 | ✅ 三引擎 | Sprite Sheet / GIF / SVG，Rive 已注册未接入 |
| 多变体动画 | ✅ 完成 | 同一状态多个变体随机切换 |
| 情境气泡系统 | ✅ 完成 | 检测前台应用 + 规则匹配 + 角色语录本 |
| 皮肤管理面板 | ✅ 完成 | 导入、编辑、manifest 编辑、热切换、删除 |
| 点击穿透 | ✅ V1 | 矩形热区 + 动态 `ignoresMouseEvents` |
| 菜单栏入口 | ✅ 完成 | MenuBarExtra |
| 新行为状态 | ⬚ 计划 | sit / cling（坐/趴在窗口上） |
| 设置面板 | ⬚ 骨架 | 侧栏 tab 已占位 |
| 聊天 / 角色系统 | ⬚ 占位 | Data 层目录已创建，功能未实现 |
| 内置皮肤 | ⬚ 未启用 | Bundle Skins 机制未实装 |

### 1.2 当前方向

项目不再按线性里程碑推进。当前处于"功能可用但不完整"的状态，优先级：

1. **稳定已有功能** — 确保皮肤系统可靠运行
2. **追偿技术债** — 独立物理控制器、alpha-based 点击穿透等
3. **按需扩展** — 聊天、角色、Function Calling 等未来特性，不预先锁定方案

---

## 2. 技术栈

| 层 | 技术 | 说明 |
|---|---|---|
| 语言 | **Swift 5.9+** | 使用 `@Observable`、`async/await` |
| UI 框架 | **SwiftUI** | 业务界面和状态驱动渲染 |
| 桌面窗口 | **AppKit** | 透明窗口、层级、Spaces、点击穿透 |
| 并发 | **Swift Concurrency** | `async/await`、`Task`、`@MainActor` |
| 持久化 | **Codable + JSON / UserDefaults** | 不引入 SwiftData / Core Data |
| 动画引擎 | **Sprite Sheet** / **GIF** / **SVG (WebKit)** | 通过 `AnimationAdapter` protocol 统一 |
| 构建 | **XcodeGen** | `project.yml` → Xcode 项目 |
| 最低系统 | **macOS 14.0+** | 使用完整 SwiftUI API + `@Observable` + `CADisplayLink` |

---

## 3. 系统架构

### 3.1 总体分层

```
App 层 ─────────────── 入口 + 依赖注入 + 全局编排
   │
Data 层 ────────────── 未来数据存储占位（Persona / Chat / Memory / Config）
   │
Domain 层 ──────────── 模型 + 运行时控制器 + 服务接口（纯业务逻辑）
   │
Infrastructure 层 ──── 系统能力封装（窗口 / 动画引擎 / 文件存储）
   │
Features 层 ────────── SwiftUI View（只消费状态，不包含业务逻辑和 I/O）
```

### 3.2 运行时内核

宠物在桌面上"活着"的所有状态和行为，由以下组件协作：

```
┌─────────────────────────────────────────────────────────┐
│                    AppCoordinator                        │
│  持有所有运行时组件引用，负责依赖注入和编排               │
└──────────────┬──────────────┬───────────────┬────────────┘
               │              │               │
    ┌──────────▼──┐  ┌────────▼────────┐  ┌──▼───────────────┐
    │ SkinService  │  │BehaviorController│  │PetWindowController│
    │             │  │                 │  │                   │
    │ 皮肤发现    │  │ 状态机          │  │ 窗口管理          │
    │ 皮肤加载    │  │ 计时调度        │  │ 拖拽              │
    │ 引擎切换    │──│ 引擎调用        │  │ 点击穿透          │
    │ 导入/删除   │  │ (通过 Adapter)  │  │ 右键菜单          │
    └──────────┬──┘  └────────┬────────┘  │ 物理循环(walk)    │
               │              │           └──┬───────────────┘
          ┌────▼──────────────▼──────────────▼───┐
          │           PetRuntimeState              │
          │  behaviorState / facingDirection /      │
          │  position / currentSkinID / petSize /   │
          │  isDragging / bubble                    │
          └────────────────────────────────────────┘
```

**关键原则**：
- `SkinService` 统一管理皮肤的发现、加载和引擎创建/销毁
- `BehaviorController` 只管行为状态，通过 `AnimationAdapter` protocol 与引擎交互，不知道有哪些引擎类型
- `PetWindowController` 管理窗口、交互和当前阶段的物理循环（walk 位移）
- `PetRuntimeState` 是所有状态的唯一事实来源

> **技术债**: 物理逻辑（walk 位移、边界检测、下落动画）目前内嵌在 `PetWindowController` 中，
> 后续应提取到独立的 `PetPhysicsController`。但这不是阻断性问题。

### 3.3 多引擎动画系统

```
AnimationAdapter (protocol)
    │
    ├── SpriteAdapter    — Sprite Sheet 逐帧裁切 + CALayer 渲染
    │                      使用 SpriteRenderView（CALayer + nearest filter）
    │
    ├── GifAdapter       — CGImageSource 解码 GIF 帧 + 自带延迟
    │                      也使用 SpriteRenderView 进行渲染
    │
    ├── SvgAdapter       — WKWebView 渲染 SVG 矢量动画
    │                      内含 SvgRenderView（WKWebView 包装）
    │
    └── (RiveAdapter)    — 工厂已注册但注释掉，待引入 Rive SPM
```

引擎创建通过 `AdapterFactory`，不硬编码在业务层。新增引擎 = 新增 Adapter 类 + 在 Factory 注册。

**帧推进策略**：优先使用 `CADisplayLink`（macOS 14+），不可用时回退 `Timer`。Sprite 和 GIF 引擎均使用 `lastFrameTime` + 目标间隔来控制实际帧率，避免与显示刷新率耦合。

### 3.4 数据流

```
用户交互 (拖拽、点击、定时器)
    ↓
BehaviorController → PetRuntimeState (状态变化)
    ↓                        ↓
adapter.play(state)    PetWindowController (窗口位置)
    ↓                        ↓
渲染引擎更新画面       PetBubbleView (气泡)
```

状态 → 副作用是单向流。View 只读取 `PetRuntimeState`，不直接修改。

---

## 4. 窗口架构

### 4.1 PetPanel（宠物窗口）

`NSPanel` 子类，透明无边框悬浮面板：

```swift
styleMask = [.borderless, .nonactivatingPanel]
isOpaque = false; backgroundColor = .clear; hasShadow = false
level = .floating
collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
ignoresMouseEvents = true  // 初始穿透
```

窗口内容通过 `HitTestView`（`NSHostingView<PetView>` 子类）嵌入。`HitTestView` 处理原生 `mouseDown` / `mouseDragged` / `mouseUp` / `rightMouseDown` 事件，SwiftUI `DragGesture` 在 `nonactivatingPanel` 下不可靠，因此改用 AppKit 原生方案。

### 4.2 点击穿透（已实现）

桌面宠物产品的核心可用性——透明区域不能挡住用户点击。

**当前实现**：

1. `PetPanel` 初始 `ignoresMouseEvents = true`
2. `PetWindowController` 注册全局 + 本地鼠标监听
3. 鼠标位置在宠物精灵矩形热区内（±8pt 容错）→ 关闭穿透
4. 鼠标位置在透明区域 → 开启穿透
5. 拖拽过程中强制关闭穿透

**后续优化方向**：从矩形热区升级到 alpha-based 像素级检测。

### 4.3 控制面板

SwiftUI `Window`，`NavigationSplitView` 布局：

```
Sidebar             Detail
┌───────────────┬───────────────────────┐
│ 💬 聊天 (占位) │                       │
│ 👥 角色 (占位) │ SkinGalleryView       │
│ 🎨 皮肤       │   └ SkinSectionView   │
│ ⚙️ 设置 (占位) │     └ SkinCard        │
└───────────────┴───────────────────────┘
```

皮肤管理支持的操作：
- 浏览所有皮肤（按 group 分组展示）
- 点击卡片立即热切换引擎
- 右键菜单：编辑皮肤设置 / 高级编辑 manifest / 删除
- 工具栏：导入新皮肤 / 刷新列表

---

## 5. 皮肤与动画资源

### 5.1 Manifest 模型（states/variants）

当前 `SkinManifest` 使用 **状态 → 变体列表 + 选择策略** 的模型，比早期的扁平 `animations` 字典更灵活：

```
SkinManifest
  ├── states: { "idle": StateConfig, "walk": StateConfig, ... }
  │     └── StateConfig
  │           ├── selection: SelectionStrategy (.single / .random / .weightedRandom / .firstMatch)
  │           └── variants: [AnimationVariant]
  │                 ├── id, file
  │                 ├── frames?, fps?, loop?    ← sprite 必填
  │                 ├── weight?                 ← weightedRandom 用
  │                 └── conditions?, priority?  ← 条件匹配用
  ├── frameSize, scale
  ├── group, tag, preview                      ← UI 元数据
  └── directoryURL, isBuiltIn                  ← 运行时注入，不序列化
```

变体选择通过 `resolveVariant(for:context:)` 方法，支持按条件过滤 + 按策略选取。

| 字段 | Sprite | GIF | SVG | Rive |
|---|---|---|---|---|
| `id`, `name`, `type` | ✅ | ✅ | ✅ | ✅ |
| `frameSize`, `scale` | ✅ | ✅ | ✅ | — |
| `states` (variants) | ✅ (需 frames/fps/loop) | ✅ (只需 file) | ✅ (只需 file) | — |
| `file`, `stateMachine`, `canvasSize` | — | — | — | ✅ |
| `group`, `tag`, `preview` | ✅ | ✅ | ✅ | ✅ |

**类型约束**：
- `scale` 是 `Double`（支持 1.5 等小数值）
- `FrameSize.width/height` 是 `Double`
- `AnimationVariant.frames/fps/loop` 是 `Optional`（GIF/SVG 不需要这些字段）

### 5.2 资源位置

| 来源 | 路径 | 状态 |
|---|---|---|
| 用户导入皮肤 | `~/Library/Application Support/DesktopPet/Skins/{skinID}/` | ✅ 唯一数据源 |
| 内置皮肤 | App Bundle `Resources/Skins/` | ⬚ 机制未启用 |

当前所有皮肤均来自用户数据目录。`SkinService.discoverUserSkins()` 扫描该目录下的所有子文件夹。

### 5.3 面板中的皮肤管理

面板提供两个层级的编辑：

1. **SkinEditorModal** — 基础属性编辑（名称、引擎类型、分组、标签）+ 新皮肤导入
2. **ManifestEditorModal** — 结构化 manifest 编辑（状态列表、变体配置、选择策略、帧参数等）

文件 I/O 操作（导入、保存、删除）全部在 `SkinService` 中完成。

---

## 6. 行为系统

### 6.1 状态机

```
idle → walk    (随机计时器 4~8s)
walk → idle    (计时器 2~5s 或撞到屏幕边缘)
idle/walk → drag  (mouseDown)
drag → fall    (mouseUp 且不在地面)
drag → idle    (mouseUp 且在地面)
fall → idle    (落地)
```

### 6.2 当前职责分布

| 组件 | 职责 |
|---|---|
| `BehaviorController` | 状态机 + 随机行为计时 + 通过 Adapter 驱动动画 + 皮肤加载 |
| `PetWindowController` | 窗口位置 + 拖拽 + walk 位移 + 下落动画 + 边界检测 + 点击穿透 + 右键菜单 |

> **注意**：物理逻辑（walk 速度、边界检测、fall 动画）目前在 `PetWindowController` 中。
> 如果后续需要更复杂的物理行为（加速度、弹跳等），应提取到独立的 `PetPhysicsController`。

**多变体动画**：idle 状态下计时器触发时，70% 概率重新 resolve 变体（多个 idle 动画随机切换），30% 切换到 walk。

### 6.3 情境气泡系统

**规则和语录分离**：

- `bubble_rules.json`（Application Support）定义"什么时候触发"
  - `appGroups`：应用分组（browsers / code_editors / social 等 15 组）
  - `rules`：触发规则（概率 + 冷却）
  - `fallbackPhrases`：兜底语录
- `phrases.json`（皮肤目录，可选）定义"说什么"
  - key = 规则 ID，value = 角色台词列表
  - **新增角色 = 给皮肤目录添加 phrases.json，规则文件不需要动**

触发流程：NSWorkspace 通知 → bundleID 匹配 → 冷却/概率判定 → PhraseBook 查语录 → fallback → 显示气泡 → 4s 自动隐藏

LLM 接口：`showBubble(text:duration:)` 直接弹任意文字

---

## 7. 目录结构

```
desktop-pet-macos/
├── DesktopPet/
│   ├── App/
│   │   ├── DesktopPetApp.swift           # @main + MenuBarExtra + Window
│   │   ├── AppDelegate.swift             # 创建宠物窗口
│   │   └── AppCoordinator.swift          # 依赖注入与全局编排
│   ├── Data/                             # 🔮 未来数据层占位
│   │   ├── Config/                       #    全局配置（空）
│   │   ├── Memory/                       #    记忆系统（空）
│   │   ├── Persona/Chats/                #    角色聊天（空）
│   │   └── UserPersona/                  #    用户人设（空）
│   ├── Domain/
│   │   ├── Models/
│   │   │   ├── PetBehaviorState.swift    # 行为状态 + 朝向枚举
│   │   │   ├── SkinManifest.swift        # 皮肤 manifest 模型
│   │   │   └── BubbleRuleSet.swift       # 气泡规则 + PhraseBook 语录本
│   │   ├── PetRuntime/
│   │   │   ├── PetRuntimeState.swift     # 运行时状态聚合
│   │   │   ├── BehaviorController.swift  # 状态机 + 计时 + 皮肤加载
│   │   │   └── ContextBubbleController.swift # 情境气泡控制器
│   │   └── Services/
│   │       ├── SkinService.swift         # 皮肤发现/加载/导入/编辑/删除
│   │       ├── AdapterFactory.swift      # 引擎工厂
│   │       └── SettingsStore.swift       # UserDefaults 封装
│   ├── Infrastructure/
│   │   ├── Windowing/
│   │   │   ├── PetPanel.swift            # NSPanel 子类
│   │   │   ├── PetWindowController.swift # 窗口 + 拖拽 + 穿透 + 物理
│   │   │   └── HitTestView.swift         # NSHostingView 子类
│   │   ├── Animation/
│   │   │   ├── AnimationAdapter.swift    # protocol 定义
│   │   │   ├── SpriteAdapter.swift       # Sprite Sheet 帧动画
│   │   │   ├── GifAdapter.swift          # GIF 帧动画
│   │   │   ├── SvgAdapter.swift          # SVG + 内嵌 SvgRenderView
│   │   │   └── SpriteRenderView.swift    # CALayer 渲染视图
│   │   └── Persistence/
│   │       └── AppPaths.swift            # 路径管理
│   ├── Features/
│   │   ├── Pet/
│   │   │   ├── PetView.swift             # 宠物窗口根 View
│   │   │   ├── PetBubbleView.swift       # 对话气泡
│   │   │   └── PetRenderView.swift       # 动画渲染容器
│   │   ├── Panel/
│   │   │   ├── PanelRootView.swift       # 控制面板根 View + PanelSection
│   │   │   ├── SkinGalleryView.swift     # 皮肤画廊 + SkinSectionView
│   │   │   ├── SkinEditorModal.swift     # 皮肤导入/编辑弹窗
│   │   │   ├── ManifestEditorModal.swift # manifest 结构化编辑器
│   │   │   └── SkinCard.swift            # 皮肤卡片组件
│   │   └── Shared/Components/            # 共享组件（空）
│   ├── Resources/
│   │   └── Assets.xcassets
│   └── DesktopPet.entitlements
├── project.yml                           # XcodeGen 配置
├── AGENTS.md                             # AI agent 规范
└── SPEC_NATIVE.md                        # 本文件
```

---

## 8. 开发规范

### 代码风格

- 界面 SwiftUI，系统能力封装后再给 SwiftUI 调
- 业务逻辑放在 `@Observable` 对象或控制器中
- UI 相关对象标 `@MainActor`
- 不在 View 中直接读写文件
- 不在 View 中直接调用 AppKit 窗口 API
- 一个类/struct 一个文件（小型辅助类型除外）

### 命名规则

| 类型 | 模式 | 示例 |
|---|---|---|
| 状态对象 | `SomethingState` | `PetRuntimeState` |
| 控制器 | `SomethingController` | `BehaviorController` |
| 服务 | `SomethingService` | `SkinService` |
| 工厂 | `SomethingFactory` | `AdapterFactory` |
| 存储 | `SomethingStore` | `SettingsStore` |
| 窗口桥接 | `SomethingPanel/WindowController` | `PetPanel` |
| 动画适配器 | `SomethingAdapter` | `GifAdapter` |
| SwiftUI View | `SomethingView` | `SkinGalleryView` |

---

## 9. 已知技术债与未来方向

### 技术债（不阻断，按需处理）

| 项 | 说明 | 优先级 |
|---|---|---|
| 物理控制器独立 | walk 位移、边界、下落目前在 `PetWindowController` | 中 |
| 点击穿透升级 | 矩形热区 → alpha-based 像素级检测 | 低 |
| 内置皮肤机制 | Bundle `Resources/Skins/` 发现+加载 | 低 |
| SvgRenderView 独立 | 目前内嵌在 `SvgAdapter.swift` 中 | 低 |
| Rive 引擎接入 | 工厂已注册，需引入 Rive SPM 和实现 RiveAdapter | 按需 |

### 未来方向（不锁定方案）

以下是 `Data/` 层占位目录暗示的未来方向，但**不预先规定实现细节**：

- **Persona / 角色系统** — 宠物性格、对话风格
- **Chat / 聊天** — 与宠物对话（可能涉及 LLM 集成）
- **Memory / 记忆** — 上下文持久化
- **Config / 全局配置** — 统一配置管理
- **UserPersona / 用户人设** — 用户自定义偏好

这些功能的具体技术方案在实际动工时再决定。
