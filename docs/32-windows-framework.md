# Windows 框架开发：契约、桌面 API、输入

目标日期：2026-11-12。主线是框架；环境变量管理器用于回归验证。

## 1. 后端契约与生命周期

已实现：

- `platform/unsupported.nim` 为 Backend、NativeWindow、Dialogs、Clipboard 的每个函数提供显式失败默认值。Windows 从默认值构造再覆盖已支持的函数；缺失功能抛 `UnsupportedBackendError`，包含平台与接口名称，不调用空指针。
- `Backend.shutdown` 提供初始化后释放入口，允许没有进入 run 的失败路径清理。Windows 清理是幂等的，销毁剩余窗口、释放派发窗口、清空回调与遗留 WM_QUIT。
- 每个 Windows Backend 实例记录是否拥有 host；重复初始化失败的实例不会清理另一个实例的资源。
- Windows ready 异常、事件回调异常、正常退出都经过清理。core 在 finally 中清理后端、IPC 池及调度循环，并清空当前后端和 allClosedHook。
- 创建和 setSize 的宽高使用 96 DPI 逻辑客户区像素；根据窗口实际 DPI 换算物理像素并调整非客户区。绘制和鼠标坐标使用同一 scale。setPosition 的 Windows 坐标仍是物理桌面坐标，不能与 DIP 宽高混淆。
- 动态 setResizable、最大化/恢复切换、全屏/恢复实现。全屏保存原窗口样式及 placement，销毁时释放保存数据。

待完善/验证：Windows 实际生命周期、异常路径和多显示器 DPI 验证；退出期间的模态循环/系统注销；进一步窗口状态查询与状态恢复边界。

## 2. 常规桌面 API

已实现文件对话框首版：`IFileOpenDialog` / `IFileSaveDialog`，支持 Unicode、多选、目录、默认路径/扩展名、扩展名过滤、覆盖确认。用户取消返回空结果，其他 HRESULT 失败抛 BackendError；在拥有线程运行并成对释放 COM、Shell item 与返回缓冲区。

原生菜单首版已实现：子菜单、分隔项、复选/禁用状态、原生命令 ID 映射和每窗口独立的菜单/加速键资源。支持 Ctrl/Shift/Alt、字母数字、F1–F24 和常用导航键；cmd/command 是 Windows Ctrl 别名。重复快捷键、无效绑定或不支持的角色在安装前报错。禁用父菜单也禁用其子项快捷键。

菜单角色已接入 quit（经过 quitRequested）、close（经过关闭拦截）、minimize/zoom/fullscreen、剪切/复制/粘贴/撤销/重做/全选/删除，以及 hide/showAll/bringAllToFront/about。hideOthers 等不适合当前 Windows 后端的角色明确报不支持。

菜单替换保留客户区 DIP 尺寸；新窗口继承当前菜单，每个窗口保留对应版本的命令路由。关闭窗口释放菜单及加速键表。安装失败尝试恢复旧菜单，无法恢复的窗口禁用命令路由，避免把新菜单 ID 交给旧回调。core 的菜单回调表改为每次安装独立捕获，失败版本不会污染现有菜单。

仍待实现/验证：真实菜单交互与快捷键运行验收；任意按钮文字的消息框（目前 OK 与 OK/Cancel）；窗口状态 API 的完整统一。

## 3. 输入完整性

已接入失焦/捕获丢失取消：SurfaceHandler 增加 cancelInput，Windows 的 WM_CAPTURECHANGED / WM_CANCELMODE 取消按压与拖动，WM_KILLFOCUS 还清除残留 UTF-16 高代理项和未提交组合文本。正文和原输入焦点位置保留；正常 mouse-up 先提交点击再释放捕获，避免释放事件误取消点击。共享引擎测试已验证不会产生幽灵点击、不会提交被取消的组合文本。

IME 原生桥接首版已接入（窗口 `ime: true`）：IMM32 读取组合串、提交串、UTF-16 光标和目标子句属性，交给共享引擎显示与替换选区。支持同一消息提交上一子句并开始下一子句。组合结束、失焦、点击切换输入位置取消未提交文本；组合期间不让候选选择键修改正文，消费 WM_IME_CHAR 防止二次提交。组合串读取失败显式报错，缓冲区有上限并成对释放。

SurfaceHandler 增加 textInputActive，core 根据当前焦点是否接受文本启停 IME。组合窗/候选窗使用逻辑光标矩形乘窗口 DPI，绘制、鼠标、键盘及候选列表变化后更新；位置更新有重入保护，避免 IMM 同步通知递归。

