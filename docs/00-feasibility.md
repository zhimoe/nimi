# Nimi 可行性分析:用 Nim 重实现 MyGo

> 2026-11-06 重评：本文包含目标设计，不能作为当前 API/线程安全/兼容性承诺。实现边界与后续验收以 [整改基线](28-remediation-status.md) 为准；历史工期不作为剩余工期。

> 状态:草案 · 日期:2026-11-04 · 范围:macOS 优先,Windows/Linux 后续
> 参考实现:`/Users/zhimoe/code/nimi/mygo`(稳定基线 MyGo v0.8.3 `5add3817`;本地能力盘点快照 `f234638d`,MIT License)
> 验证代码:`/Users/zhimoe/code/nimi/spikes/`(7 个可运行的 Nim 原型)

---

## 1. 目标与"fork"的定义

### 1.1 目标

用 Nim 重实现 MyGo 的完整能力,形成一个独立的桌面应用框架 **Nimi**(暂定名,取自工作目录):

- **WebView 窗口**:使用系统 WebView(macOS WKWebView / Windows WebView2 / Linux WebKitGTK),页面通过类型化 IPC 调用 Nim 代码。
- **原生 UI 窗口**:不依赖 HTML/JS,由 Nimi 自己布局、绘制、处理输入和文本。
- **桌面 API**:窗口、菜单、托盘、对话框、通知、剪贴板、全局快捷键、深链、文件关联、最近文档、文件监视等。
- **工具链**:项目模板、开发服务器、TypeScript 客户端生成、构建、签名、公证、打包、自动更新。
- **平台顺序**:macOS 完整落地 → Windows 底层 → Linux 底层。

### 1.2 什么是"fork",什么不是

Go 和 Nim 无法做到源码级兼容。这里的 fork 是**架构与行为层面的重实现**,不是把 `.go` 文件逐行翻译成 `.nim`。明确保留与放弃的东西:

| 保留(兼容目标) | 放弃(不做源码兼容) |
|---|---|
| 分层架构:core → platform contract → backend | Go 包路径、`go.mod`、Go 类型/接口签名 |
| 公开 API 的语义、生命周期、事件顺序 | Go 的 `reflect`、`context.Context`、goroutine/channel 语义 |
| JSON IPC 线协议、secret/token、Channel 流控 | `mygo-runtime` 的包名(计划改为 `nimi-runtime`,保留兼容别名) |
| 生成的 TypeScript 客户端形态与命名规则 | Go 的 `encoding/json/v2` 全部边角行为(按需兼容) |
| 配置字段、构建产物、打包/签名流程 | `mygo.config.ts` 求值器的实现方式(可用 `nimi.config.nims`) |
| 示例应用作为一致性测试语料 | 插件二进制兼容、Go 插件源兼容 |

> **关键判断**:如果目标是"现有 MyGo 应用不改代码就能用 Nim 编译",那不可行;如果目标是"同样的应用形态、同样的前端协议、类似的心智模型,用 Nim 重写",则完全可行。本方案按后者设计。

### 1.3 非目标(v0.1)

- Windows/Linux 后端(先留接口与桩)。
- 浏览器/wasm 后端。
- CEF 内置浏览器。
- 官方插件全家桶(terminal、glass、game、sqlite、updater 等)。
- 与 Go 版双向互操作、插件 ABI 兼容。
- 移动端。

---

## 2. MyGo 现状盘点

### 2.1 代码规模

```text
非测试 Go 代码:373,636 行 / 1,064 个文件
测试 Go 代码:  167,402 行 / 752 个文件
```

统计日期 2026-11-09，基于本地 `mygo/` HEAD `f234638d`；排除 `_test.go`、`testdata`、`.git`、`node_modules`、`dist`。自 v0.7.4 起增加 328 个提交，能力面明显扩大，详见 [MyGo 能力对照](30-mygo-alignment.md)。

