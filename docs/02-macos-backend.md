# macOS 后端设计

> 状态:草案 · 日期:2026-11-04 · 关联:[架构](01-architecture.md)、[原生 UI](03-native-ui.md)、[路线图](05-roadmap.md)
> 参考:MyGo `internal/darwin`(14.5k 行)、`internal/gpu/metal`(6.1k 行)、`internal/text/coretext_darwin.go`(1.6k 行)
> 原型:`spikes/objc_hello`、`spikes/wkwebview`、`spikes/coretext`、`spikes/metal`、`spikes/blocks`

---

## 1. 范围与基线

| 项 | 取值 |
|---|---|
| 最低系统 | macOS 12.0(与 MyGo 默认一致) |
| 架构 | arm64 优先;amd64 后续;Universal 由 `lipo` 合并 |
| 窗口类型 | WebView 窗口 + 原生 UI 窗口(可混合) |
| Objective-C 交互 | 纯 Nim runtime 调用;无 cgo、无 `.m` shim(原型已验证) |
| 文本 | CoreText |
| GPU | Metal(macOS 12+);CoreGraphics CPU 回退 |
| 音频 | AudioToolbox AudioQueue |
| 打包 | `.app` + `.dmg`,codesign/notarytool/stapler |

> **与 MyGo 的差异**:MyGo 因为"无 cgo"必须用 purego + 汇编 trampoline。Nim 直接生成 C,可以直接声明 `objc_msgSend` 的强类型变体,不需要 purego。这简化了一层,但 ABI 细节仍需自己保证(见 §2.2)。

---

## 2. Objective-C 交互层

### 2.1 框架加载

启动时 `dlopen` 或静态链接以下框架。推荐**静态链接系统框架**(`{.passL: "-framework AppKit".}` 等),因为 macOS 构建机一定有 SDK;动态加载只在需要可选框架/私有类时使用。

| 框架 | 用途 | 必需 |
|---|---|---|
| `libobjc.A.dylib` | runtime | 是 |
| Foundation / CoreFoundation | 基础类型、RunLoop、通知 | 是 |
| AppKit | 窗口、菜单、对话框、剪贴板、托盘 | 是 |
| WebKit | WKWebView | WebView 窗口 |
| QuartzCore | CALayer、CAMetalLayer | 原生 UI |
| Metal / MetalKit | GPU 渲染 | 原生 UI(GPU) |
| CoreText / CoreGraphics | 文本、位图 | 是 |
| CoreServices / Carbon | 全局快捷键、文件图标 | 可选 |
| UserNotifications | 通知 | 可选 |
| ServiceManagement | 登录项 | 可选 |
| Security | Keychain | 可选 |
| AudioToolbox | 音频输出 | 可选 |
| FSEvents(CoreServices) | 文件监视 | 可选 |
| UniformTypeIdentifiers | 文件类型过滤 | 可选 |

### 2.2 `objc_msgSend` 的类型化封装

**不要**用 `varargs` 调用 `objc_msgSend`。Nim 的 varargs 在 Apple arm64 上会把浮点参数放到栈上,而 `objc_msgSend` 期望常规参数寄存器。必须按签名强转函数指针:

```nim
type
  Id = pointer
  SEL = distinct pointer

  MsgSend0 = proc(a: Id, s: SEL): Id {.cdecl.}
  MsgSendVoid = proc(a: Id, s: SEL) {.cdecl.}
  MsgSendId1 = proc(a: Id, s: SEL, b: Id): Id {.cdecl.}
  MsgSendVoidId = proc(a: Id, s: SEL, b: Id) {.cdecl.}
  MsgSendVoidBool = proc(a: Id, s: SEL, b: bool) {.cdecl.}
  MsgSendVoidInt = proc(a: Id, s: SEL, b: int) {.cdecl.}
  MsgSendVoidDouble = proc(a: Id, s: SEL, b: float64) {.cdecl.}
  MsgSendVoidRect = proc(a: Id, s: SEL, r: NSRect) {.cdecl.}
  MsgSendRect = proc(a: Id, s: SEL): NSRect {.cdecl.}
  # ... 按需增加

let msgSend = cast[pointer](symAddr(objc, "objc_msgSend"))

proc send0(o: Id, s: SEL): Id =
  cast[MsgSend0](msgSend)(o, s)

proc sendVoidId(o: Id, s: SEL, b: Id) =
  cast[MsgSendVoidId](msgSend)(o, s, b)
```

ABI 规则:

| 类型 | 注意 |
|---|---|
| `BOOL` | 1 字节 signed char;Nim `bool` 是 1 字节,可直接用;不要用 `int` |
| `NSInteger`/`NSUInteger` | 64-bit `long`;Nim `int`/`uint` 在 64-bit 平台匹配 |
| `CGFloat` | `float64`(Apple 64-bit) |
| `NSRect`/`NSPoint`/`NSSize` | 32/16/16 字节 by-value struct;Nim `object {.bycopy.}` 匹配 |
| `NSRange` | 两个 `NSUInteger`;Nim `object {.bycopy.}` 匹配 |
| 结构体返回 | arm64 直接返回;x86_64 大于 16 字节需 `objc_msgSend_stret` |
| 浮点参数 | 用强类型函数指针,不能用 varargs |
| 空返回值 | 用 `{.cdecl.}` 的 void 函数指针,不要返回 Id |

**x86_64 的 stret**:如果 M7 支持 Intel,需要一个 `msgSendStret` 分支,并在编译期 `when defined(amd64)` 选择。arm64 不需要。

**selector/class 缓存**:

```nim
var selectorCache: Table[string, SEL]
proc sel(name: string): SEL =
  selectorCache.mgetOrPut(name, registerName(name.cstring))

var classCache: Table[string, Id]
proc cls(name: string): Id =
  classCache.mgetOrPut(name, getClass(name.cstring))
```

**调用辅助**:为每类高频签名提供 `send…` 包装;不要为每次调用创建闭包。所有调用在主线程。

### 2.3 运行时定义类

AppKit 需要子类/委托时,用 runtime 创建:

