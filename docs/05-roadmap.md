# 实施路线图

> 状态:草案 · 日期:2026-11-04 · 关联:[可行性](00-feasibility.md)、[架构](01-architecture.md)、[macOS 后端](02-macos-backend.md)、[原生 UI](03-native-ui.md)
> 估算口径:1 名资深工程师全职 + AI 辅助;复用 MyGo 的 JS/协议/模板/示例;不移植着色器编译器;系统文本引擎。工期为规划量级(±50%)。

---

## 0. 路线原则

1. **纵向切片,不做横向铺开。** 每个里程碑以"能跑的示例 + 测试"验收,不是"模块都写完了"。
2. **先 WebView,后原生 UI。** 最短闭环是 WebView + IPC + CLI;原生 UI 从 M2 进入主线。
3. **CPU 优先,Metal 第二。** 先用 CoreGraphics 跑通布局/文本/输入,再替换渲染器。
4. **每个里程碑可发布。** M1 后有可运行的 WebView 框架;M2 后有原生 UI;不等到"全做完"。
5. **协议先定,API 后调。** IPC 线协议、TS 客户端形态、配置字段尽早冻结;公开 Nim API 可以迭代。
6. **测试与实现同步。** Fake 后端、Tester、黄金测试、E2E 在对应里程碑内完成,不留到最后。

---

## 1. 里程碑总览

| 里程碑 | 内容 | 工期 | 累计 | 状态 |
|---|---|---|---:|---|
| M0 | 可行性原型 | 1–2 天 | 1–2 天 | ✅ 已完成 |
| M1 | 仓库骨架 + core + macOS WebView + IPC + `hello` | 6–10 周 | 2–3 月 | 进行中(核心切片已跑通) |
| M2 | 原生 UI 基础 + CoreText + `counter-native` | 8–12 周 | 4–6 月 | |
| M3 | 控件/布局/滚动 + Metal 起步 + `gallery` 子集 | 10–16 周 | 7–10 月 | 切片(5 个新控件;Metal/其余控件未开始) |
| M4 | 桌面 API:菜单/托盘/通知/快捷键/对话框/剪贴板 | 8–12 周 | 9–13 月 | 切片(Clipboard/菜单/对话框;其余未开始) |
| M5 | 文档/会话/Cookie/协议/文件监视/深链/单实例 | 8–12 周 | 11–16 月 | 未开始 |
| M6 | 文本编辑/IME/可访问性 + Metal 完整 | 12–20 周 | 14–21 月 | 切片(单行 TextInput;其余未开始) |
| M7 | 打包/签名/公证/DMG/更新/CI | 6–10 周 | 16–23 月 | 切片(.app/DMG/签名/图标;更新/CI/公证验证未完成) |
| M8 | Windows:Win32 + WebView2 + D3D11 + 打包 | 4–8 月 | 20–31 月 | |
| M9 | Linux:GTK3 + WebKitGTK + GL + 打包 | 4–8 月 | 24–39 月 | |
| M10 | 插件/i18n/音频/自动化/浏览器后端 | 持续 | | |

> "累计"从 M1 开始按单人全职估算。3 人并行可压缩 macOS 阶段约 30–40%。

---

## 2. M0 可行性原型(已完成)

### 交付

- `spikes/objc_hello/spike.nim`:NSWindow + 运行时类 + NSTimer。
- `spikes/wkwebview/spike_webview.nim`:WKWebView + JS message handler + eval。
- `spikes/coretext/spike_coretext.nim`:CoreText 混排 + PNG。
- `spikes/nim_meta/spike_meta.nim`:宏生成 TS + JSON。
- `spikes/metal/spike_metal.nim`:CAMetalLayer clear pass。
- `spikes/blocks/spike_blocks.nim`:纯 Nim ObjC block。
- `spikes/threads/spike_threads.nim`:arc/orc/atomicArc/yrc 跨线程。

### 结论

技术可行;主要成本是广度。详见 `00-feasibility.md`。

---

## 3. M1:WebView + Core + IPC(6–10 周)

