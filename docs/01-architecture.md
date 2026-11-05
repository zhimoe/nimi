# Nimi 架构设计

> 状态:持续更新 · 日期:2026-11-05 · 关联文档:[可行性分析](00-feasibility.md)、[路线图](05-roadmap.md)
> 目标:用 Nim 复现 MyGo 的分层、线程模型、IPC 与原生 UI 架构;macOS 优先。

---

## 1. 设计原则

1. **策略在 core,后端只做翻译。** 默认值、窗口注册表、事件顺序、退出流程、IPC 路由、菜单模型、协议与信任检查全部在平台无关层。后端只把 `platform` 契约翻译成原生调用,不发明行为。
2. **平台层主线程专属。** 所有 `platform.*` 调用与回调都在主线程;后端内部不需要锁。公开 API 必须从任意线程安全调用。
3. **Nim 惯用,而非 Go 仿写。** 公开 API 用 camelCase、`ref object`、`proc` 闭包、异常;不照搬 `context.Context`、goroutine、反射。
4. **线程边界只传值。** 跨线程只传 JSON 字符串、值类型或 `Isolate[T]`;不共享可变 `ref` 图。IPC 天然满足这一点。
5. **系统能力优先。** 文本用 CoreText/DirectWrite/Pango,窗口用 AppKit/Win32/GTK,GPU 用 Metal/D3D11/GL;不重写平台引擎。
6. **渲染器可替换。** UI 只产出 `scene` display list;CG / Metal / raster / GL / D3D11 是并列后端。
7. **默认小、按需付费。** 不用到的功能不进入二进制、不启动线程、不加载库。Linux 后端在首次需要 WebKit 时才 `dlopen`。
8. **协议兼容优先于 API 兼容。** 前端 wire protocol、TS 客户端形态、配置字段尽量与 MyGo 一致;Nim API 形态可以更 Nim。

---

## 2. 仓库与模块布局