| 区域 | 非测试行数 | 说明 |
|---|---:|---|
| `internal/` | 156,360 | 平台后端、GPU、文本、场景、着色器、TS 生成、更新、E2E |
| `ui/` | 104,795 | 原生 UI 根包 67,985；editor、markdown、richtext、video、chart、shader |
| `plugins/` | 32,274 | terminal、glass、updater、permissionflow、loading、automation、sqlite、game、sfsymbols 等 |
| 根包 `mygo` | 22,102 | 公开 API、生命周期、IPC、菜单、协议、文档、会话 |
| `examples/` | 16,248 | 38 个示例,可作为移植验收语料 |
| `cmd/mygo` | 15,777 | CLI:init/generate/dev/build/doctor/native/打包/签名/更新 |
| `i18n/` | 17,261 | 语言匹配、CLDR、消息格式、目录、代码生成 |
| `audio/` | 4,889 | 播放器、混音、流式解码、WAV/MP3/Vorbis/FLAC/AAC/ALAC、平台输出 |
| `native/` + `ffi/` | 3,460 | Swift/Rust/Zig 原生模块、无 cgo 的 C 库绑定 |

`internal/` 的主要构成:

| 子包 | 行数 | 作用 |
|---|---:|---|
| `gpu/` | 35,548 | Metal / D3D11 / GL / WebGL2 渲染器与实例格式 |
| `windows/` | 22,809 | Win32 + WebView2 + COM |
| `linux/` | 16,825 | GTK3 + WebKitGTK + dlopen |
| `darwin/` | 15,975 | AppKit + WKWebView + ObjC runtime |
| `text/` | 11,985 | 字体、shaping、断行、编辑、字形栅格化 |
| `nativegen/` | 7,201 | Swift/Rust/Zig 原生模块生成与桥接 |
| `shader/` + `shaderir/` | 11,327 | Go 语法着色器编译器及其 IR/GLSL/HLSL/MSL/解释器 |
| `platform/` | 4,084 | 后端契约 |
| `svg/` | 3,370 | SVG 解析与绘制 |
| `raster/` | 3,042 | CPU 场景渲染器 |
| `l10n/` | 2,986 | 语言/区域格式 |
| `web/` | 2,500 | 浏览器 wasm + WebGL2 后端 |
| `scene/` | 2,476 | display list、字形图集 |
| `fake/` | 2,130 | 单元测试用内存后端 |

`ui/` 子包:editor 16,690、markdown 8,359、richtext 6,635、video 2,545、chart 1,735、shader 846。

### 2.2 架构要点

MyGo 的分层非常清晰,这是重实现最大的有利条件:

```text
用户代码 ──► package mygo ──► platform.Backend ──► darwin | linux | windows | web
                ▲    │              ▲
                │    └─ handlers ───┘
 page (JS) ◄── bridge.js ◄── Eval ─┘
     └──── postMessage(JSON) ──► WindowHandler.Message
```

- **核心策略在 `package mygo`**:默认值、窗口注册表、事件、退出流程、IPC 路由、菜单、协议、信任检查。不直接调用原生 API。
- **`internal/platform` 是同步、主线程专属的窄契约**:`Backend`、`Window`、`Surface`、`AppHandler`、`WindowHandler`。后端只做翻译,不发明策略。
- **线程模型**:
  - 主 goroutine 锁定主线程,`App.Run` 在其中跑原生事件循环。
  - 所有 `platform.*` 调用与回调都在主线程。
  - 公开方法任意 goroutine 安全:`postMain` / `onMain` / `await` + `Backend.Step` 泵事件。
  - 事件监听器同步跑主线程;绑定方法各自 goroutine,可阻塞。
- **无 cgo**:macOS/Linux 通过 purego `dlopen` + 汇编 trampoline 调原生库;Windows 通过 `syscall` + COM vtable。所有平台可从任意机器交叉编译。
- **两种窗口**:
  - WebView:WKWebView / WebKitGTK 4.1 / WebView2,系统自带,不捆绑浏览器。
  - 原生 UI:`ui` 包构建 → `internal/scene` → Metal/D3D11/GL/CPU raster;文本走 CoreText/DirectWrite/Pango。
- **IPC**:页面端 `window.mygo` → `postMessage(secret + JSON)` → 后端消息处理器 → 主线程路由;绑定方法在独立 goroutine 执行;Channel 有 1 MiB 窗口和半窗口 ack;事件在 DOM ready 前最多保留 1024 条。
- **TS 生成**:`Bind`/`NewEvent` 在 Go 反射层登记类型;`mygo generate` 构建宿主并以 `MYGO_GENERATE` 运行,`App.Run` 只写客户端后返回;`internal/tsgen` 用反射 + `go/parser` 还原参数名、注释、常量枚举,输出 `mygo-runtime` 客户端。

