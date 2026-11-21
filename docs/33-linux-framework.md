# Linux 后端：GTK3、Cairo、WebKitGTK 第一切片

> 日期：2026-11-22 · 状态：第一切片已实现，待实机桌面复核
> 关联：[Windows/Linux 规划](06-windows-linux.md)、[平台契约](../src/nimi/platform/contract.nim)、[Linux CI](../.github/workflows/linux.yml)

## 1. 结论

Linux 已经可以作为**可用后端**启动 Nimi 应用：

- 原生 UI：GTK3 窗口 + `GtkDrawingArea` + Cairo/Pango 自绘，scene 渲染、布局、鼠标/滚轮/键盘、焦点、动画、菜单、对话框、剪贴板、文件监视都已接通。
- Web 页面：WebKitGTK 4.1（回退 4.0）加载 HTML/URL、注入 Nimi bridge、JS→Nim 消息、双向 eval、`nimi://` 自定义 scheme（由 `FileServer` 提供静态资源）、默认 Cookie 存储查询/清理。
- 桌面 API：显示器/工作区/缩放、光标位置、主题探测、显示与主题变化通知、libnotify 通知。
- CLI：Linux 主机上 `nimi build` 生成 `dist/linux-<arch>/<slug>`、复制 resources、生成 `.desktop`。
- 测试：Ubuntu 24.04 + xvfb + dbus 下 33 个共享/Linux 测试程序，包含 WebKitGTK 端到端测试；GitHub Actions `linux.yml` 覆盖同一套。

构建机不需要 GTK/WebKit 头文件：所有平台库通过 `dlopen` 在运行时加载。运行时只需安装 GTK3；只有页面窗口需要 WebKitGTK。

## 2. 实现结构

```text
src/nimi/platform/linux/
├── ffi.nim        # dlopen：GLib/GObject/GIO/GDK/GTK/Cairo/Pango/GdkPixbuf/WebKit/JSC/libsoup/libnotify
├── pangohelper.nim# Pango 字体描述、布局、测量、绘制
├── state.nim      # 后端/窗口共享状态（避免模块环）
├── app.nim        # 生命周期、dispatch/wake、契约装配
├── window.nim     # GtkWindow、drawing area、输入、动画、WebKitGTK、自定义 scheme
├── menu.nim       # GtkMenuBar、角色、快捷键、测试钩子
├── clipboard.nim  # UTF-8 文本 + text/html selection
├── cookie.nim     # WebKitCookieManager + libsoup
├── dialogs.nim    # GtkFileChooserNative、GtkDialog
├── desktop.nim    # GdkScreen/GtkSettings/libnotify
└── watch.nim      # inotify + GUnixFdSource
src/nimi/render/cairo.nim  # scene → Cairo：矩形/圆角/裁剪/文本/图片/纹理四边形/多边形/PNG
```

选择与 macOS/Windows 一致：`core/app.nim` 只在 `defined(linux)` 时导入 Linux 后端与 Cairo 渲染器；core/UI/scene/文本布局代码完全共享。

### 2.1 加载策略

- `ensureCore()`：Cairo、Pango、PangoCairo、GdkPixbuf、GLib、GObject。布局测量与离屏渲染只需要这些库。
- `ensureGtk()`：再加载 GDK3/GTK3，绑定窗口、输入、菜单、剪贴板、对话框符号。
- `ensureWebKit()`：按 `libwebkit2gtk-4.1.so.0` → `4.0.so.37` → `4.0.so` 顺序尝试，并加载 `libjavascriptcoregtk` 读取 JS 消息。缺失时原生窗口仍然工作，页面窗口抛出明确错误。
- `ensureNotify()`：`libnotify.so.4` 可选；缺失时通知静默降级。
- 所有 `mustBind` 失败都抛出带符号名的 `BackendError`；不会把空函数指针带进运行期。

### 2.2 主循环

