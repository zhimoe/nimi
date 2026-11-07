# 异步 IPC 与工作池

> 2026-11-07 · 对应 `src/nimi/core/ipcpool.nim`、`src/nimi/core/ipc.nim`、
> `src/nimi/core/window.nim`。本文解释“IPC 在 UI 线程同步 dispatch”的含义、
> 为什么不能把所有服务直接搬到线程池，以及现在的使用方式和边界。

---

## 1. “同步 dispatch”是什么意思

页面调用：

```js
const name = await Greeter.greet("Ada");
```

这条路径在修复前是：

```text
WKWebView JS
  → postMessage
  → macOS 主线程 message handler
  → Window.handleMessage
  → dispatch("Greeter.greet", args)   ← 直接在 UI 线程执行
  → window.__nimi._resolve(...)
```

`dispatch` 会立即调用绑定的 Nim proc。如果这个方法里做了：

- 网络请求；
- 大文件读写；
- 图片解码/压缩；
- SQLite 查询；
- 大量 JSON 编解码或 CPU 计算；

那么 **UI 线程（AppKit 主线程）会在整个调用期间被占住**。窗口不能重绘、
不能处理点击/键盘、菜单和动画都会卡住。页面的 `Promise` 虽然是异步 API，
但它只能等待 Nim 侧返回，不能避免主线程被阻塞。

这就是“IPC 仍在 UI 线程同步 dispatch”。

---

## 2. 为什么不能把所有 `bindService` 自动搬到工作线程

`bindService` 生成的闭包通常会捕获：

- `ref object` 应用状态；
- 控件树、窗口、剪贴板、菜单等 UI 对象；
- `Content.Engine`、场景和渲染状态。

Nim 的 `gcsafe` 只表示“不会做 GC 不安全的操作”，**不表示数据竞争安全**。
把这些闭包直接放到线程池会有两类问题：

1. 多个线程同时改同一个 `ref`/`Table`/`seq`，产生数据竞争；
2. 工作线程直接调用 AppKit/WKWebView（例如 `eval`、`invalidate`、对话框）
   会崩溃或产生未定义行为。

因此当前设计是明确的两条路径：

| 路径 | 执行线程 | 适合做什么 |
|---|---|---|
| `bindService`（已有 API） | UI 线程 | 读写应用状态、控件树、窗口、菜单、短小计算 |
| `bindBackgroundService`（新增） | IPC 工作池 | 网络/磁盘/CPU 等耗时任务，输入输出都是 JSON 字符串 |

这样既解决了 UI 卡顿，又不破坏既有代码的主线程契约。

---

## 3. 使用后台 IPC 服务

后台方法必须是顶层、`{.nimcall, gcsafe.}` 的 proc，参数和返回值都是 JSON
字符串。它不能访问 UI，也不应修改非线程安全的应用全局状态。

```nim
import std/json
import nimi

proc searchWork(args: string): string {.gcsafe.} =
  ## 工作线程执行。只做线程安全的 I/O/计算。
  let query = parseJson(args)[0].getStr
  let songs = searchLocalIndex(query)   # 必须自行保证线程安全
  $(%*songs)

proc registerServices() =
  bindBackgroundService("Catalog", [
    backgroundMethod("search", searchWork,
      params = [ParamDef(name: "query", typ: "string")],
      resultType: "string")
  ])
```

页面调用方式与普通服务完全一致：

```ts
const songs = await Catalog.search("中文");
```

生成的 TypeScript 会把同步方法和后台方法合并到同一个服务对象里：

```ts
export const Catalog = {
  search(query: string): Promise<string> { ... },
} as const;
```

### 运行时路径

```text
WKWebView JS
  → postMessage
  → UI 线程 handleMessage
  → hasBackgroundMethod? 是
  → submitIpc(...)          ← 只做入队，不执行工作
  → IPC worker 线程执行 work(args)
  → Channel 发送 IpcResult
  → wakeMainThread()        ← dispatch_async 唤醒主线程
  → UI 线程 drainIpcPool()
  → completeIpcCall()
  → window.__nimi._resolve/_reject
```

UI 线程只负责解析消息、入队和最后的 `eval`，实际工作在线程池里完成。

---

## 4. 背压、错误和关闭

### 背压

工作池默认：

- 4 个 worker；
- 最多 256 个在途请求；
- 超出上限时 `submitIpc` 返回 false，页面 Promise 立即被 reject：
  `IPC queue is full or worker pool is closed`。

主线程不会因为队列满而阻塞。可以在第一次后台调用前调整：

```nim
app.whenReady(proc() =
  startIpcPool(workers = 8, maxInflight = 512)
  # ...
)
```

`startIpcPool` 必须在 UI 线程调用；重复调用不会重建已有池。

### 错误

- `work` 抛出的 `CatchableError` 会变成 `_reject(message)`。
- 返回值不是合法 JSON 时也会 reject（`invalid background IPC response`）。
- 工作线程不会把异常直接抛到 UI 线程。

### 关闭

`App.run` 在 native loop 退出后执行：

```nim
setIpcCompletion(nil)
shutdownIpcPool(200)
shutdownLoop()
```

`shutdownIpcPool` 会停止接收新请求、唤醒 worker、有限等待并 join。超过超时
仍未退出（例如工作函数不响应取消）时，按进程退出场景放弃 worker/shared
状态，避免退出被无限阻塞。

---

## 5. 边界与后续

已实现：

- 显式后台服务注册；
- 多 worker 线程池；
- 有界在途请求和立即拒绝；
- 主线程结果投递和 Promise resolve/reject；
- 关闭时有界等待；
- TypeScript 合并生成；
- 测试 `tests/test_ipc.nim`（注册/TS）和 `tests/test_ipc_pool.nim`
  （结果、错误、背压、窗口 resolve/reject）。

尚有限制：

- 后台调用没有 per-call 超时或强制取消；工作函数必须自己限制 I/O 时间
  （例如 curl 的 `--max-time`、文件读取大小上限）。需要更细粒度取消时，
  应使用应用自己的 `TaskExecutor`，或后续为后台 IPC 增加 `CallContext`。
- 没有 Channel/流式返回和批处理。
- 后台 work 的复杂类型仍需要在 `backgroundMethod` 中手动声明
  `params`/`resultType`；TS 只保证基础标量。
- 一个进程只有一个全局 IPC 池；不同服务共享 4 个默认 worker。重 CPU 和
  慢 I/O 混在一起时，建议调大 `workers` 或拆成应用自己的 `TaskExecutor`。
- `bindService` 的同步方法仍按主线程契约执行；短小 UI 状态操作应继续用它。

如果后续要实现“所有服务自动异步”，必须先引入可序列化的服务状态或
actor 模型，并重新定义 UI 对象的所有权；不能只把闭包塞进线程池。