键盘增加 PageUp/PageDown、Insert、F1–F24 映射、WM_UNICHAR 支持与 UTF-16 代理项解码。AltGr 留给字符消息；文本输入空格走 WM_CHAR，按钮空格保留键盘激活。共享引擎忽略未绑定的快捷键、Insert 和功能键，避免把键名插进正文。非法代理序列替换为 U+FFFD，失焦重置待配对状态。

剪贴板文本读区分无文本和失败；未初始化、非拥有实例/线程、占用、非法无终止符数据均报 ClipboardError。写入先校验 UTF-8/NUL，clear 真正调用 EmptyClipboard。原生事件中的剪贴板错误提示系统提示音并保持应用运行；剪切/粘贴在读写成功后才修改正文，空文本不删除选区。粘贴统一 CRLF/CR，再按单行/多行处理换行。

仍待继续：微软拼音/日语输入法实机验证，候选窗在多屏 DPI/滚动下定位；IME reconversion/document-feed 和纯 TSF 输入服务；更完整的 Ctrl 单词导航/系统快捷键行为。HTML 剪贴板仍明确不支持。源码接入和交叉编译不等于完整输入验收。

实现依据：[Microsoft 的 WM_IME_COMPOSITION 消息契约](https://learn.microsoft.com/en-us/windows/win32/intl/wm-ime-composition)及 [IMM32 组合串读取流程](https://learn.microsoft.com/en-us/windows/win32/intl/processing-the-wm-ime-composition-message)。

## 4. 渲染与帧驱动

已实现：

- `opImage` 通过 WIC 解码为 32bpp PBGRA，`AlphaBlend` 缩放绘制；按路径缓存，默认上限 128 项，提供与 CoreGraphics 对齐的 `clearImageCache` / `setImageCacheLimit` / `imageCacheStats`。缓存是条目上限，不是字节预算或 LRU。
- `opPolygon` 使用 GDI path + `SelectClipPath`，不透明与半透明填充都走同一路径，DPI 世界变换在 path 构造与填充之间保持一致。
- 动画：`NativeWindow.startAnimation` / `stopAnimation` 接入 Win32 `SetTimer`；帧消息中由 `getMonoTime()` 计算单调时间与 dt，异常长帧钳制到 250 ms。`SetTimer` 约 15.6 ms 分辨率，120 fps 会被系统节流。
- 新增 `tests/test_windows_render.nim` 与 `tests/test_windows_animation.nim`，已加入 Windows CI 和交叉构建。

待完善/验证：

- `opImageQuad` 仍未实现；`opText` 的颜色 alpha 仍未应用。
- WIC 解码、AlphaBlend 缩放、半透明多边形和帧节奏已在 Windows CI 执行通过；视觉质量与真实帧节奏仍待人工验收。
- D3D11/DirectComposition 呈现循环尚未开始，目前是 GDI + `SetTimer`。

## 5. CLI 与分发

已实现：

- `nimi build` 在 Windows 主机上编译 `dist/windows-<arch>/<slug>.exe`，复制 `resources` 到同目录，并用 `--passL:-Wl,--subsystem,windows` 选择 GUI 子系统。
- `windows.icon`（缺省回退 `icon`）支持 `.ico` 或 ≤256×256 PNG；PNG 由纯 Nim 包装为 ICO。`windres` 可用时把图标和 manifest 编译为 COFF 资源并链接。
- manifest 声明 `asInvoker`、`PerMonitorV2`、`longPathAware` 和 Windows 10/11 兼容性。

待完善/验证：

- 未适配 MSVC 的 `rc.exe`/`link.exe`；`windres` 缺失时只警告并跳过图标/manifest。
- 未生成安装器、未签名、未做自动更新；`resources/` 的运行时定位约定尚未写入模板。
- Windows CI 已加入 `nimi.exe` 构建、`nimi version` 和 `nimi build examples/hello`，但尚未取得远端执行结果。

## 6. 显示、主题与全局快捷键

已实现：

- 显示器枚举：`EnumDisplayMonitors`/`GetMonitorInfoW`，逻辑坐标相对主屏，`GetDpiForMonitor` 动态加载并回退 96 DPI。
- 光标位置转主屏逻辑坐标。
- 主题：`AppsUseLightTheme` + DWM `AccentColor`；`WM_SETTINGCHANGE`、`WM_THEMECHANGED` 触发主题回调，`WM_DISPLAYCHANGE`/`WM_DPICHANGED`/`WindowMetrics` 触发显示回调。
- 全局快捷键：复用 accelerator 解析，`RegisterHotKey` 注册在 message-only 窗口，`WM_HOTKEY` 经 `NIMI_HOTKEY` 回主线程，退出时注销。
- `tests/test_windows_desktop.nim` 已加入交叉构建和 Windows CI。

待完善/验证：

- 混合 DPI 多显示器的坐标换算是近似值，需要实机校准。
- 托盘、气泡/Toast 通知、文件监视、Cookie、NowPlaying/媒体键仍未实现。
- 以上 API 已在 Windows CI 执行通过；真实键鼠与窗口管理器交互仍待人工验收。

## 7. WebView2、IPC 与协议

已实现：

- Vendor WebView2 SDK `1.0.4314.35` 头文件与 x64/arm64 loader，附带 Microsoft LICENSE/NOTICE；MinGW 缺失的 `EventToken.h` 用最小兼容头补齐。
- `webview2.c` 动态加载 loader、检查 Runtime、异步创建 environment/controller；controller 就绪前缓存 load/eval；`WebMessageReceived` 回到 `WindowHandler.message`。
- 页面 shim 将 `window.webkit.messageHandlers.nimi.postMessage` 映射到 `chrome.webview.postMessage`，core bridge 协议不变；Nim→页面仍用 `ExecuteScript`。
- `nimi://app/...` 经 `SetVirtualHostNameToFolderMapping` 映射到 FileServer 根目录；`loadHTML` 用 `NavigateToString` 并支持 `<base>`。
- `nimi build` 复制架构对应的 `WebView2Loader.dll`；`ephemeral` 使用临时用户数据目录。
- 测试：`test_windows_webview`、`test_windows_webview_protocol` 已加入交叉构建和 CI。

待完善/验证：

- WebView2 Runtime 缺失/Loader 版本、DPI/IME、真实页面交互和视觉仍待人工验收；IPC 与 `nimi://` 协议自动化已通过。
- `file://` baseURL、非 `app` 主机的自定义协议、cookie/会话隔离与下载尚未实现。
- Nim 2.4.0 Windows 编译器需要 8 MiB 栈才能检查 `ui/context.nim`；CI 通过修改编译器 PE 头规避，长期应拆分模块。

## 验证

- `tests/test_platform_contract.nim`：检查所有默认接口非空，未支持操作的异常类型/名称，以及覆盖实现后的错误传播。本机执行通过。
- `tests/test_windows_host.nim`：新增 DIP 客户区尺寸、动态样式、全屏恢复、ready 异常清理、重新初始化和重复实例隔离检查。已在 Windows CI 执行通过。
- Windows 全套交叉构建（含环境变量 demo 和端到端测试）通过；文件对话框 C/COM 代码已完成编译和链接。
- Windows 文件对话框的交互结果、DPI 和窗口状态仍需实际运行验证；不能把交叉编译当作这几项验收完成。
- `tests/test_windows_menu_plan.nim` 的命令映射、父菜单禁用、快捷键校验测试，本机通过；`tests/test_menu_callbacks.nim` 的菜单版本回调隔离与失败恢复测试，本机通过。
- `tests/test_windows_menu.nim` 验证实际 HMENU/HACCEL 资源、快捷键路由、角色、两窗口替换和客户区尺寸。已交叉编译，尚未执行；其中快捷键通过测试钩子读取原生加速键表再发送命令，不等同于物理键盘验证。
- 本机菜单规划、菜单回调生命周期、desktop、UI 和共享 IME 测试通过；Windows 菜单/取消事件的实际事件链已在 `windows-latest` CI 执行通过。
- 新目标保持进行中，完整输入仍需开发；实机通道不影响继续补齐源码和测试。
- `tests/test_windows_input.nim`：7 项回归覆盖 UTF-16/AltGr/选区、无效快捷键、剪贴板失败保留正文和撤销历史、换行、连续 IME 子句。本机通过；共享 IME 6 项、UI 27 项和 desktop 7 项回归通过。
- `tests/test_windows_input_native.nim`：发送原生窗口消息检查组合期间抑制、取消、Unicode/空格和失焦；剪贴板检查 Unicode、格式清除、非法文本、无终止符数据、另一线程占用。已于 2026-11-13 在 `windows-latest` 执行通过；不包含真实输入法结果串/候选 UI 验证。
- `tests/test_windows_render.nim`：真实窗口绘制路径，覆盖 WIC 图像解码/缓存命中与半透明多边形；`tests/test_windows_animation.nim`：真实定时器帧计数、dt 范围、停止和关窗；`tests/test_windows_desktop.nim`：显示器/工作区/scale、主屏、光标、主题和全局快捷键注册/注销。`tests/test_windows_webview.nim` / `test_windows_webview_protocol.nim`：WebView2 IPC 往返与 `nimi://` 文件服务。以上均已加入 Windows CI，并于 2026-11-13 在 `windows-latest` 执行通过（run 43396708087）。
- 本轮最终 Windows 全套交叉构建通过（含新增渲染/动画测试、输入测试和环境变量 demo）。平台契约、菜单回调和 demo UI 本机回归通过，`git diff --check` 通过。
