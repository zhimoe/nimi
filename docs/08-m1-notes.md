# M1 实现状态与踩坑记录

> 日期:2026-11-04 · 对应路线图 M1(WebView + Core + IPC)

---

## 1. 已实现

### 1.1 macOS WebView 垂直切片

- `NSApplication` 生命周期:启动、`applicationDidFinishLaunching`、`Run`、`Quit`、退出后 `app.run` 返回。
- `NSWindow` + `WKWebView`,运行时注册 delegate,接受页面脚本消息。
- 注入 `bridge.js`(document start),页面端 `window.nimi.call` / `window.mygo` 别名。
- 双向 JSON 调用:页面 → Nim 方法 → JSON 结果 → 页面 Promise。
- IPC secret + 每页 token 校验;消息前缀不匹配/ token 错误直接丢弃。
- 类型化事件到页面:`event.emitPage(win, payload)` → `window.nimi.on(name, fn)`。
- 窗口关闭、最后窗口关闭、`app.quit` 的退出路径。
- 多次连续调用(50 次)与关窗退出压测通过。
- `nimi dev` 监听项目源文件,变更后自动重建并重启;`Ctrl+C` 清理子进程。

### 1.2 Core

| 文件 | 内容 |
|---|---|
| `src/nimi/core/ipc.nim` | `bindService(instance, procs...)` 宏、JSON 编解码、`dispatch`、TS 生成 |
| `src/nimi/core/loop.nim` | `postMain` / `onMain` / `drainMain` / `shutdownLoop` |
| `src/nimi/core/events.nim` | `Event[T]`、`on`/`emit` |
| `src/nimi/core/window.nim` | `WindowOptions`、窗口注册表、`Page`、消息路由、关闭事件 |
| `src/nimi/core/app.nim` | `App` 单例、`whenReady`/`onReady`/`onBeforeQuit`、`run`/`quit` |
| `src/nimi/core/bridge.nim` | M1 bridge JS |
| `src/nimi/platform/contract.nim` | `Backend`/`WindowHandler`/`AppHandler`/`NativeWindow` |

### 1.3 macOS 平台层

| 文件 | 内容 |
|---|---|
| `platform/darwin/objc.nim` | ObjC runtime、typed `objc_msgSend`、类注册、block 常量、libdispatch 唤醒 |
| `platform/darwin/app.nim` | `NSApplication`、app delegate、菜单(Quit)、`stop`/wake |
| `platform/darwin/window.nim` | `NSWindow`、`WKWebView`、delegate、`NativeWindow` 方法 |
| `platform/darwin/types.nim` | Darwin 全局状态与映射表 |

### 1.4 CLI

```sh
nim c -o:nimi src/nimi/cli.nim

./nimi init my-app
./nimi generate my-app
./nimi dev my-app
./nimi build my-app      # dist/darwin-arm64/My App.app
./nimi doctor
```

- `generate`:编译临时二进制 + `NIMI_GENERATE` 运行,写出 `frontend/nimi.ts` 和运行时 stub。
- `build`:release 编译、`.app` 结构、`Info.plist`、ad-hoc 签名。
- `dev`:编译并运行;监听项目内 `.nim`/`.nims` 与 `nimi.json`,变更后重建重启。
- `init`:web/native 两种最小模板。

### 1.5 测试

```sh
nim c -r --path:src tests/test_ipc.nim
nim c -r --path:src tests/test_loop.nim
```

当前全部通过。

---

## 2. 已验证的端到端行为

```text
$ NIMI_SMOKE=quit ./examples/hello (debug binary)
Greeter.greet called from the page: world
exit=0

$ NIMI_SMOKE=calls   # 50 次连续 JS→Nim 调用,最后一次 quit
Greeter.greet called from the page: x0 .. x49
exit=0

$ NIMI_SMOKE=close   # 页面请求关窗,走 windowShouldClose → closed → quit
Greeter.greet called from the page: world
exit=0
```

