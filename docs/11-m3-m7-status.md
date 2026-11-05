# M3–M7 当前状态(切片)

> 日期:2026-11-05 · 对应路线图 M3–M7
>
> **重要**:M3–M7 完整范围约 42–66 工程师周。本文件记录当前已落地的切片,
> 以及尚未完成的部分。没有把“部分完成”写成“完成”。

---

## 1. 总览

| 里程碑 | 状态 | 已实现 | 未实现 |
|---|---|---|---|
| M3 | 🟡 切片 | Checkbox/Switch/Slider/Progress/Divider、Image(ImageIO)、文本换行、焦点/键盘 | Metal 渲染器;其余控件(List/Table/Tabs/Select…);动画;可访问性 |
| M4 | 🟡 切片 | Clipboard、菜单/对话框、屏幕/主题、窗口控制/焦点、托盘、通知、全局快捷键、动态菜单 | 剪贴板图片/文件、通知权限/点击、托盘图标、快捷键冲突提示 |
| M5 | 🟡 切片 | `nimi://`/FileServer、资源复制、深链、Session、FSEvents、Cookie 查询、Document 控制器、protocol/watch/document 示例 | Cookie 写入/删除/并发、内容规则、单实例边界 |
| M6 | 🟡 切片 | TextInput/TextArea(含内部滚动)、选择/剪贴板、Undo/Redo、ScrollView/滚动条、IME | 真实 IME 验证、可访问性、完整 Metal、虚拟列表 |
| M7 | 🟡 切片 | `.app`、DMG、ad-hoc/Developer ID 签名、entitlements、图标(icns)、notarize 钩子、macOS CI 构建/测试/artifact | 自动更新(Ed25519/delta)、release workflow、DMG 背景/布局、公证实际执行验证、Sparkle 风格更新窗口 |

M2 的 Tester、离屏 PNG、焦点/键盘、文本换行继续作为 M3–M7 的基础。

---

## 2. 本轮实现

### M3 控件

新增 `ui/context` 控件:

| 控件 | API | 交互 |
|---|---|---|
| Checkbox | `checkbox(c, label, checked, onToggle, key)` | 点击/Enter/Space 切换 |
| Switch | `switch(c, on, onToggle, key)` | 点击/Enter/Space 切换 |
| Slider | `slider(c, value, onInput, min, max, key)` | 按下/拖动更新 |
| Progress | `progress(c, value, max)` | 只读 |
| Divider | `divider(c)` | 只读;填充父宽 |

- 状态用**回调**而不是 `var` 指针:`checkbox(c, "x", s.on, proc() = s.on = not s.on, "k")`,避免闭包捕获栈变量。
- Slider 使用 `Hit.onDrag`,Engine 保存 `pressedDrag/pressedRect`,拖动时按 hit rect 映射到值。
- 新增 `tests/test_ui.nim` 的 checkbox/switch/slider 测试。
- 新增 `examples/widgets-native`,已截图确认。
- 新增 `ui.image` + scene `opImage` + ImageIO/CG 渲染;示例 `examples/image-native`。
- 详见 [原生 Image](22-m3-image.md)。

### M4 菜单与对话框

- 核心 `core/menu.nim`:`Menu`/`MenuItem`/`submenu`/`separator`/`checkItem`/`defaultMenu`。
- 平台契约 `PlatformMenu`/`PlatformMenuItem`/`MenuHandler`;`Backend.setMenu`。
- Darwin `platform/darwin/menu.nim`:
  - 构建 `NSMenu`,自定义项通过 runtime `NimiMenuTarget` + tag 回调
  - role:quit/about/hide/undo/redo/cut/copy/paste/selectAll/minimize/zoom/close/fullscreen/bringAllToFront
  - accelerator 解析(`cmd+q`、`shift+cmd+z` 等)
  - 默认菜单:App/File/Edit/Window
- 对话框 `core/dialog.nim` + `platform/darwin/dialogs.nim`:
  - `dialog.open` → NSOpenPanel
  - `dialog.save` → NSSavePanel
  - `dialog.message` → NSAlert
  - 实际截图确认 About 消息框与 Save 文件面板均可打开

### M4 macOS 桌面 API

- `screens()` / `primaryDisplay()` / `cursorPosition()` / `onScreensChanged()`
- `themeInfo()` / `isDark()` / `accentColor()` / `onThemeChanged()`
- `focusedWindow()`、`Window.focused`、`onFocusChanged()`
- 窗口控制:`center/minimize/zoom/fullscreen/setSize/setPosition/setResizable/setAlwaysOnTop/hide/focus`
- 动态菜单:`app.setMenuItemEnabled/Checked`、`Menu.findItem`
- 托盘:`newTray` → NSStatusItem + NSMenu
- 通知:`notify(title, body)` → NSUserNotification
- 全局快捷键:Carbon `RegisterEventHotKey`
- 对话框:扩展名过滤、默认扩展名、多按钮、`dialog.confirm`

