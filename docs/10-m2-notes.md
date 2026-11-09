# M2 实现状态:原生 Surface + 布局/控件 + Counter

> 日期:2026-11-04 · 对应路线图 M2

---

## 1. 已跑通的切片

一个**没有任何 HTML/WKWebView** 的 Nimi 窗口:

```sh
# 交互式 counter:Column/Row/Text/Button + 命中测试
nim c -r --path:src examples/counter-native/main.nim
```

`counter-native` 实际截图确认:白色背景、大号数字、`- / Reset / +` 三个按钮、提示文本;布局居中。点击 `+`/`-`/`Reset`、方向键、Tab+Enter 都会改变数字并重绘。最早的 `native-smoke` 静态画面已退役，自定义绘制路径由 counter-native/widgets-native 覆盖。

多行换行也已验证:`The quick brown fox... 你好世界,这是自动换行。` 在 220px 宽内正确分成多行,离屏 PNG 输出确认。

## 1.1 测试钩子

```sh
NIMI_SMOKE=check     # 构建 hits,按 key 点击 + 三次,断言 n=3,退出
NIMI_SMOKE=mouse     # 用 + 按钮坐标走 handleMouseDown/Up,断言 n=4
NIMI_SMOKE=appkit    # 合成鼠标 NSEvent 经 NSApp 分发,断言 n=4
NIMI_SMOKE=keys      # 方向键 up/up/down,断言 n=4
NIMI_SMOKE=appkitkey # 合成 keyDown NSEvent 经 NSApp 分发,断言 n=4
NIMI_SMOKE=appkitfocus # Tab×3 聚焦 +,Enter 激活,断言 n=4
```

`appkit`/`appkitkey` 模式是为了绕过本机辅助功能权限(`AXIsProcessTrusted=false`)无法用 CGEvent 自动点击的限制。它们验证:

```text
NSEvent(mouse) → NimiSurfaceView mouseDown/Up
  → locationInWindow 转换 → hit test → onClick → requestFrame

NSEvent(keyDown) → NimiSurfaceView keyDown
  → keyCode 映射(126=up,125=down,48=tab,36=enter,...)
  → Content.handleKeyDown
  → Engine.pendingKeys / focus(Tab/Enter)
  → view 的 c.keyPressed → 状态更新
```

真实鼠标/键盘事件由用户在窗口中验证;代码路径与合成事件相同。

## 2. 管线

```text
WindowOptions.content
  └─ core/content.nim: uiView(view)
       └─ ui/context.nim: Context + Node tree + layout + Scene + hits
       └─ text/measure.nim: CoreText 真实文本测量 + rune 级换行
            └─ scene/scene.nim: opRect / opText
                 └─ render/cg.nim: CGContext + CTLine
                      └─ NSView drawRect: 的 CGContext
```

- `platform/darwin/window.nim`:
  - `NimiSurfaceView`(NSView 子类)
  - `drawRect:` → `NSGraphicsContext currentContext` → `graphicsPort` → `SurfaceHandler.draw`
  - `acceptsFirstResponder`、mouse/key 方法骨架(暂为 no-op)
- `platform/contract.nim`:
  - `SurfaceHandler`(draw/mouse/key)
  - `PlatformWindowOptions.content`
  - `NativeWindow.requestFrame`
- 场景坐标是左上原点;`render/cg.nim` 转成 AppKit 的左下原点。
- 文本用 `CTLine`/`CTFont`;矩形用 `CGContextFillRect`/`CGPathCreateWithRoundedRect`。
- 点击后重绘:core `Window.invalidate()` → `NativeWindow.requestFrame()` → `[NSView setNeedsDisplay:]`。

## 3. 新增文件

| 文件 | 内容 |
|---|---|
| `src/nimi/scene/scene.nim` | `Color`/`Rect`/`Op`/`Scene`;rect/text |
| `src/nimi/render/cg.nim` | CoreGraphics/CoreText 渲染器 |
| `src/nimi/ui/context.nim` | `Context`、`Node`、Column/Row、Text/Button、布局、绘制、命中、键队列、Engine |
| `src/nimi/text/measure.nim` | CoreText 真实文本测量 + `layoutText` 换行 |
| `src/nimi/ui/tester.nim` | `Tester`:render/click/key/texts/hasText/resize |
| `src/nimi/render/cg.nim` | 新增 `renderSceneToPng` 离屏 PNG |
| `src/nimi/ui.nim` | UI 门面 |
| `src/nimi/core/content.nim` | `Content`/`uiView`/`renderContent` |
| `src/nimi/platform/darwin/window.nim` | Surface 分支、`NimiSurfaceView`、drawRect 回调 |
| `examples/counter-native/main.nim` | Column/Row/Text/Button + 点击验收 |
| `tests/test_ui.nim` | 无窗口布局/命中/点击/键盘/Tester 测试 |
| `tests/test_render.nim` | 离屏 PNG 渲染测试 |

