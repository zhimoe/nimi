# 框架整改与后续开发基线

更新于 2026-11-24。当前开发基线为三平台 Preview。设计参考 MyGo v0.10.0（`ebde9399`），已对照的本地快照为 `9b0ae9ef`。参阅 [MyGo 能力对照](30-mygo-alignment.md)。

## 平台能力

| 能力 | macOS | Windows | Linux |
|---|---|---|---|
| WebView 与原生渲染 | WKWebView · CoreGraphics/CoreText | WebView2 · GDI | WebKitGTK · Cairo/Pango |
| 原生 IME | NSTextInputClient | IMM32 | GtkIMContext |
| 文件监视 | FSEvents | ReadDirectoryChangesW | inotify |
| 媒体控制与本地音频 | Now Playing · AVAudioPlayer | 待实现 | MPRIS2 · GStreamer |
| URL 深链、登录项与单实例 | URL 深链和登录项 | 待实现 | D-Bus 单实例与 URL 转发 |
| 构建输出 | `.app`、DMG、签名与公证配置 | exe、manifest、WebView2 Loader | 程序目录、`.desktop`，有 `dpkg-deb` 时生成 `.deb` |

三平台共用 IPC、原生 UI 布局、基础控件与文件服务。平台细节见 [macOS 桌面 API](14-macos-desktop-apis.md)、[Windows 后端](32-windows-framework.md)、[Linux 后端](33-linux-framework.md)。

## 自动化与实机验收

