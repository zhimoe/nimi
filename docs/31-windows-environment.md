# Windows GUI 开发回检与环境变量工具

> 2026-11-12 范围校正：主目标是补齐 **Nimi Windows 框架能力**；环境变量管理器只是驱动开发和验收的 demo，不作为独立产品持续扩展。Windows 自动化运行已由 `windows-latest` CI 覆盖（2026-11-13 首次全绿）；交互式人工验收仍需实机。下方历史记录中的“受阻”仅适用于人工运行验收，不能代表整个框架开发无法推进。
>
> 当前框架阶段：原生 GUI、WebView2 与 Win32 桌面 API 首版已接通，尚非完整 Windows 后端。已接入 core 生命周期、Win32 窗口/派发、GDI rect/text/clip/图像/多边形、动画帧驱动、基础输入、IME 组合/候选窗、菜单/文件对话框/剪贴板、WebView2 + IPC + `nimi://` 协议、显示/主题/光标/全局快捷键、环境变量注册表工具，以及 `nimi build` 的 exe/资源/manifest/WebView2Loader。仍缺托盘/通知/文件监视/Cookie/NowPlaying、图像四边形/文字 alpha/D3D11，以及 Windows 实机运行验收。
>
> 后续优先级：① 统一未实现 API 的错误边界，补窗口/DPI/生命周期契约；② 文件打开/保存对话框与菜单；③ IME 组合/候选窗、键盘和焦点完整性；④ 补 scene 图像/多边形、动画计时与渲染测试（2026-11-13 已完成源码并在 Windows CI 执行通过）；⑤ 接入 Windows CLI 构建/资源/manifest（2026-11-13 已完成源码并在 Windows CI 执行 `nimi build examples/hello`）；⑥ WebView2、协议与 IPC（2026-11-13 已完成源码，WebView2 IPC 与 `nimi://` 协议测试在 Windows CI 通过）；⑦ 托盘/通知/监视等桌面能力（屏幕/光标/主题/全局快捷键已于 2026-11-13 实现并通过 Windows CI；托盘/通知/监视仍待补）。环境变量 demo 用于验证前五项，不再把业务备份等细节作为主线。Windows 运行验证贯穿各阶段。

回检日期：2026-11-11。对照本地 MyGo `f234638d`，不是在线最新版。

## 当前进展与差距

源码依据：`src/nimi/core/app.nim` 的平台选择、`src/nimi/platform/contract.nim`、`src/nimi/platform/darwin/`；MyGo 对照 `mygo/internal/windows/`、`mygo/internal/e2e/*windows_test.go`。更广泛的能力映射见 [30](30-mygo-alignment.md)。

| 能力 | Nimi 当前证据 | Windows 尚缺 |
|---|---|---|
| 应用/窗口 | core 生命周期、Backend 契约、Darwin 后端 | Win32 host 首版已有消息循环、窗口销毁、调度、DPI 消息处理；已接入 core 和基础 GDI 绘制，运行未验收 |
| WebView/IPC | macOS WKWebView、类型化 IPC、后台池 | WebView2 初始化、导航、消息桥、资源协议、安全限制 |
| 原生 UI | scene、布局、输入、基础控件、虚拟列表；CG/CoreText 渲染 | GDI 文本/rect/clip、WIC 图像（含缓存）与半透明多边形、键鼠/Unicode、文本剪贴板、IME 组合/候选窗首版已有；图像四边形、文字 alpha、D3D11 待补 |
| 桌面集成 | Darwin 菜单、对话框、托盘等 | Windows 实现及逐项能力声明，不能调用空回调 |
| 业务示例 | Notes、Music 等 macOS 示例 | 环境变量 GUI 已实现并交叉编译；尚缺运行及交互验收 |
| 分发 | macOS CI、app/DMG | exe、图标/manifest、安装/签名、Windows CI 与运行验收 |

MyGo 已有 Windows 平台实现及窗口、WebView、菜单等 E2E 测试。Nimi 的差距首先是平台执行链，不是再增加几个 UI 控件。此前 README 的 M1–M7 状态是 macOS 功能切片，不能推导三平台完成。