### 2.3 许可证

MIT License,Copyright (c) 2026 MyGo contributors。允许 fork、修改、再发布,需保留版权与许可声明。JS bridge、`mygo-runtime`、模板、文档、示例均可复用/改写。

---

## 3. Nim 能力评估

### 3.1 结论先行

**技术可行,关键路径已用可运行原型验证。** 主要成本在"广度"而不是"未知技术":

- Nim 2.4 的 C ABI、宏、线程、内存管理足以支撑这个框架。
- macOS 最难的五件事——ObjC runtime 调用、运行时类/回调、WKWebView + JS 消息、CoreText 混排、Metal 上屏——全部在原型中跑通。
- Objective-C block 也可以直接在 Nim 中构造,不需要任何 `.m` shim。
- 主要缺口是现成的 WebView2/GTK 绑定与原生 UI 控件库,这些需要自建,但 MyGo 的 Go 实现可以作为逐行参考。

### 3.2 逐项评估

| 能力 | Nim 支持 | 验证 | 结论 |
|---|---|---|---|
| C ABI 调用 | `importc` / `dynlib` / `{.cdecl.}` / by-value struct | 7 个原型 | ✅ 成熟 |
| Objective-C runtime | `objc_getClass` / `sel_registerName` / `objc_msgSend` 强转函数指针 | AppKit 窗口、WKWebView | ✅ 可行 |
| 运行时定义 ObjC 类 | `objc_allocateClassPair` + `class_addMethod` + Nim `{.cdecl.}` 回调 | 窗口 delegate、WKScriptMessageHandler | ✅ 可行 |
| Objective-C block | 手工构造全局 block literal(`_NSConcreteGlobalBlock` + invoke) | WKWebView `evaluateJavaScript:completionHandler:` | ✅ 可行 |
| AppKit 事件循环 | `NSApplication run` + `NSTimer` / CFRunLoopSource | 窗口 1 秒后退出 | ✅ 可行 |
| WKWebView | `loadHTMLString:` + 导航 delegate + script message handler | 页面 JS → Nim,返回值回传 | ✅ 可行 |
| CoreText / CoreGraphics | C API,CTLine/CTFont/CGBitmapContext | 拉丁/中日韩/阿拉伯混排,PNG 输出 | ✅ 可行 |
| Metal | ObjC API + `CAMetalLayer`;shader 可预编译 `.metallib` | 20 帧 clear pass 上屏 | ✅ 可行 |
| 线程 | `--threads:on` + `std/typedthreads` + `std/locks` | arc/orc/atomicArc/yrc 均通过 | ✅ 可行 |
| 内存管理 | ARC/ORC/atomicArc/YRC 可选 | 跨线程 ref 实测 | ⚠️ 需选型(见 §5.4) |
| 编译期反射 | `std/macros`、`getTypeImpl`、`getImpl` | 从 proc 签名生成 TS 接口 | ✅ 可行 |
| JSON | `std/json` / `jsonutils` / 第三方 `jsony` | 对象序列化往返 | ✅ 可行 |
| 交叉编译 | C 后端;mingw(`-d:mingw`);需目标 SDK/工具链 | 未验证 Windows/Linux | ⚠️ 见 §5.5 |
| 构建/打包 | `nim c` + 外部命令 | 未验证 .app/dmg | ⚠️ 工作量大但无技术风险 |

### 3.3 已完成的可行性原型

六个原型都在 `/Users/zhimoe/code/nimi/spikes/`,可直接编译运行:

| 原型 | 验证内容 | 观察结果 |
|---|---|---|
| `objc_hello/spike.nim` | ObjC runtime + NSWindow + 运行时类 + NSTimer | 窗口显示,1 秒后 `terminate:` 退出 |
| `wkwebview/spike_webview.nim` | WKWebView + JS message handler + `evaluateJavaScript` | `JS -> Nim: {hello = "from the page"; n = 42}` |
| `coretext/spike_coretext.nim` | CoreText shaping + CG 位图 + PNG | 拉丁/中日韩/阿拉伯混排,6781 个亮像素 |
| `nim_meta/spike_meta.nim` | 宏读 proc 签名 + 生成 TS + JSON 往返 | 生成 `greet(name: string...): Promise<string>` |
| `metal/spike_metal.nim` | CAMetalLayer + command buffer + clear pass | `drew 20 frames; clear colour presented` |
| `blocks/spike_blocks.nim` | 纯 Nim 构造 ObjC block 并传回 WKWebView | `block called: result=answer: 42 error=false` |