**目标**:`examples/hello` 的 Nim 版。页面调用 Nim `Greeter.greet`,返回字符串;`nimi generate` 输出 TS;`nimi dev` 可启动;`nimi build` 产出 `.app`。

**当前状态(2026-11-04)**:核心垂直切片已跑通。已实现 AppKit 窗口、WKWebView、bridge 注入、JS→Nim JSON 调用、`bindService` 宏、TS 生成、IPC secret/token、页面侧事件、`init/generate/dev/build/doctor` CLI、dev 文件监听/自动重启、`.app` 打包、单元测试。50 次连续调用 + 关窗退出压测通过。剩余项:工作线程池、页面侧 Channel、`Eval` 返回值、trusted/untrusted 细分、更多 IPC 类型黄金测试。详见 [M1 实现状态](08-m1-notes.md)。

### 3.1 工作包

#### W1.1 仓库骨架(2–3 天)

- [ ] `nimi.nimble`、`config.nims`(`--mm:atomicArc --threads:on`)。
- [ ] `src/nimi.nim` 门面;`src/nimi/core/`、`platform/`、`ui/`、`tsgen/`、`cli/` 目录。
- [ ] `tests/`、`examples/hello`、`docs/`。
- [ ] CI:macOS `nim c` + `nimble test` + 示例构建。
- [ ] 版本/许可证/README。
- [ ] 编码规范:命名、错误、线程、内存、FFI。

**验收**:空项目 `nim c` 通过;CI 绿。

#### W1.2 Core 运行时(1–2 周)

- [ ] `core/loop.nim`:`postMain`、`onMain`、`onMainValue`、`await`、`deliver`、`shutdown`。
- [ ] `core/events.nim`:监听器表、可取消事件、`off` 返回值。
- [ ] `core/app.nim`:`Application` 单例、`run`、`whenReady`、`isReady`、`quit`、`exit`、`relaunch`、`path`、`name/version`。
- [ ] `core/window.nim`:窗口注册表、`WindowOptions`、`newWindow`、`show/hide/close/destroy`、基本几何/标题、事件注册。
- [ ] `core/page.nim`:`Page`、`loadURL/loadFile/loadHTML`、`eval`、导航事件。
- [ ] `core/paths.nim`。
- [ ] `core/platform.nim` 选择后端(`when defined(macosx)`)。

**验收**:Fake 后端下窗口创建/关闭/事件顺序正确;`postMain`/`await` 单元测试;主线程阻塞测试。

#### W1.3 平台契约 + macOS 基础(2–3 周)

- [ ] `platform/contract.nim`:`Backend`、`Window`、`Surface`、`AppHandler`、`WindowHandler`、事件类型。
- [ ] `platform/darwin/objc.nim`:typed msgSend、selector/class 缓存、runtime 类、block、autorelease pool、Owned/Borrowed。
- [ ] `platform/darwin/app.nim`:NSApplication、delegate、run/quit/signal/step/wake、CFRunLoopSource。
- [ ] `platform/darwin/window.nim`:NSWindow 子类、创建/样式/标题/几何/显隐/关闭、事件 delegate、坐标转换。
- [ ] `platform/darwin/webview.nim`:WKWebView、configuration、user content controller、script message handler、navigation delegate、loadHTML/URL、eval。
- [ ] `platform/fake/`:内存后端,覆盖 Backend/Window/Page 最小集。
- [ ] `platform/unsupported.nim`。

**验收**:真实窗口显示 HTML;JS `window.webkit.messageHandlers.nimi.postMessage` 到达 Nim;`eval` 返回;关闭窗口进程退出;Fake 后端单测通过。

#### W1.4 Bridge + IPC(2–3 周)