```nim
proc addMethod(c: Id, name: string, imp: pointer, types: cstring): bool =
  class_addMethod(c, sel(name), imp, types)

proc allocateClassPair(super: Id, name: cstring, extra: uint): Id =
  objc_allocateClassPair(super, name, extra)

proc registerClassPair(c: Id) =
  objc_registerClassPair(c)
```

方法类型编码:

| 方法签名 | encoding |
|---|---|
| `- (void)foo` | `"v@:"` |
| `- (void)foo:(id)x` | `"v@:@"` |
| `- (void)foo:(id)x bar:(id)y` | `"v@:@@"` |
| `- (BOOL)foo` | `"c@:"` |
| `- (void)foo:(BOOL)b` | `"v@:c"` |
| `- (void)foo:(NSRect)r` | `"v@:{CGRect={CGPoint=dd}{CGSize=dd}}"` |
| `- (void)foo:(NSInteger)i` | `"v@:q"` |
| `- (void)foo:(NSRange)r` | `"v@:{_NSRange=QQ}"` |

- 简单方法用 `"v@:@"` 通常足够;需要精确的类型编码(NSRect/NSRange/BOOL 参数)时写全。
- 协议只在运行时应存在时添加(`objc_getProtocol` + `class_addProtocol`);不要假设 `WKScriptMessageHandler` 在所有版本都注册。
- overrides 调 super 时,用 `objc_msgSendSuper` + **声明该方法的类**解析超类,不要用对象当前 isa(KVO 会替换 isa,导致递归)。
- 类的 `isa` 指针在 Nim 侧用 `Id`;不要把它放进 `ref object` 的析构器。

### 2.4 Block

**全局 block(无捕获)** 已验证可行:

```nim
type
  BlockDescriptor {.bycopy.} = object
    reserved: uint
    size: uint
  BlockLiteral {.bycopy.} = object
    isa: pointer
    flags: int32
    reserved: int32
    invoke: pointer
    descriptor: ptr BlockDescriptor

var descriptor = BlockDescriptor(reserved: 0, size: uint(sizeof(BlockLiteral)))
var block = BlockLiteral(
  isa: globalBlockIsa,          # _NSConcreteGlobalBlock
  flags: int32(1 shl 28),       # BLOCK_IS_GLOBAL
  invoke: cast[pointer](myCallback),
  descriptor: addr descriptor)
```

- 回调签名必须与 block 的 `invoke` 完全一致,第一个参数是 block 自身。
- `globalBlockIsa` 从 `libSystem` 的 `_NSConcreteGlobalBlock` 取;block 需保持全局存活。
- 传给系统后系统通常会 copy;若 API 不 copy,block 也必须常驻。

**带捕获的 block**:不要把 Nim 闭包直接转成函数指针。用 C 分配上下文 + 全局表:

```nim
type BlockContext = object
  requestId: uint64
  windowId: uint32

# 分配 malloc 的上下文;把 requestId 放进额外的 block 字段(或全局表)
# invoke 回调按 requestId 查 Nim 侧注册表
```

需要 descriptor 的 `copy`/`dispose` 辅助函数来释放上下文;不要捕获 Nim `ref`。

**系统传回的 block**:如果系统可能在调用返回后异步调用(decision handler、completion handler),先 `_Block_copy`,调用后 `_Block_release`。MyGo 在 `dialog.go`/`auth.go` 明确这样做。

**生命周期**:

- 传给系统的 block:调用后系统负责 copy;调用完可释放我们自己的引用。
- 系统传给我们的 block:不拥有;需要晚调用则 copy。
- 所有 block 回调必须 `try/except` 捕获,不允许 Nim 异常穿过 ObjC 栈。

### 2.5 内存所有权

定义两个概念:

```nim
type
  Owned[T] = object      # +1,必须 release
    raw: T
  Borrowed[T] = object   # 不拥有
    raw: T
```

规则:

1. `alloc`/`init`、`new`、`copy`、`mutableCopy`、`Create`/`Copy` 返回 +1 → `Owned`。
2. 便利构造器(`windowWith...`、`systemFont...`、`sharedApplication`)返回 autoreleased → `Borrowed`。
3. `withPool` 包裹临时对象:

```nim
proc withPool(body: proc()) =
  let pool = objc_autoreleasePoolPush()
  try: body()
  finally: objc_autoreleasePoolPop(pool)
```

- 每个进入 ObjC 的回调都应 push/pop pool;pool 属于线程。
- Nim 的 ARC/ORC 只管理 Nim 堆,不会 retain/release ObjC 对象。**不要**给 ObjC 指针加 Nim 析构器来 release;统一在窗口/应用清理路径释放。
- 窗口 delegate、webview delegate、block、KVO observer、display link、NSTrackingArea 必须在关闭时显式解除,顺序见 §7。
- `NSString`/`NSData` 的临时指针在调用期间必须稳定;Nim `string` 的 `cstring` 在调用期间不移动,但不要保存。

---

## 3. 应用生命周期

### 3.1 启动

```text
main
 └─ app.run()
     ├─ backend.init(handler, options)
     │   ├─ NSApplication sharedApplication
     │   ├─ setActivationPolicy
     │   ├─ registerClasses()
     │   ├─ setDelegate(MyGoAppDelegate)
     │   ├─ CFRunLoopSourceCreate + add to common modes
     │   ├─ KVO/Notification: appearance, screens, locale, power
     │   └─ 注册 URL scheme / 通知 delegate / 登录项
     ├─ backend.signal()
     ├─ backend.run()          # [NSApp run]
     │   └─ applicationDidFinishLaunching
     │       ├─ activateIgnoringOtherApps (regular)
     │       ├─ handler.ready()
     │       └─ 投递启动 URL/文件
     └─ finish()
```

### 3.2 Delegate 方法

| ObjC 方法 | 行为 |
|---|---|
| `applicationWillFinishLaunching:` | 安装 Quit Apple Event 处理器;记录是否登录启动 |
| `applicationDidFinishLaunching:` | 激活、`ready()` |
| `applicationShouldTerminate:` | 调用 `quitRequested()`;允许则 `quit()`,始终返回 `NSTerminateCancel` |
| `applicationWillTerminate:` | `terminating()` |
| `applicationShouldHandleReopen:hasVisibleWindows:` | `activated(hasVisibleWindows)` |
| `applicationDidBecomeActive:` / `DidResignActive:` | 通知 core |
| `application:openURLs:` / `openFiles:` | 投递 URL/文件 |
| `applicationSupportsSecureRestorableState:` | true |
| `applicationShouldTerminateAfterLastWindowClosed:` | false(core 决定) |

