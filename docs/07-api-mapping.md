# MyGo → Nimi API 映射

> 2026-11-06 重评：本文包含目标设计，不能作为当前 API/线程安全/兼容性承诺。实现边界与后续验收以 [整改基线](28-remediation-status.md) 为准；历史工期不作为剩余工期。

> 状态:草案 · 日期:2026-11-04 · 关联:[架构](01-architecture.md)、[工具链](04-tooling-and-ipc.md)
> 目标:给实现者和迁移者一张"Go API 在 Nim 里长什么样"的对照表。不是逐方法完整清单,而是命名/语义/常用面的映射。

---

## 1. 命名规则

| 类别 | Go / MyGo | Nimi | 说明 |
|---|---|---|---|
| 包门面 | `mygo.App` | `nimi.app` | 单例小写 |
| 构造函数 | `mygo.NewWindow` | `nimi.newWindow` | 动词 + camelCase |
| 类型 | `WindowOptions` | `WindowOptions` | 类型名保持 PascalCase |
| 方法 | `win.SetTitle` | `win.setTitle` | 方法 camelCase |
| 字段 | `Title` | `title` | 字段 camelCase |
| 常量 | `KeyUp` | `KeyUp` 或 `kuUp`? | 推荐枚举:`Key.Up`;兼容别名 `KeyUp` |
| 事件注册 | `OnClose(fn)` | `onClose(fn)` | 返回 `proc()` 用于移除 |
| 布尔 | `IsReady()` | `isReady()` | 查询用 `is/has` 前缀 |
| 回调 | `func(*Window)` | `proc(w: Window)` | 闭包 |
| 错误 | `(T, error)` | 异常或 `Result[T, E]` | 见 §3 |
| 上下文 | `context.Context` | `CallContext` | 首参,不暴露给 TS |
| 通道 | `*mygo.Channel[T]` | `Channel[T]` | 首参之后的参数 |
| 泛型 | `Event[T]` | `Event[T]` | 同名 |

> 不提供 Go 风格别名(如 `SetTitle`);Nim 代码按 Nim 风格写。协议/TS 兼容层不受影响。

---

## 2. 应用(App)

| MyGo | Nimi |
|---|---|
| `mygo.App` | `nimi.app` |
| `App.Run() error` | `app.run()` |
| `App.WhenReady(fn)` | `app.whenReady(fn)` |
| `App.IsReady() bool` | `app.isReady(): bool` |
| `App.Quit()` | `app.quit()` |
| `App.Exit(code)` | `app.exit(code)` |
| `App.Relaunch()` | `app.relaunch()` |
| `App.SetName(s)` / `Name()` | `app.setName(s)` / `app.name` |
| `App.SetVersion(s)` / `Version()` | `app.setVersion(s)` / `app.version` |
| `App.IsPackaged()` | `app.isPackaged` |
| `App.SetMenu(m)` / `Menu()` | `app.setMenu(m)` / `app.menu` |
| `App.SetActivationPolicy(p)` | `app.setActivationPolicy(p)` |
| `App.Focus()` / `IsActive()` | `app.focus()` / `app.isActive` |
| `App.Hide()` / `Show()` / `IsHidden()` | `app.hide()` / `app.show()` / `app.isHidden` |
| `App.SetBadgeCount(n)` | `app.setBadgeCount(n)` |
| `App.ShowAboutPanel()` | `app.showAboutPanel()` |
| `App.ClearBrowsingData() error` | `app.clearBrowsingData()` |
| `App.Path(name) (string,error)` | `app.path(name): string` |
| `App.SetPath(name, path)` | `app.setPath(name, path)` |
| `App.SetWindowStateStore(s)` | `app.setWindowStateStore(s)` |
| `App.RegisterURLScheme(s)` | `app.registerURLScheme(s)` |
| `App.RequestSingleInstanceLock() bool` | `app.requestSingleInstanceLock(): bool` |
| `App.OnSecondInstance(fn)` | `app.onSecondInstance(fn)` |
| `App.SetOpenAtLogin(b)` | `app.setOpenAtLogin(b)` |
| `App.OnReady(fn)` | `app.onReady(fn)` |
| `App.OnWindowAllClosed(fn)` | `app.onWindowAllClosed(fn)` |
| `App.OnBeforeQuit(fn)` | `app.onBeforeQuit(fn)` |
| `App.OnWillQuit(fn)` | `app.onWillQuit(fn)` |
| `App.OnQuit(fn)` | `app.onQuit(fn)` |
| `App.OnActivate(fn)` | `app.onActivate(fn)` |
| `App.OnDidBecomeActive(fn)` | `app.onDidBecomeActive(fn)` |
| `App.OnDidResignActive(fn)` | `app.onDidResignActive(fn)` |
| `App.OnOpenURL(fn)` | `app.onOpenURL(fn)` |
| `App.OnOpenFile(fn)` | `app.onOpenFile(fn)` |
| `App.OnNotificationClick(fn)` | `app.onNotificationClick(fn)` |
| `App.OnWindowCreated(fn)` | `app.onWindowCreated(fn)` |
| `App.Dock.*` | `app.dock.*` |