这些原型同时证明了:**不需要 cgo、不需要 Objective-C 源文件、不需要外部绑定生成器**。难度从"未知"降为"工程量大"。

### 3.4 Nim 生态可复用的东西

| 项目 | 用途 | 采用建议 |
|---|---|---|
| `treeform/metal4` / `elcritch/metalx` | Metal 1–4 / CAMetalLayer 绑定 | 参考实现;可先自建薄绑定,后续评估 |
| `khchen/winim` | Win32 + COM 头文件/常量 | Windows 后端首选 |
| `StefanSalewski/gintro` | GTK3/GTK4 GObject-Introspection 绑定 | **不建议直接依赖**:其 `dlopen` 方式与交叉编译体验不佳;参考 MyGo 的纯 `dlopen` 方案 |
| `neroist/webview` / `nimino` | 轻量跨平台 WebView | 只作参考,不满足 IPC/协议/多窗口需求 |
| `treeform/jsony` | 直接到对象的 JSON 解析/序列化 | 推荐;比 `std/json` 快 3–6 倍 |
| `windy` / `fidget` / `nimx` | Nim 原生 UI 框架 | 设计参考,不作为底座(目标是 MyGo 的 API/行为) |

---

## 4. 可行性结论

### 4.1 总体判断

| 维度 | 判断 |
|---|---|
| 技术可行性 | ✅ 可行。macOS 关键路径全部有原型证据。 |
| 1:1 完整功能移植 | ⚠️ 可行但巨大:约 32 万行 Go,完整三平台是 2–3 年单人工作量。 |
| API 形态 + 协议兼容的重实现 | ✅ 推荐。保留核心心智模型与前端协议,不追求 Go 源码兼容。 |
| macOS 可用版本 | ✅ 现实目标:3–6 个月做到 WebView + 基础原生 UI + 打包。 |
| Windows/Linux 后端 | ✅ 可行,但各自需要 4–8 个月,且交叉编译体验需重新设计。 |
| 最大风险 | 原生 UI 的广度(当前 123 个顶层控件入口、文本编辑/IME、可访问性),不是底层未知。 |

### 4.2 推荐路线(结论)

1. **先 WebView,后原生 UI**:WebView + IPC + CLI 是最短的可运行闭环,也复用 MyGo 现成的 JS bridge;原生 UI 从第一天并行做基础原型,但在 M2 才进入主线。
2. **macOS 单平台纵向切片**:每个里程碑都以"能跑的示例"为验收,而不是按模块横向铺开。
3. **系统文本引擎优先**:CoreText / DirectWrite / Pango 代替移植 MyGo 的纯 Go 文本栈(9.4k 行 + 字形栅格化),可省下大量工作并提升原生质量。
4. **CPU 渲染优先,GPU 随后**:macOS 先用 CoreGraphics 位图 + CALayer 上屏,跑通 UI/输入/文本;再用 Metal 替换渲染器。避免第一周就陷进 shader/管线。
5. **不移植着色器编译器**:MyGo 的 `internal/shader` + `shaderir` 共 1.2 万行,是 Kage 的 fork。Nimi 直接写 MSL/GLSL/HLSL,预编译为 `.metallib`/字节码。
6. **复用 JS 资产**:`packages/bridge`、`packages/runtime`、TS 协议、模板、示例、文档均可在 MIT 下复用;这是最快达成协议兼容的方式。

---

## 5. 关键决策点

### 5.1 "fork"的兼容边界

| 方案 | 含义 | 成本 | 建议 |
|---|---|---|---|
| A. 源码兼容 | 现有 Go 应用不改代码 | 不可行 | ❌ |
| B. 协议 + API 形态兼容 | 前端协议、TS 客户端、公开 API 心智模型一致;Nim 代码重写 | 中 | ✅ **推荐** |
| C. 仅概念借鉴 | 完全重新设计 API | 低 | 不满足"fork"诉求 |