## 按顺序实施

1. **环境变量领域模型**：作用域、原始值/类型、PATH 无损拆分合并、保存前冲突检查。已实现 `core/environment.nim`，3 项本地测试通过。
2. **Windows 持久化**：HKCU Environment / HKLM Session Manager Environment，Unicode 注册表读写、枚举、删除、WM_SETTINGCHANGE。首版已实现 `platform/windows/environment.nim`；Windows 目标静态检查及 Zig 交叉编译通过，运行尚待 Windows 集成测试。系统写入按当前权限返回错误。
3. **Windows 窗口纵向切片**：实现 Backend init/run/quit/signal/newWindow，尺寸、关闭和 DPI；建立可运行最小示例。已加入 `platform/windows/app.nim` 与薄 C host，以及 `tests/test_windows_host.nim`；Windows x64 交叉编译通过。现已接入 core 启动路径、scene surface、GDI 文本测量与基础绘制；明确拒绝尚未实现的 WebView。`test_windows_surface.nim` 覆盖 core 到真实 paint 的链路，尚待 Windows 执行。
4. **GUI 所需渲染/交互**：优先让列表、文本输入、按钮、选择、滚动、键盘焦点、中文输入可用；复用现有 UI 状态机，接 Windows 绘制和输入桥。已实现基本键鼠、滚轮、UTF-16 输入、Ctrl 快捷键、文本剪贴板与 OK/Cancel 确认框；IME 组合和候选窗定位已有首版。GDI 支持 rect/text/clip、WIC 图像（128 项缓存）和半透明多边形，并接入 `SetTimer` 帧驱动与单调时钟 dt；图像四边形和文字 alpha 仍未实现。WebView2 仍未实现。
5. **环境变量编辑器**：`examples/environment/`，用户/系统切换，变量列表、新增/编辑/删除确认，PATH 分项增删排序，保留展开类型，刷新、未保存提示、错误反馈。首版已实现上述界面，系统权限不足作为错误显示；不自动提升整应用权限。Windows x64 GUI 子系统 exe 已成功交叉编译。
6. **可恢复编辑**：写入前导出原始名称/作用域/类型/值，提供显式恢复；恢复同样检查外部变更。已实现逐次 JSON 恢复记录、显式恢复与冲突检查；保存失败保留编辑内容，广播失败提示“已保存，通知超时”。控制器测试验证保存/恢复/删除/冲突与权限失败后保留草稿。
7. **交付验收**：Windows 10/11 编译运行、中文/PATH/空值/删除/冲突/权限失败、重启后读回，GUI 实测与截图，发布 exe 和使用说明。正常用户变量操作不需要管理员权限。

## 当前验证与边界

- `nim c -r --hints:off tests/test_environment.nim`：已通过。
- `./scripts/test.sh`：本次完整执行成功（退出码 0，包含新增环境变量测试）。现有 Subsonic 测试仍有 md5/sha1 弃用警告。
- `nim check --os:windows --cpu:amd64 src/nimi/platform/windows/environment.nim`：已通过，仅语义检查。
- `tests/test_environment_windows.nim`：Windows 集成测试，使用唯一临时 HKCU 变量并清理，覆盖 Unicode、展开类型、空值、枚举、大小写查找、删除。已在 Windows CI 执行通过（run 43396708087）。
- `.github/workflows/windows.yml`：已配置 Windows 测试，未触发远端工作流，不能当作已通过证据。
- 保存前比较不构成注册表事务，比较与写入之间仍可能出现并发竞态。
- 不调用 `setx`，不展开 `%VAR%`，不对 PATH 自动去重/去空项；已运行进程不会因为广播自动重建自身环境。
- 当前主机 macOS 无 MinGW/Wine，但可用 Zig 0.17.1。`./scripts/windows-cross-build.sh` 已成功将领域测试、注册表集成测试、Win32 host/surface/render/animation 测试编译为 Windows x64 PE 可执行文件，产物位于 `dist/windows-tests/`。这证明编译/链接通过，不等于运行通过。
- Win32 host 测试覆盖 ready、消息派发、关闭拦截、幂等 destroy 和 terminated；已在 Windows CI 执行通过。当前 DPI 消息会采用系统建议矩形，逻辑尺寸换算/缩放绘制仍需随渲染接入实现。
- 环境变量 GUI 位于 `examples/environment/`；使用与构建说明见该目录 README。应用 exe 已生成至 `dist/windows-tests/NimiEnvironment.exe`，实机交互验收尚未完成。目标保持进行中。
- 本轮 macOS 完整回归通过；新增控制器测试单独执行通过。Windows 自动化测试已于 2026-11-13 在 `windows-latest` 全绿；交互式人工验收仍未完成，不能据此声称所有视觉/输入行为均已验收。