### 示例

```nim
import nimi

type Greeter = ref object

proc greet(self: Greeter, name: string): string {.rpc.} =
  "Hello " & name

let greeter = Greeter()
bindService(greeter, greet)

nimi.app.whenReady(proc() =
  discard nimi.newWindow(WindowOptions(
    title: "Hello",
    width: 480,
    height: 320,
    url: "/"
  ))
)

nimi.app.run()
```

---

## 3. 错误、上下文、通道

### 3.1 错误

MyGo 用 `(T, error)`;Nim 推荐:

```nim
type
  NimiError* = object of CatchableError
  CallError* = object of NimiError
    code*: string
```

- 公开 API 抛 `NimiError`;调用者用 `try/except`。
- 绑定方法抛异常 → IPC reply `ok:false,e:message`;不发送堆栈。
- 需要显式结果时用 `Result[T, E]`(可选,不作为默认)。
- `Defect`(断言/越界)不捕获;开发构建直接失败。

### 3.2 上下文

```nim
type
  CallContext* = ref object
    cancelled*: bool
    window*: Window
    page*: Page
    deadline*: Option[DateTime]

proc callerWindow*(ctx: CallContext): Option[Window]
proc callerPage*(ctx: CallContext): Option[Page]
proc isCancelled*(ctx: CallContext): bool
```

- 绑定方法首参可选 `ctx: CallContext`;TS 不暴露。
- 页面导航/窗口关闭时置 `cancelled`;长任务应检查。
- 替代 Go 的 `context.Context`;不引入标准库 context。

### 3.3 通道

```nim
type Channel*[T] = ref object
  # 由宏/IPC 创建;应用只 Send/Close

proc send*[T](c: Channel[T], value: T)
proc close*[T](c: Channel[T])
```

- 只能作为 `{.rpc.}` 方法参数。
- `send` 在非主线程可阻塞(1 MiB 窗口);主线程不阻塞。
- 页面 close/导航 → `CallContext.cancelled`。
- 替代 Go 的 `*mygo.Channel[T]`。

---

## 4. 窗口(Window)

### 4.1 选项

| MyGo `WindowOptions` | Nimi `WindowOptions` |
|---|---|
| `Title` | `title` |
| `URL` | `url` |
| `Width` / `Height` | `width` / `height` |
| `UseContentSize` | `useContentSize` |
| `X` / `Y` | `x` / `y` |
| `MinWidth` / `MinHeight` | `minWidth` / `minHeight` |
| `MaxWidth` / `MaxHeight` | `maxWidth` / `maxHeight` |
| `FitContent` | `fitContent` |
| `Hidden` | `hidden` |
| `Frameless` | `frameless` |
| `TitleBarStyle` | `titleBarStyle` |
| `TrafficLightPosition` | `trafficLightPosition` |
| `TitleBarHeight` | `titleBarHeight` |
| `HideWindowButtons` | `hideWindowButtons` |
| `DisableResize/Move/Minimize/Maximize/Close/FullScreen` | `disableResize`/... |
| `AlwaysOnTop` | `alwaysOnTop` |
| `FullScreen` | `fullScreen` |
| `Maximized` | `maximized` |
| `SkipTaskbar` | `skipTaskbar` |
| `AutoHideMenuBar` | `autoHideMenuBar` |
| `Transparent` | `transparent` |
| `BackgroundColor` | `backgroundColor` |
| `Vibrancy` | `vibrancy` |
| `CornerRadius` | `cornerRadius` |
| `Opacity` | `opacity` |
| `Parent` | `parent` |
| `Modal` | `modal` |
| `Panel` | `panel` |
| `Page PageOptions` | `page: PageOptions` |
| `StateKey` | `stateKey` |
| `Content Content` | `content: Content` |