```text
nimi/
├── nimi.nimble                     # 包定义
├── config.nims                     # 全局编译选项(--mm:atomicArc --threads:on)
├── src/
│   ├── nimi.nim                    # 公开门面:re-export
│   └── nimi/
│       ├── core/                   # 平台无关层(对应 package mygo)
│       │   ├── app.nim             # Application 单例、生命周期、退出、路径
│       │   ├── window.nim          # Window、WindowOptions、窗口注册表、状态
│       │   ├── page.nim            # Page、导航、Eval、页面事件
│       │   ├── content.nim         # 原生 UI Content、Invalidate/Update
│       │   ├── webview.nim         # 原生 UI 中嵌入的 WebView
│       │   ├── loop.nim            # postMain / onMain / await / deliver
│       │   ├── events.nim          # 监听器、可取消事件
│       │   ├── ipc.nim             # Bind、方法分发、Event[T]
│       │   ├── channel.nim         # Channel[T] 流控
│       │   ├── bridge.nim          # bridge.js 注入、消息路由、批处理
│       │   ├── protocol.nim        # 自定义 scheme、CORS、FileServer
│       │   ├── frontend.nim        # 内置前端 VFS、dev URL
│       │   ├── menu.nim            # Menu/MenuItem/Role/Icon
│       │   ├── dialogs.nim         # 打开/保存/消息对话框
│       │   ├── clipboard.nim       # 文本/HTML/图片/文件/自定义格式
│       │   ├── notifications.nim   # 通知
│       │   ├── tray.nim            # 托盘
│       │   ├── shortcuts.nim       # 全局快捷键
│       │   ├── theme.nim           # 明暗、强调色、动效偏好
│       │   ├── screen.nim          # 显示器
│       │   ├── session.nim         # 持久/临时会话、站点数据
│       │   ├── cookies.nim         # Cookie 模型与过滤
│       │   ├── watch.nim           # 文件监视(快照/去抖/提示)
│       │   ├── documents.nim       # 文档控制器、自动保存、恢复、冲突
│       │   ├── deeplink.nim        # URL scheme / 文件关联启动参数
│       │   ├── singleinstance.nim  # 单实例锁与第二实例转发
│       │   ├── paths.nim           # PathName 与默认目录
│       │   ├── power.nim           # 电池/电源
│       │   ├── network.nim         # 网络状态
│       │   ├── nowplaying.nim      # 媒体键/Now Playing
│       │   └── updater.nim         # 更新清单、验签、安装
│       ├── platform/               # 平台契约与后端
│       │   ├── contract.nim        # Backend / Window / Surface / handlers
│       │   ├── darwin/
│       │   │   ├── objc.nim        # objc_msgSend、类、selector、block、pool
│       │   │   ├── app.nim         # NSApplication、delegate、run loop
│       │   │   ├── window.nim      # NSWindow 子类、样式、事件
│       │   │   ├── webview.nim     # WKWebView、配置、delegate、scheme handler
│       │   │   ├── surface.nim     # NSView + CAMetalLayer/CG、输入、IME
│       │   │   ├── menu.nim        # NSMenu
│       │   │   ├── dialogs.nim     # NSOpenPanel/NSSavePanel/NSAlert
│       │   │   ├── clipboard.nim   # NSPasteboard
│       │   │   ├── system.nim      # 通知、托盘、快捷键、屏幕、主题、电源
│       │   │   ├── watch.nim       # FSEvents
│       │   │   ├── cookies.nim     # WKHTTPCookieStore
│       │   │   └── audio.nim       # CoreAudio
│       │   ├── windows/
│       │   │   ├── win32.nim       # winim 封装、窗口、消息循环
│       │   │   ├── webview2.nim    # COM 接口与事件
│       │   │   ├── d3d11.nim       # D3D11 渲染器
│       │   │   ├── imm32.nim       # 输入法
│       │   │   ├── uia.nim         # UI Automation
│       │   │   └── ...
│       │   ├── linux/
│       │   │   ├── ffi.nim         # dlopen GLib/GObject/GTK/WebKit
│       │   │   ├── app.nim         # gtk_init、主循环
│       │   │   ├── window.nim
│       │   │   ├── webview.nim     # WebKitGTK
│       │   │   ├── surface.nim     # GtkGLArea/GtkDrawingArea
│       │   │   ├── atk.nim         # 可访问性
│       │   │   └── ...
│       │   ├── web/                # wasm(后续)
│       │   ├── fake/               # 单元测试内存后端
│       │   └── unsupported.nim     # 其他平台:编译通过,Run 返回错误
│       ├── effects/                # 可复用视觉效果
│       │   └── shred.nim           # 碎纸纸带物理
│       ├── ui/                     # 原生 UI
│       │   ├── context.nim         # Context、Key、Services、Theme
│       │   ├── element.nim         # 元素句柄、arena、生命周期
│       │   ├── node.nim            # 内部渲染树
│       │   ├── build.nim           # beginBuild/endBuild、输入队列
│       │   ├── layout.nim          # flexbox / grid / measure
│       │   ├── paint.nim           # 构建 scene
│       │   ├── input.nim           # 指针/键盘/滚轮/焦点/拖拽
│       │   ├── scroll.nim
│       │   ├── theme.nim
│       │   ├── text.nim            # 文本控件、行布局、编辑
│       │   ├── editor/             # 代码编辑器 / diff
│       │   ├── richtext.nim
│       │   ├── markdown.nim
│       │   ├── chart.nim
│       │   ├── access.nim          # AccessTree
│       │   ├── widgets/            # 120 个构造器的分批实现
│       │   └── tester.nim          # 无窗口测试器
│       ├── scene/                  # display list、图集
│       ├── render/
│       │   ├── renderer.nim        # 接口
│       │   ├── cg.nim              # CoreGraphics CPU(macOS M2)
│       │   ├── raster.nim          # 可移植 CPU(M4)
│       │   ├── metal.nim           # Metal(M3)
│       │   ├── gl.nim              # OpenGL/WebGL2(M9)
│       │   └── d3d11.nim           # D3D11(M8)
│       ├── text/
│       │   ├── font.nim            # 字体加载、缓存
│       │   ├── shape.nim           # shaping run
│       │   ├── linebreak.nim
│       │   ├── coretext.nim
│       │   ├── directwrite.nim
│       │   ├── pango.nim
│       │   └── glyphcache.nim
│       ├── bridge/                 # 复用的 JS 运行时
│       │   ├── bridge.js           # 由 packages/bridge 构建
│       │   └── embedded.nim        # staticRead / 压缩内嵌
│       ├── tsgen/                  # TypeScript 客户端生成
│       ├── cli/                    # nimi init/dev/build/generate/doctor
│       └── packaging/              # .app/.dmg/deb/NSIS/安装脚本
├── tests/
│   ├── unit/
│   ├── golden/                     # 场景/文本/TS 黄金测试
│   ├── e2e/                        # 真实 GUI 测试
│   └── fixtures/
├── examples/
│   ├── hello/                      # WebView + Bind(M1 验收)
│   ├── counter-native/             # 原生 UI(M2 验收)
│   ├── todo/                       # 前端 + TS 客户端(M2)
│   └── ...
└── docs/
```

> 现状提示:上图是目标布局。当前切片实际实现的是 `core/` 的
> app/window/content/ipc/loop/events/menu/dialog/clipboard/fileserver/
> document/watch/cookie/screen/theme/tray/notification/shortcut,
> `ui/context.nim` + `ui/tester.nim`(尚未拆成 element/layout/paint),
> `scene/scene.nim`、`render/cg.nim`、`render/metal.nim`、`effects/shred.nim`。
> 未列出的模块是路线图目标,不应把本文当成“已实现清单”。

> 命名空间用 Nim 的点路径:`import nimi/core/[app, window, ipc]`。门面 `nimi.nim` re-export 常用符号,应用通常 `import nimi` + `import nimi/ui`。

---

## 3. 分层与数据流

### 3.1 WebView 路径

