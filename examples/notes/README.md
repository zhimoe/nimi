# Nimi Notes

本地 Markdown 笔记应用，用于验证 Nimi 的 WebView 路径。macOS 使用 WKWebView，Linux CI 也构建 WebKitGTK 版本。

- 系统 WebView 页面与原生窗口
- Nim ↔ JS 类型化 JSON IPC
- 原生菜单(新建/保存/导入/导出/搜索)
- 系统文件对话框导入、导出 Markdown
- 自动保存、搜索、实时预览、明暗主题
- `NIMI_NOTES_DIR` 可覆盖存储目录。默认沿用 `~/Library/Application Support/Nimi Notes/notes.json`，其他系统也使用同一相对主目录路径。
- 可打包成 `.app` 与 DMG

## 运行

```sh
nim c -r --path:src examples/notes/main.nim
```

## 在 macOS 打包

```sh
./nimi build examples/notes
open "examples/notes/dist/darwin-$(uname -m | sed s/x86_64/amd64/)/Nimi Notes.app"
```

## 冒烟测试

使用临时数据目录,避免碰真实笔记:

```sh
notes_dir=$(mktemp -d)
NIMI_NOTES_DIR="$notes_dir" NIMI_SMOKE=crud \
  nim c -r --path:src examples/notes/main.nim
# smoke crud: ok (1 -> 2)
```

`NIMI_SMOKE=title` 只读取笔记数量后退出;`NIMI_SMOKE=quit` 用于测试启动/退出。

## 结构

```text
examples/notes/
├── main.nim              # IPC 服务、存储、菜单、窗口
├── nimi.json
└── frontend/
    ├── index.html        # 页面骨架,编译期嵌入
    ├── style.css         # 明暗主题与布局
    └── app.js            # 列表/编辑/预览/自动保存
```

前端通过 `window.nimi.call("Notes.listNotes")` 调用 Nim。窗口 Option 里的 secret/token
由框架自动注入 bridge;页面不能直接访问文件系统。
