# Windows / Linux 后端规划

> 状态:草案 · 日期:2026-11-04 · 关联:[架构](01-architecture.md)、[macOS 后端](02-macos-backend.md)、[路线图](05-roadmap.md)
> 参考:MyGo `internal/windows`(20.5k 行非测试)、`internal/linux`(15.8k 行)、`internal/gpu/{d3d11,gl}`、`cmd/mygo` 打包

---

## 1. 共同原则

1. **契约不变。** Windows/Linux 后端实现与 macOS 相同的 `platform.Backend`/`Window`/`Surface`/handlers;core/UI/渲染器不感知平台差异。
2. **主线程专属。** 所有平台调用与回调在主线程;跨线程经 `postMain`/`await`。
3. **按需加载。** Linux 的 WebKitGTK 只在需要网页窗口时 `dlopen`;Windows 的 WebView2 Runtime 只在需要网页窗口时初始化。仅原生 UI 的 app 不依赖浏览器运行时。
4. **后端只翻译。** 窗口几何、DPI、菜单、磁盘路径等平台策略可以在后端,但不得改变 core 的状态机。
5. **构建与运行解耦。** Linux 后端用纯 `dlopen` 绑定,构建机不需要 GTK/WebKit 头文件;Windows 用 `winim`/COM vtable,构建机需要 MinGW 导入库但不需要 WebView2 SDK。

---

## 2. Windows 后端(`platform/windows`)

### 2.1 技术选型

| 层 | 方案 |
|---|---|
| Win32 调用 | `winim`(khchen/winim)或自建薄绑定;`std/dynlib` + 函数指针 |
| COM | 手写 vtable 调用(参考 MyGo `com.go`);`QueryInterface` 探测可选接口 |
| WebView2 | 直接 COM,不用 C++ SDK;runtime 通过注册表/loader 查找 |
| 原生 UI | 子窗口 `MyGoSurface` + D3D11 swap chain(或 DirectComposition) |
| 文本 | DirectWrite |
| 输入法 | IMM32 |
| 可访问性 | UI Automation provider(COM) |
| 音频 | WASAPI shared mode |
| 打包 | NSIS 安装器;signtool/osslsigncode |

### 2.2 启动与消息循环

```text
Init
 ├─ CoInitializeEx(APARTMENTTHREADED)
 ├─ SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)
 ├─ registerClasses():MyGoApp、MyGoWindow、MyGoSurface、caption/topedge
 ├─ 创建隐藏顶层 MyGoApp 窗口(appHwnd)
 ├─ register TaskbarCreated / TaskbarButtonCreated
 └─ OLE drop target
Run
 └─ GetMessageW / TranslateMessage / DispatchMessageW
Signal  → PostMessage(appHwnd, wmAppDispatch)
Wake    → PostMessage(appHwnd, wmAppWake)
Step    → MsgWaitForMultipleObjectsEx + PeekMessage
Quit    → PostQuitMessage(0)
```

- `IsMainThread`:记录初始化时的 `GetCurrentThreadId`。
- `wndProc` 按 HWND 分派到 app/window/caption/topEdge/surface,最后 `DefWindowProcW`。
- 模态对话框/菜单循环会把 `WM_QUIT` 转发给外层。
- 所有 Win32 DLL 从 `%SystemRoot%\System32` 加载,避免 DLL 劫持。

### 2.3 窗口

- 样式:`WS_OVERLAPPEDWINDOW`、`WS_POPUP`、`WS_EX_TOOLWINDOW`、`WS_EX_NOACTIVATE`、`WS_EX_NOREDIRECTIONBITMAP`。
- `WM_NCCALCSIZE` 去掉标题栏但保留边框;Windows 10/11 分支不同。
- 隐藏标题栏:layered child window 画按钮(Segoe Fluent Icons / MDL2),GDI + `UpdateLayeredWindow`。
- 顶部缩放边:layered child window,`WM_NCHITTEST` 返回 `HTTOP*`。
- `WM_DPICHANGED`:保持窗口矩形,不二次缩放。
- DWM:`DwmSetWindowAttribute`(dark mode/corner/backdrop)、`DwmExtendFrameIntoClientArea`(vibrancy)。
- 菜单:Win32 菜单;Win11 owner-draw;暗色菜单栏;菜单图标。
- 任务栏:进度条、跳转列表、缩略图工具栏。