- `init` 调用 `gtk_init_check`；无 display 时给出“安装 GTK3 / 使用 X11/Wayland / CI 用 xvfb-run”的错误。
- `run` 先触发 `AppHandler.ready`，再进入 `gtk_main()`。
- `signal`/`wake` 从任意线程调用 `g_idle_add`，在主上下文执行 `dispatch`（IPC 结果、`postMain` 队列）。
- `isMainThread` 用 Nim `getThreadId()` 与初始化线程比较。
- `step` 是单次非阻塞 `g_main_context_iteration(nil, false)`，供测试和主循环外驱动使用。

### 2.3 窗口与渲染

- 每个窗口：`GtkWindow` → `GtkBox`（菜单栏 + 内容）。内容为 `GtkDrawingArea` 或 `WebKitWebView`。
- `draw` 信号把 `cairo_t*` 直接交给 core 安装的 `drawScene`。scene 使用左上角坐标，与 macOS/Windows 契约一致。
- 文本使用 Pango `Sans`/`Monospace`，`pango_font_description_set_absolute_size(size * PANGO_SCALE)`，因此 `fontSize` 与 macOS/Windows 一样按像素解释，而不是 point。
- 字体测量使用 `pango_layout_get_extents` + `pango_context_get_metrics`，缓存仍由共享 `text/measure.nim` 负责。
- 图片通过 GdkPixbuf 解码，转换为 Cairo ARGB32 surface；裁剪结果按 `(path,x,y,w,h)` 缓存，条目上限与 CoreGraphics 一致。
- 纹理四边形对两个三角形分别裁剪，并把源图坐标仿射到目标四边形。
- 动画用 `g_timeout_add(1000/fps)`，单调时钟计算 `dt`，异常长帧钳制到 250 ms；`stopAnimation`/关窗会移除 source。
- `setAppearance(dark)` 修改 `GtkSettings` 的 `gtk-application-prefer-dark-theme`，这是应用级设置；GTK3 没有逐窗口深色标题栏 API。

### 2.4 输入与焦点

- 鼠标：按下/释放/移动/滚轮；双击计数在 400 ms + 4 px 内累计到 3。
- 滚轮：GTK 3.4+ smooth delta 优先，离散方向回退；Shift+滚轮走横向滚动。
- 键盘：GDK keyval 映射到共享 UI 键名（导航键、F1–F24、可打印 Unicode）。`KeyShortcut` 在 Linux 上是 Control，与 Windows 一致。
- `testClick`/`testKey`/`testKeyText`/`testKeyMods`/`testMenuKey` 已实现，测试不依赖合成原生事件。
- IME 尚未接入 `GtkIMContext`：当前输入法组合走 GTK 默认处理或普通 keyval，marked text 不进入共享 engine。这是下一阶段优先项。

### 2.5 菜单、对话框、剪贴板

- 菜单是窗口内 `GtkMenuBar`；应用级 `setMenu` 会重建所有窗口的菜单。
- 角色：quit/close/minimize/zoom/fullscreen/hide/hideOthers/showAll/bringAllToFront/about/undo/redo/cut/copy/paste/selectAll/delete；未知角色忽略。
- 快捷键语法与 Windows 相同（`cmd`/`ctrl`/`control` → Control，`alt`/`option` → Mod1，`shift`）。`testMenuKey` 直接查加速键表。
- 文件对话框用 `GtkFileChooserNative`，支持多选、目录、默认路径、扩展名过滤；取消返回空。
- 消息对话框支持自定义按钮，返回从 0 开始的索引；关闭/Esc 返回 `-1`。
- 剪贴板：`gtk_clipboard_wait_for_text`/`set_text`；HTML 通过 `text/html` target + GtkSelectionData 读写。非 UTF-8 或含 NUL 的文本抛 `ClipboardError`。
- 注意：`GtkTargetEntry` 必须用 `g_malloc0` 分配，因为 Nim `alloc0` 使用自有分配器，不能交给 `g_free`。

### 2.6 文件监视