- [ ] 复用 `packages/bridge` 源码,构建 `bridge.js`;改命名空间为 `nimi`(保留 `mygo` 别名)。
- [ ] `core/bridge.nim`:注入脚本、secret、消息解析、`dom-ready`、事件保留、批量 `eval`。
- [ ] `core/ipc.nim`:`ServiceDef`/`MethodDef`/`TypeDef`;`{.rpc.}` + `bindService(instance, procs...)` 宏(显式 proc 列表,按 self 类型选重载);JSON 编解码;工作线程池;错误/panic 转换;`CallContext`。
- [ ] `core/channel.nim`:`Channel[T]`、1 MiB 窗口、ack、close、取消。
- [ ] `core/events_ipc.nim`: `newEvent[T]`、`emit`、`broadcast`。
- [ ] 内置 `nimi:window` 服务(最小:close/minimize/maximize)。
- [ ] TS 生成:`tsgen/` 描述符 → TypeScript;`generate` 模式。

**验收**:页面 `nimi.call("Greeter.Greet","world")` resolve;Nim 事件到页面;Channel 流式传输;TS 客户端可被 `tsc` 编译;协议黄金测试。

#### W1.5 CLI 最小集(1–2 周)

- [ ] `cli/main.nim`:命令分发。
- [ ] `init`:web/native 模板;生成配置/图标。
- [ ] `generate`:编译 + `NIMI_GENERATE` 运行 + 写 TS。
- [ ] `dev`:构建 + 启动 + 文件监听 + 重启;`devUrl` 等待。
- [ ] `build`:macOS `.app` 最小;资源复制;ad-hoc 签名。
- [ ] `doctor`:Nim/clang/SDK/Bun 检查。
- [ ] 配置解析/默认值/校验。

**验收**:`nimi init` → `nimi dev` 打开窗口;修改 Nim 文件自动重启;`nimi build` 产出可双击的 `.app`。

#### W1.6 桌面基础(1 周,可并行)

- [ ] 菜单:模型、role、默认菜单、快捷键、点击回调。
- [ ] 对话框:open/save/message。
- [ ] 剪贴板:text/HTML/image。
- [ ] Shell:openExternal/openPath。
- [ ] 主题:isDark/preferences(只读)。

**验收**:`examples/hello` 有应用菜单;Cmd+Q 走 core 退出;打开文件对话框;复制/粘贴。

#### W1.7 测试与示例(1 周)

- [ ] `tests/unit`:loop/events/ipc/json/tsgen。
- [ ] `tests/golden`:TS 输出。
- [ ] `tests/e2e`:真实 WKWebView 加载 hello,JS 调用,断言。
- [ ] `examples/hello`:最小 WebView + Bind。
- [ ] `examples/todo`(可选):前端 + TS 客户端。

### 3.2 M1 验收清单

- [ ] `nimi init web` + `nimi dev` 打开窗口,页面显示。
- [ ] 页面调用 Nim 方法,参数/返回值/错误正确。
- [ ] Nim `emit` 事件,页面 `on` 收到。
- [ ] `Channel` 流式发送,页面收到 `end`。
- [ ] `nimi generate` 生成 TS,`tsc --noEmit` 通过。
- [ ] `nimi build` 产出 `.app`,双击运行。
- [ ] 菜单/Cmd+Q 退出,无 crash/僵尸线程。
- [ ] 关闭最后一个窗口,进程按策略退出。
- [ ] `nimble test` 绿;E2E 绿。
- [ ] 二进制大小记录(基线)。

### 3.3 M1 风险与 Gate

| 风险 | Gate |
|---|---|
| ObjC ABI | 每种签名单测;真实窗口 |
| 主线程嵌套 | 在菜单/对话框中调用 `onMain`/`await` |
| IPC 类型 | 黄金测试覆盖 object/seq/Option/出错 |
| TS 生成 | 与 MyGo 输出逐项对比 |
| 内存模型 | 用真实 IPC 负载 benchmark atomicArc vs orc;M1 结束定稿 |

**Gate 1**:M1 验收通过后,冻结 IPC 线协议和 TS 客户端形态。

---

## 4. M2:原生 UI 基础 + Counter(8–12 周)

**目标**:`examples/counter-native` 运行;点击/键盘改变数字;headless Tester 通过;CPU 渲染。

