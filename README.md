# Nimi

**用 Nim 重实现 [MyGo](https://github.com/egoist/mygo) 的桌面应用框架。**

> 官网：<https://nimi.zhi.moe> · 仓库：<https://github.com/zhimoe/nimi>
>
> **Preview**：macOS、Windows、Linux 三平台均可运行。API 仍可能调整；
> 版本范围、平台差异与后续计划统一维护在 [项目 backlog](docs/backlog/README.md)。

Nimi 保留 MyGo 的架构与开发体验——系统 WebView + 类型化 IPC + 自绘原生 UI +
一套桌面 API——但用 Nim 编写，不依赖 cgo，也不依赖 Go 运行时。

## Preview 能力

- **三平台后端**：macOS（AppKit / WKWebView / CoreGraphics / CoreText）、
  Windows（Win32 / WebView2 / GDI）、Linux（GTK3 / WebKitGTK / Cairo / Pango）。
- **两条 UI 路径**：系统 WebView 承载页面，或完全自绘的原生 UI；两者共享窗口、
  菜单、事件、输入法、滚动与测试设施。
- **类型化 IPC**：`bindService`、编译期 TypeScript 客户端、secret/token、
  后台工作池、超时与窗口关闭取消。
- **桌面 API（按平台）**：菜单、托盘、通知、全局快捷键、文件对话框、剪贴板、
  屏幕、主题、Now Playing、登录项、单实例/深链、文件监视、Cookie 与 Document 控制器。
- **打包**：macOS `.app` / DMG / 签名钩子，Windows exe / manifest，
  Linux `.desktop` / `.deb`。
- **测试**：macOS 192 个、Linux 200 个测试用例；Windows 交叉构建与实机 GUI 回归。

Preview 版本仍在快速迭代；各平台功能范围与真实设备验收状态只在
[backlog](docs/backlog/README.md) 维护，首页不逐项列出。

## 为什么

- **Nim 的形态**：编译为 C、ARC/atomicArc、小二进制、强宏能力、直接 C/ObjC FFI。
- **MyGo 的形态**：系统 WebView、类型化 Go↔TS IPC、自绘原生 UI、完整桌面 API。
- **目标**：在 Nim 里得到同样的低开销、单二进制、跨平台桌面开发体验。

Nimi 不是 Go 源码兼容层，也不是 MyGo 的分支维护；它是一个独立的 Nim 重实现。

## 快速开始

需要 Nim 2.4+。macOS 需要 12+ 与 Xcode Command Line Tools；Linux 需要 GTK3
（原生 UI）与可选 WebKitGTK 4.1（页面窗口）；Windows 需要 WebView2 Runtime。

```sh
git clone https://github.com/zhimoe/nimi.git
cd nimi

# 构建 CLI
nim c -o:nimi src/nimi/cli.nim

# WebView + 类型化 IPC
./nimi generate examples/hello
./nimi dev examples/hello

# 原生 UI：无 HTML，CoreGraphics/CoreText 自绘
nim c -r --path:src examples/counter-native/main.nim

# 打包（macOS 产出 .app + DMG）
./nimi build examples/hello
open "examples/hello/dist/darwin-arm64/Hello Nimi.app"
```

Linux 桌面依赖（Ubuntu 24.04）：

```sh
sudo apt install libgtk-3-0t64 libwebkit2gtk-4.1-0 \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good
./scripts/test-linux.sh
```

macOS 运行测试：`./scripts/test.sh`。Windows 使用 `nimi build` 生成 exe 与
manifest；WebView2 Runtime 缺失时页面窗口会给出明确错误。

## 示例

| 示例 | 内容 |
|---|---|
| [`hello`](examples/hello) | WKWebView/WebView2/WebKitGTK 页面、bridge、类型化 IPC |
| [`counter-native`](examples/counter-native) | 原生布局、鼠标、键盘、Tab/Enter、Tester |
| [`widgets-native`](examples/widgets-native) | Checkbox、Switch、Slider、Progress、Image、ScrollView |
| [`form-native`](examples/form-native) | TextInput/TextArea、菜单、文件/消息对话框、IME |
| [`desktop-native`](examples/desktop-native) | 屏幕、主题、窗口、托盘、通知、快捷键、Now Playing |
| [`protocol-native`](examples/protocol-native) | 自定义 `nimi://` scheme 与 FileServer |
| [`watch-native`](examples/watch-native) | 文件监视（FSEvents / inotify / ReadDirectoryChangesW） |
| [`document-native`](examples/document-native) | Document 生命周期、保存、冲突与外部修改 |
| [`notes`](examples/notes) | WebView-first 完整应用：Markdown、搜索、自动保存、打包 |
| [`music`](examples/music) | 原生 UI + 音频 + 队列/会话 + Subsonic |
| [`environment`](examples/environment) | Windows 环境变量工具与桌面集成 |
| [`shredder`](examples/shredder) | WebGL 碎纸效果 + Nim Verlet 物理 |
| [`shred-native`](examples/shred-native) | CoreGraphics/GDI 纹理四边形与帧驱动 |
| [`shred-metal`](examples/shred-metal) | Metal mask/LayerEffect |

完整清单与验收路径见 [examples/README.md](examples/README.md)。

## 文档

| 文档 | 内容 |
|---|---|
| [可行性分析](docs/00-feasibility.md) | 代码规模、Nim 能力评估、原型结果与工作量 |
| [架构设计](docs/01-architecture.md) | 分层、线程/内存模型、平台契约、IPC、原生 UI |
| [macOS 后端](docs/02-macos-backend.md) | ObjC runtime、AppKit、WKWebView、Surface、CoreText、打包 |
| [原生 UI](docs/03-native-ui.md) | Element/arena、布局、scene、文本、输入、控件、Tester |
| [工具链与 IPC](docs/04-tooling-and-ipc.md) | CLI、配置、TS 生成、打包、插件与测试 |
| [实施路线图](docs/05-roadmap.md) | M0–M10、范围与验收标准 |
| [Windows/Linux](docs/06-windows-linux.md) | Win32/WebView2、GTK3/WebKitGTK 与跨平台设计 |
| [API 映射](docs/07-api-mapping.md) | MyGo → Nimi 命名与语义对照 |
| [Backlog](docs/backlog/README.md) | Preview 版本范围、平台差异与后续工作 |
| [文档索引](docs/README.md) | 所有设计、实现、验证与平台文档 |

建议阅读顺序：`00 → 01 → 05 → 02/03 → 04 → 06 → 07`。

## 仓库结构

```text
nimi/
├── docs/                   # 设计、实现与 backlog
│   └── backlog/            # Preview 版本范围与平台差异
├── site/                   # 官网（GitHub Pages）
├── src/nimi/
│   ├── core/               # app/window/ipc/loop/events/bridge/content/menu/dialog
│   ├── platform/
│   │   ├── contract.nim    # 平台契约
│   │   ├── darwin/         # ObjC/AppKit/WKWebView/CoreGraphics/CoreText
│   │   ├── windows/        # Win32/WebView2/GDI/IME/menu/tray/watch
│   │   └── linux/          # GTK3/Cairo/Pango/WebKitGTK/menu/clipboard/watch
│   ├── scene/              # rect/text/clip/image/imageQuad/polygon display list
│   ├── render/             # cg / cairo / gdi / metal
│   ├── text/               # CoreText / Pango / GDI 测量与换行
│   ├── effects/            # 可复用效果（碎纸物理等）
│   ├── ui/                 # Context/控件/Tester
│   └── cli.nim             # init/generate/dev/build/doctor
├── tests/                  # IPC/loop/ui/render/desktop/platform 测试
├── examples/               # 可运行验收示例
└── spikes/                 # 可行性原型
```

公开仓库不包含 `mygo/`。本地开发时可把 MyGo v0.10.0 的只读副本放在
`mygo/` 用于架构对照；当前能力盘点快照是 `9b0ae9ef`。

## 许可与致谢

- Nimi 的 JS bridge、TypeScript 运行时、协议、模板与文档设计参考自
  [MyGo](https://github.com/egoist/mygo)，MIT License，
  Copyright (c) 2026 MyGo contributors。
- MyGo 的架构思想（分层、主线程调度、typed IPC、scene display list、
  CPU/GPU 双渲染器）是 Nimi 的基础。
- Nimi 自身代码计划采用 MIT License（待定稿）。