构建注记：Nim 2.4.0 的 `--app:gui` 遇到运行库 `MessageBoxA` 声明顺序错误，因此使用显式链接器 `--passL:-Wl,--subsystem,windows`。已直接检查产物 PE header 的 Subsystem = 2，确认应用为 GUI 子系统；测试程序仍使用 console 子系统。


## 本轮交互验收与修复

- 将真实应用视图抽到 `examples/environment/view.nim`，注入存储和确认函数；Windows 入口仍使用同一视图。`tests/test_environment_ui.nim` 通过 UI 按钮验证变量选择、PATH 排序/删除、保存/恢复和丢弃确认。
- 测试实际发现并修复循环闭包捕获最后一项的错误，避免变量选择及 PATH 按钮作用于错误条目。
- 视图在窄窗口改为上下排列，整页可滚动；640×480 下验证恢复操作仍可到达。单行输入增加裁剪、跟随光标的横向滚动，点击定位及候选位置使用同一偏移。
- 已检查 [940×790 布局](assets/environment-editor-macos-fixture.png) 与 [640×480 滚动布局](assets/environment-editor-narrow-macos-fixture.png)。这些图来自 **macOS CoreGraphics + 内存测试数据**，证明共享布局与交互，不是 Windows/GDI 截图。
- 发现 UTM 中已有 `tiny11 core ARM64` 虚拟机。尝试启动后，`utmctl exec` 多次返回“QEMU 客户机代理没有运行或未安装”；CUA 获取 UTM 窗口返回 `cgWindowNotFound`。未取得 Windows 运行证据。已发送正常关机请求，并确认虚拟机回到 stopped。
- Windows 运行验收仍需可操作的虚拟机窗口或客户机执行通道，当前不标记目标完成。


验证补充（2026-11-12）：

- 更新后的 Windows 交叉构建完成，应用 PE Subsystem 再次确认是 2（GUI）。
- 环境变量领域、控制器、共享 GUI 测试，以及 UI 横向滚动测试通过；`git diff --check` 通过。
- **本轮完整回归未全绿**：原有 `test_audio.nim` 两个播放相关测试失败（`play()` 返回 false、完成回调未触发）；单独复跑仍失败。补跑后续测试，Subsonic 的音频播放断言也失败，其余后续检查通过。系统仍列出默认扬声器，不能仅凭现象认定是设备缺失。未修改音频实现，也未跳过或放宽相关测试；原因尚未定位。
- 前文“完整回归通过”记录的是之前轮次，不能作为本次工作树全量通过的证据。


后续开发与验收准备（2026-11-12）：

- PATH 分项草稿纳入未保存判断；未应用的草稿会阻止保存、重排和整值覆盖，并支持显式放弃。选择其他分项、切换变量/作用域、刷新及关窗均不会静默丢弃草稿。非法分项验证失败时保持原选中项和值。
- 作用域切换先读取目标列表，失败时保留原作用域、变量列表、选中项和未保存内容。新增失败回滚测试通过。
- 新增 `tests/test_environment_app_windows.nim`：真实 Win32 绘制后通过共享界面执行新建、Unicode/展开类型保存、修改、备份恢复和删除，再读回真实 HKCU 注册表核对。测试仅使用唯一临时变量并清理；已经交叉编译，**未在 Windows 运行**。
- 已准备 Windows CI，并查询现有远端运行；未发现这批代码的 Windows 验证结果。未提交或推送本地改动。已请求确认是否允许推送独立分支以运行 CI；不合并 main，保留原有工作树改动。
- 当前剩余完成门槛仍是 Windows 执行和实际界面验收，不能用测试可编译替代。若没有可用虚拟机/远端运行授权，本目标不能标记完成。


