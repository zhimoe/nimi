# 框架整改与后续开发基线

日期：2026-11-06（2026-11-09 更新）。参考：MyGo v0.8.3 `5add3817`；本地能力盘点快照 `f234638d`。本文是当前状态入口；旧设计中的接口和工期不代表已交付承诺。MyGo 能力差异见 [30](30-mygo-alignment.md)。

## 已实施的整改

- 文本左右导航、Backspace/Delete、鼠标定位和上下行定位按 grapheme cluster 取整（UAX #29 实用子集）；排版记录每行起始字节，自动换行后的 caret/选择不再错位。合成 IME 测试已覆盖组合、提交和替换；真实拼音/日文输入法仍待人工验收。
- Document 保存先写同目录临时文件，flush/close 后替换，保留普通文件权限，失败清理临时文件并保留 dirty 状态。不是断电持久性保证；尚无 fsync、恢复日志、扩展属性保留或完整符号链接策略。
- 默认 Cookie store 的查询与清理统一串行排队，避免覆盖全局 pending callback。仍无按 Session 指定 store、写入、单项删除、取消；真实 WebKit 并发验收待补。
- Tester 按 key 点击走真实鼠标处理路径，修复输入控件没有 onClick 时的空回调崩溃。

## 后续框架功能：图片缓存容量控制

CG renderer 新增 clearImageCache、setImageCacheLimit、imageCacheStats。原图与裁剪缓存各默认最多 128 项，达到上限时清理对应缓存并释放 CF 对象。该第一版是条目上限，不是字节预算或 LRU；单张巨图仍可能占用较多内存。仅允许渲染线程调用，远程下载和文件变化失效策略仍待实现。

## 当前契约

- 应用状态、控件树、服务注册与平台操作应在主线程使用；不能承诺所有公开 API 任意线程安全。后台结果通过 postMain 投递，捕获对象的所有权仍由调用者保证。
- IPC 分为两条路径：`bindService` 方法仍在 UI 线程同步执行，适合短小状态操作；`bindBackgroundService` 方法进入有界工作池，以 JSON 字符串跨线程，结果通过主线程回投。后台调用暂无 per-call 超时/取消、流式 Channel 和批处理。详见 [异步 IPC](29-async-ipc.md)。
- TS 生成仅覆盖基础标量，其他类型为 unknown。window.mygo 别名不构成上游 runtime 或 wire protocol 的完整兼容保证。
- 原生 UI 每帧建树、遍历布局；已有固定行高虚拟列表和换行行偏移；尚无可变行高虚拟化和布局缓存。CG 是通用默认渲染器，Metal 仅支持专用效果。
- 单元和离屏测试不等于真实窗口、输入法、网络、音频与发布验收。

## 后续开发顺序与验收

1. 正确性：grapheme 编辑、IME UTF-16/range、保存失败恢复、窗口关闭回调失效。验收：中日韩/emoji 编辑、关闭期间任务完成、失败保存不丢原文件。代码与合成测试已完成；真实拼音/日文输入法人工验收仍待执行。
2. 异步核心：明确主线程契约，任务标识/取消/关闭清理，再实现工作池；补错误返回与复杂类型生成。验收：慢请求期间 UI 可交互、旧结果不污染新页面。当前 TaskExecutor 支持协作取消、超时和有限等待关闭；后台 IPC 已有有界工作池，同步 `bindService` 仍按 UI 线程契约执行。
3. 音乐应用基础：固定行高虚拟列表、有限容量封面缓存、音频后端原型。验收：一万行仅构建视口及 overscan；播放/暂停/seek/切歌/结束/关闭可重复验证。
4. macOS 完善：Session Cookie、凭据存储、Now Playing、通知与拖放。每项需要打包应用实测。
5. 发布：真实签名公证、干净机器启动、升级回滚；再拓展通用 Metal 和其他平台。

不把以上工作压成一个“框架完成百分比”。每项分别记录：设计目标、已实现、自动测试、真实场景验收。工期待异步和音频原型完成后重新估算。

## 文档维护规则

00–07 保留为目标设计资料；引用 API 前必须核对源码与当前状态。11 记录切片，27 保留历史回检。本文件集中管理整改限制与后续优先级。README 与路线图链接到本文件，避免重复维护多份完成状态。

## Music 集成进展

新增 `src/nimi/audio.nim`（显式导入，不扩大默认 facade）及 `examples/music`。
macOS AVAudioPlayer 后端提供本地解码、播放/暂停、时长/进度、seek、音量与显式关闭。
真实 WAV 测试覆盖成功路径、无效文件和关闭后的操作；网络流仍未实现；播放结束 delegate 已接入并实测。
原生界面已经接入本地队列与播放控制。队列已支持自动下一首、单曲/列表循环、随机与历史返回；会话保存并恢复队列、位置、音量和模式。真实无声 WAV 的结束回调、回调内关闭，以及队列/会话逻辑均有测试。下一步补后台加载、远程服务、歌词/封面及 UI 对齐。

## 曲库虚拟化

新增 `virtualList(c, key, count, rowHeight, viewportHeight, buildRow, overscan)`。
固定行高与固定视口高度，构建范围为视口加两侧 overscan；总滚动高度仍按全部数据计算。
`revealListRow` 将目标行移入视口，已可见时不跳动。Music 队列已接入，并提供 Now playing 定位按钮。
测试覆盖一万行的构建数量上界、滚动后点击、末行、数据缩短/清空和程序化定位。
此处只验证算法与交互，不声称真实窗口已达到 60/120fps。可变行高、键盘跨虚拟边界导航、数据重排锚点与资源后台加载仍待实现。