详细设计与限制见 [macOS 桌面 API](14-macos-desktop-apis.md)。

### M4 Clipboard

- `platform/contract.Clipboard`:read/write text/HTML/clear。
- `platform/darwin/clipboard.nim`:`NSPasteboard generalPasteboard`,`public.utf8-plain-text`、`public.html`。
- `core/clipboard.nim`:`clipboard.readText/writeText/readHTML/writeHTML/clear`。
- `examples/counter-native` 新增 `NIMI_SMOKE=clipboard`,保存/恢复原剪贴板并验证读写。

### M6 单行 TextInput

- `ui.textInput(c, value, onText, key, placeholder, size)`
- 支持:字符输入、Backspace/Delete、←/→、Home/End、Enter(忽略)、Escape(失焦)
- 鼠标点击定位 caret;Tab 焦点;caret 绘制
- 状态仍由 app 通过 `onText` 回调持有,不捕获栈指针
- 合成 AppKit key event 验证:`form name: Ada`

### M6 基础 TextArea

- `ui.textArea(...)`,复用 `layoutText` 换行
- 多行输入、Enter 换行、上下行移动、点击定位 caret
- `examples/form-native` 的 Notes 字段参与保存/加载
- 合成 AppKit 键盘事件验证 `hello\nworld`
- 选择/剪贴板:modifier keys、Shift 选择、Cmd+A/C/X/V、Engine clipboard hooks
- 原生 surface 实现 copy/cut/paste/selectAll/undo/redo responder
- Cmd+Z / Shift+Cmd+Z / Cmd+Y;每控件独立 undo 栈
- ScrollView:垂直滚动、scene clip、命中裁剪、滚轮/Tester.scrollAt、滚动条拖动
- TextArea 内部滚动、caret 自动可见、文本/marked/选择区裁剪
- 详见 [基础 TextArea](19-m6-textarea.md)、[选择与剪贴板](20-m6-selection.md)
- 详见 [ScrollView](21-m6-scrollview.md)
- 双击选词、三击选行/全文
- IME:opt-in `WindowOptions.ime`;NSTextInputClient/inputContext/caretRect/fallback
- 详见 [IME](24-m6-ime.md)

### 示例应用 `examples/form-native`

一个基本可用的原生 GUI 应用:

- 文本输入(Name)
- Checkbox、Slider、Progress、Divider
- 菜单:Form/File/Edit/Window
- File → Open/Save 调用系统文件对话框,读写表单状态
- About/按钮调用 NSAlert
- `.app` + DMG 打包

### M5 自定义协议与 FileServer

- `FileServer` + `WindowOptions.files` + WKURLSchemeHandler
- `nimi://app/index.html` 可加载本地 HTML/CSS/JS
- `nimi.json` 的 `resources` 复制到 `.app/Contents/Resources`
- `urlSchemes` → Info.plist → `application:openURLs:` → `app.onOpenURL`
- 安全路径解析、MIME、404、`NIMI_SMOKE=protocol`
- FSEvents 文件监视 → `watch(path, fn)`,支持 created/modified/removed/renamed
- Session 隔离:`WindowOptions.session` → `WKWebsiteDataStore` 默认/非持久化
- Cookie 查询/清理:`cookies(cb)`、`clearCookies(cb)` → `WKHTTPCookieStore`
- Document:`openDocument/newDocument/setText/save/reload/close`、dirty/conflict、FSEvents 外部变更
- 详见 [M5 FileServer](15-m5-file-server.md)、[M5 文件监视](16-m5-file-watching.md)、[M5 Cookies](17-m5-cookies.md)、[M5 文档](23-m5-document.md)

### M7 macOS CI

- `.github/workflows/macos.yml`
- Nim 2.4.0 + 测试 + CLI + desktop/protocol/notes 三个 DMG
- artifact 上传;`nimi build` 输出按实际 CPU 架构命名
- 详见 [macOS CI](18-macos-ci.md)

### M7 打包

`nimi build` 现在:

1. 编译 release 二进制
2. 组装 `.app` / `Info.plist` / `PkgInfo`
3. `resources/icon.png` → `sips` 生成 iconset → `iconutil` 生成 `AppIcon.icns`
4. 签名:
   - `macos.signingIdentity` 为 `-` → ad-hoc
   - 真实 identity → `--options runtime --timestamp`,可选 `macos.entitlements`