### 2.4 WebView2

**Runtime 查找**:

1. `WEBVIEW2_BROWSER_EXECUTABLE_FOLDER` 固定版本。
2. 注册表 `SOFTWARE\Microsoft\EdgeUpdate\ClientState\{F3017226-...}`(Stable/Beta/Dev/Canary)。
3. 目录必须同时有 `msedgewebview2.exe` 和 `EBWebView\<arch>\EmbeddedBrowserWebView.dll`。
4. 都没有 → `WebViewAvailable=false`;仅原生 UI 的 app 仍可运行。

**初始化**:

- 可选 `WebView2Loader.dll`(exe 旁);否则直接加载 runtime 的 `CreateWebViewEnvironmentWithOptionsInternal`。
- 自实现 `ICoreWebView2EnvironmentOptions`(AdditionalBrowserArguments/Language/TargetCompatibleBrowserVersion)。
- 用户数据目录 `%LOCALAPPDATA%\<name>\WebView2`。
- 异步创建;失败重试 3 次(1s/2s);`E_ABORT` 不重试。
- 可选接口按 IID `QueryInterface` 降级:`_4`(下载)、`_8`(静音/音频)、`_11`、`_13`(Profile)、`_14`、`Controller2`、`Settings2/3/5/6`。
- Session:profile 名 `nimi-<UUID>`,临时 profile `nimi-private-<n>` + InPrivate。
- 权限/证书/下载/context menu/accelerator key。

**自定义 scheme**:

- WebView2 没有真正自定义 scheme API;映射为 `http://<scheme>.localhost/`。
- `AddWebResourceRequestedFilter` 拦截 `http://<scheme>.localhost/*` 和 `http://*.<scheme>.localhost/*`。
- 响应缓冲为完整 stream,`CreateWebResourceResponse` + `IStream`。
- `Content-Disposition: attachment` / `application/octet-stream` 走 `SchemeDownload`。
- `window.open` 重写 app scheme URL,保持 opener。

**Eval**:

- 优先 `ExecuteScript`;需要 Promise/异常细节时走 DevTools Protocol `Runtime.evaluate` + `awaitPromise`。
- 编辑命令 `document.execCommand`;Paste 用 `Input.dispatchKeyEvent`。
- 进程 ID:`get_BrowserProcessId`。

**原生 UI 中的 WebView2**:

- `CreateCompositionController` + `put_RootVisualTarget` → DirectComposition visual。
- Surface 在页面之上;鼠标 `SendMouseInput` 转发。
- 拖放用 `CompositionController3`。
- UIA 用 `get_AutomationProvider` 嵌入页面树。

### 2.5 原生 Surface + D3D11

- 子窗口 `MyGoSurface`,`WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS`;默认 `ImmAssociateContextEx(hwnd,0,0)` 禁用 IME。
- CPU: `SetDIBitsToDevice`;透明/材质窗口用 DirectComposition。
- GPU:
  - `D3D11CreateDevice` feature level 11_0 → 10_1 → 10_0;硬件失败 WARP。
  - `CreateSwapChainForHwnd`(flip model, `DXGI_SCALING_NONE`)或 `CreateSwapChainForComposition`。
  - `Present1` + dirty rects;frame latency waitable;`DwmFlush` pacing。
  - shader:预编译 DXBC(HLSL)嵌入;源码变更时 `d3dcompiler_47` 现场编译;effect 缓存。
- IME:
  - `ImmGetContext`/`ImmSetCompositionWindow`/`ImmSetCandidateWindow`/`ImmNotifyIME`。
  - `WM_IME_*` 消息;composition/caret DPI 换算。
- 可访问性:
  - `WM_GETOBJECT` → `UiaReturnRawElementProvider`。
  - 实现 `IRawElementProviderSimple/Fragment/FragmentRoot` + patterns(Invoke/Toggle/Selection/RangeValue/Value/ExpandCollapse/Selection/ScrollItem/Text)。
  - 树变更事件;`UiaClientsAreListening` 才更新。
  - TextProvider/TextRangeProvider 是最大工作量之一。

### 2.6 音频/打包