当前验收边界：PATH 草稿保护、作用域失败回滚、嵌套滚动的完全裁剪命中修复均已通过本机测试。UI 测试与工具交叉构建已更新。Windows 运行通道仍不可用，独立分支 CI 推送确认尚未收到；没有把编译成功或 macOS 预览当作 Windows 验收完成。此前音频播放测试失败记录仍有效，尚未宣称全量回归恢复通过。

## GDI 图像/多边形与帧驱动（2026-11-13）

- `platform/windows/graphics.c` 新增 WIC 图像解码：PNG/JPEG/BMP/GIF 等经 `IWICFormatConverter` 统一为 32bpp PBGRA，`AlphaBlend` 绘制；`render/gdi` 提供 128 项路径缓存及 `clearImageCache` / `setImageCacheLimit` / `imageCacheStats`，与 macOS CoreGraphics 的同名接口对齐。当前是条目上限，不是字节预算或 LRU。
- 新增 `opPolygon`：用 GDI path + `SelectClipPath` 处理 DPI 世界变换，支持不透明与半透明填充。
- 新增 Win32 动画定时器：`SetTimer` 触发帧消息，Nim 侧用 `getMonoTime()` 计算单调时间与 dt，并钳制异常长帧；`startAnimation` / `stopAnimation` 已接入平台契约。`SetTimer` 分辨率约 15.6 ms，120 fps 实际会被系统节流，后续可换高精度定时器或 D3D11 呈现循环。
- 新增测试：`tests/test_windows_render.nim`（真实窗口绘制 + WIC 缓存命中 + 半透明多边形）与 `tests/test_windows_animation.nim`（帧计数、dt 范围、停止与关窗）。两者已加入 Windows CI 和交叉构建，**尚未在 Windows 运行**。
- 仍未实现：`opImageQuad`、文字 alpha、D3D11 后端；这些不影响当前环境变量 demo 和基础原生 UI。

## Windows CLI 构建（2026-11-13）

- `nimi build <dir>` 在 Windows 主机上输出 `dist/windows-<arch>/<slug>.exe`，并把 `nimi.json` 的 `resources` 复制到同目录的 `resources/`。macOS 仍走原有 `.app`/DMG 路径。
- 图标读取 `windows.icon`，缺省回退到顶层 `icon`。支持 `.ico`，或不超过 256×256 的 PNG（纯 Nim 包装成单条目 ICO，PNG payload 由 Vista+ 支持）；更大的 PNG 会警告并跳过图标。这与 macOS 用 1024×1024 PNG 生成 `.icns` 的路径不同，Windows 项目需要单独准备 `windows.icon`。
- 找到 `windres` 时生成 `.rc`，把图标和 manifest 编译为 COFF 资源并链接进 exe。manifest 声明 `asInvoker`、`PerMonitorV2` 和 `longPathAware`；找不到 `windres` 时警告并继续构建，不阻断 exe。
- 链接使用 `--passL:-Wl,--subsystem,windows` 选择 GUI 子系统，继续规避 Nim 2.4.0 `--app:gui` 的 `MessageBoxA` 声明顺序问题。
- 新增 `tests/test_cli_windows.nim` 覆盖 ICO 结构、非法/超大 PNG 拒绝和 manifest 内容；本机通过并加入交叉构建。Windows CI 现在会构建 `nimi.exe`、运行 `nimi version`、并执行 `nimi build examples/hello`，首次获得真实 Windows 打包路径的执行结果。
- 限制：当前是 MinGW 风格链接参数；未适配 MSVC `rc.exe`/`link.exe`，未生成安装器、代码签名或自动更新。`resources/` 的运行时定位约定仍需写进应用模板。

## 屏幕、光标、主题与全局快捷键（2026-11-13）