```text
用户代码 ──► nimi/core ──► platform.Backend ──► darwin | windows | linux
                ▲    │              ▲
                │    └─ handlers ───┘
 page (JS) ◄── bridge.js ◄── eval(批量) ─┘
     └──── postMessage(JSON) ──► WindowHandler.message
```

- `core` 维护窗口/页面注册表、事件、退出流程、IPC 路由、协议、信任检查。
- `platform` 契约同步、主线程专属;后端把 `WindowOptions` 翻译成 `NSWindow`/`HWND`/`GtkWindow`。
- 页面端 `bridge.js` 提供 `window.nimi`(兼容别名 `window.mygo`),消息经原生 webview 的 message handler 进入 `WindowHandler.message`。
- 绑定方法在工作线程执行;结果编码成 JSON 后回主线程批量 `eval`。

### 3.2 原生 UI 路径

```text
 view (Nim) ──► ui: build → layout → paint ──► scene ──► renderer(cg | metal | raster | gl | d3d11)
                  ▲        └─ text: CoreText | DirectWrite | Pango
                  │
 platform.Surface ◄── core.Content ◄── WindowOptions.content
```

- 后端提供 `Surface`:原生视图、尺寸/缩放、刷新率、请求帧、呈现、光标、输入法、输入事件。
- UI 引擎不知道窗口来自哪个平台;渲染器不知道 UI/输入。
- 输入事件经 `WindowHandler.surfaceEvent` 进入 UI;UI 的请求经 `Surface.requestFrame` 回到主循环。

### 3.3 模块依赖方向

```text
nimi.nim ─► core ─► platform.contract
              │
              ├─► content ─► ui ─► scene
              │      ▲
              │      └─ SceneRenderer(由 composition root 注入)
              └─► app(composition root)──► render/cg(CoreGraphics)
cli ─► tsgen ─► descriptors(由宏生成,位于 core/ui 编译期)
```

硬规则:

- `core` 不 import 任何具体后端;通过 `platform.currentBackend()` 或编译期 `when defined(macosx)` 选择。
- `core/window` 不 import 具体渲染器;它通过 `content.drawContent` 调用注入的
  `SceneRenderer`。`core/app.nim` 是 macOS composition root,安装
  `defaultContentRenderer = drawScene`。
- `ui` 不 import `core` 的 Window/Page;只依赖 `scene`、`text`、`platform.Surface` 的窄接口。
- `render` 只依赖 `scene` 与裸图形 API;不依赖 `ui`。`render/metal.nim` 是
  macOS 专用路径,依赖 Darwin ObjC/Metal,且不被 `nimi.nim` 导出。
- `tsgen` 只吃编译期描述符与 JSON,不依赖 UI。

---

## 4. 公开 API 形态

### 4.1 WebView 应用

```nim
import nimi

type
  Greeter = ref object

proc greet(self: Greeter, name: string): string =
  "Hello " & name & ", from Nim " & NimVersion

nimi.bind(Greeter())

nimi.app.whenReady(proc() =
  discard nimi.newWindow(WindowOptions(
    title: "Hello Nimi",
    width: 480,
    height: 320,
    url: "/"
  ))
)

nimi.app.run()
```

对应 MyGo:

```go
mygo.Bind(Greeter{})
mygo.App.WhenReady(func() {
    mygo.NewWindow(mygo.WindowOptions{Title: "Hello", Width: 480, Height: 320, URL: "/"})
})
mygo.App.Run()
```

### 4.2 原生 UI 应用

```nim
import nimi
import nimi/ui

type
  Counter = ref object
    n: int

proc view(s: Counter, c: Context) =
  if c.shortcut({}, KeyUp): inc s.n
  if c.shortcut({}, KeyDown): dec s.n

  column(c).fill().center().gap(16).children(proc() =
    text(c, $s.n).fontSize(56).bold()
    row(c).gap(8).children(proc() =
      if button(c.key("decrement"), "−").clicked(): dec s.n
      if button(c.key("reset"), "Reset").disabled(s.n == 0).clicked(): s.n = 0
      if primaryButton(c.key("increment"), "+").clicked(): inc s.n
    )
    text(c, "↑ and ↓ count too").fontSize(12).textColor(c.theme.textMuted)
  )

let s = Counter()
nimi.app.whenReady(proc() =
  discard nimi.newWindow(WindowOptions(
    title: "Counter",
    width: 360,
    height: 260,
    content: uiView(proc(c: Context) = s.view(c))
  ))
)
nimi.app.run()
```

### 4.3 命名约定

| MyGo | Nimi | 约定 |
|---|---|---|
| `mygo.App` | `nimi.app` | 单例,小写 |
| `mygo.NewWindow` | `nimi.newWindow` | 动词开头,camelCase |
| `WindowOptions{Title: ...}` | `WindowOptions(title: ...)` | 对象构造,字段 camelCase |
| `mygo.Bind(v)` | `nimi.bind(v)` | 小写 |
| `mygo.NewEvent[T](name)` | `newEvent[T](name)` 宏 | 宏在编译期登记类型 |
| `mygo.Channel[T]` | `Channel[T]` | 同名 |
| `ui.Column(c).Fill()` | `column(c).fill()` | 控件构造器小写;链式选项 camelCase |
| `Page.Eval` | `page.eval` | 同上 |

