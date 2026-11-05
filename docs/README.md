# Nimi 设计文档

> 状态:持续更新 · 日期:2026-11-05

## 索引

| 文档 | 内容 | 适合谁 |
|---|---|---|
| [00 可行性分析](00-feasibility.md) | 代码规模、Nim 能力、原型、风险、工作量、Go/No-Go | 决策者、评审者 |
| [01 架构设计](01-architecture.md) | 分层、模块布局、线程/内存、平台契约、IPC、UI、构建 | 所有实现者 |
| [02 macOS 后端](02-macos-backend.md) | ObjC/AppKit/WKWebView/Surface/Metal/CoreText/打包 | macOS 后端 |
| [03 原生 UI](03-native-ui.md) | Element/arena、布局、scene、文本、输入、控件、Tester | UI/渲染 |
| [04 工具链与 IPC](04-tooling-and-ipc.md) | CLI、配置、模板、TS 生成、打包、更新、插件 | 工具链 |
| [05 实施路线图](05-roadmap.md) | M0–M10、任务、验收、估算、Gate | 项目管理 |
| [06 Windows/Linux](06-windows-linux.md) | Win32/WebView2/D3D11、GTK3/WebKitGTK/GL、交叉编译 | 平台后端 |
| [07 API 映射](07-api-mapping.md) | MyGo → Nimi 命名/语义/API 对照 | 迁移者、API 设计 |
| [08 M1 实现状态](08-m1-notes.md) | 已实现内容、崩溃修复、已知限制、下一步 | 实现者、评审者 |
| [09 Nim 实践参考](09-nim-practices.md) | planetis-m/skills 的采用/偏离与落点 | 实现者 |
| [10 M2 实现状态](10-m2-notes.md) | 原生 Surface + 布局/控件/输入/焦点/换行 + Tester/PNG + counter、决策、限制 | 实现者、评审者 |
| [11 M3–M7 状态](11-m3-m7-status.md) | 控件/菜单/对话框/TextInput/DMG;M5 与剩余项 | 实现者、评审者 |
| [12 Nimi Notes 验收](12-notes-demo.md) | WebView-first 笔记应用、IPC、菜单、导入导出、自动保存、打包 | 实现者、评审者 |
| [13 官网与 Pages](13-website.md) | 静态官网、`nimi.zhi.moe` 自定义域名、Cloudflare DNS、GitHub Actions 部署 | 实现者、评审者 |
| [14 macOS 桌面 API](14-macos-desktop-apis.md) | 屏幕/主题/窗口/托盘/通知/快捷键/对话框;决策、验证与限制 | 实现者、评审者 |
| [15 M5 FileServer](15-m5-file-server.md) | 自定义 `nimi://` scheme、FileServer、深链、Session、资源打包 | 实现者、评审者 |
| [16 M5 文件监视](16-m5-file-watching.md) | FSEvents、文件事件、关闭与后续去抖/忽略规则 | 实现者、评审者 |
| [17 M5 Cookies](17-m5-cookies.md) | WKHTTPCookieStore 查询/清理、异步 block、限制 | 实现者、评审者 |
| [18 macOS CI](18-macos-ci.md) | GitHub Actions 测试/构建/DMG artifact、架构输出 | 实现者、评审者 |
| [19 基础 TextArea](19-m6-textarea.md) | 多行输入、Enter、上下行、点击 caret、限制 | 实现者、评审者 |
| [20 选择与剪贴板](20-m6-selection.md) | Shift 选择、Cmd+A/C/X/V、responder 菜单、限制 | 实现者、评审者 |
| [21 ScrollView](21-m6-scrollview.md) | 垂直滚动、scene clip、命中裁剪、滚轮 | 实现者、评审者 |
| [22 原生 Image](22-m3-image.md) | ImageIO、scene opImage、缓存与限制 | 实现者、评审者 |
| [23 M5 文档](23-m5-document.md) | Document 生命周期、dirty/conflict、FSEvents 外部变更 | 实现者、评审者 |
| [24 M6 IME](24-m6-ime.md) | NSTextInputClient、marked text、候选窗、fallback | 实现者、评审者 |
| [25 碎纸效果](25-shredder.md) | MyGo shader 来源、Nim Verlet 物理、WebGL 纸带渲染、限制 | 实现者、评审者 |
| [26 原生碎纸](26-native-shred.md) | NSTimer 帧驱动、scene 纹理四边形、Metal mask/LayerEffect | 实现者、评审者 |
| [27 项目回检](27-project-review.md) | 2026-11-05 架构/文档/测试回检、已修复项与剩余债务 | 实现者、评审者 |

## 阅读顺序

1. **所有人**:00 → 01 → 05。
2. **macOS 后端**:02 + `spikes/`。
3. **UI/渲染**:03 + 02 的渲染/文本部分。
4. **工具链**:04 + 01 §7/§9。
5. **Windows/Linux**:06 + 01/02。
6. **API 迁移**:07。

## 约定

- "必须" = 设计约束;"建议" = 推荐但可调整;"待定" = 需要评审决定。
- 工期为规划量级(±50%),不是承诺。
- 所有原型结果来自 `spikes/` 的实际运行,命令见根 README。
- 参考仓库 `mygo/` 是 MyGo 0.7.4 只读副本;行数统计以它为准。

## 变更

| 日期 | 变更 |
|---|---|
| 2026-11-04 | 初稿:可行性、架构、macOS、原生 UI、工具链、路线图、Windows/Linux、API 映射;7 个原型 |
| 2026-11-04 | M1 核心切片实现:macOS WebView + IPC + TS 生成 + CLI;新增 08 M1 笔记 |
| 2026-11-04 | M2 第一步:原生 NSView Surface + CoreGraphics/CoreText 静态场景;新增 10 M2 笔记 |
| 2026-11-04 | M3 控件切片(Checkbox/Switch/Slider/Progress/Divider)、M4 剪贴板、M7 .app/DMG/签名;新增 11 状态 |
| 2026-11-05 | 碎纸效果:MyGo Verlet 物理移植到 `effects/shred`,WebGL 纸带 demo;新增 25 |
| 2026-11-05 | 原生碎纸:帧驱动、纹理四边形、Metal mask/LayerEffect;新增 26 |
| 2026-11-05 | 项目回检:renderer 注入、Metal 可移植性、动画语义、可移植测试;新增 27 |