### 4.2 方法/事件

| MyGo | Nimi |
|---|---|
| `NewWindow(opts) *Window` | `newWindow(opts): Window` |
| `Windows() []*Window` | `windows(): seq[Window]` |
| `FocusedWindow() *Window` | `focusedWindow(): Option[Window]` |
| `WindowByID(id) *Window` | `windowByID(id): Option[Window]` |
| `win.ID` | `win.id` |
| `win.Parent()` | `win.parent` |
| `win.IsDestroyed()` | `win.isDestroyed` |
| `win.Show/ShowInactive/Hide/Focus/Blur` | `win.show/showInactive/hide/focus/blur` |
| `win.Close()/Destroy()` | `win.close()/destroy()` |
| `win.SetTitle/Title` | `win.setTitle/title` |
| `win.SetRepresentedFile/RepresentedFile` | `win.setRepresentedFile/representedFile` |
| `win.SetDocumentEdited/IsDocumentEdited` | `win.setDocumentEdited/isDocumentEdited` |
| `win.SetBounds/Bounds` | `win.setBounds/bounds` |
| `win.SetContentBounds/ContentBounds` | `win.setContentBounds/contentBounds` |
| `win.SetSize/Size` | `win.setSize/size` |
| `win.SetContentSize/ContentSize` | `win.setContentSize/contentSize` |
| `win.SetPosition/Position` | `win.setPosition/position` |
| `win.SetMinimumSize/SetMaximumSize` | `win.setMinimumSize/setMaximumSize` |
| `win.Center()` | `win.center()` |
| `win.SetResizable/IsResizable` | `win.setResizable/isResizable` |
| `win.SetMovable` / `SetMinimizable` / `SetMaximizable` / `SetClosable` | `win.setMovable` / ... |
| `win.SetAlwaysOnTop/IsAlwaysOnTop` | `win.setAlwaysOnTop/isAlwaysOnTop` |
| `win.SetBackgroundColor` | `win.setBackgroundColor` |
| `win.SetOpacity/Opacity` | `win.setOpacity/opacity` |
| `win.SetHasShadow` | `win.setHasShadow` |
| `win.SetIgnoreMouseEvents` | `win.setIgnoreMouseEvents` |
| `win.SetActiveAppearance` | `win.setActiveAppearance` |
| `win.SetWindowButtonsTheme` | `win.setWindowButtonsTheme` |
| `win.SetContentProtection` | `win.setContentProtection` |
| `win.SetVibrancy` | `win.setVibrancy` |
| `win.SetProgressBar` | `win.setProgressBar` |
| `win.FlashFrame` | `win.flashFrame` |
| `win.SetSkipTaskbar` | `win.setSkipTaskbar` |
| `win.SetVisibleOnAllWorkspaces` | `win.setVisibleOnAllWorkspaces` |
| `win.SetIcon` | `win.setIcon` |
| `win.SetMenu` | `win.setMenu` |
| `win.SetAutoHideMenuBar` | `win.setAutoHideMenuBar` |
| `win.NativeHandle()` | `win.nativeHandle` |
| `win.OnClose(fn)` | `win.onClose(fn)` |
| `win.OnClosed(fn)` | `win.onClosed(fn)` |
| `win.OnFocus/OnBlur` | `win.onFocus/onBlur` |
| `win.OnShow/OnHide` | `win.onShow/onHide` |
| `win.OnReadyToShow` | `win.onReadyToShow` |
| `win.OnResize/OnMove` | `win.onResize/onMove` |
| `win.OnFileDrop` | `win.onFileDrop` |
| `win.OnMaximize/OnUnmaximize` | `win.onMaximize/onUnmaximize` |
| `win.OnMinimize/OnRestore` | `win.onMinimize/onRestore` |
| `win.OnEnterFullScreen/OnLeaveFullScreen` | `win.onEnterFullScreen/onLeaveFullScreen` |
| `win.Page()` | `win.page(): Option[Page]` |
| `win.Invalidate()` | `win.invalidate()` |
| `win.Update(fn)` | `win.update(fn)` |

