# Windows GUI 开发回检与环境变量工具

> 2026-11-12 范围校正：主目标是补齐 **Nimi Windows 框架能力**；环境变量管理器只是驱动开发和验收的 demo，不作为独立产品持续扩展。Windows 实际运行暂不可验证，不妨碍继续实现框架缺项。下方历史记录中的“受阻”仅适用于运行验收，不能代表整个框架开发无法推进。
>
> 当前框架阶段：原生 GUI 最小实现，尚非完整 Windows 后端。已接入 core 生命周期、Win32 窗口/派发、GDI 基础绘制、基础输入和文本剪贴板。仍缺完整后端能力声明与不支持错误处理、DPI 尺寸契约、完整 IME、文件对话框/菜单、图像/多边形/动画、WebView2、桌面集成及 Windows CLI 分发。
>
> 后续优先级：① 统一未实现 API 的错误边界，补窗口/DPI/生命周期契约；② 文件打开/保存对话框与菜单；③ IME 组合/候选窗、键盘和焦点完整性；④ 补 scene 图像/多边形、动画计时与渲染测试（2026-11-13 已完成源码与交叉编译，待 Windows 运行）；⑤ 接入 Windows CLI 构建/资源/manifest；⑥ WebView2、协议与 IPC；⑦ 托盘/通知/快捷键/主题/屏幕/监视等桌面能力。环境变量 demo 用于验证前五项，不再把业务备份等细节作为主线。Windows 运行验证贯穿各阶段。

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
- `tests/test_environment_windows.nim`：Windows 集成测试，使用唯一临时 HKCU 变量并清理，覆盖 Unicode、展开类型、空值、枚举、大小写查找、删除。已静态检查，尚未运行。
- `.github/workflows/windows.yml`：已配置 Windows 测试，未触发远端工作流，不能当作已通过证据。
- 保存前比较不构成注册表事务，比较与写入之间仍可能出现并发竞态。
- 不调用 `setx`，不展开 `%VAR%`，不对 PATH 自动去重/去空项；已运行进程不会因为广播自动重建自身环境。
- 当前主机 macOS 无 MinGW/Wine，但可用 Zig 0.17.1。`./scripts/windows-cross-build.sh` 已成功将领域测试、注册表集成测试、Win32 host/surface/render/animation 测试编译为 Windows x64 PE 可执行文件，产物位于 `dist/windows-tests/`。这证明编译/链接通过，不等于运行通过。
- Win32 host 测试覆盖 ready、消息派发、关闭拦截、幂等 destroy 和 terminated；已加入 Windows CI，尚未在 Windows 执行。当前 DPI 消息会采用系统建议矩形，逻辑尺寸换算/缩放绘制仍需随渲染接入实现。
- 环境变量 GUI 位于 `examples/environment/`；使用与构建说明见该目录 README。应用 exe 已生成至 `dist/windows-tests/NimiEnvironment.exe`，实机交互验收尚未完成。目标保持进行中。
- 本轮 macOS 完整回归通过；新增控制器测试单独执行通过。Windows host/surface/registry/controller 及 GUI 编译通过，但尚无 Windows 执行结果，不能据此声称运行可用。

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