- WASAPI shared mode,事件驱动 10ms;默认设备变化重开。
- `windowsgui` 子系统;资源(图标/manifest/版本)用 `.rc`/`.res` 或生成的 `.syso` 等价物。
- NSIS 用户级安装 `%LOCALAPPDATA%\Programs\<name>`;开始菜单/桌面快捷方式;卸载项;文件关联/URL scheme;覆盖前关闭 app。
- 签名:`signtool` / `osslsigncode`;时间戳;只签无签名表的 PE;helper 也签。
- MSVC/UCRT 依赖:Nim 默认可能链接 MSVC 运行库;发布前确认静态链接或随包携带。

### 2.7 工作量与风险

| 阶段 | 估算 |
|---|---:|
| Win32 基础 + 窗口/菜单/DPI | 4–6 周 |
| WebView2 | 6–10 周 |
| Surface + D3D11 | 6–10 周 |
| IMM32 + UIA | 4–8 周 |
| 打包/签名/更新 | 3–5 周 |
| 测试/CI | 4–6 周 |
| **合计** | **4–8 月** |

**风险**:

- WebView2 接口版本/降级;runtime 缺失。
- Win32 窗口装饰/DPI 的版本差异(Win10/11)。
- D3D11/DirectComposition 与嵌入 WebView2 的合成竞争。
- UIA/IME 的测试难度。
- C 运行库依赖。

---

## 3. Linux 后端(`platform/linux`)

### 3.1 技术选型

| 层 | 方案 |
|---|---|
| GTK | GTK3,纯 `dlopen` 绑定(不用 gintro) |
| WebView | WebKitGTK 4.1(回退 4.0)+ libsoup3/2.4 |
| 原生 UI | GtkGLArea(GTK 3.16+);无 GL 时 GtkDrawingArea + cairo |
| 文本 | Pango + cairo(HarfBuzz 由 Pango 内置) |
| 输入法 | GtkIMContext |
| 可访问性 | ATK → AT-SPI |
| 音频 | PulseAudio simple → ALSA |
| 打包 | `.deb`、PKGBUILD、`install.sh` |

### 3.2 dlopen 绑定

- 入口:`platform/linux/ffi.nim`;`open(names...)` 支持多候选库名;`bind`/`mustBind` 注册函数指针。
- 硬依赖(7 个):
  - `libglib-2.0.so.0`
  - `libgobject-2.0.so.0`
  - `libgio-2.0.so.0`
  - `libgdk-3.so.0`
  - `libgtk-3.so.0`
  - `libcairo.so.2`
  - `libgdk_pixbuf-2.0.so.0`
- 懒加载:
  - WebKitGTK:`libwebkit2gtk-4.1.so.0` → `4.0.so.37`;JSC + soup 对应版本;通过比较库句柄判定 soup3。
  - AppIndicator、ATK、libsecret、X11、gtk-layer-shell、dbusmenu、libepoxy、libwayland-client、Pulse/ALSA、EGL、Pango、XTEST。
- 新符号用可选 `bind`,按存在性降级;`mustBind` 只用于硬依赖。
- 构建机不需要 GTK/WebKit 头文件;运行时缺库给出明确安装提示。

### 3.3 主循环与窗口

```text
Init
 ├─ load()
 ├─ 设置 WEBKIT_DISABLE_DMABUF_RENDERER=1(可配置)
 ├─ gtk_init_check(0,0)
 ├─ 读 GtkSettings(暗色偏好)
 ├─ 判断 X11/Wayland
 ├─ 绑定平台特有函数
 └─ 一次性创建 C 回调
Run
 └─ g_idle_add(ready) + gtk_main()
Signal → g_idle_add(dispatch),原子去重
Step   → g_main_context_iteration(NULL, TRUE)
Wake   → g_main_context_wakeup(NULL)
Quit   → 隐藏 modal + 退出嵌套 loop + gtk_main_quit()
```

- `IsMainThread`:`gettid() == getpid()`。
- 信号 `g_signal_connect_data`,user data 是窗口 ID;按 ID 找回对象,忽略已关闭窗口。
- **不要照搬 MyGo 的固定偏移读 GDK 事件结构**;Nim 用真实结构体绑定。

**窗口几何**(Linux 最大隐性复杂度):