> 不提供 Go 风格的 PascalCase 别名。兼容层只覆盖协议与 TS,不覆盖 Nim 源码风格。

---

## 5. 线程与内存模型

### 5.1 主线程

- 进程主线程即 UI 主线程。Nim 的 `main` 默认在进程主线程;不创建"UI 线程",也不允许把 `App.run` 放到其他线程。
- `Backend.init` 必须在主线程调用;`Backend.run` 阻塞直到退出。
- 所有 `platform.*` 方法与 handler 回调在主线程执行。
- 事件监听器同步执行;可取消事件(`onClose`、`onBeforeQuit`、`onWillNavigate`)必须同步返回决定。
- 绑定方法在工作线程池执行,可阻塞。

### 5.2 主线程调度原语

```nim
# core/loop.nim
proc postMain*(fn: proc()) : bool
proc onMain*(fn: proc())
proc onMainValue*[T](fn: proc(): T): T
proc await*[T](f: Future[T]): T       # 主线程时泵事件
proc deliver*[T](f: Future[T], value: T)
```

- `postMain`:FIFO 入队;首次入队调用 `backend.signal()`;关闭后返回 false 并丢弃。
- `onMain`:已在主线程直接执行;否则入队并阻塞等待。
- `await`:非主线程直接等;主线程循环 `backend.step()` 泵原生事件,直到 `deliver` 唤醒。嵌套/模态循环必须安全。
- 后端提供 `signal`、`step`、`wake`、`isMainThread`:
  - macOS:`CFRunLoopSource`(所有 common modes)+ `CFRunLoopRunInMode`;`Step` 跑一次 run loop。
  - Linux:`g_idle_add` + `g_main_context_iteration`。
  - Windows:`PostMessage(WM_APP)` + `PeekMessage/GetMessage`。

### 5.3 工作线程池

- 固定大小(默认 `max(2, cpuCores div 2)`,可配置),任务队列 + 条件变量。
- 每个 IPC 调用是一个 `Task`:入参是已解析的 `JsonNode`/原始 JSON 字符串,结果是 JSON 字符串或异常。
- 取消:任务持有 `CallContext`(原子取消标志 + 页面/窗口引用);页面导航/窗口关闭时置位;阻塞操作应定期检查。
- 不在工作线程触碰 UI 对象;需要 UI 的结果经 `postMain` 回主线程。

### 5.4 内存模型

**生产默认:`--mm:atomicArc`。** 理由:

- UI 主线程需要确定性释放、无 GC 停顿。
- IPC 工作线程与主线程之间可能传递闭包/结果;原子引用计数使 `ref` 跨线程安全。
- 无环收集器避免 UI 树扫描带来的抖动。

规则:

1. **禁止所有权环。** 父子节点用整数句柄/`ptr` 做反向边;UI 元素树用 arena + generation 句柄,不用 `ref` 环。
2. **跨线程只传值。** 即使 atomicArc 允许共享 `ref`,也把"跨线程只传 JSON/值/`Isolate`"作为代码评审硬规则,减少生命周期推理。
3. **ObjC 对象独立管理。** `ObjcRef` 包装 + `=copy`/`=destroy` 做 retain/release;`NSAutoreleasePool` 用 `withPool` 作用域;从 `alloc/init` 得到的对象归调用者,convenience 构造器返回 autoreleased。
4. **回调只注册一次。** 原生回调(Nim `{.cdecl.}` proc)按签名/窗口 ID 路由;不在每次调用创建闭包。用户数据用整数 ID,不用指针捕获 Nim 闭包。
5. **循环检测。** 开发构建提供 `-d:nimiLeakCheck`,在窗口关闭后统计 arena 存活节点;CI 跑长生命周期测试。

备选:`--mm:orc` + `std/isolation` 强制跨线程所有权转移;`--mm:yrc` 用于确实需要跨线程环的场景。M1 用真实 IPC 负载 benchmark 后定稿。

---

## 6. 平台契约(`platform/contract.nim`)

契约要小、同步、主线程专属。建议按功能分组,而不是一个大接口:

```nim
type
  Backend* = ref object of RootObj

  AppOptions* = object
    name*, version*: string
    activationPolicy*: ActivationPolicy
    ...

  WindowOptions* = object
    # core 已填好默认值;后端只翻译
    title*: string
    frame*: Rect
    style*: set[WindowStyle]
    page*: PageOptions
    surface*: SurfaceOptions

  Surface* = ref object of RootObj
    # 原生句柄、尺寸/缩放、刷新率
    handle*: pointer
    scale*: float32
    refreshRate*: float32

  AppHandler* = ref object
    ready*: proc()
    activate*: proc(hasVisibleWindows: bool)
    openURL*: proc(url: string)
    openFile*: proc(path: string)
    beforeQuit*: proc(e: var QuitEvent)
    ...

  WindowHandler* = ref object
    message*: proc(w: platform.Window, msg: string)
    surfaceEvent*: proc(w: platform.Window, ev: SurfaceEvent): bool
    closeRequested*: proc(w: platform.Window): bool
    ...

  Backend* = ref object of RootObj
    # 生命周期
    method init*(b: Backend, h: AppHandler, opts: AppOptions)
    method run*(b: Backend)
    method quit*(b: Backend)
    method signal*(b: Backend)
    method step*(b: Backend)
    method wake*(b: Backend)
    method isMainThread*(b: Backend): bool
    # 应用
    method setMenu*(b: Backend, menu: platform.Menu)
    method setBadge*(b: Backend, n: int)
    method openExternal*(b: Backend, url: string)
    # 窗口
    method newWindow*(b: Backend, opts: WindowOptions, h: WindowHandler): platform.Window
    method windowSetTitle*(b: Backend, w: platform.Window, title: string)
    method windowSetBounds*(b: Backend, w: platform.Window, r: Rect)
    method windowShow*(b: Backend, w: platform.Window)
    method windowClose*(b: Backend, w: platform.Window)
    # 页面
    method pageLoadURL*(b: Backend, w: platform.Window, url: string)
    method pageEval*(b: Backend, w: platform.Window, js: string, id: uint64)
    # ...
```

设计约束:

- `core` 传入的 options 已完全默认化;后端不做策略。
- 每个方法在主线程调用;后端内部状态无需锁。
- 异步结果用一次性回调:`method ... (b, w, reqId)` → 后端完成后调用 `handler.deliver(reqId, result)`;`core` 用 `await` 等待。
- 每个平台方法必须在 `darwin`、`windows`、`linux`、`web`、`fake`、`unsupported` 中实现(后两者可返回 `ErrUnsupported`)。
- 后端只暴露原生句柄(`nativeHandle`),不暴露框架对象。

### 6.1 事件类型

| 事件 | 方向 | 线程 |
|---|---|---|
| `ready`、`activate`、`openURL`、`openFile` | 后端 → core | 主线程 |
| `beforeQuit`、`willQuit` | core ↔ 后端 | 主线程,同步 |
| `windowCloseRequested` | 后端 → core | 主线程,返回 bool |
| `windowResized/Moved/Focused/...` | 后端 → core | 主线程 |
| `message`(页面 IPC) | 后端 → core | 主线程 |
| `surfaceEvent`(输入/绘制) | 后端 → core | 主线程 |
| `deliver`(异步结果) | 后端 → core | 主线程 |

---

## 7. IPC 与 Bridge

### 7.1 线协议(与 MyGo 对齐)

页面 → Nim(secret 前缀 + JSON 字符串):

| 消息 | 字段 |
|---|---|
| 调用 | `{"t":"call","id":N,"k":token,"m":"Service.Method","a":[...]}` |
| channel ack | `{"t":"chan-ack","c":N,"k":token,"n":S}` |
| channel close | `{"t":"chan-close","c":N,"k":token}` |
| DOM ready | `{"t":"dom-ready"}` |
| 主题色 | `{"t":"theme-color","v":"#rrggbbaa"}` |
| 内容尺寸 | `{"t":"content-size","w":W,"h":H,"sw":SW,"sh":SH}` |
| 拖拽区 | `{"t":"drag"}` / `{"t":"dblclick"}` |
| 右键菜单 | `{"t":"context-menu",...}` |
| 文件 drop | `{"t":"drop","x":X,"y":Y}` |

Nim → 页面(每轮主循环合并为一次 `__nimi.receive([...])`):

| 消息 | 字段 |
|---|---|
| 回复成功 | `{"t":"reply","id":N,"k":token,"ok":true,"v":value}` |
| 回复失败 | `{"t":"reply","id":N,"k":token,"ok":false,"e":"message"}` |
| channel 值 | `{"t":"chan","c":N,"k":token,"p":value,"a":1?}` |
| channel 结束 | `{"t":"chan","c":N,"k":token,"end":true}` |
| 事件 | `{"t":"event","n":"name","p":payload}` |

- `secret`:每窗口随机;注入 bridge 闭包,页面消息必须带前缀。
- `k`:每页 token;导航后旧 reply 不 resolve 新页的 Promise。
- 消息批处理:`outbox` 三段式(head/value/tail),主线程 `flush` 一次 eval。
- 事件在 DOM ready 前最多保留 1024 条;reply 不保留。
- untrusted 页面:超过 4 KiB 的消息直接丢弃;call 在主线程拒绝,不创建任务。

### 7.2 Bridge 复用

- 直接复用 MyGo 的 `packages/bridge`(TypeScript)与构建产物 `bridge.js`;只改命名空间/配置字段。
- 页面端保留 `window.mygo` 别名,至少到 Nimi 1.0;新代码用 `window.nimi`。
- `nimi-runtime` npm 包 fork 自 `mygo-runtime`,保持 `call`/`event`/`Channel` 的导出形态。

