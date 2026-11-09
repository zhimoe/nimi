# Nimi examples

每个示例都对应一条验收路径；不是所有历史切片都需要长期保留。完整回检见
[docs/30-mygo-alignment.md](../docs/30-mygo-alignment.md)。

| 示例 | 验收内容 | 状态 / 建议 |
|---|---|---|
| `hello` | M1 WebView + bridge + typed IPC 最小闭环 | 保留 |
| `counter-native` | M2 原生 UI、Tester、离屏 PNG | 保留 |
| `native-smoke` | 最早的 NSView/CoreGraphics 静态画面 | **可删除**：已被 counter-native/widgets-native 覆盖 |
| `form-native` | TextInput/TextArea、菜单、对话框、IME | 保留 |
| `widgets-native` | Checkbox/Switch/Slider/Progress/Divider | 保留 |
| `image-native` | Image/PNG 渲染 | 暂留；可并入 widgets-native |
| `scroll-native` | ScrollView/裁剪/滚动条 | 暂留；可并入 widgets-native |
| `protocol-native` | 自定义 `nimi://` 协议/FileServer | 保留 |
| `watch-native` | FSEvents 文件监视 | 保留 |
| `document-native` | Document 控制器 | 保留 |
| `desktop-native` | M4 桌面 API（菜单/托盘/通知/快捷键/对话框等） | 保留 |
| `notes` | WebView-first 完整应用：IPC、Markdown、导入导出 | 保留 |
| `music` | 原生 UI + 音频 + 队列/会话 + Subsonic | 保留（主 dogfood） |
| `shredder` | WebView/WebGL 碎纸效果 | 保留（唯一 WebView 效果路径） |
| `shred-native` | CoreGraphics 纹理四边形/原生帧驱动 | 保留（CPU 路径） |
| `shred-metal` | Metal mask + LayerEffect | 保留（GPU 路径） |

## CI 构建

当前 macOS workflow 构建并打包：

- `desktop-native`
- `protocol-native`
- `notes`
- `shred-native`
- `shred-metal`

`music` 已经是完整原生应用，建议加入 DMG 构建/冒烟；其余示例按需编译即可。