- `Bounds` = WM frame extents(`gdk_window_get_frame_extents`);`ContentBounds` = 内容区。
- `SetBounds` 异步:GTK 在 configure 后确认;X11 reparenting WM 先按创建位置放 frame;Wayland 无位置。
- `UseContentSize`、不可缩放窗口的自然尺寸、`constrain`、`SetContentBounds` 都有专门逻辑。
- Frameless/hidden titlebar:外缘 5px 缩放,`gtk_window_begin_resize_drag`;Wayland 激活 configure 可能带回旧 buffer 尺寸,idle callback 再请求。
- Wayland CSD:空 `GtkHeaderBar` 让 GTK 画阴影/边框;X11 用 WM frame。
- maximize/fullscreen/tiled 由 `window-state-event` 维护。

### 3.4 WebView

- `webkit_user_content_manager_new` + `register_script_message_handler("nimi")`。
- `webkit_web_view_new_with_user_content_manager`。
- Settings:DevTools、file URL、clipboard、UA、背景节流、zoom、swipe、pinch。
- 信号:`load-changed`、`load-failed`、`notify::title`、`notify::is-playing-audio`、capture state、`decide-policy`、`create`、`close`、`web-process-terminated`、`button-press`、`motion-notify`、`drag-data-received`、`drag-drop`、`permission-request`、`context-menu`。
- 原生 UI 嵌入:`GtkOverlay` + `GtkLayout`;用 `gdk_window_input_shape_combine_region`/`shape_combine_region` 把洞透给页面;圆角 mask;Tab 在页面/原生 UI 间传递。
- 自定义 scheme:`webkit_web_context_register_uri_scheme` + secure/CORS;响应用 pipe + `g_unix_input_stream_new` 流式写;旧版无 `finish_with_response` 时降级。
- DMA-BUF:NVIDIA/VM/容器下可能空白,默认禁用;可配置。

### 3.5 原生 Surface + GL

- `GtkGLArea`(3.16+)或 `GtkDrawingArea`(无 GPU)。
- `gtk_gl_area_set_required_version(3,3)`;`set_auto_render(false)`;透明 `set_app_paintable`。
- GL 函数通过 `libepoxy.so.0` 加载;OpenGL 3.3 / GLES 3.0。
- 帧:GL 在 `render` 信号画;GTK frame clock 驱动。内存模式用 tick callback + cairo `draw`。
- `PresentPixels` cairo image surface;Wayland damage 用 `wl_surface.damage`。
- 输入:`button-press/motion/scroll/key-press/release/focus/scale-factor/touch/gesture`。
- IME:
  - `GtkIMContext`;`gtk_im_context_filter_keypress` 优先。
  - `set_surrounding`/`get_surrounding`/`delete_surrounding` 支持 Hangul 等。
  - 无输入法时走 keyval→Unicode。
- 拖放:`gtk_drag_dest_set`、`gtk_drag_get_data`、`gtk_drag_finish`、`gtk_drag_begin_with_coordinates`、`gtk_selection_data_set`。
- 触摸:`GDK_TOUCH_MASK`;tap/长按/双指缩放;转成鼠标/滚轮/zoom。
- 可访问性:
  - 动态注册 GObject 类型(`GtkWidgetAccessible`/`AtkObject` 及 range/text/editable/selection 接口)。
  - 校验 `atkObjectClassSize`;不匹配则放弃可访问性。
  - `UpdateAccessibility` 同步树;announcement(ATK 2.46)。
  - 页面用 `AtkSocket` 嵌入 WebKit 的树。
- 音频:PulseAudio simple → ALSA;48kHz/stereo/float32;10ms 写;失败退回静默设备并重试。

### 3.6 打包

- `.desktop`、hicolor 图标、MIME XML。
- `.deb`:纯 Nim 写 ar + control.tar.gz + data.tar.gz;安装 `/opt/<slug>`;`/usr/bin` 链接;依赖 `libgtk-3-0 | libgtk-3-0t64` + `libwebkit2gtk-4.1-0`(可配置)。
- `PKGBUILD`:Arch;依赖映射;`options=('!strip' '!debug')`。
- `install.sh`:POSIX sh;`~/.local/<name>.app`;`~/.local/bin` 链接;desktop/MIME;依赖检查;`--uninstall`;Ed25519 更新验签。