方案 B 的具体承诺:

- IPC 线协议字段(`t/id/k/m/a/reply/event/chan`)与语义保持一致。
- 生成的 TS 客户端调用形态保持一致;包名可从 `mygo-runtime` 改为 `nimi-runtime`,并提供兼容转发包。
- 公开 API 采用 Nim 惯用命名(camelCase),但类型/方法语义一一对应,例如 `mygo.NewWindow(WindowOptions{...})` → `nimi.newWindow(WindowOptions(...))`。
- 配置字段与构建产物保持一致,便于复用文档与打包脚本。

### 5.2 首个可运行切片

**推荐:WebView-first。**

```text
M1 目标:examples/hello 的 Nim 版
- App.Run + NSApplication 事件循环
- 一个 NSWindow + WKWebView
- 注入 bridge.js
- Nim 侧 Bind(Greeter) + JS 调用 Greet
- 生成 TS 客户端
- `nimi dev` 能启动并热重载
```

理由:它同时验证 core、backend、IPC、bridge、CLI 五层,且能直接复用 MyGo 的 JS 运行时。原生 UI 的 `counter-native` 作为 M2 的第二个验收目标。

### 5.3 渲染路线

| 阶段 | macOS 渲染 | 理由 |
|---|---|---|
| M2 | CoreGraphics 位图 → CALayer | 最快跑通;文本/路径/渐变直接可用 |
| M3 | Metal 2D 管线 | 60/120fps、低 CPU;逐步替换 CG |
| M4+ | 可移植 raster(CPU) | Linux/Windows 无 Metal 时的兜底 |
| M5+ | GL / D3D11 | Linux/Windows 的 GPU 路径 |

`scene` 的 display list 从第一天就独立于渲染器;CG/Metal/raster 只是三个后端。这样不会把 UI 层绑死在某个图形 API 上。

### 5.4 内存模型

Nim 2.4 提供 `--mm:arc|orc|atomicArc|yrc`。框架需要:

- 主线程 UI 对象生命周期确定、无 GC 停顿。
- IPC 工作线程与主线程之间传递闭包/对象。
- Objective-C 对象由手动 retain/release 管理,与 Nim 堆分离。

**建议**:生产默认 `--mm:atomicArc`。

- 原子引用计数,跨线程共享 `ref` 安全;无环收集器,不会因 UI 树产生 GC 停顿。
- 代价:循环引用会泄漏。通过所有权规则规避:父子关系用 `ptr`/整数句柄做反向边,UI 元素树用 arena + 代际句柄,而不是 `ref` 环。
- 备选:`--mm:orc` + `std/isolation` 强制跨线程所有权转移;实现更复杂,但能收集环。
- `--mm:yrc` 作为"确实需要跨线程环"时的兜底,性能约为 ORC 的 1/2。

**硬规则**:线程边界只传 JSON 字符串、值类型或 `Isolate[T]`;不共享可变 `ref` 图。这与 MyGo 的"IPC 边界天然是 JSON"一致。M1 结束时用真实 IPC 负载 benchmark 一次三种 MM,再最终定稿。

### 5.5 交叉编译与构建

MyGo 的核心卖点是"任意机器 `GOOS=... go build`"。Nim 的现实:

- macOS 产物:macOS 上直接编译,arm64/amd64 分别编译 + `lipo`。
- Windows 产物:macOS/Linux 上可用 `nim c -d:mingw` + MinGW-w64;WebView2/D3D11 通过 `winim` 静态链接导入库,可行。
- Linux 产物:需要目标 libc/GTK 头文件或纯 `dlopen`(不链接 GTK),可用 Zig/交叉 clang + sysroot;比 Go 麻烦,但可脚本化。
- **建议**:先支持"宿主平台构建 + CI 矩阵",把 `nimi build -platform` 的多平台承诺推迟到 M7/M8;文档中明确各平台构建机要求。

### 5.6 绑定策略

