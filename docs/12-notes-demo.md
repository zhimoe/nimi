# Nimi Notes:WebView-first GUI 验收

> 日期:2026-11-04 · 对应 `examples/notes`

---

## 1. 目标

用一个真实可用的应用验证 Nimi 的 WebView-first 路径,而不是只做控件画廊:

- 页面负责富内容:列表、搜索、Markdown 编辑、实时预览、明暗主题
- Nim 负责系统能力:文件存储、原生菜单、打开/保存面板
- 两者通过框架已有的 secret/token bridge 和类型化 JSON IPC 通信
- 最终仍由 `nimi build` 打成 `.app` + DMG

## 2. 应用能力

| 能力 | 实现 |
|---|---|
| 笔记列表/搜索 | 前端渲染,后端 `Notes.listNotes` |
| 新建/编辑/删除 | `Notes.createNote/updateNote/removeNote` |
| 自动保存 | 450ms debounce + 串行保存队列 |
| 实时预览 | 前端安全转义 + 轻量 Markdown 渲染 |
| 原生菜单 | 文件/编辑/窗口/帮助;`⌘N`、`⌘S`、`⌘O`、`⇧⌘S` |
| 导入/导出 Markdown | NSOpenPanel / NSSavePanel |
| 窗口标题 | 页面通过 `Shell.setTitle` 更新 |
| 本地存储 | `~/Library/Application Support/Nimi Notes/notes.json` |
| 打包 | `Nimi Notes.app` + `nimi-notes-0.1.0.dmg` |

## 3. 数据流

```text
HTML/CSS/JS
  │  window.nimi.call("Notes.listNotes")
  ▼
core/window.handleMessage (secret + token 校验)
  ▼
core/ipc.dispatch -> Notes 服务
  ▼
notes.json (pretty JSON, 原子替换)
```

菜单方向相反:

```text
NSMenu 项
  ▼
core/menu onSelect
  ▼
focusedWindow().eval("window.nimiNotes.newNote()")
  ▼
页面状态更新
```

## 4. IPC 服务

```nim
bindService(notes, listNotes, createNote, updateNote, removeNote,
            exportNote, importNote)
bindService(shell, setTitle, quit, report)
```

| 方法 | 参数 | 返回 |
|---|---|---|
| `Notes.listNotes` | — | 笔记数组 |
| `Notes.createNote` | `title` | 新笔记 |
| `Notes.updateNote` | `id, title, body` | 更新后的笔记 |
| `Notes.removeNote` | `id` | `bool` |
| `Notes.exportNote` | `id` | 保存路径(取消为空) |
| `Notes.importNote` | — | 新笔记(取消为 null) |
| `Shell.setTitle` | `title` | `void` |
| `Shell.quit` | — | `void` |
| `Shell.report` | `text` | `void`(冒烟输出) |

`nimi generate examples/notes` 会生成 `frontend/nimi.ts` + `nimi-runtime.ts`;
当前 demo 为了零构建直接使用原生 JS bridge,生成类型客户端保留给带打包器的项目。

## 5. 关键决策

| 决策 | 原因 |
|---|---|
| 前端 HTML/CSS/JS 用 `staticRead` 编译期嵌入 | 无需资源目录/本地文件 URL;`.app` 单二进制即可运行 |
| 存储用单个 JSON 文件 | demo 规模足够;便于观察与备份。后续换 SQLite/FTS |
| 写文件先写 `.tmp` 再替换 | 避免半写文件;当前实现先删旧文件再 `moveFile`,后续可换成平台原子 rename |
| 自动保存用串行 Promise 队列 | 切换笔记/导出/删除时不会把 A 的内容存到 B |
| 切换笔记前 flush 旧笔记 | 避免 450ms debounce 内切走导致丢保存 |
| 用页面内确认框代替 `window.confirm` | 当前没有 WKUIDelegate;`confirm` 不会可靠显示 |
| Markdown 先转义再渲染 | 笔记内容不可信,避免注入 HTML |
| 原生菜单项通过 `eval` 调页面动作 | 菜单在 Nim,具体编辑状态在页面,保持单一数据源 |
| 笔记路径支持 `NIMI_NOTES_DIR` 覆盖 | 冒烟测试不污染真实用户数据 |

## 6. 验证

```sh
# 数据/IPC
NIMI_NOTES_DIR=/tmp/nimi-notes-smoke NIMI_SMOKE=crud \
  nim c -r --path:src examples/notes/main.nim
# smoke crud: ok (1 -> 2)

# UI 输入 + 自动保存
NIMI_NOTES_DIR=/tmp/nimi-notes-typing NIMI_SMOKE=typing \
  nim c -r --path:src examples/notes/main.nim
# smoke typing: ok

# 编辑中切换笔记,旧笔记仍被保存
NIMI_NOTES_DIR=/tmp/nimi-notes-switch NIMI_SMOKE=switch \
  nim c -r --path:src examples/notes/main.nim
# smoke switch: ok

# 页面内删除确认框
NIMI_NOTES_DIR=/tmp/nimi-notes-delete NIMI_SMOKE=delete \
  nim c -r --path:src examples/notes/main.nim
# smoke delete: ok

# 打包
./nimi build examples/notes
hdiutil verify examples/notes/dist/darwin-arm64/nimi-notes-0.1.0.dmg
# checksum is VALID
```

实际截图确认:

- 窗口标题随当前笔记更新
- 侧边栏列表/搜索/导入
- 左右分栏 Markdown 编辑 + 预览
- 菜单栏显示 `Nimi Notes / 文件 / 编辑 / 窗口 / 帮助`
- 暗色主题与自定义图标

## 7. 已知限制

- 单窗口;多窗口/标签页未做
- 轻量 Markdown 子集(标题/列表/引用/代码/粗斜体/链接/分隔线)
- 无全文索引、标签、反向链接、附件
- 删除确认是页面内模态,不是原生 NSAlert
- JSON 全量读写;大笔记库需要 SQLite
- 未做 iCloud/多设备同步
- 未公证(ad-hoc 签名),分发到其他机器仍需 Developer ID + notarize
- 前端使用原生 JS;生成的 TS 客户端尚未接入打包流程

## 8. 下一步

1. SQLite + FTS5 搜索,增量保存。
2. 文件监视 + 外部 Markdown 文件夹模式。
3. 多窗口/标签页,窗口状态恢复。
4. 原生 NSAlert 删除确认(补 WKUIDelegate 或 core dialog 的 cancel 版本)。
5. 用生成 TS + bundler 重写前端,验证类型化客户端工作流。
6. 自动更新、公证、CI。