- 三次运行都没有新的 `nimi_hello` 崩溃报告。
- `examples/hello/frontend/nimi.ts` 由 CLI 生成,含 `Greeter.greet`、`AppControl.quit`、`AppControl.closeWindow`、`AppControl.emitPing`、`AppControl.report`。
- 页面事件验证:`window.nimi.on("ping")` 收到 Nim 发出的 `hello from a Nim event`,再通过 `AppControl.report` 回传给终端。

---

## 3. 崩溃根因与修复

### 3.1 `dispatch_get_main_queue` 在 macOS 上是内联符号

- 现象:`postMain`(以及任何从非主线程/队列唤醒主线程的路径)触发 `SIGSEGV`,崩溃栈在 `dispatch_async_f`。
- 根因:`dlsym("/usr/lib/libSystem.B.dylib", "dispatch_get_main_queue")` 返回 **nil**;该 API 在 macOS 上是 inline/macro,导出对象是 `_dispatch_main_q`。
- 修复:`dispatchMainQueue = symAddr(libsystem, "_dispatch_main_q")`;`newDarwinBackend` 在不可用时抛清晰错误。
- 验证:50 次连续调用 + quit/close 均退出 0,无新崩溃报告。

### 3.2 `AppHandler` 构造器里的多行 proc 字段

- 现象:更早的崩溃在 `applicationDidFinishLaunching` 调用 `ready` 时,`EXC_BAD_ACCESS` at 0x0。
- 根因:对象构造器里多行 `proc() = ...` 字段的逗号/缩进解析错误,导致 `ready` 字段为 nil 或未正确初始化。
- 修复:改为 `var handler = AppHandler()` 后逐字段赋值;启动路径加 nil 检查。
- 验证:当前 `ready` 每次都能正常执行,窗口创建/页面调用正常。

### 3.3 `.app` 直接 exec 与 `open`

- 现象:直接执行 `MyApp.app/Contents/MacOS/MyApp` 会立即退出 0;通过 `open MyApp.app` 或 Finder 启动则正常运行。
- 这是 macOS 的 LaunchServices/bundle 行为,不是应用崩溃;`nimi dev` 运行的是裸二进制,不受影响。
- 测试 `.app` 时用 `open`;`nimi build` 产物给用户双击/`open` 使用。

---

## 4. M1 已知限制(按计划在后续里程碑补齐)

| 限制 | 计划 |
|---|---|
| Channel 尚未暴露给页面 | M2 |
| 同步 `bindService` 仍在主线程；耗时方法需显式注册到后台工作池 | 已提供 `bindBackgroundService`，见 [异步 IPC](29-async-ipc.md) |
| 无 trusted/untrusted 细分(只有 secret/token) | M2 |
| 无 focus 跟踪,`focusedWindow()` 返回任意窗口 | M2 |
| 无 `Eval` 返回值、无页面导航事件 | M2 |
| 菜单只有 Quit;无 role/动态菜单 | M4 |
| 对话框/剪贴板/通知/托盘/快捷键未实现 | M4 |
| 无保存/恢复窗口状态 | M4 |
| `.app` 无图标/资源/本地化/公证/DMG | M7 |
| 只支持 macOS | M8/M9 |
| 原生 UI(`ui`/scene/CoreText)未实现 | M2 |

---

## 5. 下一步(M1 剩余)

1. 后台 IPC 的流式返回；超时/窗口关取消已实现，同步 `bindService` 保持 UI 线程契约。
2. Channel 页面侧消息 + TS 事件/Channel 描述符。
3. `Eval` 返回值、导航事件、页面标题。
4. trusted/untrusted 细分、消息大小限制。
5. 错误/panic 边界、日志、`NIMI_DEBUG`。
6. 更多 IPC 类型(object/seq/Option)的黄金测试。

---

*本文件记录实际实现与设计文档的差异;设计目标仍以 `docs/01-architecture.md` 为准。*