**当前状态(2026-11-04)**:核心切片已跑通。`NSView` Surface、`drawRect:` → CGContext、CoreGraphics/CoreText 渲染、CoreText 真实文本测量、rune 级换行、Column/Row 布局、Text/Button、命中测试、鼠标事件、方向键、Tab/Enter 焦点、`ui.Tester`、离屏 PNG、`Window.invalidate()` 链路可用;`examples/native-smoke` 和 `examples/counter-native` 已实际截图验证,鼠标/键盘/焦点的坐标与 AppKit NSEvent 测试通过;`tests/test_ui.nim`/`test_render.nim` 无窗口测试通过。剩余项:ellipsis/maxLines、场景/像素 golden、TextInput、完整焦点模型、Scroll/List、Metal。详见 [M2 实现状态](10-m2-notes.md)。

### 4.1 工作包

#### W2.1 Surface + CPU 呈现(2 周)

- [ ] `platform/darwin/surface.nim`:NimiSurfaceView、layer、tracking area、帧请求、display link/timer、PresentPixels(CGImage)。
- [ ] `core/content.nim`:`Content`、`uiView`、`invalidate`、`update`、surface 事件路由。
- [ ] 输入事件:鼠标/键盘/滚轮/焦点;坐标转换。
- [ ] 最小 IME 接口(先不实现完整 composition)。

**验收**:窗口显示纯色/圆角矩形;鼠标/键盘事件到达。

#### W2.2 Scene + CPU 渲染(2 周)

- [ ] `scene/`:Op/Glyph/Scene/Atlas;fill/border/clip;damage 先不做。
- [ ] `render/cg.nim`:CGBitmapContext 画矩形/圆角/边框/图片/裁剪。
- [ ] `render/raster.nim` 骨架(可先用 CG)。
- [ ] 颜色/缩放/HiDPI。

**验收**:离屏渲染 PNG;golden 对比。

#### W2.3 文本(CoreText)(2–3 周)

- [ ] `text/font.nim`:字体加载/缓存/回退。
- [ ] `text/shape.nim`:CoreText CTTypesetter/CTLine;多语言。
- [ ] `text/layout.nim`:行/段落/对齐/ellipsis。
- [ ] `text/glyphcache.nim`:alpha/color bitmap;atlas。
- [ ] `text/caret.nim`:caret/selection 基础。
- [ ] UI Text 控件:换行/字号/颜色/粗体。

**验收**:中英日混排正确;golden;字体回退正确。

#### W2.4 UI 核心(2–3 周)

- [ ] `ui/context.nim`、`ui/element.nim`、`ui/node.nim`、`ui/build.nim`。
- [ ] arena/chunk/generation;state 表;key。
- [ ] flexbox:Column/Row/Box;Width/Height/Fill/Grow/Padding/Gap/Align/Justify/Margin。
- [ ] paint:背景/边框/文本/裁剪。
- [ ] `children` 模板 + 构造器 begin/end。
- [ ] Button/PrimaryButton、Text、Spacer/Divider、Checkbox/Radio/Switch。
- [ ] hover/press/click;焦点/Tab/Enter/Space。
- [ ] Theme(浅/深)。

**验收**:counter-native 运行;点击/键盘;布局嵌套正确。

#### W2.5 Tester(1 周)

- [ ] headless host;确定性时钟;离屏渲染。
- [ ] click/key/type/settle/find/texts。
- [ ] `render(view,w,h,scale)`。
- [ ] counter 行为测试 + golden。

#### W2.6 构建/打包完善(1 周)

- [ ] `nimi build` 资源嵌入(`staticRead`)、Info.plist、图标、ad-hoc 签名。
- [ ] `nimi dev` 对 native 模板的 watch/restart。
- [ ] 二进制大小基线。

### 4.2 M2 验收清单

- [ ] `nimi init native` → `nimi dev` 打开 counter。
- [ ] 点击 +/− 改变数字;键盘 ↑/↓ 生效。
- [ ] 窗口 resize 后布局正确。
- [ ] Tester:点击后文本变 "1";golden PNG。
- [ ] 空闲 CPU ≈0%;不请求帧。
- [ ] 关闭 100 次无泄漏/crash。
- [ ] `nimi build` 产出可双击 `.app`。

### 4.3 M2 风险与 Gate