### 4.3 语义差异

- `Window` 是 `ref object`;关闭后调用方法应报错或忽略(与 Go 的 `IsDestroyed` 一致)。
- 事件注册返回 `proc()` 用于移除;不返回闭包 ID。
- `OnClose` 可取消:回调返回 `bool` 或在 `CloseEvent` 上 `preventDefault()`。推荐显式事件对象:

```nim
win.onClose(proc(e: var CloseEvent) =
  if hasUnsaved: e.preventDefault()
)
```

- 窗口创建必须在 `whenReady` 之后;之前调用抛 `NimiError`(与 MyGo 的 panic 对应)。
- 状态恢复:`stateKey` + 默认存储;可注入 `WindowStateStore`。

---

## 5. 页面(Page)

| MyGo | Nimi |
|---|---|
| `win.Page().LoadURL(url)` | `page.loadURL(url)` |
| `LoadFile(path)` | `page.loadFile(path)` |
| `LoadHTML(html, base)` | `page.loadHTML(html, base)` |
| `Reload()` / `ReloadIgnoringCache()` | `page.reload()` / `page.reloadIgnoringCache()` |
| `Stop()` | `page.stop()` |
| `GoBack()` / `GoForward()` | `page.goBack()` / `page.goForward()` |
| `CanGoBack()` / `CanGoForward()` | `page.canGoBack` / `page.canGoForward` |
| `URL()` | `page.url` |
| `IsLoading()` | `page.isLoading` |
| `SetZoomFactor/ZoomFactor` | `page.setZoomFactor/zoomFactor` |
| `SetUserAgent/UserAgent` | `page.setUserAgent/userAgent` |
| `OpenDevTools/CloseDevTools/IsDevToolsOpened/ToggleDevTools` | `page.openDevTools/...` |
| `Print()` | `page.print()` |
| `CapturePage()` | `page.capturePage()` |
| `Eval(code) (any,error)` | `page.eval(code): JsonNode` |
| `EvalAs[T](code)` | `page.evalAs[T](code)` |
| `OnPageTitleUpdated(fn)` | `page.onPageTitleUpdated(fn)` |
| `OnWillNavigate(fn)` | `page.onWillNavigate(fn)` |
| `OnDidNavigate(fn)` | `page.onDidNavigate(fn)` |
| `OnDOMReady(fn)` | `page.onDOMReady(fn)` |
| `OnDidFinishLoad(fn)` | `page.onDidFinishLoad(fn)` |
| `OnDidFailLoad(fn)` | `page.onDidFailLoad(fn)` |
| `OnRenderProcessGone(fn)` | `page.onRenderProcessGone(fn)` |
| `OnThemeColorChanged(fn)` | `page.onThemeColorChanged(fn)` |
| `OnAudibleChanged(fn)` | `page.onAudibleChanged(fn)` |
| `OnCaptureStateChanged(fn)` | `page.onCaptureStateChanged(fn)` |
| `SetWindowOpenHandler(fn)` | `page.setWindowOpenHandler(fn)` |
| `SetAuthHandler(fn)` | `page.setAuthHandler(fn)` |
| `SetCertificateErrorHandler(fn)` | `page.setCertificateErrorHandler(fn)` |
| `PageOptions` | `PageOptions` |

`PageOptions` 字段映射同理(camelCase):`preloadScript`、`preloadAllFrames`、`trustedOrigins`、`devTools`、`zoomFactor`、`userAgent`、`safariTabFocus`、`pictureInPicture`、`swipeNavigation`、`pinchZoom`、`userAgentSuffix`、`contentRules`、`session`、`untrusted`、`backgroundThrottling`、`autoplay`、`sessionState`。