| 平台 | 方案 |
|---|---|
| macOS | 运行时 ObjC + 手写薄绑定 + 少量 C API;不引入 `.m` shim(block 已验证) |
| Windows | `winim` + 手写 WebView2 COM 接口 vtable + D3D11 COM |
| Linux | 自建 `dlopen` 绑定(镜像 MyGo `internal/linux/ffi.go`),不依赖 gintro,保证构建机无 GTK 也能编译 |
| 生成器 | 常量/枚举可用脚本从 SDK 头文件生成;函数签名手写并配编译期测试 |

---

## 6. 风险矩阵

概率/影响:高/中/低。

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| 原生 UI 控件广度(123 个顶层构造器) | 高 | 高 | 分三批;MVP 只做 10–15 个核心控件;以 `examples/counter-native`、`gallery` 子集验收 |
| 文本编辑 / IME / 选区 / 双向文本 | 高 | 高 | 直接用 CoreText/NSTextInputClient;先单行/多行编辑,后富文本;IME 单独里程碑 |
| 可访问性(NSAccessibility/ATK/UIA) | 高 | 中 | M3 后置;先保留 AccessTree 数据结构,后接原生桥 |
| ObjC 内存管理 / 回调生命周期 | 中 | 高 | 封装 `ObjcRef`;autorelease pool;回调注册一次;用 Instruments/Zombies 测试 |
| IPC 类型系统与 TS 生成保真度 | 中 | 高 | 宏 + 显式类型描述符;用 MyGo 的 `tsgen` 测试用例做黄金测试 |
| JSON 规则差异 | 中 | 中 | 定义 Nimi JSON 规范;与 Go 版做差分测试;envelope 层严格兼容 |
| 线程/内存模型选型错误 | 中 | 高 | M1 做 MM benchmark;CI 跑 ThreadSanitizer(如可用);坚持 JSON 边界 |
| Metal 管线/颜色管理 | 中 | 中 | 先 CG;Metal 逐效果替换;用 golden image 对比 |
| WebView2 COM 绑定 | 中 | 高 | 参考 MyGo `internal/windows` + `internal/webview2`;先跑通最小窗口 |
| GTK/WebKitGTK 版本碎片化 | 中 | 高 | 镜像 MyGo 的 4.1/4.0 双版本 + 可选符号探测;CI 用容器 |
| 交叉编译体验不如 Go | 高 | 中 | 明确"每平台构建机";CI 矩阵;后续再优化 |
| 上游 MyGo 持续演进 | 中 | 低 | 锁定参考版本;按里程碑同步;协议版本化 |
| 单人长期投入 | 高 | 高 | 明确 MVP/非目标;每阶段可交付;文档与测试先行 |

---

## 7. 工作量估算

> 假设:1 名资深系统/图形工程师全职,熟悉 Nim 与 macOS,有 AI 辅助;复用 JS bridge/协议/模板/示例;系统文本引擎;不移植着色器编译器。
> 估算为规划量级(±50%),不是承诺。

### 7.1 纵向里程碑

| 里程碑 | 内容 | Nim 代码量(估) | 工期(单人) |
|---|---|---:|---:|
| M0 | 可行性原型(已完成) | ~1k | 1–2 天 |
| M1 | Core + macOS WebView + IPC + `hello` | 15–25k | 6–10 周 |
| M2 | 原生 UI 基础 + `counter-native` | +15–20k | 8–12 周 |
| M3 | 控件/文本/滚动/输入 + `gallery` 子集 | +20–30k | 10–16 周 |
| M4 | 桌面 API + 菜单/对话框/托盘/通知/快捷键 | +10–15k | 8–12 周 |
| M5 | 文档/会话/Cookie/协议/文件监视/深链 | +10–15k | 8–12 周 |
| M6 | Metal 渲染 + 文本编辑/IME + 可访问性 | +15–25k | 12–20 周 |
| M7 | 打包/签名/公证/DMG/更新 + CI | +8–12k | 6–10 周 |
| **macOS 合计** | 可广泛使用的 macOS 版本 | **~100–140k** | **14–21 个月** |
| M8 | Windows:Win32 + WebView2 + D3D11 + 打包 | +30–40k | 4–8 个月 |
| M9 | Linux:GTK3 + WebKitGTK + GL + 打包 | +30–40k | 4–8 个月 |
| **三平台合计** | 接近 MyGo 覆盖面 | **~160–220k** | **2–3 年** |

### 7.2 可交付的子集