| 风险 | Gate |
|---|---|
| CoreText 布局与 caret | 多语言 golden;caret 移动测试 |
| 布局缓存 | 随机树有/无缓存对照 |
| 元素生命周期 | 窗口开关压力测试 |
| CPU 性能 | 1000 标签基准;不达标则提前 Metal |
| IME 延迟 | 中文输入 E2E(可 M3 完成) |

**Gate 2**:M2 验收后,决定 Metal 优先级和 P1 控件顺序。

---

## 5. M3:控件广度 + Metal 起步(10–16 周)

**目标**:`gallery` 子集;常用表单/列表/弹层;60fps;Metal 渲染基础。

**当前状态(2026-11-04)**:已新增 Checkbox/Switch/Slider/Progress/Divider,含回调式状态、拖动、焦点、测试与 `widgets-native` 示例。Metal、List/Table/Tabs/Select 等尚未开始。详见 [M3–M7 状态](11-m3-m7-status.md)。

### 工作包

- **控件 P1**(6–8 周):List 虚拟化、ScrollBoth、Grid、Tabs/Segmented、Select、Combobox、SearchField、Popover/Modal/Overlay、Tooltip、Image/Icon(SVG)、Spinner/Progress/Meter/Badge/Avatar、Form/Field/Fieldset、Split/Toolbar/Sidebar、Collapsible/Accordion、Stepper/RangeSlider/Rating、Number/Decimal/Date/Time/Calendar/ColorPicker、Table/Tree/GridView、Router/RichText/Toast/AlertDialog。
- **Metal 基础**(3–5 周):CAMetalLayer、预编译 MSL、单管线实例化 quad、fill/glyph/image/clip、presenter 线程、与 CPU golden 对比。
- **动画/过渡**(2–3 周):transition、spring、timeline 基础。
- **无障碍最小集**(1–2 周):AccessTree + macOS NSAccessibility 基础 role/label/value/action。
- **性能**(1–2 周):damage、帧节奏、内存 trim。

### 验收

- `gallery` 子集可用;常用表单可构建。
- 千行列表滚动 60fps;内存不随行数增长。
- CPU/GPU golden 一致(允许抗锯齿差异)。
- VoiceOver 能读出主要控件。

---

## 6. M4:桌面 API(8–12 周)

**当前状态(2026-11-04)**:Clipboard、菜单模型/NSMenu/role/快捷键、Open/Save/Message 对话框已实现并截图/冒烟验证。补充:`examples/notes` 已用菜单 + 打开/保存面板完成一个实际笔记应用,见 [Nimi Notes 验收](12-notes-demo.md)。通知/托盘/全局快捷键/屏幕/主题尚未开始。

- 菜单完整:role/动态更新/上下文菜单/Dock 菜单。
- 托盘:图标/菜单/点击/深浅色。
- 通知:授权/显示/点击/移除/图片。
- 全局快捷键。
- 屏幕/主题/电源/网络/Now Playing。
- 对话框完整:sheet/过滤器/破坏性按钮/checkbox。
- 剪贴板完整:文件/自定义格式/延迟提供。
- Shell:回收站/文件图标/已安装应用。
- 窗口高级:标题栏样式/traffic lights/vibrancy/透明度/全屏/多屏/状态持久化。
- 单实例/深链/文件关联/最近文档/登录项。

### 验收

- 每个能力有示例 + E2E。
- 菜单/托盘/通知在打包 `.app` 中可用。
- 多屏/DPI/深浅色切换正确。

---

## 7. M5:文档、会话、协议、监视(8–12 周)

**当前状态(2026-11-04)**:未开始。

- 自定义协议 + FileServer + CORS + 分块。
- 内置前端 VFS / `nimi://` / dev URL。
- 会话:持久/临时/ClearData。
- Cookie 列表/设置/删除/清空。
- 内容规则、认证、证书错误。
- 文件监视:FSEvents + 快照/去抖/提示/限额。
- 文档控制器:泛型、自动保存、冲突、恢复、最近文档、File 菜单 role、退出询问。
- 深链/启动文件/单实例完善。
- i18n:locale 匹配、消息目录、默认菜单文案(最小)。