- `Eval` 返回 `JsonNode`;类型化用 `evalAs[T]`。
- 导航会重置页面 token;旧 Promise 不 resolve 新页。
- `SetWindowOpenHandler` 返回 `Option[WindowOptions]`;`none` 阻止。

---

## 6. IPC

| MyGo | Nimi |
|---|---|
| `mygo.Bind(v)` | `bindService(instance, procs...)`(宏) |
| `mygo.BindAs(name, v)` | `bindServiceAs("Store", instance, procs...)` |
| `mygo.NewEvent[T](name)` | `newEvent[T]("note-added")` |
| `event.Emit(win, payload)` | `event.emit(win, payload)` |
| `event.EmitPage(page, payload)` | `event.emitPage(page, payload)` |
| `event.Broadcast(payload)` | `event.broadcast(payload)` |
| `*mygo.Channel[T]` | `Channel[T]` |
| `mygo.CallerWindow(ctx)` | `callerWindow(ctx)` |
| `mygo.CallerPage(ctx)` | `callerPage(ctx)` |
| `mygo.GenerateTypeScript()` | `generateTypeScript()` |
| `mygo.WriteTypeScript(path)` | `writeTypeScript(path)` |
| `mygo.Plugin{Name, Service, Setup}` | `Plugin(name, service, setup)` |
| `mygo.Use(ps...)` | `use(ps)` |

### 示例

```nim
type
  Note = object
    id: int
    title: string

  Notes = ref object
    items: seq[Note]

let noteAdded = newEvent[Note]("note-added")

proc add(self: Notes, title: string): Note {.rpc.} =
  result = Note(id: self.items.len + 1, title: title)
  self.items.add result
  noteAdded.broadcast(result)

proc list(self: Notes): seq[Note] {.rpc.} =
  self.items

let notes = Notes()
bindService(notes, add, list)
```

---

## 7. 菜单

| MyGo | Nimi |
|---|---|
| `mygo.NewMenu(items)` | `newMenu(items)` |
| `Menu.Append/Insert/Remove` | `menu.append/insert/remove` |
| `Menu.ItemByID` | `menu.itemByID` |
| `Menu.Popup(win)` / `PopupAt` | `menu.popup(win)` / `popupAt` |
| `MenuItem.Type` | `item.kind` |
| `MenuItem.Role` | `item.role` |
| `MenuItem.Accelerator` | `item.accelerator` |
| `MenuItem.Disabled/Hidden/Checked` | `item.disabled/hidden/checked` |
| `MenuItem.Click` | `item.onClick` |
| `MenuItem.SetEnabled/IsEnabled` | `item.setEnabled/isEnabled` |
| `MenuItem.SetVisible` | `item.setVisible` |
| `MenuItem.SetChecked/IsChecked` | `item.setChecked/isChecked` |
| `MenuItem.SetLabel` | `item.setLabel` |
| `MenuItem.SetAccelerator` | `item.setAccelerator` |
| `MenuItem.SetIcon` | `item.setIcon` |
| `mygo.NewMenuIcon(data, template)` | `newMenuIcon(data, template)` |
| `mygo.MenuRole*` | `MenuRole.*` |
| `mygo.MenuItemNormal/Separator/Submenu/Checkbox/Radio` | `MenuItemKind.Normal/...` |

Role 名称映射:`RoleUndo` → `MenuRole.Undo`,`RoleNew` → `MenuRole.New`,等等。51 个 role 同名。

---

## 8. 桌面模块

