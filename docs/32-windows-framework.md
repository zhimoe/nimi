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

## 验证

- `tests/test_platform_contract.nim`：检查所有默认接口非空，未支持操作的异常类型/名称，以及覆盖实现后的错误传播。本机执行通过。
- `tests/test_windows_host.nim`：新增 DIP 客户区尺寸、动态样式、全屏恢复、ready 异常清理、重新初始化和重复实例隔离检查。已交叉编译，未在 Windows 运行。
- Windows 全套交叉构建（含环境变量 demo 和端到端测试）通过；文件对话框 C/COM 代码已完成编译和链接。
- Windows 文件对话框的交互结果、DPI 和窗口状态仍需实际运行验证；不能把交叉编译当作这几项验收完成。
- `tests/test_windows_menu_plan.nim` 的命令映射、父菜单禁用、快捷键校验测试，本机通过；`tests/test_menu_callbacks.nim` 的菜单版本回调隔离与失败恢复测试，本机通过。
- `tests/test_windows_menu.nim` 验证实际 HMENU/HACCEL 资源、快捷键路由、角色、两窗口替换和客户区尺寸。已交叉编译，尚未执行；其中快捷键通过测试钩子读取原生加速键表再发送命令，不等同于物理键盘验证。
- 本机菜单规划、菜单回调生命周期、desktop、UI 和共享 IME 测试通过；Windows 菜单/取消事件的实际事件链尚未运行验收。
- 新目标保持进行中，完整输入仍需开发；实机通道不影响继续补齐源码和测试。
- `tests/test_windows_input.nim`：7 项回归覆盖 UTF-16/AltGr/选区、无效快捷键、剪贴板失败保留正文和撤销历史、换行、连续 IME 子句。本机通过；共享 IME 6 项、UI 27 项和 desktop 7 项回归通过。
- `tests/test_windows_input_native.nim`：发送原生窗口消息检查组合期间抑制、取消、Unicode/空格和失焦；剪贴板检查 Unicode、格式清除、非法文本、无终止符数据、另一线程占用。这些测试接入 Windows CI/交叉构建；尚未在 Windows 执行，不包含真实输入法结果串/候选 UI 验证。
- 本轮最终 Windows 全套交叉构建通过（含新增输入测试和环境变量 demo）。平台契约、菜单回调和 demo UI 本机回归通过，`git diff --check` 通过。