- inotify：目录递归添加 watch，文件监视单个路径。
- GLib `g_unix_fd_add` 把 fd 可读事件接入主上下文，因此回调天然在主线程。
- 事件映射：CREATE→created、DELETE/MOVED_FROM→removed、MOVED_TO→renamed、CLOSE_WRITE/MODIFY/ATTRIB→modified（同一批事件内按路径去重）。
- 新建目录会补充 watch；删除/移走目录会回收整棵子树。
- `IN_Q_OVERFLOW` 报告根路径 modified，提示调用方重新扫描。

### 2.7 WebKitGTK

- 每个窗口独立的 `WebKitUserContentManager`：先连接 `script-message-received::nimi`，再注册 handler，然后注入 `bridgeJs`（secret/token 替换与 macOS 完全一致）。
- 页面侧仍是 `window.webkit.messageHandlers.nimi.postMessage`；WebKitGTK 原生提供该 API，无需 shim。
- `eval` 使用 `webkit_web_view_evaluate_javascript` 异步接口，回调中调用 `*_finish` 并释放 JSCValue。
- `nimi://` 等自定义 scheme 通过 `webkit_web_context_register_uri_scheme` 注册，响应体由 `core/fileserver` 的 `serve` 生成，使用 `GMemoryInputStream` 流式返回；同时注册为 secure 和 CORS-enabled。
- 页面加载失败写入 stderr（`nimi: page load failed <uri>: <message>`），避免静默白屏。
- Cookie：`webkit_cookie_manager_get_all_cookies`（WebKitGTK 2.42+）查询默认 profile 的全部 Cookie，`delete_all_cookies` 清空；`getCookies` 回调在主上下文执行，关停时会取消未完成请求的回调。旧版 WebKitGTK 没有 `get_all_cookies` 时返回空列表。
- 在容器/Xvfb 中测试 WebKit 需要：
  ```sh
  WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
  WEBKIT_DISABLE_DMABUF_RENDERER=1
  ```
  测试程序会自行设置；正常桌面应用不需要。

### 2.8 CLI 与分发

`nimi build` 在 Linux 上：

1. 编译 release 可执行文件到 `dist/linux-<arch>/<slug>`；
2. 复制 `resources` 到同目录；
3. 复制配置图标；
4. 生成 `<slug>.desktop`（Exec/Terminal/Categories/Icon，含 URL scheme handler）。

尚未生成 `.deb`/PKGBUILD/AppImage，也未做签名与更新。

## 3. 测试与 CI

### 3.1 本地

Ubuntu 24.04 依赖：

```sh
sudo apt-get install -y build-essential libgtk-3-dev libwebkit2gtk-4.1-dev \
  libnotify-dev xvfb dbus-x11 fonts-dejavu-core
```

运行：

```sh
xvfb-run -a dbus-run-session -- ./scripts/test-linux.sh
```

`scripts/test-linux.sh` 运行：

- 全部平台无关测试（IPC、UI、布局、IME 共享逻辑、Document、FileServer、shred、音乐队列等）；
- `test_render`（Linux 分支走 Cairo）；
- `test_linux_render`：像素/裁剪/圆角/Pango/PNG/图片四边形；
- `test_linux_backend`：窗口绘制、输入、菜单快捷键、剪贴板、屏幕/主题/通知、inotify；
- `test_linux_app`：`app.run` 完整生命周期、ready、原生窗口、动画帧、退出清理；
- `test_linux_webview`：WebKitGTK 页面消息、eval、`nimitest://` scheme、Cookie 查询/清理；
- Subsonic fixture。

### 3.2 CI

`.github/workflows/linux.yml` 在 `ubuntu-24.04` 上安装 GTK3/WebKitGTK/notify/xvfb/dbus，执行同一脚本，然后构建 CLI 与 `counter-native`、`widgets-native`、`desktop-native`、`hello`。

## 4. 已验证 / 待验证

已验证（2026-11-22，Ubuntu 24.04 arm64 容器 + Xvfb；Linux 套件 33 个程序、195 项检查全部通过）：