- `Cmd+Q`、Dock 退出、AppleScript、注销都走 `applicationShouldTerminate:`,返回 `NSTerminateCancel` 让 `run` 正常返回,由 core 执行退出序列。
- Quit Apple Event 由 `NSAppleEventManager` 安装处理器;取消时回 `-128`。
- 实现 `applicationShouldTerminate:` 时不要调用 `[NSApp terminate:]` 递归。

### 3.3 事件循环与主线程泵

| 原语 | 实现 |
|---|---|
| `run` | `[NSApp run]` |
| `quit` | `[NSApp stop:]` + 投递一个事件;模态时 `abortModal` |
| `signal` | `CFRunLoopSourceSignal` + `CFRunLoopWakeUp` |
| `step` | `nextEventMatchingMask:untilDate:inMode:dequeue:`(0.5s)+ `sendEvent:` |
| `wake` | 投递 `NSEventTypeApplicationDefined` 事件 |
| `isMainThread` | `pthread_main_np()` |

- `CFRunLoopSource` 必须加入 `kCFRunLoopCommonModes`,否则菜单跟踪、窗口缩放、模态面板期间主线程队列不排空。
- `step` 是主线程 `await` 的泵;它不能简单 sleep,必须处理原生事件。
- `dispatch` 回调进入 autorelease pool;先排空后端队列,再排空 core 队列。
- 嵌套 run loop 是正常的;队列必须可重入,排空时若还有任务再次 signal。

### 3.4 退出序列

```text
quit()
 ├─ quitRequested() → onBeforeQuit 可取消
 ├─ 关闭所有窗口(onClose 可取消)
 ├─ willQuit() → onWillQuit 可取消
 ├─ clipboard.flush()
 ├─ backend.quit() → [NSApp stop:]
 └─ finish()
     ├─ 停止 watch、保存窗口状态
     ├─ onQuit
     ├─ 可选 relaunch
     └─ 关闭主循环队列
```

- 3 秒 `stopGrace`(与 MyGo 一致)后强制退出。
- `exit(code)` 直接 `exit`,不触发事件。

### 3.5 其他应用级能力

| 能力 | API |
|---|---|
| 激活策略 | `setActivationPolicy:` 0/1/2 |
| 隐藏/显示 | `hide:`/`unhide:`/`activateIgnoringOtherApps:` |
| Dock 徽标 | `[NSApp dockTile] setBadgeLabel:` |
| Dock 弹跳 | `requestUserAttention:` / `cancelUserAttentionRequest:` |
| Dock 菜单 | `applicationDockMenu:` |
| Dock 图标 | `setApplicationIconImage:` |
| 关于面板 | `orderFrontStandardAboutPanel:` |
| 最近文档 | `NSDocumentController` 或 `noteNewRecentDocumentURL:` |
| URL scheme | `Info.plist` + `LSSetDefaultHandlerForURLScheme`(私有/已废弃,优先用 `NSWorkspace`) |
| 登录项 | `SMAppService`(13+),旧版 LaunchAgent |
| 单实例 | Unix domain socket + JSON(见 core) |
| 通知点击 | `UNUserNotificationCenterDelegate` |
| 媒体键 | `MPRemoteCommandCenter` / `MPNowPlayingInfoCenter` |

---

## 4. 窗口

### 4.1 类层次

| 类 | 基类 | 用途 |
|---|---|---|
| `NimiWindow` | `NSWindow` | 普通窗口;允许 key/main;`orderWindow` 处理显示时机 |
| `NimiPanel` | `NSPanel` | 浮动面板;`canBecomeKey` true,`canBecomeMain` false |
| `NimiFlyout` | `NSPanel` | 父窗口拥有的浮层;仅 focusable 时成为 key |
| `NimiWebView` | `WKWebView` | 记录 mouseDown、拖拽、右键、滚轮、无障碍父节点 |
| `NimiSurfaceView` | `NSView` | 原生 UI 绘制面 + 输入 + IME |
| `NimiWindowDelegate` | `NSObject` | 窗口/导航/UI/脚本消息/下载 delegate |

### 4.2 创建与样式

- `initWithContentRect:styleMask:backing:defer:`;`setReleasedWhenClosed:NO`。
- style mask:`Titled | Closable | Miniaturizable | Resizable`;隐藏标题栏加 `FullSizeContentView`;Panel 创建时带 `NonactivatingPanel`。
- `titlebarAppearsTransparent`、`titleVisibility = Hidden`、traffic lights 隐藏/偏移、`hiddenInset` 用空 `NSToolbar`。
- `collectionBehavior`:全屏、All Spaces、transient flyout。
- 初始 frame:`setFrame:display:` / `center`。
- 圆角:`contentView.layer.cornerRadius` + `masksToBounds`;窗口透明 + `NSWindow` 阴影。
- Vibrancy:`NSVisualEffectView`(macOS 26 用 `NSGlassEffectView`),`blendingMode = BehindWindow`;玻璃用 `setStyle:`。
- 外观:`_setForceMainAppearance:`(私有,需探测),`NSAppearance`。
- 全屏:`toggleFullScreen:`;最大化:`zoom:`;`isZoomed && !fullscreen`。
- 可见性:`makeKeyAndOrderFront:`、`orderOut:`、`orderBack:`。
- 遮挡:`windowDidChangeOcclusionState:` → Surface 停止动画。

### 4.3 坐标

- AppKit 全局原点在主屏左下,MyGo 在左上。转换:

```nim
proc primaryScreenHeight(): float64 =
  NSScreen.screens[0].frame.height  # 需处理 screens 为空

proc rectToMac(r: Rect): NSRect =
  NSRect(x: r.x, y: primaryScreenHeight() - r.y - r.h, w: r.w, h: r.h)

proc rectFromMac(r: NSRect): Rect =
  Rect(x: r.x, y: primaryScreenHeight() - r.y - r.h, w: r.w, h: r.h)
```