| MyGo | Nimi |
|---|---|
| `mygo.Dialog.Open(opts)` | `dialog.open(opts)` |
| `mygo.Dialog.Save(opts)` | `dialog.save(opts)` |
| `mygo.Dialog.Message(opts)` | `dialog.message(opts)` |
| `mygo.Dialog.Error(title, content)` | `dialog.error(title, content)` |
| `mygo.Clipboard.ReadText/WriteText` | `clipboard.readText/writeText` |
| `mygo.Clipboard.ReadHTML/WriteHTML` | `clipboard.readHTML/writeHTML` |
| `mygo.Clipboard.ReadImage/WriteImage` | `clipboard.readImage/writeImage` |
| `mygo.Clipboard.AvailableFormats/Clear` | `clipboard.availableFormats/clear` |
| `mygo.Clipboard.Write/Read/Formats/Flush` | `clipboard.write/read/formats/flush` |
| `mygo.Shell.OpenExternal/OpenPath` | `shell.openExternal/openPath` |
| `mygo.Shell.ShowItemInFolder/TrashItem` | `shell.showItemInFolder/trashItem` |
| `mygo.Shell.FileIcon/TypeIcon` | `shell.fileIcon/typeIcon` |
| `mygo.Shell.InstalledApps/LaunchApp/Beep` | `shell.installedApps/launchApp/beep` |
| `mygo.Screen.Displays/PrimaryDisplay` | `screen.displays/primaryDisplay` |
| `mygo.Screen.CursorScreenPoint` | `screen.cursorScreenPoint` |
| `mygo.Screen.OnDisplaysChanged` | `screen.onDisplaysChanged` |
| `mygo.Theme.IsDark` | `theme.isDark` |
| `mygo.Theme.Preferences()` | `theme.preferences` |
| `mygo.Theme.Source/SetSource` | `theme.source/setSource` |
| `mygo.Theme.SetGTKCSS` | `theme.setGTKCSS` |
| `mygo.Theme.OnUpdated` | `theme.onUpdated` |
| `mygo.GlobalShortcut.Register(acc, fn)` | `globalShortcut.register(acc, fn)` |
| `mygo.GlobalShortcut.IsRegistered` | `globalShortcut.isRegistered` |
| `mygo.GlobalShortcut.Unregister/UnregisterAll` | `globalShortcut.unregister/unregisterAll` |
| `mygo.NewTray(opts)` | `newTray(opts)` |
| `mygo.Tray.SetIcon/SetTitle/SetToolTip` | `tray.setIcon/setTitle/setToolTip` |
| `mygo.Tray.SetMenu/PopUpMenu` | `tray.setMenu/popUpMenu` |
| `mygo.Tray.Bounds/Destroy` | `tray.bounds/destroy` |
| `mygo.NewNotification(opts)` | `newNotification(opts)` |
| `notification.Show/ShowContext/Close` | `notification.show/showContext/close` |
| `notification.OnClick` | `notification.onClick` |
| `mygo.ClearNotifications()` | `clearNotifications()` |
| `mygo.NotificationsSupported()` | `notificationsSupported()` |
| `mygo.Power.*` | `power.*` |
| `mygo.Network.*` | `network.*` |
| `mygo.NowPlaying.*` | `nowPlaying.*` |

---

## 9. Cookie / Session / Watch / Documents

| MyGo | Nimi |
|---|---|
| `mygo.Cookies.List(filter)` | `cookies.list(filter)` |
| `mygo.Cookies.Set(cookie)` | `cookies.set(cookie)` |
| `mygo.Cookies.Delete(cookie)` | `cookies.delete(cookie)` |
| `mygo.Cookies.Clear()` | `cookies.clear()` |
| `mygo.DefaultSession()` | `defaultSession()` |
| `mygo.NewSession(name)` | `newSession(name)` |
| `mygo.NewEphemeralSession()` | `newEphemeralSession()` |
| `session.ClearData(kind)` | `session.clearData(kind)` |
| `mygo.WatchFiles(ctx, path, opts)` | `watchFiles(ctx, path, opts)` |
| `watcher.Next(ctx)` | `watcher.next(ctx)` |
| `watcher.Close/Done/Err` | `watcher.close/done/err` |
| `mygo.NewDocuments[T](opts)` | `newDocuments[T](opts)` |
| `docs.New/Open/OpenDialog` | `docs.new/open/openDialog` |
| `doc.Content/Set/Changed` | `doc.content/set/changed` |
| `doc.Save/SaveAs/SaveAnyway` | `doc.save/saveAs/saveAnyway` |
| `doc.Revert/Rename/MoveTo/Duplicate/Close` | `doc.revert/rename/moveTo/duplicate/close` |
| `doc.State/OnStateChange/OnReload` | `doc.state/onStateChange/onReload` |
| `doc.IsReadOnly/HasConflict` | `doc.isReadOnly/hasConflict` |