### 7.3 绑定与类型描述符

Nim 没有 Go 的运行时方法反射,因此用**编译期宏 + 显式服务声明**:

```nim
type
  Note* = object
    id*: int
    title*: string
    body*: string

  Notes* = ref object
    items: seq[Note]

proc add*(self: Notes, title: string): Note {.rpc.} =
  result = Note(id: self.items.len + 1, title: title)
  self.items.add result

proc list*(self: Notes): seq[Note] {.rpc.} =
  self.items

let notes = Notes()
bindService(notes, add, list)
# 宏显式接收服务实例与 proc 列表,生成注册表/编解码/TS 描述。
# 服务名取自实例类型;Nim 无法按 pragma 枚举类型的所有方法。
# {.rpc.} 是可选标记,用于校验与工具。
```

宏展开产出:

- `ServiceDef(name: "Notes", methods: [...])`,含每个方法的参数名、类型描述符、返回类型、文档。
- `dispatch(service, method, args: JsonNode, ctx: CallContext): JsonNode`:按类型解码参数、调用、编码结果/异常。
- `tsDescriptor`:供 `nimi generate` 输出 TypeScript。
- 可选 `bindAs("Store", Notes)`。

类型描述符是一个编译期生成的 `TypeDef` 树:

```nim
TypeDef = object
  kind: TypeKind       # tkString, tkInt, tkObject, tkSeq, tkOption, ...
  name: string
  fields: seq[FieldDef]
  enumValues: seq[(string, JsonNode)]
```

`toJson`/`fromJson` 由宏按 `TypeDef` 生成,不依赖 `std/jsonutils` 的运行时规则。JSON 规则见 §7.5。

### 7.4 TS 生成流程

1. `nimi generate` 运行 `nim c -d:nimiGenerate --out:.nimi/gen app.nim`(或直接 `nim r`)。
2. 应用启动时 `app.run` 检测 `NIMI_GENERATE` 环境变量/编译期 define,调用 `generateTypeScript()` 后退出,不初始化后端。
3. `generateTypeScript()` 遍历已登记的服务/事件描述符,输出:
   - 类型声明(interface/type union)
   - 服务对象(`export const Notes = { add(...): Promise<Note> {...} }`)
   - 事件对象(`export const events = { noteAdded: event<Note>("note-added") }`)
4. 输出路径来自 `nimi.config.nims` 的 `bindings`;内容未变不重写。
5. 没有绑定/事件的 app 不写文件,也不链接 tsgen。

与 Go 版的差异:

- 参数名来自宏,不依赖源码解析;没有 `source.go` 的 PC→AST 回溯。
- 文档注释:宏默认拿不到 `##` 注释;需要文档时在 `{.rpc.}` 旁用 `{.doc: "...".}` 或服务声明中的 `doc` 字段。后续可写一个 `nim doc --json` 辅助工具补全。
- 常量的字面量联合类型:宏可读 `const` 值,生成 `"a" | "b"`;复杂 `iota`/位运算需要显式标注。

### 7.5 JSON 规则

目标:与 MyGo 的 TS 客户端形态一致;不追求 `encoding/json/v2` 的全部边角。

| Nim | JSON / TS |
|---|---|
| `bool` | `boolean` |
| `string` | `string` |
| `int`/`int64`/`float` | `number`(超过 2^53 的 ID 建议用 `string` 标注) |
| `seq[T]` | `T[]`;nil seq → `[]` |
| `array[N, T]` | `T[]` |
| `Option[T]` | `T \| null`;`some`/`none` |
| `Table[string, T]` | `Record<string, T>` |
| `object` / `ref object` | 同名 interface |
| 字段名 | 默认 camelCase(宏生成);可用 `{.json: "id".}` 覆盖 |
| `distinct string` + const | 字面量 union |
| `seq[byte]` | base64 string |
| `DateTime` | RFC 3339 string |
| `Duration` | number(纳秒) |
| 变体对象 | 带 `kind` 的 discriminated union(需显式标注) |

- `omitempty`:Nim 没有结构体标签级省略;用 `Option[T]` 或 `{.jsonOmitIfDefault.}` 标注。
- 变体对象/泛型:第一版只支持常见形态;复杂类型用自定义 `toJson`/`fromJson` 钩子。
- envelope 字段(`t/id/k/m/a/reply/event/chan`)严格与 MyGo 一致。

### 7.6 事件与 Channel

- `newEvent[T]("note-added")` 是宏:登记名称、payload 类型、声明位置;生成 `Event[T]` 对象。
- `emit(win, payload)` / `emitPage(page, payload)` / `broadcast(payload)`。
- `Channel[T]` 只能作为 `{.rpc.}` 方法参数;宏识别并生成 channel 创建逻辑。
- 流控:1 MiB 窗口;每半窗口要求 ack;`send` 在非主线程等待,主线程不等待;调用返回时先发 `end` 再发 reply。
- 页面提前 close/导航/窗口关闭 → 取消 `CallContext`。

