# Nimi 示例与验证

在仓库根目录运行 `nim c -r --path:src examples/<示例>/main.nim`。也可用
`./nimi dev examples/<示例>`（Windows PowerShell 用 `.\nimi.exe`）。
各示例的 GUI 和系统集成依赖 [平台运行环境](../README.md#快速开始)。

| 示例 | 验证内容 |
|---|---|
| [hello](hello) | 三平台 WebView、类型化 IPC 和页面事件 |
| [counter-native](counter-native) | 原生 UI、布局、键鼠、Tester |
| [form-native](form-native) | TextInput/TextArea、菜单、对话框和原生 IME |
| [widgets-native](widgets-native) | Checkbox、Switch、Slider、Progress、Image、ScrollView |
| [protocol-native](protocol-native) | 自定义 `nimi://` 协议与 FileServer |
| [watch-native](watch-native) | FSEvents、ReadDirectoryChangesW、inotify |
| [document-native](document-native) | 文档状态、保存、重载和外部冲突 |
| [desktop-native](desktop-native) | 各平台的显示、主题、托盘、快捷键等桌面 API |
| [environment](environment/README.md) | Windows 环境变量、注册表、UAC 和原生 UI |
| [notes](notes/README.md) | WebView Markdown 笔记、IPC、原生菜单和导入导出 |
| [music](music/README.md) | macOS/Linux 本地音频、媒体控制、队列和 Subsonic |
| [shredder](shredder) | WebView/WebGL 与 Nim 碎纸物理 |
| [shred-native](shred-native) | CoreGraphics/GDI/Cairo 纹理四边形与帧驱动 |
| [shred-metal](shred-metal) | macOS Metal mask 与 LayerEffect |

Image 和 ScrollView 演示位于 `widgets-native`。沿用 `NIMI_SMOKE=image` 和
`NIMI_SMOKE=scroll` 触发对应路径。

## 自动化验证

| 平台 | 测试与 CI 构建 |
|---|---|
| macOS | `./scripts/test.sh`。CI 构建并校验 `desktop-native`、`protocol-native`、`notes`、`music`、`shred-native`、`shred-metal` 的 DMG。 |
| Windows | [Windows workflow](../.github/workflows/windows.yml) 运行原生测试并构建 `hello` 与 `environment`。用 Zig 执行 `./scripts/windows-cross-build.sh amd64` 或 `./scripts/windows-cross-build.sh arm64` 验证交叉编译。 |
| Linux | `./scripts/test-linux.sh`。无显示环境时用 Xvfb + D-Bus，安装依赖见 [Linux 后端](../docs/33-linux-framework.md#31-本地)。CI 构建 `counter-native`、`widgets-native`、`desktop-native`、`hello`、`notes`、`shred-native` 并检查 `.deb`。 |

各平台最近一次 CI 结果与人工验收项见 [开发基线](../docs/28-remediation-status.md#自动化与实机验收)。
