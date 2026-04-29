# DesktopPet

macOS 原生桌面宠物应用。一只会走路、会睡觉、会趴窗口、会吐槽你在干什么的小动物常驻桌面。

## 特性

- **常驻桌面** — 透明无边框悬浮窗口，适配 Spaces 和全屏
- **自主行为** — 闲逛、走路、拖拽、下落、坐下、挂窗、睡觉、点击反馈
- **多引擎动画** — Sprite Sheet / GIF / SVG，Rive 待接入
- **多变体动画** — 同一状态下多个动画变体随机切换
- **情境气泡** — 检测前台应用，根据规则匹配触发角色语录
- **皮肤系统** — 导入、编辑、热切换皮肤，控制面板管理
- **点击穿透** — 像素级 alpha 检测，透明区域不挡操作
- **控制面板** — 聊天、角色管理、皮肤画廊、运行时设置

## 系统要求

- macOS 14.0 (Sonoma) 及以上
- Apple Silicon（arm64）

## 构建

```bash
# 安装依赖
brew install xcodegen

# 生成 Xcode 项目
xcodegen generate

# 构建
xcodebuild -project DesktopPet.xcodeproj -scheme DesktopPet -configuration Debug build

# 或直接在 Xcode 打开
open DesktopPet.xcodeproj
```

## 架构

```
App 层           — 入口、依赖注入
Domain 层        — 模型、运行时控制器、服务接口
Infrastructure 层 — 窗口桥接、动画引擎、文件存储
Features 层      — SwiftUI View
```

- 语言：Swift 5.9+
- UI：SwiftUI + AppKit
- 并发：Swift Concurrency (`async/await`, `@MainActor`)
- 状态管理：`@Observable` (Observation framework)
- 持久化：Codable + JSON / UserDefaults

## 皮肤格式

支持多种动画引擎，通过 `manifest.json` 描述：

- **Sprite Sheet** — 帧动画图集
- **GIF** — GIF 解码
- **SVG** — 矢量动画（WebKit 渲染）

皮肤放置于 `~/Library/Application Support/DesktopPet/Skins/{skinID}/`。