### 验收

- `examples/notes` 类应用可保存/恢复/冲突处理。
- 自定义协议页面可加载。
- 文件监视在 IDE 场景稳定。
- Cookie/会话隔离测试。

---

## 8. M6:文本编辑、IME、可访问性、Metal 完整(12–20 周)

**当前状态(2026-11-04)**:单行 TextInput(caret/退格/方向键/Home/End)已实现并通过合成 AppKit 键盘事件验证;TextArea/选择/撤销/剪贴板/IME/可访问性/完整 Metal 未开始。

- TextInput/TextArea 完整:selection/undo/redo/密码/剪贴板/多行滚动。
- IME:NSTextInputClient 完整;中文/日文/韩文/死键/emoji;候选窗定位。
- 富文本显示/编辑基础。
- 代码编辑器(`ui/editor`)可选。
- 无障碍完整:表格/树/公告/live region;VoiceOver E2E。
- Metal 完整:阴影/渐变/effect/宽色域/damage/pipeline 特化/P3。
- 性能:120Hz/ProMotion、输入延迟、空闲 trim。
- 拖放完整。

### 验收

- 中文输入法可用;候选窗跟随光标。
- VoiceOver 能完成主要流程。
- Metal 覆盖 gallery;CPU/GPU 一致。
- 输入→屏幕延迟达标(参考 MyGo 的测量)。

---

## 9. M7:打包、签名、更新、CI(6–10 周)

**当前状态(2026-11-04)**:`.app`、DMG、ad-hoc/Developer ID 签名配置、entitlements、图标(icns)、notarize 钩子已实现;DMG 已 `hdiutil verify` 并挂载验证。自动更新、CI/release 未开始。

- `.app` 完整:Info.plist/本地化/图标/Assets.car(可选)。
- Universal binary(arm64 + amd64)。
- Developer ID 签名、hardened runtime、entitlements、provisioning profile。
- notarytool + stapler。
- DMG(背景/布局/签名)。
- 更新:Ed25519 清单、tar.gz/delta、安装/重启;更新窗口(原生 UI)。
- CI:macOS 构建/测试/notarize;bench;release workflow。
- `nimi doctor` 完整。
- 文档:安装/签名/公证/更新。

### 验收

- 可分发的签名/公证 `.app` + `.dmg`。
- 自动更新从旧版到新版成功。
- 干净 macOS 机器可运行。

---

## 10. M8:Windows 后端(4–8 月)

**目标**:`hello` 与 `counter-native` 在 Windows 10/11 运行;NSIS 安装器。

### 阶段

1. **Win32 基础**(4–6 周):winim/win32 封装、消息循环、窗口、DPI、菜单、对话框、剪贴板、托盘。
2. **WebView2**(6–10 周):runtime 探测、environment、controller、事件、scheme 映射、Eval、下载、session/cookie、权限。
3. **原生 UI surface + D3D11**(6–10 周):子窗口、PresentPixels、D3D11 swap chain、IMM32、UIA 最小。
4. **打包**(3–5 周):资源/manifest、NSIS、签名、更新。
5. **测试/CI**(4–6 周):Windows runner、WebView2、UIA/IME。

### 风险

- WebView2 COM vtable/版本降级。
- DPI/Win32 窗口装饰。
- D3D11/DirectComposition 与嵌入式 WebView2。
- UIA/IME。
- Nim 产物的 MSVC/UCRT 依赖。

---

## 11. M9:Linux 后端(4–8 月)

**目标**:`hello` 与 `counter-native` 在 GTK3/WebKitGTK 运行;`.deb`/PKGBUILD/install.sh。

### 阶段

1. **GTK3 dlopen + 主循环**(3–5 周):GLib/GObject/GTK/GDK/cairo 绑定、Init/Run/Step/Signal、窗口、菜单、对话框。
2. **WebKitGTK**(5–8 周):4.1/4.0、脚本消息、scheme、下载、session/cookie、权限。
3. **原生 UI + GL**(5–8 周):GtkGLArea/GtkDrawingArea、GL 3.3/ES 3.0、输入、IME、ATK 最小。
4. **打包**(3–5 周):`.desktop`/MIME/`.deb`/PKGBUILD/install.sh。
5. **测试/CI**(4–6 周):Xvfb + dbus + XTEST;WebKitGTK 容器。