## 4. 本次实现决策

| 决策 | 原因 |
|---|---|
| 每帧重建 `Node` 树,不做 arena/generation | M2 先验证布局/输入/绘制;arena 与 layout cache 在控件变多、性能需要时再引入 |
| 布局用简单的 Column/Row + 固定/填充尺寸 | 覆盖 counter 与大多数基础界面;flex grow/wrap/grid 下一步 |
| 文本测量用 CoreText `CTLineGetTypographicBounds` | 布局与渲染一致;带 `(text,size,bold)` 缓存,避免每帧重建字体/行 |
| 换行先用 rune 级贪心:优先在空格断行,长词/CJK 按 rune 断 | M2 不引入 CTTypesetter/Pango;覆盖中英文常见段落。后续替换为真实断行 |
| `wrap()` 用父容器可用宽度;`width()` 可固定宽度 | 符合常见布局直觉;后续支持 min/max content 与 maxLines |
| Button 用显式 `key` 做命中/hover/press | 跨帧稳定身份;同名按钮需显式 key |
| 根 Column `fill().center()` 同时居中横/纵 | 符合 MyGo counter 的视觉;其他容器默认左/上对齐 |
| 直接画到 `NSView drawRect:` 的 CGContext | 最短路径;不引入 bitmap/CAMetalLayer;Metal 在 M3 |
| 每帧全量重绘 | M2 规模小;scene diff/damage 后续 |
| 构造器/setter 标 `{.discardable.}` | 允许 `text(c, "x").bold()` 作为语句使用 |
| 键盘事件进入 `Engine.pendingKeys`,view 用 `while c.keyPressed(...)` 消费 | 一帧内可能有多个 key repeat;`while` 能全部消费,`if` 只消费一个 |
| Tab/Enter/Space 由 Engine 处理,不进 pendingKeys | 焦点是框架级状态,不应让每个 view 重复实现 |
| 焦点顺序 = hit 顺序;鼠标按下也设置焦点 | 与绘制/命中顺序一致;按钮天然可聚焦 |
| `Tester` 包装同一个 `Engine` | 无窗口测试与窗口绘制走同一套布局/绘制/命中 |
| 离屏 PNG 用 `CGBitmapContext` + ImageIO | 在测试/CI 中生成可查看的截图;暂不比像素 golden |
| macOS keyCode 映射方向/编辑键,其他键用 `characters` | 方向键的 characters 不可靠;keyCode 稳定 |
| 合成 `NSEvent` 做 AppKit 测试 | 本机无辅助功能权限,无法用 CGEvent 自动点击 |

## 5. 已知限制(M2 后续)

| 限制 | 下一步 |
|---|---|
| 布局只有 Column/Row/固定/填充 | Flex grow/wrap、Grid、绝对定位 |
| 只有 rect/text 两种 op | 图片/SVG/渐变/裁剪/阴影 |
| 多行已支持;无 ellipsis/maxLines/justify/选择 | ellipsis、maxLines、对齐、选择 |
| 无 glyph atlas | font/glyph 缓存 + atlas |
| 控件只有 Text/Button | Checkbox/Radio/TextInput/Scroll/List |
| 焦点只支持 Tab 正向/Enter/Space;无 Shift+Tab、无文本输入焦点 | 完整焦点模型、Shift+Tab、IME |
| PNG 测试只检查文件生成,未做像素 golden | 场景快照/像素 golden |
| 无 layout cache/damage | 全量布局/重绘;后续缓存 |
| 无 Metal | CG 参考路径;M3 接 Metal |
| 无像素 golden | 已有 `Tester` + 离屏 PNG;下一步做场景/像素 golden |
| 无 Retina 特殊处理 | AppKit 的 CGContext 已按 points 缩放;后续验证混合屏 |
| 无键盘/箭头计数 | counter 目前只支持鼠标 |

## 6. 下一步

1. **ellipsis/maxLines/对齐**:补全文本布局的常用选项。
2. **场景/像素 golden**:基于 `Tester.scene` 或离屏 PNG 做回归。
3. **TextInput**:单行/多行、caret、selection、剪贴板、IME。
4. **完整焦点模型**:Shift+Tab、文本输入焦点。
5. **更多控件**:Checkbox/Radio/Scroll/List。
6. **Metal**:M3 起用 scene → instanced quad,presenter 线程。

---

*本文件记录 M2 核心切片的实际实现;设计目标见 `docs/03-native-ui.md`。*