### 3.7 工作量与风险

| 阶段 | 估算 |
|---|---:|
| GTK dlopen + 主循环/窗口 | 3–5 周 |
| WebKitGTK | 5–8 周 |
| Surface + GL + IME | 5–8 周 |
| ATK/UIA 等价 | 3–6 周 |
| 打包 | 3–5 周 |
| 测试/CI | 4–6 周 |
| **合计** | **4–8 月** |

**风险**:

- X11/Wayland 窗口几何/CSD 是长尾工作。
- GTK3/WebKitGTK 版本矩阵 + 可选符号。
- ATK 二进制布局;GTK4 会重写。
- DMA-BUF/NVIDIA/VM/容器。
- 发行版依赖与 `linux.webview=false` 的一致性。
- GObject 信号/回调生命周期。

---

## 4. 共享抽象与差异

### 4.1 共享

| 层 | 说明 |
|---|---|
| Core | 完全共享 |
| 平台契约 | 完全共享 |
| Scene/UI/Text 布局 | 共享;文本引擎按平台替换 |
| Renderer 接口 | 共享;Metal/GL/D3D11 实现 |
| IPC/Bridge/TS | 完全共享 |
| CLI 配置/模板/打包编排 | 共享;平台分支 |
| 测试 harness | 共享;平台输入钩子不同 |

### 4.2 平台差异表

| 能力 | macOS | Windows | Linux |
|---|---|---|---|
| 窗口系统 | AppKit | Win32 | GTK3 |
| WebView | WKWebView | WebView2 | WebKitGTK 4.1/4.0 |
| 自定义 scheme | WKURLSchemeHandler | `http://<scheme>.localhost` 映射 | `register_uri_scheme` |
| 原生 UI surface | NSView + CAMetalLayer | 子窗口 + D3D11 | GtkGLArea |
| 文本 | CoreText | DirectWrite | Pango/cairo |
| IME | NSTextInputClient | IMM32 | GtkIMContext |
| 可访问性 | NSAccessibility | UI Automation | ATK/AT-SPI |
| 音频 | AudioQueue | WASAPI | Pulse/ALSA |
| 文件监视 | FSEvents | ReadDirectoryChangesW | inotify |
| 托盘 | NSStatusItem | Shell_NotifyIcon | AppIndicator |
| 全局快捷键 | Carbon | RegisterHotKey | X11/portal |
| 打包 | `.app`/`.dmg` | NSIS `.exe` | `.deb`/PKGBUILD/install.sh |
| 交叉编译 | macOS 上 | MinGW | Zig/sysroot + CI |

### 4.3 平台策略归属

- **可以放在后端**:窗口 frame extents、DPI 换算、CSD、DWM 材质、菜单渲染、原生对话框、托盘图标、IME 窗口定位、可访问性桥。
- **必须放在 core**:窗口注册表、事件顺序、退出序列、IPC 路由/信任、菜单模型/role、协议/CORS、会话/Cookie 规范、文档状态机、路径规则、单实例协议。
- **不要放在后端**:默认值、策略判断、状态机、重试/退避逻辑(除非是原生 API 必需)。

---

## 5. 构建与交叉编译

### 5.1 现实约束

MyGo 的卖点是"任意机器 `GOOS/GOARCH` 构建";Nim 需要目标 C 工具链/系统库:

| 目标 | 在 macOS 上 | 在 Linux 上 | 在 Windows 上 |
|---|---|---|---|
| macOS | ✅ clang + SDK | ❌ 需 macOS SDK(法律/技术限制) | ❌ |
| Windows | ✅ `nim c -d:mingw` + MinGW-w64 | ✅ mingw | ✅ MSVC/MinGW |
| Linux | ⚠️ Zig/交叉 clang + sysroot | ✅ | ⚠️ WSL/容器 |

### 5.2 建议策略

1. **M1–M7 只支持宿主平台构建**(macOS 上编 macOS)。
2. **CI 矩阵**:macOS runner 编 macOS;Windows runner 编 Windows;Linux runner 编 Linux。
3. **后续再提供 `nimi build -platform`**:
   - Windows:macOS/Linux 用 MinGW。
   - Linux:用 Zig 作为 C 交叉编译器 + sysroot;或 Docker 镜像。
   - macOS:只能在 macOS 上构建(签名/公证也需要)。