| 平台 | 最近的 GitHub Actions 记录（2026-11-22） | 人工验收重点 |
|---|---|---|
| macOS | 测试和 CLI 构建通过。`protocol-native` 的 DMG 校验返回 `Resource temporarily unavailable`，未上传产物。[运行记录](https://github.com/zhimoe/nimi/actions/runs/44978676441) | 真实输入法、媒体键、登录项审批、签名与公证 |
| Windows | Windows 原生测试、CLI 和示例构建通过。[运行记录](https://github.com/zhimoe/nimi/actions/runs/44978288254) | 微软拼音/日语 IME、混合 DPI、WebView2 Runtime 安装场景 |
| Linux | Xvfb/D-Bus 测试、CLI 和示例构建与打包检查通过。[运行记录](https://github.com/zhimoe/nimi/actions/runs/44978676429) | GNOME/KDE、原生 Wayland、输入法、媒体键、实际安装 |

2026-11-24 本地复跑通过 macOS 192 项、Ubuntu 24.04 arm64 容器 200 项测试。macOS CI 清单内六个 DMG 均在本地通过校验。

后续顺序见 [路线图](05-roadmap.md#当前执行计划)，未完成项见 [各平台 backlog](backlog/README.md)。

## 已实施的整改

- 文本左右导航、Backspace/Delete、鼠标定位和上下行定位按 grapheme cluster 取整（UAX #29 实用子集）；排版记录每行起始字节，自动换行后的 caret/选择不再错位。合成 IME 测试已覆盖组合、提交和替换；真实拼音/日文输入法仍待人工验收。
- Document 保存先写同目录临时文件，flush/close 后替换，保留普通文件权限，失败清理临时文件并保留 dirty 状态。不是断电持久性保证；尚无 fsync、恢复日志、扩展属性保留或完整符号链接策略。
- 默认 Cookie store 的查询与清理统一串行排队，避免覆盖全局 pending callback。三平台均有默认 store 查询和清理。按 Session 访问、写入、单项删除和取消仍待补齐。
- Tester 按 key 点击走真实鼠标处理路径，修复输入控件没有 onClick 时的空回调崩溃。

## 后续框架功能：图片缓存容量控制

CG renderer 新增 clearImageCache、setImageCacheLimit、imageCacheStats。原图与裁剪缓存各默认最多 128 项，达到上限时清理对应缓存并释放 CF 对象。该第一版是条目上限，不是字节预算或 LRU；单张巨图仍可能占用较多内存。仅允许渲染线程调用，远程下载和文件变化失效策略仍待实现。

## 当前契约

- 应用状态、控件树、服务注册与平台操作应在主线程使用；不能承诺所有公开 API 任意线程安全。后台结果通过 postMain 投递，捕获对象的所有权仍由调用者保证。
- IPC 分为两条路径：`bindService` 方法仍在 UI 线程同步执行，适合短小状态操作；`bindBackgroundService` 方法进入有界工作池，以 JSON 字符串跨线程，结果通过主线程回投。后台调用已有 per-call 超时、窗口关闭取消和迟到结果丢弃；仍缺流式 Channel 和批处理。详见 [异步 IPC](29-async-ipc.md)。
- TS 生成仅覆盖基础标量，其他类型为 unknown。window.mygo 别名不构成上游 runtime 或 wire protocol 的完整兼容保证。
- 原生 UI 每帧建树、遍历布局；已有固定行高虚拟列表和换行行偏移；尚无可变行高虚拟化和布局缓存。通用渲染器分别是 CoreGraphics、GDI 和 Cairo。Metal 路径用于 macOS 碎纸专用效果。
- 单元和离屏测试不等于真实窗口、输入法、网络、音频与发布验收。

## 文档维护

[文档索引](README.md) 提供使用入口。00–04、06–07 保留设计范围，切片文档保留对应时期的验证记录。后续任务及验收条件随路线图和 backlog 更新。

## Music 集成进展

新增 `src/nimi/audio.nim`（显式导入，不扩大默认 facade）及 `examples/music`。
macOS AVAudioPlayer 后端提供本地解码、播放/暂停、时长/进度、seek、音量与显式关闭。
Linux 通过 GStreamer 提供本地文件播放和结束回调。两端均有真实 WAV 自动化测试，网络流仍待实现。
原生界面已经接入本地队列与播放控制。队列已支持自动下一首、单曲/列表循环、随机与历史返回；会话保存并恢复曲目元数据、位置、音量和模式。真实无声 WAV 的结束回调、回调内关闭，以及队列/会话逻辑均有测试。Now Playing/媒体键与封面 artwork 已接入；下一步补远程服务 UI 对齐与缓存管理。

## 曲库虚拟化

新增 `virtualList(c, key, count, rowHeight, viewportHeight, buildRow, overscan)`。
固定行高与固定视口高度，构建范围为视口加两侧 overscan；总滚动高度仍按全部数据计算。
`revealListRow` 将目标行移入视口，已可见时不跳动。Music 队列已接入，并提供 Now playing 定位按钮。
测试覆盖一万行的构建数量上界、滚动后点击、末行、数据缩短/清空和程序化定位。
此处只验证算法与交互，不声称真实窗口已达到 60/120fps。可变行高、键盘跨虚拟边界导航、数据重排锚点与资源后台加载仍待实现。

## 后台执行与歌词

新增独立导入的 `nimi/core/tasks`：单 worker、有界在途任务数、字符串输入/结果与错误传递。UI 闭包留在主线程，窗口定时调用 poll 交付结果。cancel 删除回调，旧结果不会写入新页面；它不抢占正在运行的任务。close 丢弃回调并有界等待。网络工作仍需配置 I/O 超时。同步 IPC 继续在主线程执行。

Music 已用它后台读取同名 .lrc（上限 2 MB），切歌取消旧回调，关闭释放 executor。新增 LRC 解析和活动行二分查询：多时间戳、毫秒、offset、无效输入、向后 seek。当前是逐行歌词，逐字歌词/翻译/动画/桌面歌词仍待实现。

## Subsonic 适配切片

Music 新增后台 Subsonic token 认证和 search3 曲库搜索。系统 curl 提供 TLS，认证 URL 只通过 stdin 传递；最大请求时间 15 秒、响应上限 8 MiB、禁用重定向（默认不启用 follow）。本地 HTTP fixture 验证认证 token、中文查询、响应和认证拒绝。

开发环境变量作为暂时连接入口；未提供正式登录 UI/Keychain，不保存凭据。结果已接入后台下载后播放；流式播放尚未实现。后续优先流式播放、分页、封面缓存淘汰与账号隔离，再推进其他服务。

## Subsonic 下载播放

本地 fixture 已验证搜索 → HTTP WAV 下载 → AVAudioPlayer 解码/静音播放，以及缓存复用、协议错误清理与预算拒绝。Music 搜索结果可点击下载并加入队列。使用独立容量 2 执行器，旧结果取消交付；取消现在会轮询并终止 curl，关闭最多等待配置的超时。真实服务连通性、流式播放与缓存淘汰仍待实现；封面已接入。

## 文本输入与关闭生命周期整改（2026-11-07）

- 新增 `src/nimi/text/grapheme.nim`：UTF-8 解码、UTF-16 ↔ UTF-8 偏移转换和 UAX #29 实用子集（组合符、变体选择符、emoji modifier、ZWJ、区域指示符、CRLF）。光标移动、Backspace/Delete、上下行定位、鼠标命中和双击选词都按 grapheme boundary 取整。
- 排版新增 `lineStarts`，修正自动换行后每行起始字节偏移；此前按“行尾 + 1”推算，换行行会错位。
- IME 的 `TextRange` 使用 UTF-16 offset，`replacementRange` 在提交和组合替换时生效；`markedRange`/`selectedRange` 返回真实文档位置；`attributedSubstring` 返回组合显示文本；`characterIndexForPoint` 映射到 UTF-16 索引。
- marked text 不写入文档，但通过虚拟显示文本参与测量、换行、绘制、候选窗定位和滚动跟随。提交、取消、切换焦点都会清理组合状态。
- TaskExecutor 新增协作取消、per-task 超时、关闭后拒绝提交和有限等待 `close(timeoutMs)`；超时仍未退出时牺牲 worker/shared 状态，避免应用关闭被网络任务无限阻塞。Subsonic 搜索/下载会轮询取消并终止 curl。
- 窗口 `closed` 为幂等操作：关闭后清空 close/closed/title/focus/frame 监听器，`onClosed` 立即执行，后续 `invalidate`/`eval`/`load*`/`emitPage` 被拒绝。
- 自动测试：`tests/test_unicode.nim`（grapheme/UTF-16）、`tests/test_ime.nim`（合成组合/提交/替换/滚动）、`tests/test_tasks.nim`（取消/超时/有限关闭）、`tests/test_ui.nim`（grapheme 编辑/窗口关闭）。
- 仍待人工验收：真实拼音、双拼、日文输入法的候选窗、选词提交、取消组合和重转换。合成事件通过不等于系统输入法通过。
- 仍有限制：grapheme 表是实用子集而非完整 Unicode 属性库；TaskExecutor 仍为单 worker；后台 IPC 已有超时/取消但不会强行终止阻塞 work，仍缺流式返回；同步 `bindService` 仍在 UI 线程；关闭超时后 worker 内存按进程退出场景处理，不用于长期运行时的反复创建。

## 异步 IPC 工作池（2026-11-07）

- 新增 `src/nimi/core/ipcpool.nim`：默认 4 worker、最多 256 个在途请求；请求/结果以 JSON 字符串跨线程，`Channel` 传递数据，由平台后端唤醒主线程交付结果。
- 新增 `bindBackgroundService` / `backgroundMethod`：耗时服务显式注册为 `{.nimcall, gcsafe.}` 的字符串工作函数；页面调用方式不变，TS 与同步方法合并生成。
- `handleMessage` 对后台方法只入队并立即返回；队列满时立即 reject，不阻塞 UI。结果回到主线程后才 `_resolve`/`_reject`；关闭窗口后丢弃结果。
- `App.run` 退出时 `shutdownIpcPool(200)` 有界等待并 join；超时按进程退出场景放弃 worker。
- 同步 `bindService` 保持原语义：仍在 UI 线程执行，适合短小状态/控件操作。不能把所有闭包自动搬到线程池，原因见 [异步 IPC](29-async-ipc.md)。
- 测试：`tests/test_ipc.nim`（注册/合并 TS/冲突）、`tests/test_ipc_pool.nim`（窗口 resolve/reject、错误、背压、关闭后拒绝提交）。
- 已补：per-call 超时（默认 30s）、窗口关闭取消、watchdog 超时回调、迟到结果丢弃。
- 仍缺：流式 Channel、批处理、复杂类型自动 TS 映射；超时/取消不抢占正在阻塞的 work。

## 音乐曲目元数据与会话 v2（2026-11-09）

- `media/queue` 的 `PlaybackQueue.tracks` 从 `seq[string]` 升级为 `seq[Track]`：路径、标题、歌手、专辑、来源、远程 ID、封面 ID/缓存路径、时长。
- 队列身份稳定：本地按路径，远程按 `source:remoteId`；重复导入/重复下载不会生成重复项。
- 本地标题取文件名（去扩展名）；远程下载完成后保留搜索结果的标题/歌手/专辑/封面 ID，队列不再显示缓存哈希。
- 会话升级到版本 2，保存完整 Track 元数据；仍读取版本 1 的纯路径会话并迁移为本地曲目。损坏会话保留原文件并回退安全默认值。
- 测试：`tests/test_queue.nim`（本地/远程身份与去重）、`tests/test_music_session.nim`（v2 往返、v1 迁移、损坏文件）。
- 封面已通过 `getCoverArt` 后台下载、独立缓存并在当前播放区显示；Now Playing/媒体键/artwork 已接入；仍待缓存淘汰 UI、流式播放、真实媒体键与 Subsonic 账号验收。

## Now Playing / 媒体键（2026-11-09）

- 新增 `core/nowplaying` 和 `platform/darwin/nowplaying`：懒加载 MediaPlayer.framework，接入 MPNowPlayingInfoCenter 与 MPRemoteCommandCenter。
- 支持标题/歌手/专辑/时长/位置/播放状态，以及 play/pause/toggle/stop/next/previous/seek 命令。
- Music 已接入切歌、播放/暂停、seek、上一首/下一首与停止；关窗/退出清除系统状态。
- 已接入封面 artwork（`MPMediaItemArtwork`）。未做：真实媒体键/控制中心人工验收、Windows 媒体控制；Linux 已接入 MPRIS2。

## macOS 登录项与首次激活点击（2026-11-22）

- 新增 `app.setOpenAtLogin(enabled)`、`app.openAtLogin()`、`app.wasOpenedAtLogin()`。macOS 13+ 使用 `SMAppService`，macOS 12 回退到 `~/Library/LaunchAgents`；要求应用运行在 `.app` 内。
- `wasOpenedAtLogin` 在 `applicationDidFinishLaunching:` 读取 launch Apple Event，并识别 `--nimi-opened-at-login` 标记。
- 新增 `WindowOptions.consumeActivationClick`；Darwin 的 `NimiWebView`/`NimiSurfaceView` 按窗口选项覆盖 `acceptsFirstMouse:`。Linux/Windows 暂忽略该选项。
- Linux/Windows 的 `setOpenAtLogin` 抛 `UnsupportedBackendError`；两个查询返回 false，命令行标记仍由共享层识别。
- 测试：`tests/test_window_options.nim`、`tests/test_darwin_login.nim`；macOS 套件 192 项通过。真实 `.app` 的登录项注册/系统审批仍需人工验收。
