# Nimi

**用 Nim 重实现 [MyGo](https://github.com/egoist/mygo) 的桌面应用框架。**

> 官网:<https://nimi.zhi.moe> · 仓库:<https://github.com/zhimoe/nimi>

Nimi 的目标是保留 MyGo 的架构与开发体验——系统 WebView + 类型化 IPC + 自绘原生 UI + 一套桌面 API——但用 Nim 编写,不依赖 cgo,不依赖 Go 运行时。

> 当前状态:**M1 核心已实现**(macOS WebView + typed IPC + TS 生成 + CLI + hello);
> **M2 核心切片已跑通**(原生 NSView Surface + CoreGraphics/CoreText + 布局/Text/Button + 鼠标/键盘/焦点 + 多行换行 + `Tester`/离屏 PNG + `counter-native`)。
> **M3 控件、M4 macOS 桌面 API(菜单/对话框/剪贴板/屏幕/主题/窗口/托盘/通知/全局快捷键)、M5 自定义 `nimi://` FileServer/深链/Session/文件监视/Cookie、M6 单行 TextInput、M7 `.app`/DMG/签名/CI**已落地;`examples/desktop-native` 是桌面 API 验收,`examples/form-native` 是原生 GUI 验收,`examples/notes` 是 WebView-first 的完整笔记应用,`examples/protocol-native` 是自定义协议验收。其余差距见 [M3–M7 状态](docs/11-m3-m7-status.md)。
> Windows/Linux 在 M8/M9。
> 参考实现:MyGo 0.7.4(MIT License)。

---

## 为什么

- **Nim 的形态**:编译为 C、无 GC 停顿(ARC/atomicArc)、小二进制、强宏能力、直接 C/ObjC FFI。
- **MyGo 的形态**:系统 WebView(WKWebView / WebView2 / WebKitGTK)、类型化 Go↔TS IPC、自绘原生 UI、完整桌面 API、可打包分发。
- **目标**:在 Nim 里得到同样的低开销、单二进制、跨平台桌面开发体验。

## 不是什么

- 不是 Go 源码兼容层。现有 Go 应用不能不改代码编译成 Nimi。
- 不是 MyGo 的分支维护;是独立的 Nim 重实现。
- 不是 Electron 替代品的营销项目;是一个长期工程,按里程碑推进。

---

## 文档

| 文档 | 内容 |
|---|---|
| [可行性分析](docs/00-feasibility.md) | 代码规模、Nim 能力评估、7 个原型结果、风险、工作量、Go/No-Go |
| [架构设计](docs/01-architecture.md) | 分层、模块布局、线程/内存模型、平台契约、IPC、原生 UI、构建 |
| [macOS 后端](docs/02-macos-backend.md) | ObjC runtime、AppKit、WKWebView、Surface、Metal、CoreText、打包 |
| [原生 UI](docs/03-native-ui.md) | Element/arena、布局缓存、scene、文本、输入、控件优先级、Tester |
| [工具链与 IPC](docs/04-tooling-and-ipc.md) | CLI、配置、模板、TS 生成、打包、更新、插件、测试 |
| [实施路线图](docs/05-roadmap.md) | M0–M10、任务清单、验收标准、估算、风险 Gate |
| [Windows/Linux](docs/06-windows-linux.md) | Win32/WebView2/D3D11、GTK3/WebKitGTK/GL、交叉编译 |
| [API 映射](docs/07-api-mapping.md) | MyGo → Nimi 命名/语义/常用 API 对照 |
| [M1 实现状态](docs/08-m1-notes.md) | 已实现内容、崩溃修复、已知限制、下一步 |
| [Nim 实践参考](docs/09-nim-practices.md) | 采用的 Nim 工程规范、与 planetis-m/skills 的对应 |
| [M2 实现状态](docs/10-m2-notes.md) | 原生 Surface + 布局/控件/输入/焦点/换行 + Tester/PNG + counter、决策、限制 |
| [M3–M7 状态](docs/11-m3-m7-status.md) | 控件/菜单/对话框/TextInput/DMG;M5 与剩余项 |
| [macOS 桌面 API](docs/14-macos-desktop-apis.md) | 屏幕/主题/窗口/托盘/通知/快捷键/对话框;决策与限制 |
| [M5 FileServer](docs/15-m5-file-server.md) | 自定义 `nimi://` scheme、本地资源服务、打包资源复制 |
| [M5 文件监视](docs/16-m5-file-watching.md) | FSEvents、文件事件、去抖/忽略规则后续 |
| [M5 Cookies](docs/17-m5-cookies.md) | 默认数据存储的 Cookie 查询/清理、异步回调 |
| [macOS CI](docs/18-macos-ci.md) | GitHub Actions 测试/构建/DMG artifact、架构输出 |
| [Nimi Notes 验收](docs/12-notes-demo.md) | WebView-first 笔记应用:IPC/菜单/导入导出/自动保存/打包 |
| [官网与 Pages](docs/13-website.md) | 静态站点结构、自定义域名 `nimi.zhi.moe`、DNS 与部署工作流 |

建议阅读顺序:`00 → 01 → 05 → 02/03 → 04 → 06 → 07`。

---

## 可行性结论(摘要)

MyGo 非测试 Go 代码约 **32.3 万行**,测试约 **13.9 万行**。完整 1:1 移植是三平台 2–3 年的单人工作量;但 macOS 关键路径已全部验证:

| 原型 | 验证 | 结果 |
|---|---|---|
| `spikes/objc_hello` | ObjC runtime + NSWindow + 运行时类 + 事件循环 | ✅ 窗口显示,1 秒后退出 |
| `spikes/wkwebview` | WKWebView + JS→Nim 消息 + eval | ✅ `JS -> Nim: {hello = "from the page"; n = 42}` |
| `spikes/coretext` | CoreText 混排 + CG 位图 + PNG | ✅ 拉丁/中日韩/阿拉伯 |
| `spikes/nim_meta` | 宏生成 TS + JSON | ✅ `greet(name: string...): Promise<string>` |
| `spikes/metal` | CAMetalLayer + clear pass | ✅ 20 帧上屏 |
| `spikes/blocks` | 纯 Nim 构造 ObjC block | ✅ `result=answer: 42` |
| `spikes/threads` | arc/orc/atomicArc/yrc 跨线程 | ✅ 四种 MM 均通过 |

**推荐路线**:WebView-first → 原生 UI 基础 → 控件广度 → 桌面 API → 文本编辑/IME → 打包 → Windows → Linux。

**推荐内存模型**:`--mm:atomicArc` + 禁止所有权环 + 跨线程只传值。
**推荐渲染路线**:CoreGraphics CPU 先行 → Metal 第二 → 可移植 raster / GL / D3D11。
**推荐文本路线**:CoreText / DirectWrite / Pango,不移植 MyGo 的纯 Go 文本引擎。

---

## 快速开始(M1)

需要 Nim 2.4+、macOS 12+、Xcode Command Line Tools。

```sh
# 构建 CLI
nim c -o:nimi src/nimi/cli.nim

# 最小示例:WKWebView 页面调用 Nim 方法
./nimi generate examples/hello
./nimi dev examples/hello        # 关闭窗口退出

# 原生 UI:无 HTML,CoreGraphics/CoreText 自绘
nim c -r --path:src examples/native-smoke/main.nim

# M3 控件:Checkbox/Switch/Slider/Progress/Divider
nim c -r --path:src examples/widgets-native/main.nim

# macOS 桌面 API:屏幕/主题/窗口/托盘/通知/全局快捷键
nim c -r --path:src examples/desktop-native/main.nim

# 自定义协议:从 nimi:// 加载 HTML/CSS/JS
nim c -r --path:src examples/protocol-native/main.nim

# FSEvents 文件监视
nim c -r --path:src examples/watch-native/main.nim

# 基本 GUI 应用:TextInput + 控件 + 菜单 + 文件/消息对话框
nim c -r --path:src examples/form-native/main.nim

# WebView-first 完整应用:Markdown 笔记 + 原生菜单 + 导入/导出
nim c -r --path:src examples/notes/main.nim

# 原生交互 counter:Column/Row/Text/Button + 鼠标/方向键/Tab+Enter
nim c -r --path:src examples/counter-native/main.nim

# 打包 .app(用 Finder 或 open 启动)
./nimi build examples/hello
open "examples/hello/dist/darwin-arm64/Hello Nimi.app"

# 单元测试
./scripts/test.sh
```

`NIMI_SMOKE=quit|calls|close` 是 hello 示例的测试开关,分别测试单次调用后退出、50 次连续调用后退出、关窗退出。`nimi dev` 会监听项目源文件,修改后自动重建重启。

> `.app` 请通过 Finder 或 `open` 启动;直接 exec 包内二进制会触发 macOS 的 bundle/LaunchServices 行为而立即退出,不是应用崩溃。详见 [M1 笔记](docs/08-m1-notes.md)。

## 仓库结构

```text
nimi/
├── docs/                  # 设计文档
├── site/                  # 官网(GitHub Pages)
├── src/nimi/              # 实现
│   ├── core/              # app/window/page/ipc/loop/events/bridge/content/menu/dialog/clipboard
│   ├── platform/
│   │   ├── contract.nim   # 平台契约
│   │   └── darwin/        # objc/app/window/types/menu/dialogs/clipboard
│   ├── scene/             # rect/text display list
│   ├── render/cg.nim      # CoreGraphics + CoreText
│   ├── text/measure.nim   # CoreText 测量/换行
│   ├── ui/                # Context/Tester
│   └── cli.nim            # init/generate/dev/build/doctor
├── tests/                 # test_ipc/test_loop/test_ui/test_render
├── examples/
│   ├── hello/             # WebView + IPC 验收
│   ├── native-smoke/      # 原生 Surface 验收
│   ├── counter-native/    # 原生布局/控件/点击验收
│   ├── widgets-native/    # M3 控件验收
│   ├── form-native/       # 原生 GUI 应用验收
│   ├── desktop-native/    # macOS 桌面 API 验收
│   ├── protocol-native/   # 自定义 nimi:// 协议验收
│   ├── watch-native/      # FSEvents 文件监视验收
│   └── notes/             # WebView-first 笔记应用验收
└── spikes/                # 可行性原型(可运行)
    ├── objc_hello/
    ├── wkwebview/
    ├── coretext/
    ├── nim_meta/
    ├── metal/
    ├── blocks/
    └── threads/
```

公开仓库不包含 `mygo/`。本地开发时可把 MyGo 0.7.4 的只读副本放在 `mygo/`,用于对照架构与 API。

---

## 运行原型

需要 Nim 2.4+、macOS 12+、Xcode Command Line Tools。

```sh
# 1. 最小 AppKit 窗口
cd spikes/objc_hello
nim c -r --mm:orc spike.nim

# 2. WKWebView + JS→Nim
cd ../wkwebview
nim c -r --mm:orc spike_webview.nim

# 3. CoreText 渲染
cd ../coretext
nim c -r --mm:orc spike_coretext.nim
open coretext.png

# 4. 宏生成 TS / JSON
cd ../nim_meta
nim c -r --mm:orc spike_meta.nim

# 5. Metal clear pass
cd ../metal
nim c -r --mm:orc spike_metal.nim

# 6. ObjC block
cd ../blocks
nim c -r --mm:orc spike_blocks.nim

# 7. 线程/内存模型
cd ../threads
nim c -r --threads:on --mm:atomicArc spike_threads.nim
```

原型会短暂打开窗口,然后自动退出。

---

## 里程碑(单人全职,±50%)

| 里程碑 | 内容 | 工期 |
|---|---|---|
| M0 | 可行性原型 | ✅ 已完成 |
| M1 | Core + macOS WebView + IPC + `hello` | 6–10 周 |
| M2 | 原生 UI 基础 + `counter-native` | 8–12 周 |
| M3 | 控件/布局/滚动 + Metal 起步 | 10–16 周 |
| M4 | 桌面 API | 8–12 周 |
| M5 | 文档/会话/Cookie/协议/监视 | 8–12 周 |
| M6 | 文本编辑/IME/可访问性/Metal 完整 | 12–20 周 |
| M7 | 打包/签名/公证/更新 | 6–10 周 |
| M8 | Windows | 4–8 月 |
| M9 | Linux | 4–8 月 |

macOS 可用版本约 4–6 个月;广泛兼容约 14–21 个月;三平台约 2–3 年。

---

## 许可与致谢

- Nimi 的 JS bridge、TypeScript 运行时、协议、模板与文档设计参考自 [MyGo](https://github.com/egoist/mygo),MIT License,Copyright (c) 2026 MyGo contributors。
- MyGo 的架构思想(分层、主线程调度、typed IPC、scene display list、CPU/GPU 双渲染器)是 Nimi 的基础。
- Nimi 自身代码计划采用 MIT License(待定稿)。

---

## 下一步

1. Nimi Notes:SQLite/FTS、多窗口、原生确认框、生成 TS 接入打包。
2. M3 剩余:更多控件、Metal、动画、可访问性。
3. M4 剩余:通知权限/点击、托盘图标、快捷键冲突提示、剪贴板图片/文件。
4. M6 剩余:选择/撤销/剪贴板、TextArea、IME、富文本、完整 Metal/可访问性。
5. M5 剩余:Cookie 写入/删除/并发、文档控制器、单实例边界/文件关联。
6. M7 剩余:自动更新、release workflow、DMG 背景、实际公证。
7. 每个里程碑以可运行示例与测试验收。
8. CloudMusic demo:将 MyGo 云音乐案例移植为 Nimi 示例;源目录
   `mygo-cloudmusic/` 暂不纳入仓库,待评估音频、列表/滚动、图片与网络能力后单独排期。

参见 [实施路线图](docs/05-roadmap.md) 与 [M1 实现状态](docs/08-m1-notes.md)。