- Surface view 用 `isFlipped = true`,内部坐标与 MyGo 一致;鼠标/IME 矩形需要 view → window → screen 转换。
- 多屏/混合 Retina:`viewDidChangeBackingProperties` 重建 drawable/atlas scale。

### 4.4 窗口事件

| AppKit 回调 | 事件 |
|---|---|
| `windowShouldClose:` | `shouldClose()`;false 取消 |
| `windowWillClose:` | 清理 + `closed()` |
| `windowDidBecomeKey:` / `ResignKey:` | focused/blurred |
| `windowDidResize:` | resized(注意 live resize) |
| `windowWillMove:` / `windowDidMove:` | moved |
| `windowDidMiniaturize:` / `DidDeminiaturize:` | minimized/restored |
| `windowDidEnterFullScreen:` / `DidExitFullScreen:` | fullscreen events |
| `windowDidChangeOcclusionState:` | surface shown/hidden |
| `windowDidChangeBackingProperties:` | scale changed |

- 关闭时先 `cleanup()`:停 display link、移除 observer、removeScriptMessageHandler、释放 webview/renderer;`autorelease` window/delegate,因为 AppKit 仍在关闭过程中使用。
- `windowWillClose:` 里不要立即 release window/delegate;用 `autorelease`。

### 4.5 状态持久化

- `stateKey` → 用户数据目录下的 JSON;字段:frame、screen、maximized、fullscreen、scale、Windows 像素坐标(跨平台)。
- 恢复时校验屏幕仍在;否则居中。
- 窗口状态存储可注入自定义 store。

---

## 5. WebView

### 5.1 创建

```text
WKWebViewConfiguration
 ├─ WKPreferences
 │   ├─ developerExtrasEnabled
 │   ├─ allowFileAccessFromFileURLs
 │   ├─ elementFullscreenEnabled
 │   ├─ tabFocusesLinks
 │   ├─ inactiveSchedulingPolicy / 私有节流开关
 │   ├─ allowsPictureInPictureMediaPlayback
 │   └─ mediaTypesRequiringUserActionForPlayback
 ├─ WKUserContentController
 │   ├─ addScriptMessageHandler:name:"nimi"
 │   ├─ addUserScript(preload)
 │   └─ addUserScript(titlebar)
 ├─ WKWebsiteDataStore(会话)
 └─ setURLSchemeHandler:forURLScheme:(自定义协议)
```

- `window.open()` 的 configuration 由 WebKit 提供,必须复用,不要新建;否则 opener 关系/设置丢失。
- 透明背景:私有 KVC `drawsBackground`;`setUnderPageBackgroundColor:`。
- 背景节流:公开 `inactiveSchedulingPolicy` + 私有开关,全部 `respondsToSelector:` 探测。
- DevTools:`setInspectable:`;`developerExtrasEnabled`。
- 导航手势、缩放、UA、zoom。

### 5.2 JS → Nim

- 页面:`window.webkit.messageHandlers.nimi.postMessage(secret + json)`。
- ObjC:`userContentController:didReceiveScriptMessage:`;只接受主 frame、body 为 NSString;转 UTF-8 后调用 `WindowHandler.message`。
- 消息前缀校验 secret;untrusted 页面超 4 KiB 直接丢弃。
- 兼容别名:`window.mygo` 指向同一运行时,至少保留到 1.0。

### 5.3 导航与页面事件

| 回调 | 事件 |
|---|---|
| `decidePolicyForNavigationAction:` | willNavigate;下载属性 |
| `decidePolicyForNavigationResponse:` | MIME 不可显示/attachment → 下载 |
| `didStartProvisionalNavigation:` | navigationStarted |
| `didCommitNavigation:` | navigationCommitted |
| `didFinishNavigation:` | loadFinished |
| `didFailNavigation:` / `didFailProvisionalNavigation:` | loadFailed |
| `webContentProcessDidTerminate:` | renderProcessGone |
| KVO `title` | titleChanged |
| `createWebViewWithConfiguration:...` | newWindow |

- 导航时 core 重置 page context/token,取消旧页面的 channel/调用。
- 自定义协议通过 `WKURLSchemeHandler`;`startURLSchemeTask:` 构造请求,回调 `SchemeRequest`;响应可分块;`stopURLSchemeTask:` 取消。
- 下载:`WKDownloadDelegate` 决定目标路径;自定义 scheme 的下载走 `SchemeDownload`。

### 5.4 会话/Cookie/内容规则

| 能力 | API |
|---|---|
| 持久会话 | `WKWebsiteDataStore dataStoreForIdentifier:`(14+);旧版 `defaultDataStore` |
| 临时会话 | `nonPersistentDataStore` |
| Cookie 读写 | `httpCookieStore` 的 `getAllCookies:`/`setCookie:`/`deleteCookie:` |
| 清数据 | `removeDataOfTypes:modifiedSince:completionHandler:` |
| 内容规则 | `WKContentRuleListStore` 的 compile/lookUp/remove |
| 认证 | `didReceiveAuthenticationChallenge:` + `NSURLCredential` |
| 证书错误 | `NSURLAuthenticationChallenge` server trust |
| 音频/静音 | 私有 `_isPlayingAudio`、`_setPageMuted:` |
| 捕获状态 | `cameraCaptureState`/`microphoneCaptureState`/私有 display |
| PiP | 私有 `_setAllowsPictureInPictureMediaPlayback:` 等 |
| 会话状态 | `interactionState`(12+)/私有 `_sessionStateData` |
| 进程 ID | 私有 `_webProcessIdentifier` |

- 私有 selector 集中在 `darwin/compat.nim`,全部 `respondsToSelector:`;失败时降级,不崩溃。
- Cookie 的 URL 匹配/排序/默认域在 core 做;后端只做 `NSHTTPCookie` 转换。

### 5.5 原生 UI 中的 WebView