---

## 8. 原生 UI 设计

### 8.1 元素树

MyGo 的 `Element` 是 16 字节值(owner + arena slot + 32 位 generation),依赖 Go 的 GC 与 arena。Nim 用类似但更简单的句柄:

```nim
type
  Element* = object
    owner*: uint32       # 窗口/引擎 ID
    slot*: uint32        # arena 下标
    generation*: uint32  # 代际,防复用
    # 16 字节:8 字节指针 + 2×uint32
```

- 每个窗口一个 `Arena`: `seq[Node]` + free list + generation。
- 旧句柄在 generation 不匹配时返回空/忽略;开发构建 `-d:nimiDebug` 报错。
- 关闭窗口时 owner 失效,所有句柄作废;arena 延迟回收。
- `Handle` 保存持久控件身份(用于焦点/测试),与 `Element` 分离。

### 8.2 构建阶段

- 每个控件构造器立即创建/复用节点、应用样式、排队输入。
- `beginBuild`/`endBuild` 包围每次构造;输入按构造深度延后应用(容器先构建子节点,再处理方向键等)。
- 控件返回后即可读 `clicked()`/`changed()`/`focused()`;与 Dear ImGui 的即时模式相似,但树是保留的。
- `Context.key(...)` 在状态初始化前提供稳定 ID。

### 8.3 布局

- Flexbox:row/column、grow/shrink/basis、gap、padding/margin、align/justify、wrap、min/max、aspect ratio。
- Grid:固定/分数轨道、gap、跨行跨列。
- 文本测量:通过 `text` 模块;布局缓存按内容/宽度/样式失效。
- 布局是纯函数式的一遍(或两遍:measure + arrange);不依赖原生布局。

### 8.4 绘制

- `paint` 遍历树,生成 `scene` 命令:
  - `rect`、`roundedRect`、`border`、`shadow`
  - `textRun`(glyph IDs + positions + color)
  - `image`、`svg`
  - `path`(fill/stroke)
  - `linearGradient`/`radialGradient`
  - `clip`/`transform`/`opacity`
  - `blur`/`vibrancy`(平台特效)
- 场景按图层/裁剪分组;渲染器负责批处理。
- 颜色:sRGB 为基准;macOS 支持 P3/wide color;线性空间合成。

### 8.5 文本

- `text/shape.nim` 定义 `TextRun`(glyphs、positions、font、size、color、cluster map)。
- macOS:`CoreText` 做 shaping/断行/字体回退;`CTLine`/`CTFramesetter`;glyph 用 `CTFontDrawGlyphs` 栅格化到 atlas。
- Windows:`DirectWrite` + `IDWriteTextLayout`。
- Linux:`Pango` + `HarfBuzz`(或 Pango 自带)。
- 编辑:`ui/text.nim` 维护文本缓冲(可选 rope)、选区、光标、撤销;IME 通过 `Surface.setTextInput` 与 `SurfaceEvent` 的 composition 事件。
- 第一版支持单行/多行纯文本;富文本/代码编辑器后置。

### 8.6 输入

- 指针:move/down/up/enter/leave/wheel、双击/三击、拖拽、右键菜单、触摸(后续)。
- 键盘:按下/释放/重复、修饰键、快捷键匹配(移植 `accelerator`)。
- 焦点:Tab 顺序、焦点环、隐藏控件的待定焦点、`FocusBind`。
- 滚动:滚轮/触摸板、滚动条、惯性(后续)。
- 命中测试:按树逆序 + 裁剪/变换;`IgnoreInput` 节点不参与。

### 8.7 渲染器接口

```nim
type
  Renderer* = ref object of RootObj
    method beginFrame*(r: Renderer, s: Surface, size: Size, scale: float32)
    method draw*(r: Renderer, scene: Scene)
    method endFrame*(r: Renderer)
    method present*(r: Renderer)
```

- `cg`:CoreGraphics 位图,`CGBitmapContext` + `CTLineDraw`;`present` 设置 `CALayer.contents`。
- `metal`:MTLDevice/Queue/Pipeline;`.metallib` 预编译;texture atlas;三缓冲。
- `raster`:自研 coverage rasterizer;用于 Linux/Windows 无 GPU 或测试。
- `gl`/`d3d11`:后续。

### 8.8 可访问性

- UI 每帧生成 `AccessTree`(角色、名称、值、范围、状态、边界、动作),与 MyGo 的 `ui/access.go` 对应。
- macOS:NSAccessibilityElement 子类 + 通知。
- Linux:ATK/AT-SPI。
- Windows:UI Automation。
- 第一版只保留数据结构;原生桥在 M6。

---

## 9. 构建、测试与发布

### 9.1 编译

```sh
nim c --mm:atomicArc --threads:on -d:release -d:nimiProd \
  --out:build/MyApp src/main.nim
```