- `Documents[T]` 用 Nim 泛型;回调类型用 `proc`。
- `context.Context` → `CallContext`。
- `FileEvent`/`FileWatchOptions` 字段 camelCase。

---

## 10. 原生 UI

### 10.1 入口

| MyGo | Nimi |
|---|---|
| `ui.View(view func(*ui.Context))` | `uiView(view: proc(c: Context))` |
| `ui.Render(view, w, h, scale)` | `ui.render(view, w, h, scale)` |
| `ui.NewTester(...)` | `newTester(...)` |
| `ui.Local(...)` | `local(...)` |
| `ui.DragOver` / `Drop` | `dragOver` / `drop` |

### 10.2 构造器命名

Go `ui.Column(c)` → Nim `column(c)`;所有 120 个构造器首字母小写:

| Go | Nimi | Go | Nimi |
|---|---|---|---|
| `Box` | `box` | `Column` | `column` |
| `Row` | `row` | `Spacer` | `spacer` |
| `Divider` | `divider` | `Grid` | `grid` |
| `Scroll` | `scroll` | `ScrollBoth` | `scrollBoth` |
| `Text` | `text` | `Textf` | `textf` |
| `Button` | `button` | `PrimaryButton` | `primaryButton` |
| `Checkbox` | `checkbox` | `Radio` | `radio` |
| `Switch` | `switch` | `Slider` | `slider` |
| `TextInput` | `textInput` | `TextArea` | `textArea` |
| `Select` | `select` | `Combobox` | `combobox` |
| `List` | `list` | `Table` | `table` |
| `Tree` | `tree` | `Image` | `image` |
| `Icon` | `icon` | `Popover` | `popover` |
| `Modal` | `modal` | `Tooltip` | `tooltip` |
| `Tabs` | `tabs` | `Segmented` | `segmented` |
| `Sidebar` | `sidebar` | `Toolbar` | `toolbar` |
| `Form` | `form` | `Field` | `field` |
| `Calendar` | `calendar` | `ColorPicker` | `colorPicker` |
| `Router` | `router` | `RichText` | `richText` |
| `WebView` | `webView` | `Video` | `video` |

完整列表以 `03-native-ui.md` §9.1 为准。

### 10.3 Element 方法

Go `e.Fill()` → Nim `e.fill()`;271 个方法按 camelCase 映射:

| Go | Nimi |
|---|---|
| `Width/Height/Size` | `width/height/size` |
| `Fill/FillWidth/FillHeight` | `fill/fillWidth/fillHeight` |
| `Grow/Shrink/Basis` | `grow/shrink/basis` |
| `Padding/PaddingX/PaddingY` | `padding/paddingX/paddingY` |
| `Margin/MarginX/MarginY` | `margin/marginX/marginY` |
| `Gap/GapX/GapY` | `gap/gapX/gapY` |
| `Center/Justify/AlignItems/AlignSelf` | `center/justify/alignItems/alignSelf` |
| `Row/Column/Reverse/Wrap` | 构造器/选项,见控件 |
| `TextColor/FontSize/Bold/Italic` | `textColor/fontSize/bold/italic` |
| `Background/Border/BorderColor/Radius` | `background/border/borderColor/radius` |
| `Opacity/Shadow/Clip/Scrollbars` | `opacity/shadow/clip/scrollbars` |
| `Key(...)` | `key(...)`(Context) |
| `Clicked/Hovered/Pressed/Focused/Changed/Submitted` | 同名 camelCase |
| `Disabled/ReadOnly/Hidden/Invisible` | `disabled/readOnly/hidden/invisible` |
| `Label/Tooltip` | `label/tooltip` |
| `OnClick/OnChange/OnSubmit` | `onClick/onChange/onSubmit` |

### 10.4 Context 方法