## 后台执行与歌词

新增独立导入的 `nimi/core/tasks`：单 worker、有界在途任务数、字符串输入/结果与错误传递。UI 闭包留在主线程，窗口定时调用 poll 交付结果。cancel 删除回调，旧结果不会写入新页面；它不抢占正在运行的任务。close 丢弃回调并等待已提交任务，因此网络工作必须配置超时；尚不是并行线程池，也没有改造同步 IPC。

Music 已用它后台读取同名 .lrc（上限 2 MB），切歌取消旧回调，关闭释放 executor。新增 LRC 解析和活动行二分查询：多时间戳、毫秒、offset、无效输入、向后 seek。当前是逐行歌词，逐字歌词/翻译/动画/桌面歌词仍待实现。

## Subsonic 适配切片

Music 新增后台 Subsonic token 认证和 search3 曲库搜索。系统 curl 提供 TLS，认证 URL 只通过 stdin 传递；最大请求时间 15 秒、响应上限 8 MiB、禁用重定向（默认不启用 follow）。本地 HTTP fixture 验证认证 token、中文查询、响应和认证拒绝。

开发环境变量作为暂时连接入口；未提供正式登录 UI/Keychain，不保存凭据。结果已接入后台下载后播放；流式播放尚未实现。后续优先下载/流式播放、分页、封面与账号隔离，再推进其他服务。

## Subsonic 下载播放

本地 fixture 已验证搜索 → HTTP WAV 下载 → AVAudioPlayer 解码/静音播放，以及缓存复用、协议错误清理与预算拒绝。Music 搜索结果可点击下载并加入队列。使用独立容量 2 执行器，旧结果取消交付；取消现在会轮询并终止 curl，关闭最多等待配置的超时。真实服务连通性、流式播放、远程队列身份/标题持久化和缓存淘汰仍待实现。

## 文本输入与关闭生命周期整改（2026-11-07）

- 新增 `src/nimi/text/grapheme.nim`：UTF-8 解码、UTF-16 ↔ UTF-8 偏移转换和 UAX #29 实用子集（组合符、变体选择符、emoji modifier、ZWJ、区域指示符、CRLF）。光标移动、Backspace/Delete、上下行定位、鼠标命中和双击选词都按 grapheme boundary 取整。
- 排版新增 `lineStarts`，修正自动换行后每行起始字节偏移；此前按“行尾 + 1”推算，换行行会错位。
- IME 的 `TextRange` 使用 UTF-16 offset，`replacementRange` 在提交和组合替换时生效；`markedRange`/`selectedRange` 返回真实文档位置；`attributedSubstring` 返回组合显示文本；`characterIndexForPoint` 映射到 UTF-16 索引。
- marked text 不写入文档，但通过虚拟显示文本参与测量、换行、绘制、候选窗定位和滚动跟随。提交、取消、切换焦点都会清理组合状态。
- TaskExecutor 新增协作取消、per-task 超时、关闭后拒绝提交和有限等待 `close(timeoutMs)`；超时仍未退出时牺牲 worker/shared 状态，避免应用关闭被网络任务无限阻塞。Subsonic 搜索/下载会轮询取消并终止 curl。
- 窗口 `closed` 为幂等操作：关闭后清空 close/closed/title/focus/frame 监听器，`onClosed` 立即执行，后续 `invalidate`/`eval`/`load*`/`emitPage` 被拒绝。
- 自动测试：`tests/test_unicode.nim`（grapheme/UTF-16）、`tests/test_ime.nim`（合成组合/提交/替换/滚动）、`tests/test_tasks.nim`（取消/超时/有限关闭）、`tests/test_ui.nim`（grapheme 编辑/窗口关闭）。
- 仍待人工验收：真实拼音、双拼、日文输入法的候选窗、选词提交、取消组合和重转换。合成事件通过不等于系统输入法通过。
- 仍有限制：grapheme 表是实用子集而非完整 Unicode 属性库；TaskExecutor 仍为单 worker；后台 IPC 没有 per-call 超时/取消和流式返回，同步 `bindService` 仍在 UI 线程；关闭超时后 worker 内存按进程退出场景处理，不用于长期运行时的反复创建。

## 异步 IPC 工作池（2026-11-07）

- 新增 `src/nimi/core/ipcpool.nim`：默认 4 worker、最多 256 个在途请求；请求/结果以 JSON 字符串跨线程，`Channel` 传递数据，`wakeMainThread` 通过 `dispatch_async` 唤醒主线程。
- 新增 `bindBackgroundService` / `backgroundMethod`：耗时服务显式注册为 `{.nimcall, gcsafe.}` 的字符串工作函数；页面调用方式不变，TS 与同步方法合并生成。
- `handleMessage` 对后台方法只入队并立即返回；队列满时立即 reject，不阻塞 UI。结果回到主线程后才 `_resolve`/`_reject`；关闭窗口后丢弃结果。
- `App.run` 退出时 `shutdownIpcPool(200)` 有界等待并 join；超时按进程退出场景放弃 worker。
- 同步 `bindService` 保持原语义：仍在 UI 线程执行，适合短小状态/控件操作。不能把所有闭包自动搬到线程池，原因见 [异步 IPC](29-async-ipc.md)。
- 测试：`tests/test_ipc.nim`（注册/合并 TS/冲突）、`tests/test_ipc_pool.nim`（窗口 resolve/reject、错误、背压、关闭后拒绝提交）。
- 仍缺：per-call 超时/取消、流式 Channel、批处理、复杂类型自动 TS 映射。
