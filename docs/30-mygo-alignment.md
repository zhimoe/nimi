# MyGo 当前能力对照与计划校准

> 日期：2026-11-09
> 参考快照：本地 `mygo/` HEAD `f234638d`（2026-11-09）；稳定基线 `v0.8.3`（`5add3817`，2026-11-07）。
> 自 `v0.7.4` 起共 328 个提交。本文把 Nimi 文档/计划从“0.7.4 基线”校准到当前 MyGo 能力；不是承诺 Nimi 全部实现。

---

## 1. 版本与规模

| 项 | 旧文档 | 当前快照 |
|---|---|---|
| 参考版本 | MyGo 0.7.4（`02f583c8`） | `v0.8.3`（`5add3817`）；本地 HEAD `f234638d`（含 `native-libraries`） |
| 非测试 Go | 322,996 行 / 1,621 文件 | 373,636 行 / 1,064 文件 |
| 测试 Go | 139,005 行 | 167,402 行 / 752 文件 |
| 根包 `mygo` | ~21,600 | 22,102 |
| `internal/` | 138,245 | 156,360 |
| `ui/` | 89,710 | 104,795（根包 67,985；editor 16,690；markdown 8,359；richtext 6,635；video 2,545；chart 1,735） |
| `plugins/` | 31,883 | 32,274 |
| `cmd/mygo` | 12,662 | 15,777 |
| `i18n/` | 7,966 | 17,261 |
| `audio/` | 2,330 | 4,889 |
| `native/` + `ffi/` | 未记录 | 2,954 + 506 |

规模不是目标本身，但说明 MyGo 的能力面明显大于 Nimi 当前计划中的“macOS 切片”。

---

## 2. 能力差异与计划影响