### 风险

- X11/Wayland 窗口几何/CSD。
- GTK3/WebKitGTK 版本矩阵。
- ATK 二进制布局。
- DMA-BUF/NVIDIA/VM 兼容。

---

## 12. M10:插件、i18n、音频、自动化、浏览器(持续)

- 官方插件:fetch、websocket、sqlite、watch、updater、terminal、glass、game、loading、sfsymbols、permissionflow、automation。
- i18n:CLDR 复数/日期/数字、消息目录、代码生成。
- 音频:播放器/混音/WAV/MP3/Vorbis;CoreAudio/AudioQueue、WASAPI、Pulse/ALSA。
- 自动化:兼容 MyGo 的 `MYGO_AUTOMATION` socket 协议。
- 浏览器/wasm 后端(可选)。
- Inspector/开发者工具。
- 文档/网站。

---

## 13. 并行工作流

单人时按里程碑顺序;多人时可并行:

| 工作流 | 内容 | 依赖 |
|---|---|---|
| A. Core/IPC | loop、ipc、bridge、tsgen、CLI | 无 |
| B. macOS WebView | objc/app/window/webview | A 的契约 |
| C. 原生 UI | scene/text/layout/widgets | B 的 surface |
| D. 渲染 | CG/Metal/raster | C 的 scene |
| E. 桌面 API | menu/dialog/tray/notify/... | B |
| F. 工具链/打包 | init/dev/build/package/sign | A |
| G. 测试 | fake/e2e/golden/bench | 各模块 |

3 人建议:A+B 一人,C+D 一人,E+F+G 一人;M3 后合流。

---

## 14. 验收与发布标准

### 14.1 每个里程碑的 Definition of Done

- [ ] 示例可运行(真实窗口 + headless 测试)。
- [ ] 单元/黄金/E2E 测试通过。
- [ ] 无已知 P0 崩溃/泄漏。
- [ ] 文档更新(API/平台差异)。
- [ ] 二进制大小/性能记录。
- [ ] 代码评审通过。

### 14.2 1.0 发布标准(建议)

- macOS 12+;arm64 + amd64。
- WebView + 原生 UI 均可运行。
- IPC/TS 生成稳定;协议版本化。
- 常用桌面 API 完整。
- 中文/日文 IME 可用。
- VoiceOver 基本可用。
- `.app` 签名/公证/DMG/自动更新可用。
- 8–12 个示例通过。
- 无已知数据丢失/安全漏洞。

### 14.3 版本策略

- `0.x`:M1–M6,API 可能破坏;文档标注。
- `1.0`:M7 完成,macOS 可用;Windows/Linux 标注 preview。
- `2.0`:三平台稳定。

---

## 15. 上游同步

- 锁定参考版本 MyGo 0.7.4(commit `02f583c8`)。
- 每季度对照 `docs/architecture.md` 和 `internal/platform` 变更,更新本设计。
- 协议/TS 生成变更优先同步;平台细节按需。
- 保留差异清单(`01-architecture.md` §10),避免无意识分叉。

---

## 16. 下一步(M1 启动清单)

1. 评审并确认 `00-feasibility.md` 的兼容边界。
2. 创建 `nimi.nimble`、`src/nimi.nim`、`config.nims`。
3. 实现 `core/loop.nim` + `platform/contract.nim` + `platform/fake`。
4. 实现 `platform/darwin/objc.nim` + `app.nim` + `window.nim`。
5. 实现 WKWebView + bridge 注入 + 最小 IPC。
6. 跑通 `examples/hello`。
7. 接 `nimi init/dev/generate/build`。
8. 记录基线(二进制大小、启动时间、空闲 CPU)。

---

*本路线图会随 M1/M2 的实际进展更新;工期是规划值,不是承诺。*