- `screens()` / `primaryDisplay()`：`EnumDisplayMonitors` + `GetMonitorInfoW`，每个显示器返回逻辑坐标（相对主屏左上角，按主屏 DPI 换算）、工作区、`scale` 与主屏标记；`GetDpiForMonitor` 从 `shcore.dll` 动态加载，缺失时回退 96 DPI。
- `cursorPosition()`：`GetCursorPos` 转为主屏逻辑坐标。
- `themeInfo()`：读取 `AppsUseLightTheme` 与 DWM `AccentColor`（ABGR），缺失时回退浅色/系统蓝；`onThemeChanged` 由 `WM_SETTINGCHANGE("ImmersiveColorSet")` 与 `WM_THEMECHANGED` 触发，`onDisplayChanged` 由 `WM_DISPLAYCHANGE`、`WM_DPICHANGED` 与 `WM_SETTINGCHANGE("WindowMetrics")` 触发。
- `registerGlobalShortcut` / `unregisterGlobalShortcut` / `unregisterAllGlobalShortcuts`：复用菜单的 accelerator 解析，映射到 `RegisterHotKey`；热键注册在 host 的 message-only 窗口上，`WM_HOTKEY` 经 `NIMI_HOTKEY` 回到主线程。退出时统一注销。
- 新增 `tests/test_windows_desktop.nim`：显示器/工作区/scale、主屏、光标、主题通道范围、全局快捷键注册与注销；已交叉编译并加入 Windows CI，**尚未在 Windows 运行**。
- 混合 DPI 多显示器的坐标换算采用“主屏 DPI 定位、各自 DPI 计算尺寸”的近似方案，仍需实机校准。托盘、通知、文件监视、Cookie/NowPlaying 与 WebView2 仍未实现。

## WebView2、IPC 与 `nimi://` 协议（2026-11-13）

- Vendor 了 WebView2 SDK `1.0.4314.35` 的 `WebView2.h`、x64/arm64 `WebView2Loader.dll` 及 Microsoft `LICENSE.txt` / `NOTICE.txt`，位于 `src/nimi/platform/windows/webview2/sdk/`。MinGW 缺少的 `EventToken.h` 用最小本地兼容头补齐。
- `webview2.c` 动态加载 `WebView2Loader.dll`（先找 exe 目录，再回退到源码树路径，便于 `nim c -r` 开发），同步检查 WebView2 Runtime 是否存在，然后异步创建 environment/controller。加载、导航与 `eval` 在 controller 就绪前排队。
- 页面桥接保持与 macOS 相同的 `window.__nimi` / `window.nimi` 协议；注入的 shim 把 `window.webkit.messageHandlers.nimi.postMessage` 转发到 `chrome.webview.postMessage`，`WebMessageReceived` 再回到 core 的 `WindowHandler.message`。Nim→页面的 resolve/reject 仍走 `ExecuteScript`。
- `nimi://app/...` 通过 `ICoreWebView2_3::SetVirtualHostNameToFolderMapping` 映射到 FileServer 根目录，内部重写为 `https://app.local/...`；`loadHTML` 使用 `NavigateToString`，非空 baseURL 会注入 `<base>` 标签。
- `nimi build` 会把对应架构的 `WebView2Loader.dll` 复制到 exe 同目录。`ephemeral` 会话使用临时用户数据目录，关闭后尽力删除。
- 新增 `tests/test_windows_webview.nim`（inline HTML → `Greeter.greet` → `Shell.report` 的完整 IPC 往返）与 `tests/test_windows_webview_protocol.nim`（`nimi://app/index.html` 自定义协议）；已加入交叉构建与 Windows CI，**尚未在 Windows 运行**。
- 已知限制：baseURL 为 `file://` 时相对资源可能被 WebView2 的 origin 策略阻止；自定义协议目前固定映射 `app` 主机；WebView2 Runtime 缺失时窗口创建失败并给出错误；loader/运行时版本兼容性、DPI、IME 与真实页面交互仍需实机验收。

## Windows CI 编译器栈（2026-11-13）