| 领域 | MyGo 当前能力 | Nimi 当前 | 计划/文档动作 |
|---|---|---|---|
| WebView / IPC | 绑定服务、事件、Channel（1 MiB 窗口/ack）、trusted/untrusted、preload、注入脚本顺序、Eval、页面导航/下载/权限、`WebViewAvailable`、GPU 进程 ID | 类型化 IPC、事件、后台工作池、secret/token；无 Channel、preload、trust 细分、下载/权限 | 保留 `docs/04` 的目标协议；M1 剩余项改为“Channel、preload/trust、页面下载/权限、Eval 返回值”；后台池见 `29` |
| 原生 UI | ~100 组件：editor、richtext、markdown、chart、video、table/tree/outline/grid、split/sidebar/toolbar、calendar/date/time/color、combobox/autocomplete/token、find bar/diff viewer；无障碍、RTL、transitions/motion/transforms/shaders、Tester、WASM 浏览器 | 少量基础控件、TextInput/TextArea、ScrollView、固定行高虚拟列表、基础 IME | `docs/03` 的 120 入口是旧快照；M3 只承诺基础控件；编辑器/富文本/图表/视频/无障碍进入 M6/M10/P2，不挤进 M3 |
| 音频 | Go 内混音；WAV/MP3/Vorbis/FLAC/AAC/ALAC（含 MP4 容器）；流式解码、seek、loop、变速/保持音高；Now Playing/媒体键；三平台输出 | AVAudioPlayer 本地文件、播放/暂停/seek/音量；Track 元数据/会话 v2/远程封面缓存已完成；无流式、混音、格式矩阵 | 音乐应用下一步做 Now Playing/媒体键；通用音频引擎（混音、流式、格式注册）列为 M10/P2，不阻塞 1.0 |
| 原生模块 | Swift/Rust/Zig 实现 Go 接口，无 cgo；`mygo native build/add/check/call/publish`；视图/回调/缓冲区/纹理 | 未规划 | 新增 M10/P2 条目；明确 1.0 不做，插件/动态库继续走现有路线 |
| 桌面 API | Now Playing/媒体键、Power、Network/Proxy、Secrets、权限（PermissionFlow）、Downloads、拖放、通知点击/权限、最近文档、Jump List、登录项、窗口状态、vibrancy、SetInputRegion | 菜单/托盘/通知/快捷键/对话框/剪贴板/屏幕/主题/窗口控制/Cookie 查询/文件监视/Document | `docs/14` 后补差距表；M4 增加 Now Playing、Power、Secrets、拖放、通知点击；M5 增加 Downloads、权限、窗口状态 |
| 文档 | autosave、恢复副本、外部修改、File 菜单、最近文档、文件关联、每窗口文档 | Document 控制器、原子保存、外部冲突检测；无 autosave/recovery/recent 菜单 | M5 扩展验收：崩溃恢复、自动保存、最近文档、关闭/退出询问 |
| i18n | ICU 消息目录、typed Go/TS、CLDR 复数/日期/数字、pseudo locale、ChosenLocale、MyGo 自身字符串 | 仅有 locale 概念/最小计划 | M5 从“最小 i18n”上调为独立工作包；M10 补代码生成/CLDR |
| 分发 | macOS 签名/公证/DMG、Windows 安装器、Debian/Arch/安装脚本、native libraries/helper、签名更新/增量/更新窗口 | `.app`/DMG/ad-hoc/Developer ID 配置/公证钩子/CI；更新未实现 | M7 保留 macOS 发布；M8/M9 按 MyGo 当前打包面扩展；更新/增量列入 M7/M10 |
| 测试/自动化 | Tester、AUTOMATION socket + `mygo-automation` CLI、benchmarks、输入延迟/内存基线、跨框架对照 | Tester、离屏 PNG、单元测试；无真实窗口 E2E/自动化 socket/性能基线 | M10 增加 automation 协议兼容；在 M3/M6 后补真实窗口 E2E 与性能基线 |
| 插件 | fetch、websocket、sqlite、watch、updater、terminal、glass、game、loading、sfsymbols、permissionflow、automation | 计划列表已有大部分；实现少 | `docs/05` M10 列表补 permissionflow/sfsymbols/glass/automation 的当前形态；优先级按音乐/桌面需求排 |
| 浏览器/WASM | 原生 UI 可编译为 WebAssembly，用 WebGL2 在页面里运行 | 仅在 M10 提“浏览器/wasm 可选” | 保持可选，不进入 macOS 1.0 范围 |

---

## 3. 计划调整建议

1. **参考版本改为双轨**：稳定设计对照 `v0.8.3`（`5add3817`）；本地 `mygo/` HEAD 仅用于能力盘点和新特性跟踪。不要再写“锁定 0.7.4”。
2. **保持 Nimi 1.0 的 macOS-first 范围**。MyGo 当前的 editor/richtext/markdown/video、原生模块、完整音频引擎、WASM 浏览器、Windows/Linux 三平台打包不进入 1.0 承诺；放到 M10/P2。
3. **M3 不扩表**。M3 仍以基础控件、布局、滚动、Tester 为主；MyGo 的 100 组件清单作为 M6/M10 的参考，不作为 M3 验收。
4. **M4/M5 增补桌面/文档能力**：Now Playing、Power、Secrets、Downloads、拖放、通知点击、窗口状态、autosave/recovery/recent documents、i18n。
5. **M6 明确编辑器/富文本/视频是无障碍之外的独立大项**，不要与基础 TextArea/IME 混在一起估工期。
6. **M7/M8/M9 对齐分发面**：macOS 之外的安装器、native libraries/helper、更新签名/增量在 MyGo 已有实现，Nimi 计划仍按平台推进。
7. **文档引用**：新代码/新 API 不应再引用 `docs/07` 的旧映射作为“当前能力”；先查源码，再看本文和 `docs/28`。

---

## 4. 需要更新的文档