- `NimiClipView` 作为宿主 contentView 的子视图,位于 Surface 之下。
- `PlaceWebViews` 按内容绘制顺序设置 frame/圆角/显隐/栈序;隐藏时把键盘交还 Surface。
- `hitTest:` 在 hole 区域返回 nil,让指针穿透到 Surface。
- WebView 的滚轮在滚动容器内转给宿主 Surface。
- 键盘未处理时转成 `WebViewKey` 事件;Escape 转 `SurfaceCommand`。

### 5.6 M1 WebView 最小集

- `NSApplication` + `NSWindow` + `WKWebView`
- `WKUserContentController` + script message handler
- `loadURL`/`loadHTMLString`/`loadFileURL`
- `evaluateJavaScript:completionHandler:`(block 或 nil)
- `WKNavigationDelegate` 的 start/commit/finish/fail
- 自定义 scheme handler(可选,M1 后半)
- 菜单 + 对话框 + 剪贴板(M2)

---

## 6. 菜单、托盘、对话框、系统集成

### 6.1 菜单

- `NSMenu`/`NSMenuItem`;`setAutoenablesItems:`;role → AppKit selector。
- 编辑/窗口 role 用 first responder(nil target):`undo:`、`cut:`、`copy:`、`paste:`、`selectAll:`、`performClose:`、`performMiniaturize:`、`performZoom:`、`toggleFullScreen:`、`terminate:`。
- 自定义项 target 为 `NimiMenuTarget`,通过 tag/ID 回 core。
- `validateMenuItem:` 保留 core 给的 enabled/checked 状态;禁用 role 项时指向没有该 action 的对象。
- 上下文菜单:`popUpMenuPositioningItem:atLocation:inView:`;阻塞到关闭。
- accelerator → keyEquivalent + modifier mask;特殊键用 AppKit 私有 function-key 区字符。
- 默认菜单:macOS 安装 App/File/Edit/View/Window;其他平台默认无。
- 菜单项更新:按 ID 找所有原生 item;不要依赖弱引用。

### 6.2 托盘

- `NSStatusBar systemStatusBar` + `NSStatusItem`。
- 图标 template image;按 18pt 高度缩放;`setImage:`。
- 菜单/弹出菜单;点击回调;KVO `effectiveAppearance` 判断深浅色。
- `autosaveName` 保持位置。

### 6.3 对话框

- `NSOpenPanel`/`NSSavePanel`:父窗口可见时 sheet,否则 `runModal`。
- 过滤器:`UTType typeWithFilenameExtension:` + `setAllowedContentTypes:`(12+);旧版 `setAllowedFileTypes:`。
- `NSAlert`:按钮、默认/取消/破坏性、checkbox;sheet 或 modal。
- JS 对话框(alert/confirm/prompt/file input)由 `WKUIDelegate` 回调,调用 completion block;晚调用要 copy。
- 记住 `quitAfterModal`:退出请求在 modal 中到达时,先 abort modal 再停。

### 6.4 通知

- 仅带 bundle identifier 的 `.app` 可用;`UNUserNotificationCenter`。
- 启动时立即设 delegate,避免错过"点击通知启动应用"。
- 前台也显示 banner/sound/list。
- 授权请求是异步 block;授权未回答时排队。
- 图片附件 `UNNotificationAttachment`;通信通知 `INSendMessageIntent` 需 entitlement + provisioning profile。
- 移除单个/全部;点击回 `notificationClicked(id)`。

### 6.5 剪贴板

- `NSPasteboard generalPasteboard`。
- 文本/HTML/PNG/TIFF;TIFF → PNG 用 `NSBitmapImageRep`。
- 自定义格式:`NSPasteboardItemDataProvider` 延迟提供;`clearContents` + `setDataProvider:forTypes:`。
- 文件 URL、UTI 映射;`Flush`/`Close`。
- 只读/写都在主线程;大图/大量格式可能慢,考虑后台准备数据。

### 6.6 全局快捷键

- Carbon `RegisterEventHotKey`(无需辅助功能权限)。
- accelerator key → macOS 虚拟键码(ANSI);修饰键 Carbon mask。
- 首次注册 `InstallEventHandler`;`GetEventParameter` 取 `EventHotKeyID`;回 `hotkeyPressed(id)`。
- 注销 `UnregisterEventHotKey`。

### 6.7 其他

| 能力 | 实现 |
|---|---|
| 打开 URL/路径 | `NSWorkspace openURL:` / `openFile:` |
| Finder 定位 | `activateFileViewerSelectingURLs:` |
| 废纸篓 | `NSWorkspace recycleURLs:` |
| 文件图标 | `NSWorkspace iconForFile:` |
| 屏幕 | `NSScreen`;`visibleFrame`;`backingScaleFactor`;光标位置 `NSEvent mouseLocation` |
| 主题 | `NSApp.effectiveAppearance`;`NSColor controlAccentColor`;无障碍显示选项 |
| 电源 | `NSWorkspace` 睡眠/唤醒通知;`NSProcessInfo beginActivityWithOptions:`;IOKit |
| 网络 | `nw_path_monitor` |
| Now Playing | `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` |
| Keychain | Security.framework |
| 已安装应用 | LaunchServices |
| 文件监视 | FSEvents,每目录一个 stream,后台队列 |
| 替换文件 | `replaceItemAtURL:` 保留元数据 |
| 最近文档 | `noteNewRecentDocumentURL:` |
| 登录项 | `SMAppService`(13+) |

---

## 7. 原生 UI Surface

### 7.1 视图

- `NimiSurfaceView : NSView`,`wantsLayer = YES`,`isFlipped = YES`,`layerContentsRedrawPolicy = OnSetNeedsDisplay`。
- layer `contentsGravity = resize`;Metal 时添加 `CAMetalLayer` 子层。
- `NSTrackingArea`(entered/exited/moved/cursor update/active app/visible rect)。
- 注册拖放类型 `public.file-url`。
- `acceptsFirstResponder`、`acceptsFirstMouse:`、`mouseDownCanMoveWindow`。
- `wantsUpdateLayer`/`updateLayer` 由 AppKit 驱动;不要在这里同步跑用户代码(见 §7.4)。

### 7.2 帧节奏

