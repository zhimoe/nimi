# Nimi

**用 Nim 重实现 [MyGo](https://github.com/egoist/mygo) 的桌面应用框架。**

> 官网：<https://nimi.zhi.moe> · 仓库：<https://github.com/zhimoe/nimi>
>
> **Preview**：macOS、Windows、Linux 三平台均可运行。API 仍可能调整；
> 查看 [平台能力与验证](docs/28-remediation-status.md)、[实施路线图](docs/05-roadmap.md#当前执行计划) 和 [项目 backlog](docs/backlog/README.md)。

Nimi 保留 MyGo 的架构与开发体验——系统 WebView + 类型化 IPC + 自绘原生 UI +
一套桌面 API——但用 Nim 编写，不依赖 cgo，也不依赖 Go 运行时。

## Preview 能力

- **三平台后端**：macOS（AppKit / WKWebView / CoreGraphics / CoreText）、
  Windows（Win32 / WebView2 / GDI）、Linux（GTK3 / WebKitGTK / Cairo / Pango）。
- **两条 UI 路径**：系统 WebView 承载页面，或完全自绘的原生 UI；两者共享窗口生命周期、
  菜单和事件。原生 UI 提供布局、滚动、文本输入和 Tester。
- **类型化与流式 IPC**：`bindService`、`bindBackground`、流式分块（`sendChunk` / `stream`）、`AbortSignal` 单请求取消、跨线程事件推送（`emitWindow` / `broadcastPage`）、secret/token，以及覆盖结构体/枚举/可选/数组的编译期 TypeScript 类型生成。
- **桌面 API 与宿主基建**：菜单与原生右键弹出菜单（`popupMenu`）、托盘、通知、全局快捷键、文件对话框、剪贴板、屏幕、主题、Now Playing、登录项、单实例/深链、降噪文件监视、VFS 静态内嵌与多挂载点 `FileServer`、OS Shell 集成（`nimi/shell`）、规范化数据目录与便携模式（`nimi/paths`）、脱敏滚动日志（`nimi/log`）、窗口尺寸位置记忆（`autosaveName`）及平台能力探针（`app.supports`）。
- **打包与跨平台构建**：macOS `.app`（自动捆绑第三方 `.dylib`） / DMG / 签名与公证钩子，Windows exe / manifest / `zig cc` 交叉编译绿色版与 Inno Setup 脚本，Linux `.desktop` / `.deb`。
- **验证**：本地 macOS 192 项、Ubuntu 24.04 容器 200 项自动化测试通过。Windows CI 运行原生回归，另有 Windows 11 ARM64 虚拟机的部分 GUI 验证。构建和人工验收记录见 [开发基线](docs/28-remediation-status.md#自动化与实机验收)。

## 为什么

- **Nim 的形态**：编译为 C、ARC/atomicArc、小二进制、强宏能力、直接 C/ObjC FFI。
- **MyGo 的形态**：系统 WebView、类型化 Go↔TS IPC、自绘原生 UI、完整桌面 API。
- **目标**：在 Nim 里得到同样的低开销、单二进制、跨平台桌面开发体验。

Nimi 不是 Go 源码兼容层，也不是 MyGo 的分支维护；它是一个独立的 Nim 重实现。

## 快速开始

需要 Nim 2.4+ 和 C 工具链。下列命令从仓库根目录运行。

| 平台 | 环境 |
|---|---|
| macOS | macOS 12+、Xcode Command Line Tools |
| Windows | GCC/MinGW 工具链。运行网页窗口需要 WebView2 Runtime。 |
| Linux | GTK3 和桌面会话。运行网页窗口需要 WebKitGTK 4.1（后端也支持 4.0）。 |

### macOS / Linux

```sh
git clone https://github.com/zhimoe/nimi.git
cd nimi
nim c -o:nimi src/nimi/cli.nim
./nimi doctor

# WebView + 类型化 IPC
./nimi generate examples/hello
./nimi dev examples/hello

# 原生 UI
nim c -r --path:src examples/counter-native/main.nim

# 在当前平台打包
./nimi build examples/hello
```

Ubuntu 24.04 运行示例所需的常用依赖：

```sh
sudo apt install libgtk-3-0t64 libwebkit2gtk-4.1-0 libnotify4 \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good
```

### Windows PowerShell

```powershell
git clone https://github.com/zhimoe/nimi.git
cd nimi
nim c -o:nimi.exe src/nimi/cli.nim
.\nimi.exe doctor
.\nimi.exe generate examples/hello
.\nimi.exe dev examples/hello
nim c -r --path:src examples/counter-native/main.nim
.\nimi.exe build examples/hello
```

默认构建目录为 `examples/hello/dist/<平台>-<架构>/`。macOS 输出 `.app` 和 DMG，Windows 输出 exe 和 WebView2 Loader 并嵌入 manifest，Linux 输出程序和 `.desktop`，装有 `dpkg-deb` 时也生成 `.deb`。

macOS 使用 `./scripts/test.sh`。Linux headless 依赖和 Windows CI 测试入口见 [验证指南](examples/README.md#自动化验证)。

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
| [`shred-native`](examples/shred-native) | CoreGraphics/GDI/Cairo 纹理四边形与帧驱动 |
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
| [实施路线图](docs/05-roadmap.md) | 当前执行顺序、验收条件与 M0–M10 历史范围 |
| [开发基线](docs/28-remediation-status.md) | 平台能力矩阵与 CI / 实机验证记录 |
| [Windows/Linux](docs/06-windows-linux.md) | Win32/WebView2、GTK3/WebKitGTK 与跨平台设计 |
| [API 映射](docs/07-api-mapping.md) | MyGo → Nimi 命名与语义对照 |
| [Backlog](docs/backlog/README.md) | Preview 版本范围、平台差异与后续工作 |
| [文档索引](docs/README.md) | 所有设计、实现、验证与平台文档 |

从 [文档索引](docs/README.md) 查找使用指南、平台细节和历史设计。

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
- Nimi 自身代码采用 [MIT License](LICENSE)。