- `test_linux_render`：6 项通过（像素/裁剪/圆角/Pango/PNG/图片与纹理四边形方向）。
- `test_linux_backend`：5 项通过（窗口/绘制/输入/菜单、ready 前退出、剪贴板、桌面 API、inotify）。
- `test_linux_app`：ready → 创建原生窗口 → 3 帧动画 → quit → shutdown 通过。
- `test_linux_webview`：WebKitGTK 页面消息、eval、自定义 scheme、Cookie 查询/清理通过。
- `counter-native` 在 Xvfb 下持续运行，无启动崩溃。
- `hello` 在 Xvfb + WebKitGTK 下完成真实页面 IPC：`Greeter.greet` 与 `AppControl.emitPing` 都由页面调用成功。
- `notes` 使用 `nimi://app/index.html` 启动，未出现加载失败。
- `nimi build` 已构建 `counter-native`、`widgets-native`、`desktop-native`、`hello`、`notes`、`music`。
- 共享 `test_render`、`test_ui` 在 Linux 上通过；macOS 全量回归 186 项仍通过。

仍需人工复核：

- 真实 GNOME/KDE 桌面下的窗口装饰、最大化/全屏、HiDPI 多屏、Wayland 行为。
- 中文/日文输入法的组合窗与候选窗（当前未接 GtkIMContext）。
- 系统托盘、全局快捷键、媒体键、音频。
- WebKitGTK 真实页面的下载、权限请求、context menu 与多窗口 `window.open`。
- `.deb`/PKGBUILD 与桌面菜单安装。

## 5. 明确未实现

| 能力 | 当前行为 | 后续 |
|---|---|---|
| 原生托盘 | `newTray` 抛 `UnsupportedBackendError` | AppIndicator / StatusNotifier |
| 全局快捷键 | 返回 false，不崩溃 | X11 XGrabKey / XDG portal |
| Now Playing / 媒体键 | 抛 `UnsupportedBackendError` | MPRIS2 |
| 本地音频 | `openAudio` 抛 “macOS-only” | PulseAudio → ALSA |
| IME | 普通键值输入；无 marked text | GtkIMContext |
| 无障碍 | 无 ATK provider | ATK/AT-SPI |
| GL surface | 仅 Cairo CPU 路径 | GtkGLArea / EGL |
| 拖放 | 未接 | GtkSelection |
| 打包 | 仅目录 + `.desktop` | .deb/PKGBUILD/AppImage |

## 6. 设计决策

1. **GTK3 而不是 GTK4**：与 MyGo 对齐、WebKitGTK 4.1 稳定、生命周期更长；GTK3 仍是 Ubuntu 24.04 的默认可用栈。
2. **纯 dlopen**：构建机无 GTK 头文件，CI 之外也能只在运行时安装依赖；代价是符号名拼写/版本矩阵必须由测试覆盖。
3. **Cairo CPU 优先**：与 CoreGraphics/GDI 路径一致，先保证 scene/控件/文本正确；GL/Metal 等价物后续再加。
4. **菜单栏放在窗口内**：Linux 桌面没有 macOS 的全局菜单栏；每个窗口拥有自己的 GtkMenuBar，应用级 setMenu 广播重建。
5. **WebKit 可选**：只使用原生 UI 的应用不需要 WebKitGTK；页面窗口在缺库时给出明确错误。
6. **不共享 Windows 的 menuplan**：Windows 的 VK 码/角色校验与 GTK keyval 不同；Linux 用自己的解析器，但快捷键语法保持一致。

## 7. 下一步

1. GtkIMContext：组合串、候选窗定位、提交/取消，接入共享 IME engine。
2. WebKit cookie manager + 下载/权限/新窗口回调。
3. MPRIS2 + PulseAudio，让 `examples/music` 跑通。
4. X11 全局快捷键与 AppIndicator 托盘。
5. `.deb`/PKGBUILD、桌面安装脚本、真实桌面验收脚本。
6. HiDPI/Wayland 专项：缩放、frame extents、CSD、全屏恢复。