| 目标 | 内容 | 工期 |
|---|---|---|
| **MVP-Web** | WebView 窗口、Bind/Event/Channel、TS 生成、菜单/对话框/剪贴板、`nimi dev/build`(.app) | 2–3 个月 |
| **MVP-Native** | MVP-Web + 原生 UI 基础(Column/Row/Text/Button/Input/Scroll/List)+ `counter-native` | 4–6 个月 |
| **可用框架 1.0** | MVP-Native + 常用桌面 API + 打包 + 8–12 个示例 | 6–9 个月 |
| **macOS 广泛兼容** | 120 控件、编辑器、IME、可访问性、文档、更新 | 14–21 个月 |

若 3 人团队并行(core/UI、后端、工具链),macOS 可用版本约 4–6 个月,广泛兼容约 8–12 个月。

---

## 8. Go/No-Go 建议

### 结论:**Go**,但必须接受以下前提

1. **不做 Go 源码兼容**;以协议 + API 形态兼容为目标。
2. **macOS 优先**,Windows/Linux 只保留契约与桩,不在 M1–M7 投入。
3. **原生 UI 分阶段**:先 10–15 个核心控件,不追求 123 个一次性对齐。
4. **复用 JS 资产与 MyGo 的协议/文档/示例**,把精力放在 Nim 独有的部分。
5. **每个里程碑以可运行示例验收**,不做"全都写完再联调"。

### 不建议的做法

- 逐行翻译 32 万行 Go。成本高、收益低,且会继承 Go 特有的反射/GC 设计。
- 第一版就移植 `internal/shader` / `shaderir`(1.2 万行)。直接写 MSL/GLSL/HLSL 更快。
- 第一版就做三平台。WebView2 COM 与 GTK 动态绑定会显著拖慢核心验证。
- 依赖 `gintro`/现成 WebView 包来"省事"。它们无法满足多窗口、IPC、自定义协议、原生 UI surface 的需求。

### 下一步

1. 评审本文件,确认兼容边界与首个切片。
2. 定稿 `01-architecture.md`(模块划分、线程/内存模型、平台契约)。
3. 落定 `05-roadmap.md` 的 M1 任务清单与验收标准。
4. 开始 M1:仓库骨架 + `nimi` CLI 最小实现 + macOS WebView `hello`。

---

## 附录 A:参考文件索引

| 主题 | MyGo 文件 |
|---|---|
| 架构总览 | `docs/architecture.md`(6,354 行) |
| 线程模型 | `docs/architecture.md` §Threading;`loop.go` |
| IPC 协议 | `docs/architecture.md` §IPC;`ipc.go`、`bridge.go`、`channel.go` |
| 页面 bridge | `packages/bridge/src/*.ts`;`internal/bridge/bridge.js` |
| TS 生成 | `internal/tsgen/{generate,types,source,names}.go` |
| 平台契约 | `internal/platform/` |
| macOS 后端 | `internal/darwin/`;`docs/architecture.md` §macOS |
| 原生 UI | `ui/`;`docs/architecture.md` §Native UI |
| 文本 | `internal/text/`;`ui/editor*`、`ui/text*` |
| 渲染 | `internal/scene/`、`internal/raster/`、`internal/gpu/` |
| CLI/打包 | `cmd/mygo/`;`docs/cli.md`、`docs/distribution.md` |
| 示例语料 | `examples/hello`、`examples/todo`、`examples/counter-native`、`examples/gallery` |

## 附录 B:术语

| 术语 | 含义 |
|---|---|
| Core | `package mygo` 对应的平台无关层 |
| Backend | 平台后端,实现 `platform.Backend` / `Window` / `Surface` |
| Surface | 原生 UI 的绘制面(NSView/GtkGLArea/子窗口) |
| Bridge | 注入页面的 JS 运行时,提供 `window.mygo` |
| Bound service | 通过 `Bind` 暴露给页面的 Nim 对象/方法 |
| Channel | 绑定方法向页面流式发送值的类型化通道 |
| Scene | 原生 UI 的 display list,渲染器的输入 |
| Tester | 无窗口的 UI 测试器 |

---

*本文档中的所有行数、文件数由 `wc`/`find` 在参考仓库上直接统计;原型结果来自 `spikes/` 下的实际运行输出。*