| 系统 | 方案 |
|---|---|
| macOS 14+ | `[view displayLinkWithTarget:selector:]` → `CADisplayLink`;`setPaused:YES`;加入 main run loop common modes;`setPreferredFrameRateRange:` |
| macOS 12–13 | `NSTimer` 按刷新率;或 `CVDisplayLink` + 主线程投递 |
| 刷新率 | `NSScreen maximumFramesPerSecond`(可能为 0) |

- 请求帧合并:正在跑则标 `due`;暂停超过两帧则 `drawSoon`;否则启动 link。
- `drawSoon`:把绘制投递到后端队列,避免在 AppKit display/CA commit observer 内执行可能打开模态的用户代码。
- 空闲:停止 link;窗口被遮挡时停帧;2 秒后释放内存帧。

### 7.3 呈现

| 路径 | 实现 |
|---|---|
| CPU(CG) | `CGBitmapContext` → `CGImage` → `layer.contents`;`contentsScale` 设置为屏幕 scale |
| CPU(自研 raster) | `PresentPixels`/`PresentDamage`(后续) |
| GPU(Metal) | `CAMetalLayer` + 预编译 metallib;presenter 线程 `nextDrawable` |

- CPU 位图用预乘 BGRA(与 MyGo 一致);`CGImageCreate` 的 bitmapInfo 为 little-endian premultiplied first。
- 首次呈现后 `ready()`;隐藏窗口在显示前可先画首帧(`FirstFrameSurface`)。
- 宽色域:探测 `NSScreen canRepresentDisplayGamut:NSDisplayGamutP3`;Metal 用 RGBA16Float + extended sRGB。

### 7.4 输入

| 事件 | AppKit |
|---|---|
| 鼠标移动/进入/离开 | `mouseMoved:`、`mouseEntered:`、`mouseExited:` |
| 左键 | `mouseDown:`/`mouseUp:`/`mouseDragged:` |
| 右键 | `rightMouseDown:`/...;Control-click 视为右键 |
| 中键/侧键 | `otherMouseDown:`/...;button 3/4 → Back/Forward |
| 滚轮 | `scrollWheel:`;`scrollingDeltaX/Y`、`hasPreciseScrollingDeltas`、`momentumPhase` |
| 缩放 | `magnifyWithEvent:` → PointerZoom |
| 滑动 | `swipeWithEvent:` → Back/Forward |
| 键盘 | `keyDown:`/`keyUp:`/`flagsChanged:`;虚拟键码 + 物理键 |
| 编辑命令 | `copy:`/`cut:`/`paste:`/`selectAll:`/`undo:`/`redo:`/`delete:`/`pasteAsPlainText:` |

- 坐标转成 DIP(除以 scale),内容坐标减去 view 偏移。
- 物理键用 `CGEventGetIntegerValueField` + `KBGetLayoutType`/`LMGetKbdType` 处理 ISO 键盘。
- 键盘事件先给输入法,再给 UI;有 marked text 时 `keyDown:` 不发普通 KeyPressed。
- 触摸板惯性滚动带 momentum phase;鼠标滚轮按 40 DIP/行。
- 光标:映射 `NSCursor`;对角线 resize 用 macOS 15 新 API,旧版私有;隐藏光标用透明图像而不是 `NSCursor hide`。

### 7.5 输入法(NSTextInputClient)

`NimiSurfaceView` 实现以下方法:

| 方法 | 行为 |
|---|---|
| `hasMarkedText` | 有 composition |
| `markedRange` | composition 的 UTF-16 范围 |
| `selectedRange` | 选区 |
| `setMarkedText:selectedRange:replacementRange:` | 发 TextComposition;支持 Replace/From/To |
| `unmarkText` | 取消 composition |
| `validAttributesForMarkedText` | 空数组 |
| `attributedSubstringForProposedRange:actualRange:` | 从文档取子串 |
| `insertText:replacementRange:` | 发 TextInput |
| `characterIndexForPoint:` | 用 TextInputClient.IndexForPoint |
| `firstRectForCharacterRange:actualRange:` | 用 BoundsForRange 或 caret;转 screen |
| `doCommandBySelector:` | 不处理 |

- 所有范围是 UTF-16;Nim 内部用 UTF-8/rune,需要显式转换并处理代理对。
- `interpretKeyEvents:` 只在输入法激活时调用;composition 期间不重复发普通按键。
- 内容拒绝 composition 时,若在 `interpretKeyEvents:` 内则标记 refused,之后 `discardMarkedText`;否则立即放弃。
- `SetTextInput` 光标移动时 `inputContext invalidateCharacterCoordinates`,让候选窗跟随。
- 测试:中文拼音、日文、韩文、死键(Option-E)、emoji;用真实输入法做 E2E。

### 7.6 可访问性

- 每个节点一个 `NimiAccessibilityElement : NSAccessibilityElement`,按 ID 复用。
- 设置 role/subrole/title/label/enabled/expanded/orientation/min/max/value/selected/placeholder/help/rows/index/rowCount。
- 列表用 table/rows 语义;文本用 text 属性。
- `NSAccessibilityPostNotification` 发变化;`AXScrollToVisible`。
- 弹窗只暴露 modal 层。
- 第一版只做 role/label/value/bounds/action;表格/树/公告后置。

### 7.7 拖放

- 入口:`draggingEntered:`/`draggingUpdated:`/`draggingExited:`/`prepareForDragOperation:`/`performDragOperation:`。
- 出口:`NSDraggingSource` + `NSDraggingItem` + `beginDraggingSessionWithItems:event:source:`。
- 取消拖拽:合成 Escape 事件。
- 数据用 `NSPasteboardItemDataProvider` 延迟提供;格式映射到 `transfer.Format`。

### 7.8 清理顺序

窗口关闭/应用退出:

1. 停 display link / timer。
2. 停止 webview 加载,`removeScriptMessageHandlerForName:`,清空 user scripts。
3. 移除 KVO observer、通知观察者、本地事件监视器。
4. 释放 renderer/drawable/纹理/atlas。
5. 释放 delegate/block(注意 AppKit 仍可能持有,用 autorelease)。
6. `autorelease` window;从注册表移除。