- Nim 2.4.0 的 Windows 编译器二进制默认只有 2 MiB 栈，`nim check src/nimi/ui/context.nim` 会以 `0xC00000FD`（STATUS_STACK_OVERFLOW）崩溃；macOS 上 2 MiB 可过，1 MiB 会复现。
- `.github/workflows/windows.yml` 在测试前直接修改 `.nim_runtime/bin/nim.exe` 的 PE32+ `SizeOfStackReserve` 到 8 MiB，不依赖 Visual Studio 的 `editbin`。这是 CI 侧缓解，长期仍应拆分 `ui/context.nim` 或等待编译器修复。
- Windows CI 现在用 PowerShell 循环跑全部 Windows 测试并在最后汇总失败项，避免第一个失败就遮住后续结果。

## 首次 Windows 自动化验收（2026-11-13）

- GitHub Actions `windows-latest`，run [43396708087](https://github.com/zhimoe/nimi/actions/runs/43396708087)，**success**，耗时 3m48s。
- 19 个 Windows 测试全部通过：输入/IME、原生剪贴板、菜单规划与回调、平台契约、环境变量领域与 HKCU 注册表、Win32 host 生命周期/DIP 客户区/全屏恢复、GDI surface、**WebView2 IPC 往返**、**`nimi://` 自定义协议**、显示器/主题/快捷键、动画帧、GDI 图像/多边形、CLI ICO/manifest、环境变量编辑器/UI/真实 GUI 绘制。
- `nimi 0.1.0` 构建成功；`nimi build examples/hello` 产出 `dist/windows-amd64/hello-nimi.exe`，并复制 `WebView2Loader.dll`。
- 本轮修出的真实 Windows 问题：帧回调内 `stopAnimation` 导致 seq 迭代崩溃；全屏恢复丢失客户区尺寸；Windows 会规范化无终止符的剪贴板文本；渲染测试等待不存在的第二次 paint。
- 仍需人工/交互验收：真实键鼠与微软拼音/日文 IME、候选窗、混合 DPI 多显示器、WebView2 视觉/输入/下载、托盘/通知/监视、安装器与代码签名。

## EnvMan 对等实现（2026-11-16）

主目标仍是补齐 Nimi Windows 框架能力；环境变量管理器现在同时作为完整验收应用。决策：完整功能对等、系统标题栏 + DWM 深色、中文界面。

### 框架能力

- `src/nimi/ui/context.nim`：
  - flex/盒模型：`grow/basis`、`alignItems/justifyContent/alignSelf`、margin、四边 padding、min/max、`fillWidth/fillHeight`、`spacer`；fixed-size 容器在测量子节点时使用自身尺寸，避免固定面板内溢出；两遍 arrange 让 scroll 偏移在最终视口尺寸上收敛。
  - 容器绘制：背景、圆角、1px 边框、`clipChildren`（命中裁剪同步）。
  - 交互：`buttonBase`、`whenClicked/whenDoubleClicked/whenActivated/whenSpacePressed/whenSubmitted`、hover/pressed、focus/tabStop、焦点请求、带修饰键的应用快捷键注册（优先于文本编辑，Ctrl+A/C/X/V/Z/Y 保留）。
  - 顶层：`overlay(c, modal)` 覆盖层；sheet/modal/toast 都基于它；modal 只在顶层参与 Tab；非 modal toast 不阻塞背景。
  - 文本：`opText.family`（`"mono"` 映射平台等宽字体）；等宽/粗体/对齐/单行省略；`richText` 单行 runs（`%VAR%` 与搜索高亮）；多行输入 `noWrap`、行号 gutter、横向光标滚动。
  - 自定义绘制节点 `custom` + 24×24 矢量图标（`examples/environment/icons.nim`）。
- 场景/渲染：`opClip` 支持圆角裁剪；CG 用 `CGPathCreateWithRoundedRect`，GDI 用 `RoundRect` path + `SelectClipPath`。
- Windows 文本性能：GDI 字体与测量 DC 缓存、`measureText`/`layoutText` 有界缓存；GDI mono + CJK 使用 `NSimSun` 回退。
- Windows 桌面：`NativeWindow.setAppearance` → `DwmSetWindowAttribute`（属性 20，回退 19）；`getSize/getPosition`；`textScale()`、`highContrast()`、`isElevated()`、`relaunchElevated()`、`expandEnvironment()`。
- 窗口状态：设置保存/恢复客户区逻辑尺寸和物理屏幕位置；关闭时保存。

### 应用

- `examples/environment/` 拆分为 `state/model/service/storage/theme/widgets/icons/view*/main/capture`；旧单页 `view.nim` / `editor.nim` 已替换。
- 主界面：侧栏（双范围/快速查看/admin/备份/主题）、搜索、筛选、排序、tri-state 多选、复制/导出、缺失路径、内联展开多值、等宽 rich text、行 hover/focus。
- 编辑 sheet：文本/列表模式、原始空项保留、PATH 分项增删改序、重复警告、`%VAR%` 解析预览、类型/作用域信息、删除、脏检查、Ctrl+S/Ctrl+Enter/Esc。
- 批量编辑器：行号 + noWrap、实时新增/移除/顺序/重复分析、空值清空确认、应用前备份。
- 备份：整 scope 快照最多 20；恢复确认并再次备份；8 秒撤销 toast（merge 保留无关外部修改）。
- 提权：系统变量写入 → 快照 → `pending.json` → `ShellExecuteExW runas` → 退出；提权实例 claim/apply/complete；失败保留 `.interrupted.json`；UAC 取消保留应用。
- 主题：EnvMan 调色板/metrics；浅色/深色/跟随系统；高对比度黑白回退；DWM 深色同步。
- 数据目录：`%LOCALAPPDATA%\Nimi\Environment`，支持 `--data-dir=`。

### 测试与验证

- 新增 `test_layout_legacy/test_ui_layout/test_ui_widgets`：旧布局几何冻结、flex、容器/裁剪、buttonBase、overlay、焦点/快捷键、rich text、noWrap 行号。
- 新增 `test_environment_model/test_environment_storage/test_environment_app`：领域、快照/pending/settings、搜索/筛选/多选、创建/编辑/删除、PATH 列表、批量、备份恢复、主题、脏检查、UAC pending 全流程。
- `test_environment_ui` 重写为主界面/sheet/batch/backups/深色截图与边界检查；`test_environment_app_windows` 重写为真实 Win32 绘制 + HKCU 临时变量 CRUD/恢复，并检查窗口尺寸与 DWM 调用不崩溃。
- `./scripts/test.sh` 全绿；`./scripts/windows-cross-build.sh` 全量交叉编译通过，`NimiEnvironment.exe` PE Subsystem = 2（GUI）。
- Windows CI 增加新测试与 `nimi build examples/environment`；尚未触发远端运行，需推送后确认。

### 仍未完成

- Windows 实机人工验收：中文/emoji、微软拼音/日文 IME 与候选窗、混合 DPI 多显示器、DWM 深色视觉、UAC 弹窗与提权后读回、安装器/签名。
- 自绘无边框标题栏、D3D11/DirectComposition/DirectWrite、无障碍 UIA。
- 2026-11-19 已补图像四边形、托盘、气泡通知、文件监视和默认 WebView2 Cookie API，等待 Windows 验收。NowPlaying 与媒体键仍待实现。[Windows 框架状态](32-windows-framework.md)

### GUI 复检

- 批量编辑器的横向滚动按最长行计算范围，保留固定行号。Windows 支持横向滚轮和 Shift+滚轮，手动平移时保留当前光标及选区。
- 窄窗口下编辑区、解析预览上下排列。变量过多或名称过长时改用可滚动的目标选择器，切换目标仍保留原有的草稿确认。
- 启动时把窗口恢复到最近显示器的可用工作区，保留容得下的已保存尺寸。此路径使用 Win32 的物理窗口边框和工作区坐标。
- 已在 Windows 11 ARM64 验证 640×480 批量页面、未保存草稿的目标切换确认和 HKCU 集成。原生滚轮测试验证了横向与纵向事件的分发。[Windows 框架验证](32-windows-framework.md#windows-gui-复检)