| Go | Nimi |
|---|---|
| `c.Key(...)` | `c.key(...)` |
| `c.Theme()` | `c.theme` |
| `c.Locale()` | `c.locale` |
| `c.Direction()` | `c.direction` |
| `c.Size()` | `c.size` |
| `c.Scale()` | `c.scale` |
| `c.Shortcut(mods, key)` | `c.shortcut(mods, key)` |
| `c.Announce(text)` | `c.announce(text)` |
| `c.Invalidate()` | `c.invalidate()` |
| `ui.Local(...)` | `local(...)` |

### 10.5 原生 UI 示例

```nim
import nimi
import nimi/ui

type Counter = ref object
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
  )

let s = Counter()
nimi.app.whenReady(proc() =
  discard nimi.newWindow(WindowOptions(
    title: "Counter",
    width: 360,
    height: 260,
    content: uiView(proc(c: Context) = view(s, c))
  ))
)
nimi.app.run()
```

---

## 11. 生成的 TypeScript

### 11.1 服务

```ts
export const Notes = {
  add(title: string): Promise<Note> { return call("Notes.Add", title); },
  list(): Promise<Note[]> { return call("Notes.List"); },
} as const;
```

### 11.2 事件

```ts
export const events = {
  noteAdded: event<Note>("note-added"),
} as const;

events.noteAdded((note) => console.log(note.title));
```

### 11.3 Channel

```ts
const ch = new Channel<Progress>();
await Downloads.start(ch);
for await (const p of ch) console.log(p);
```

### 11.4 命名/类型

- 方法 camelCase;参数保留 Nim 名;`self`/`ctx` 不暴露。
- `Option[T]` → `T | null`;`seq[T]` → `T[]`;`Table[K,V]` → `Record<K,V>`。
- 具名 string/number + const → 字面量 union。
- 结构体 → interface;文档用 `{.doc.}` 或显式 `doc`。
- 大整数 ID 用 `string` 标注。

---

## 12. 不映射 / 延后

| MyGo | 状态 | 原因 |
|---|---|---|
| Go 反射式 `Bind`(自动枚举导出方法) | 改为 `{.rpc.}` + 宏 | Nim 无运行时方法集 |
| `context.Context` | `CallContext` | Nim 无标准 context |
| goroutine | 工作线程池 | Nim 线程模型 |
| `sync.Mutex/Cond/Once` | `std/locks`/`std/condvar`/`once` | 标准库映射 |
| `weak.Pointer` | 整数 ID + 显式表 | Nim 无弱引用 |
| `go:embed`/`-overlay` | 生成 `staticRead` 模块 | 构建方式不同 |
| `-ldflags -X` | 生成 `nimi_build.nim` | Nim 无等价物 |
| Go 插件/`plugin:` ABI | 静态模块(第一版) | 动态 ABI 后置 |
| CEF 内置 | 不做 | 非目标 |
| wasm 后端 | 延后 | M10 |
| `ui/editor`/`richtext`/`markdown`/`chart` | 延后 | P2 |

---

## 13. 迁移检查清单

从 Go MyGo 迁移到 Nimi 时:

- [ ] 包名 `mygo` → `nimi`;`ui` 保留。
- [ ] `App` → `app`;`NewWindow` → `newWindow`;方法/字段 camelCase。
- [ ] `Bind` → `{.rpc.}` + `bindService(instance, procs...)`。
- [ ] `context.Context` → `CallContext`。
- [ ] `Channel[T]` 语义不变;检查 send/close。
- [ ] 错误处理:`(T, error)` → 异常/`Result`。
- [ ] 事件监听器返回 `proc()`;可取消事件用 `preventDefault`。
- [ ] TS 客户端包名 `mygo-runtime` → `nimi-runtime`(可用兼容别名)。
- [ ] 配置 `mygo.json` → `nimi.json`;字段同名。
- [ ] 打包命令 `mygo build` → `nimi build`。
- [ ] 原生 UI 构造器/方法 camelCase。
- [ ] 插件:静态 import;服务名 `plugin:<name>` 保留。

---

*本文档是映射约定,不是完整 API 参考;实现时以源码 doc comment 为准。*