---

## 8. 渲染

### 8.1 阶段 1:CoreGraphics CPU

- `CGBitmapContextCreate`(预乘 BGRA,8bpc)。
- 画背景/圆角矩形/边框/渐变/图片/文本/裁剪。
- 文本用 `CTLineDraw`/`CTFontDrawGlyphs`,或先走 `text` 模块的 glyph atlas。
- 每帧整窗重画;后续加 damage 矩形。
- `CGImage` 设置到 layer;`contentsScale` 与屏幕一致。
- 优点:最快跑通、文本质量原生;缺点:大窗口 CPU 高,但 MVP 足够。

### 8.2 阶段 2:Metal

参考 MyGo 的架构,但可先简化:

| 组件 | 设计 |
|---|---|
| 设备/队列 | `MTLCreateSystemDefaultDevice` + `newCommandQueue` |
| Layer | `CAMetalLayer`;BGRA8Unorm;`maximumDrawableCount=3`;`framebufferOnly=NO`(effect 需要) |
| Shader | MSL 源文件;`xcrun metal` 预编译 `.metallib`;嵌入字节;SHA 校验;失败回退源码 |
| 管线 | 顶点 `vs` + 片元 `ps`;按 class 特化;后台 worker 预建;首帧用 general |
| 实例 | 每个 op 一个 quad;14×float4(224 字节)与 MyGo shader 布局一致,或自定义更小格式 |
| 批次 | 按 scissor/texture/class 分批;不透明填充走无混合 |
| 呈现 | presenter 线程 `nextDrawable`;主线程绘制/提交;resize/含 WebView 时 `presentsWithTransaction` |
| Damage | 先整帧;后续按 drawable 记录变化区域 |
| 宽色域 | RGBA16Float + extended sRGB;探测设备支持 |
| 空闲 | 2 秒后 trim drawable 到 1×1,释放纹理 |

**关键性能规则**:

- `nextDrawable` 不在主线程阻塞;用独立 presenter 线程(QoS user-interactive)。
- 管线创建不在首帧同步;用 general 兜底。
- 每帧只提交一次 command buffer;实例 buffer 用 ring(2–3 槽)。
- 纹理上传按 atlas generation/version 增量。
- 窗口不可见时停帧;空闲时停 link。

### 8.3 场景 IR

- `Op` 变体:fill、shadow、glyphs、image、pushClip/popClip、effect、hole。
- 字段:rect、transform、radii、continuous、paint、color、gradient、border、dashed、blur、cast、image/src、opacity。
- `Glyph`:atlas UV、屏幕 rect、color、wide、colored、subpixel、thin、transform。
- `Scene`:width/height/scale/zoom/clear/background、ops、glyphs、stops、effects、atlases。
- `Atlas`:mask/color;1/4 BPP;shelf 分配;generation/version;transient。
- `Differ`:逐 op 比较产生 damage;后续。

### 8.4 文本渲染

- shaping/line break 用 CoreText;`CTLine` 的 glyph/position。
- 栅格化:
  - 普通字体:8-bit alpha-only `CGBitmapContext`;`CTFontDrawGlyphs`;y 翻转。
  - 彩色字体/emoji:BGRA 预乘 context。
  - `CGContextSetShouldSmoothFonts` 按用户 `AppleFontSmoothing`。
  - 亚像素位置量化与 AppKit 对齐。
- atlas:mask 1B/px、color 4B/px;按 font/size/scale/subpixel/shade 缓存;满时 repack/grow。
- 装饰线:下划线/删除线位置取 `CTFontGetUnderlinePosition/Thickness`。
- 文本缓存:按 `Params` LRU;每元素保留最近两个宽度。

---

## 9. 音频

- AudioToolbox Audio Queue:`AudioQueueNewOutput`、`AudioQueueAllocateBuffer`、`AudioQueueEnqueueBuffer`、`AudioQueueStart/Stop/Dispose`。
- 格式:linear PCM float32,48 kHz,立体声。
- 缓冲:512 帧;交互低延迟约 40 ms,播放约 250 ms。
- 回调:全局 `aqCallback` + 原子当前设备指针;queue 线程把空 buffer 放回队列。
- 起播前填满所有 buffer,避免 underrun。
- 默认输出设备变化由 AudioQueue 跟随(与 MyGo 一致)。

---

## 10. 打包、签名、公证

### 10.1 `.app` 结构

```text
MyApp.app/
├── Contents/
│   ├── MacOS/MyApp
│   ├── Resources/
│   │   ├── AppIcon.icns
│   │   ├── Assets.car            # 可选
│   │   └── *.lproj/              # 本地化
│   ├── Frameworks/               # 可选
│   ├── Info.plist
│   ├── PkgInfo
│   └── _CodeSignature/
```

- `Info.plist` 关键字段:`CFBundleIdentifier`、`CFBundleName`、`CFBundleDisplayName`、`CFBundleExecutable`、`CFBundleVersion`、`CFBundleShortVersionString`、`CFBundlePackageType=APPL`、`LSMinimumSystemVersion`、`NSPrincipalClass=NSApplication`、`NSHighResolutionCapable=true`、`LSApplicationCategoryType`、URL schemes、file associations、`LSUIElement`(accessory)。
- 版本注入:编译期 `-d:nimiVersion=...` 或生成 `config.nim`;不要用 `-ldflags -X`(Nim 没有等价物)。
- 资源:CLI 生成 `nimi_assets.nim`(`staticRead`)或运行时读 `Resources/`;生产推荐内嵌,开发读磁盘。
- 图标:`iconutil` 从 `.iconset` 生成 `.icns`;或直接写入 `.icns`。
- Universal:`nim c --cpu:arm64` + `nim c --cpu:amd64` + `lipo -create`。

### 10.2 签名/公证/DMG

```sh
codesign --force --deep --options runtime \
  --entitlements MyApp.entitlements \
  --sign "Developer ID Application: ..." MyApp.app

xcrun notarytool submit MyApp.zip \
  --keychain-profile "nimi-notary" --wait

xcrun stapler staple MyApp.app
hdiutil create -volname "MyApp" -srcfolder MyApp.app -ov -format UDZO MyApp.dmg
```