| 文档 | 需要改什么 |
|---|---|
| `README.md` | 参考版本 0.7.4 → v0.8.3/本地 HEAD；状态行补异步 IPC/后台池 |
| `docs/00-feasibility.md` | 参考版本、代码规模表、MyGo 能力盘点；附录文件行数 |
| `docs/03-native-ui.md` | MyGo `ui` 行数/入口数更新；补 editor/markdown/richtext/video/chart/无障碍/RTL/motion/shaders 的“后续/P2”说明 |
| `docs/04-tooling-and-ipc.md` | 补 Channel、preload、trusted/untrusted、页面下载/权限、WebViewAvailable、Eval 返回值 |
| `docs/05-roadmap.md` | 上游锁定版本；M4/M5/M6/M10 能力范围；新增本文链接 |
| `docs/07-api-mapping.md` | 标注映射基线为 0.7.4；新 API（Now Playing、Power、Secrets、Audio、Native Modules、Video）指向本文 |
| `docs/08-m1-notes.md` | 已补后台 IPC；仍缺 Channel/preload/trust |
| `docs/11-m3-m7-status.md` | 顶部说明 MyGo 0.8.3 能力面大于 Nimi 切片，避免把“MyGo 有”当成“Nimi 已完成” |
| `docs/14-macos-desktop-apis.md` | 增加与 MyGo 当前桌面 API 的差距表 |
| `docs/28-remediation-status.md` | 参考 commit 更新；异步 IPC 已实现 |
| `docs/README.md` | 参考版本、变更记录、30 入口 |

---

## 5. Examples 回检

当前 16 个示例。建议按“验收路径”保留，而不是按数量保留：

| 示例 | 作用 | 建议 |
|---|---|---|
| `hello` | M1 WebView/JS IPC 最小闭环 | 保留 |
| `counter-native` | M2 原生 UI 最小验收 | 保留 |
| `form-native` | TextInput/TextArea/菜单/对话框/IME | 保留 |
| `widgets-native` | Checkbox/Switch/Slider/Progress/Divider + Image + ScrollView | 保留（已合并 image-native/scroll-native） |
| `protocol-native` | 自定义协议/FileServer | 保留 |
| `watch-native` | FSEvents 文件监视 | 保留 |
| `document-native` | Document 控制器 | 保留 |
| `desktop-native` | M4 桌面 API 验收 | 保留 |
| `notes` | WebView-first 完整应用 | 保留 |
| `music` | 原生 UI + 音频 + 队列/会话 | 保留（主 dogfood） |
| `shredder` | WebView/WebGL 效果 | 保留（唯一 WebView 效果路径） |
| `shred-native` | CoreGraphics 纹理四边形/帧驱动 | 保留（CPU 路径） |
| `shred-metal` | Metal mask/LayerEffect | 保留（GPU 路径） |

已执行：

- 删除 `native-smoke`；自定义绘制验收由 `counter-native`/`widgets-native` 覆盖。
- 将 `image-native`、`scroll-native` 合并进 `widgets-native`，保留 `NIMI_SMOKE=image|scroll` 两个冒烟入口。
- `shred-native`/`shred-metal`/`shredder` 分别覆盖 CPU/GPU/WebView 三条渲染路径，保留；`notes`/`music` 分别覆盖 WebView-first 与原生-first 两种应用形态，保留。
- CI 构建 `desktop-native`、`protocol-native`、`notes`、`music`、`shred-native`、`shred-metal`；music 已补入 DMG 构建。

已同步更新 `README.md`、`docs/05`、`docs/10`、`docs/11`、`docs/21`、`docs/22` 与 `examples/README.md`。

---

## 6. 验证

- 本文的规模统计基于本地 `mygo/` HEAD `f234638d`，排除 `_test.go`、`testdata`、`.git`、`node_modules`、`dist`。
- Nimi 当前测试：`./scripts/test.sh` 107 个测试通过（2026-11-08 基线）。
- MyGo 能力以 `mygo/docs/` 和源码为准；本文只做映射，不替代逐项源码核对。