4. **不承诺 Go 式"一条命令全平台"**;文档明确每平台构建机要求。

### 5.3 依赖管理

- Linux 的 GTK/WebKit 用 `dlopen`,不链接;构建时只需 C 编译器。
- Windows 的 `winim` 头文件/导入库随 Nim 包提供;不需要安装 Windows SDK。
- macOS 的框架通过 `-framework` 链接;需要 Xcode Command Line Tools。
- Nim 标准库 + `nimble` 依赖尽量少;固定版本,避免供应链风险。

---

## 6. 实施顺序建议

| 顺序 | 内容 | 理由 |
|---|---|---|
| 1 | macOS 完整(M1–M7) | 验证架构/API/协议;最大用户群 |
| 2 | Windows Win32 + WebView2 | 用户群大;COM 工作量大但路径清晰 |
| 3 | Windows 原生 UI + D3D11 + IME/UIA | 可与 macOS 并行参考 |
| 4 | Linux GTK + WebKitGTK | 长尾兼容最多;放最后 |
| 5 | Linux 原生 UI + GL + ATK | 依赖 GTK 稳定 |
| 6 | 打包/更新/CI 补齐 | 三平台发布 |

**不要**在 macOS 的原生 UI 还没稳定时启动 Windows/Linux;否则三套后端会同时返工。

---

## 7. 测试与 CI

| 平台 | 测试 |
|---|---|
| macOS | 桌面会话 `nimble test` + E2E;签名/公证;Instruments |
| Windows | Windows runner;WebView2 Runtime;UIA/IME 手动 + 自动化;DPI 多屏 |
| Linux | `xvfb-run -a dbus-run-session`;WebKitGTK 容器;X11 + Wayland(Mutter/KWin);ATK/Orca |
| 跨平台 | 协议/TS/JSON/布局/场景黄金测试共享 |

- GUI 测试需要真实桌面/浏览器运行时;CI 成本高,但不可省。
- 自动化 socket 协议从 M1 就兼容 MyGo 的格式,复用测试工具。
- 每个平台至少一个"干净机器"发布测试。

---

## 8. 里程碑与预算(Windows/Linux)

| 里程碑 | 内容 | 工期 | 依赖 |
|---|---|---|---|
| M8a | Win32 基础 + 窗口/菜单/对话框/剪贴板/托盘 | 4–6 周 | M1 |
| M8b | WebView2 + IPC + 自定义 scheme | 6–10 周 | M8a |
| M8c | 原生 UI + D3D11 + IMM32 | 6–10 周 | M2/M3 |
| M8d | UIA + 打包/签名 | 4–8 周 | M8c |
| M9a | GTK3 dlopen + 主循环/窗口/菜单 | 3–5 周 | M1 |
| M9b | WebKitGTK + IPC + scheme | 5–8 周 | M9a |
| M9c | 原生 UI + GL + IME | 5–8 周 | M2/M3 |
| M9d | ATK + 打包 | 3–6 周 | M9c |

> 与 macOS 的共享层(M1–M3)完成后,Windows/Linux 可以并行;每平台 4–8 个月。

---

## 9. 关键决策待定

1. **GTK3 还是 GTK4?** 第一版 GTK3(与 MyGo 对齐,WebKitGTK 4.1 成熟);GTK4/WebKitGTK 6 作为 2.0 议题。
2. **Windows 用 winim 还是自建绑定?** 第一版 winim;COM/WebView2 自建。
3. **D3D11 还是先 Direct2D/DirectComposition?** 第一版 D3D11(与 scene/实例模型一致);可先 CPU 回退。
4. **Linux 是否支持 Wayland 优先?** 同时支持 X11/Wayland;测试矩阵优先 GNOME/Mutter + KDE/KWin。
5. **是否提供 Flatpak/Snap?** 后续;先 `.deb`/PKGBUILD/install.sh。
6. **Windows ARM64?** WebView2 支持;D3D11 支持;第一版 x64,ARM64 后续。
7. **Linux ARM64?** 后续;CI 用交叉编译 + 容器。

---

*本文档是 Windows/Linux 后端的规划;具体实现细节在 M8/M9 启动前展开为独立设计文档。*