- ad-hoc 签名(`-`)可用于本地开发;分发必须 Developer ID。
- 公证需要 `--options runtime`(hardened runtime)和必要 entitlements。
- `notarytool` 需要 App Store Connect API key 或 keychain profile。
- DMG 可自定义背景/布局(复用 MyGo 的 `dmg.go` 思路)。

### 10.3 更新(后续)

- 清单 JSON + Ed25519 签名;tar.gz/delta。
- 安装目标 `.app`;退出后替换、重启。
- Sparkle 风格的更新窗口可用原生 UI 实现。

---

## 11. 最小可运行切片

### 11.1 M1:WebView + IPC + 菜单

**目标**:`examples/hello` 运行;页面 `window.nimi.call("Greeter.Greet", "world")` 返回 Nim 字符串;`nimi generate` 输出 TS。

必需 API:

1. `NSApplication` + delegate + `run` + `stop`
2. `NSWindow` + contentView + title + show/close
3. `WKWebView` + configuration + `loadHTMLString`/`loadURL`
4. `WKUserContentController` + script message handler
5. `WKNavigationDelegate` start/commit/finish/fail
6. `evaluateJavaScript:completionHandler:`(block 或 nil)
7. `NSMenu` + `NSMenuItem`(基础应用菜单)
8. `NSOpenPanel`/`NSAlert`/`NSPasteboard`(M1 后半)
9. 主线程队列 + `CFRunLoopSource`
10. `CFRunLoopSource` 在 common modes

**验收**:

- 窗口显示本地 HTML。
- JS 调用 Nim 方法,Promise resolve。
- Nim 发事件到页面,页面收到。
- 菜单 Cmd+Q 走 core 退出序列。
- 生成 `src/nimi.ts` 并可被前端导入。
- 关闭窗口后进程干净退出(无 crash/僵尸线程)。

**代码量估计**:2.5–4k 行 Nim(不含 IPC/TS 生成);含则 5–8k。

### 11.2 M2:原生 UI counter

**目标**:`examples/counter-native` 运行;点击按钮/按键改变数字;headless 测试通过。

必需 API:

1. `NimiSurfaceView` + layer
2. CPU 呈现(CG 或先纯色)
3. `NSTextInputClient` 最小(可先不做 IME)
4. 鼠标/键盘事件
5. `CADisplayLink`/NSTimer
6. `ui` 基础:Context/Element/arena、Column/Row/Text/Button、flex、paint、scene
7. CoreText shaping + glyph 光栅化
8. `Tester` + golden PNG

**验收**:

- 窗口显示 Column/Text/Button。
- 点击 +/-,文本更新。
- 键盘 ↑/↓ 生效。
- 无窗口 `Tester` 点击后文本变为 "1"。
- golden PNG 与预期一致(允许平台字体差异)。
- 窗口空闲时 CPU ≈ 0%,不请求帧。

**代码量估计**:8–12k 行(含 text/scene/raster 基础)。

### 11.3 M1/M2 的风险点

| 风险 | 验证方式 |
|---|---|
| ObjC ABI/结构体返回 | 每个签名写单元测试;arm64 真机 |
| block 生命周期 | 异步 completion + 窗口关闭压力测试 |
| 主线程嵌套 run loop | 在菜单跟踪/模态对话框/Eval 中调用 `onMain`/`await` |
| autorelease pool/线程 | 后台回调全部 marshal;Zombies |
| CoreText UTF-16/IME | 中文/日文/死键测试 |
| Metal 首帧卡顿 | 预编译 metallib + 后台管线 |
| 窗口关闭清理 | 反复开关 100 次;Instruments 无泄漏 |

---

## 12. 与 MyGo 的差异

| 主题 | MyGo | Nimi macOS |
|---|---|---|
| ObjC 调用 | purego + 汇编 trampoline | 直接强类型 `objc_msgSend` 函数指针 |
| block | purego `objc.NewBlock` | 手工 global block / malloc context |
| 文本 | 纯 Go 文本引擎 + CoreText 仅 shaping/栅格 | 直接用 CoreText 做 shaping/断行/栅格 |
| 渲染 | Metal 全量 + CPU raster | 先 CG CPU,后 Metal |
| 窗口状态 | Go 结构 + JSON | 同 |
| 私有 API | 大量使用 + `respondsToSelector` | 同,但集中到 `compat.nim` |
| 无 cgo | 核心约束 | 不适用;但保持纯 Nim,不引入 `.m` shim |
| 交叉编译 | 任意机器 | macOS 上编 macOS;Windows/Linux 另议 |

> 如果后期遇到无法用强类型 `objc_msgSend` 表达的 ABI(例如复杂的 struct-by-value 方法),再引入一个极小的 `.m` shim 作为逃生舱;不作为默认路径。

---

## 13. 测试清单

| 层 | 测试 |
|---|---|
| ObjC FFI | selector/class 缓存、每种签名、BOOL/NSInteger/NSRect/NSRange、super 调用 |
| 应用 | 启动/退出/重开/URL 打开/单实例/登录项 |
| 窗口 | 创建/样式/移动/缩放/全屏/遮挡/多屏/DPI/状态恢复 |
| WebView | 加载/导航/JS 调用/事件/自定义协议/Cookie/下载/DevTools |
| 菜单 | role/快捷键/启用状态/上下文菜单/动态更新 |
| 对话框 | 打开/保存/消息/JS 对话框/取消/父窗口 sheet |
| 剪贴板 | 文本/HTML/图片/文件/自定义格式/大对象 |
| 通知 | 授权/显示/点击/移除/图片/通信通知 |
| Surface | 输入/IME/拖放/无障碍/帧节奏/CPU/GPU 一致性 |
| 渲染 | golden PNG、damage、宽色域、resize、隐藏窗口 |
| 文本 | 多语言 shaping、断行、caret、selection、省略、装饰线 |
| 音频 | 播放/暂停/设备切换/低延迟 |

---

*本文档是 macOS 后端的实现蓝图;具体 API 清单会随 M1/M2 的实现更新。原型的编译/运行命令见 `spikes/README.md`。*