- 开发:`-d:nimiDebug` 开启断言、元素代际检查、Inspector。
- 生产:`-d:release -d:nimiProd`,strip,关闭 Inspector。
- macOS universal:`nim c --cpu:arm64` + `nim c --cpu:amd64` + `lipo -create`。
- 内嵌前端:CLI 生成 `nimi_assets.nim`(每个文件 `staticRead` + 路径表),或生成单个归档 + 索引。

### 9.2 测试层次

| 层 | 方式 | 目标 |
|---|---|---|
| 单元 | `tests/unit` + `unittest` | core、IPC、JSON、布局、协议、TS 生成 |
| Fake 后端 | `platform/fake` | 无 GUI 测试窗口/事件/生命周期 |
| 黄金图像 | `tests/golden` | scene/raster/text 渲染;PNG 像素/感知 diff |
| 协议黄金 | 复用 MyGo `tsgen` 测试用例 | TS 输出与 Go 版一致/可解释差异 |
| E2E | `tests/e2e` | 真实 WKWebView/窗口;可用 automation socket |
| 基准 | `tests/bench` | 启动时间、空闲 CPU、帧时间、二进制大小 |

### 9.3 打包

- macOS:`MyApp.app/Contents/{MacOS,Resources,Frameworks}`、`Info.plist`、`PkgInfo`、`AppIcon.icns`、可选 `.lproj`;`codesign --deep --options runtime`;`notarytool submit` + `stapler`;`hdiutil` 生成 DMG。
- Windows(M8):`windowsgui` 子系统、资源/清单、NSIS 安装器、签名。
- Linux(M9):`.desktop`、hicolor 图标、MIME XML、`.deb`、`PKGBUILD`、`install.sh`。
- 更新(M7):Ed25519 签名清单、tar.gz/delta、`App.relaunch`;复用 MyGo 的清单格式。

---

## 10. 与 MyGo 的差异清单

| 主题 | MyGo | Nimi | 原因 |
|---|---|---|---|
| 方法反射 | `reflect.Type.Method` | 宏 + `{.rpc.}` | Nim 无运行时方法集 |
| 上下文 | `context.Context` | `CallContext` 首参 | Nim 无标准 context;需取消/调用者 |
| 并发 | goroutine/reflection | 线程池 + 值传递 | Nim 线程模型 |
| IPC 类型 | `encoding/json/v2` 反射 | 宏生成 codec | 性能/可控性 |
| 文档注释 | `go/parser` | 显式 `doc` 注解 | Nim AST 不保留注释 |
| 原生 UI 元素 | 16 字节 Go 值 + arena | 12/16 字节句柄 + arena | 类似,但无 GC 依赖 |
| 文本 | 纯 Go 引擎 | 系统文本引擎 | 省 9.4k 行,质量更好 |
| 着色器 | Kage fork/IR | 直接 MSL/GLSL/HLSL | 省 1.2 万行 |
| 交叉编译 | 任意机器 | 需目标工具链/CI | Nim 现实 |
| 弱引用 | `weak.Pointer` | 整数 ID + 显式表 | Nim 无等价物 |
| 插件 | Go 包/npm | 静态模块(第一版) | 动态插件后置 |

---

## 11. 里程碑映射

| 里程碑 | 架构落点 | 验收 |
|---|---|---|
| M1 | `core` + `platform/darwin`(window/webview/menu/dialog)+ `bridge` + `tsgen` + CLI | `examples/hello` 运行,JS 调 Nim,生成 TS |
| M2 | `platform/darwin/surface` + `ui` 基础 + `render/cg` + `text/coretext` | `examples/counter-native` 运行 |
| M3 | 控件/布局/滚动/输入 + `render/metal` 起步 | `gallery` 子集 + 60fps |
| M4 | desktop modules + `platform/darwin/system` | 菜单/托盘/通知/快捷键示例 |
| M5 | documents/session/cookies/protocol/watch/deeplink | `examples/notes` 类应用 |
| M6 | 编辑器/IME/可访问性 + Metal 完整 | `code-editor` 子集 + VoiceOver |
| M7 | packaging/signing/updater/CI | 可分发 `.app`/`.dmg` |
| M8 | `platform/windows` | `hello`/`counter-native` 在 Windows 运行 |
| M9 | `platform/linux` | 同上,GTK3/WebKitGTK |

---

## 12. 待定问题

1. `nimi.config.nims` 还是 JSON 优先?建议先 JSON,再支持 NimScript。
2. 插件模型:第一版静态链接;是否提供动态库 ABI 待定。
3. wasm/浏览器后端是否保留?建议 M9 后再评估。
4. 是否提供 `mygo-runtime` 兼容包?建议是,降低前端迁移成本。
5. 双平台 universal 构建是否在 M7 落地?建议是,但可延后到发布前。
6. 可访问性是否进入 1.0?建议 M6 起步,1.0 只保证 macOS VoiceOver 基本可用。

---

*本文档描述目标架构;具体 API 以 `docs/07-api-mapping.md` 为准,实施顺序以 `docs/05-roadmap.md` 为准。*