5. `hdiutil create -format UDZO` 生成 DMG
6. 真实 identity 时给 DMG 签名
7. `macos.notarize` + `macos.keychainProfile` → `notarytool submit --wait` + `stapler`
8. 打印 `.app` 和 `.dmg` 路径

验证:

```sh
./nimi build examples/counter-native
# Built .../Counter.app
# Built .../counter-0.1.0.dmg

hdiutil verify .../counter-0.1.0.dmg
# checksum is VALID
hdiutil attach -nobrowse -readonly .../counter-0.1.0.dmg
# /Volumes/Counter/Counter.app
```

---

## 3. 决策记录

| 决策 | 原因 |
|---|---|
| 控件状态用回调而非 `var` 指针 | 闭包捕获 `ptr` 到栈变量会在帧间悬空;回调捕获稳定的 app state 更安全 |
| Checkbox/Switch 用矩形 + 文本绘制 | 不引入 SF Symbols/图标系统;跨平台可复刻 |
| Slider 拖动用 `onDrag` + `pressedRect` | 拖动出控件仍能按原轨道映射值 |
| Progress/Divider 无 hit | 只读控件不进入焦点/Tab 顺序 |
| Clipboard 先文本/HTML | 图片/文件/自定义格式需要 transfer 抽象,下一步 |
| DMG 用 `hdiutil -srcfolder` | 最小可用;背景/布局/Applications 链接后续 |
| 图标用 `sips` + `iconutil` | 系统自带;避免引入图像库 |
| 公证通过 `notarytool --keychain-profile` | 不在仓库保存凭据;实际 notarize 需开发者账号验证 |
| 未实现项明确标 ⬜/🟡 | 避免把“能编译”当成“完成” |
| 菜单用核心模型 → PlatformMenu → NSMenu | 后端不依赖 core;以后 Windows/Linux 复用同一平台描述 |
| 自定义菜单项用 NSMenuItem tag + runtime target | 不需要为每个菜单项创建回调/闭包对象 |
| 对话框同步阻塞 | 符合文件/消息对话框语义;调用方需在主线程或自行调度 |
| TextInput 的 caret 存在 Engine,按 key 持久 | 每帧重建 Node 但输入状态不丢;字符编辑先更新 hit.text 以支持同帧多键 |
| TextInput 按字节处理 caret | M6 先覆盖 ASCII/常用输入;Unicode grapheme/IME 后续 |

---

## 4. 验证

```sh
./scripts/test.sh
```

通过:

- IPC、loop/events、contract
- UI 布局/命中/点击/键盘/Tab 焦点
- Tester 点击/文本
- 文本换行
- checkbox/switch/slider
- 离屏 PNG / 换行 PNG

其他:

- `examples/widgets-native` 截图确认控件绘制
- `NIMI_SMOKE=clipboard` 读写并恢复原剪贴板
- `examples/form-native`:
  - 菜单栏 Form/File/Edit/Window 实际显示
  - `NIMI_SMOKE=type` → `form name: Ada`(合成 AppKit 键盘事件)
  - `NIMI_SMOKE=dialog` → About NSAlert 截图
  - `NIMI_SMOKE=savedialog` → NSSavePanel 截图
  - `NIMI_SMOKE=serialize` → 保存/加载状态
- `nimi build examples/form-native` 产出 `.app` + DMG
- `hdiutil verify` 校验通过

---

## 5. 剩余工作(按建议顺序)

### M4
1. 用 UNUserNotificationCenter 替换 NSUserNotification,补权限/点击回调
2. 托盘图标、快捷键冲突提示、多屏窗口迁移
3. 剪贴板图片/文件与拖放
4. Edit role 与 TextInput 的 copy/paste 打通

### M3 剩余
1. Metal 渲染器(scene → instanced quad,presenter 线程)
2. List/Table/Tabs/Select/Radio 等控件
3. 动画/transition
4. 可访问性(AccessTree/NSAccessibility)

### M6
1. 真实 IME 端到端测试与精确 range 语义
2. 双击选词/拖拽、滚动条、虚拟列表
3. caret 自动滚动/TextArea 内部滚动
4. 富文本/代码编辑器
5. 完整 Metal/可访问性

### M5
1. FileServer 异步/流式/Range、多 scheme/多 root
2. Cookie 写入/删除/并发、内容规则
3. 自动保存/最近文档/冲突 diff
4. 单实例边界/文件关联

### M7 剩余
1. 自动更新(Ed25519 manifest/delta)
2. release workflow(标签/Release/更新 feed)
3. DMG 背景/布局/Applications 链接
4. 实际 notarize 验证
5. 更新窗口(原生 UI)

---

*本文件会随每个切片更新;完整完成标准仍以 `docs/05-roadmap.md` 的验收清单为准。*
