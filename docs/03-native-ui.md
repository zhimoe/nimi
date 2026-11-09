# 原生 UI 设计(`ui`)

> 2026-11-06 重评：本文包含目标设计，不能作为当前 API/线程安全/兼容性承诺。实现边界与后续验收以 [整改基线](28-remediation-status.md) 为准；历史工期不作为剩余工期。

> 状态:草案 · 日期:2026-11-04 · 关联:[架构](01-architecture.md)、[macOS 后端](02-macos-backend.md)、[路线图](05-roadmap.md)
> 参考:MyGo v0.8.3。`ui/` 根包 68.0k 行(非测试)、`ui/editor` 16.7k、`ui/richtext` 6.6k、`ui/markdown` 8.4k、`ui/chart` 1.7k、`ui/video` 2.5k、`ui/shader` 0.8k。
> 公开面:旧快照为 120 个顶层入口;当前 MyGo 入口更多,需重新盘点。本文的控件清单是 Nimi 的目标子集,不是 MyGo 当前全量清单。完整差异见 [MyGo 能力对照](30-mygo-alignment.md)。

---

## 1. 目标与不变量

Nimi 的原生 UI 是 MyGo `ui` 的 Nim 重实现,保持四个核心决策:

1. **view 函数 + 每帧重建树**:用户在 `proc view(s: State, c: Context)` 里按当前状态声明 UI;引擎每帧重建元素树,按结构位置/`key` 保留状态。
2. **build → layout → commit → paint 四阶段**:输入/命中/无障碍使用"已提交"几何,绘制使用同一棵树。
3. **比较式布局缓存**:view 每帧重建,布局输入未变的子树直接复用上一帧结果。
4. **scene display list + 可替换渲染器**:UI 只产出场景;CPU raster / Metal / GL / D3D11 是并列后端。

不变量:

- 控件构造器在调用时立即创建/配置节点;构造函数返回时,绑定输入已应用(`value_input` 语义)。
- 所有 UI 操作在主线程;绘制/布局不跨线程。
- 元素句柄零值安全;旧句柄不能别名新节点(owner + generation)。
- 窗口关闭后,保存的 `Element` 自动失效,不拖住窗口。
- 控件外观与行为分离;`ButtonBase` 等 base 控件可被自定义控件复用。
- 测试可无窗口运行(`Tester`),不依赖 wall clock。

---

## 2. 核心类型

### 2.1 `Context`

每个窗口一个稳定 `Context`;一次 build pass 的内部状态在 `BuildState` 中。

```nim
type
  Context* = ref object
    engine: ptr Engine
    services: Services
    build: ptr BuildState      # 仅 build 期间有效

  Services* = object
    clipboard*: ClipboardService
    openURL*: proc(url: string)
    invalidate*: proc()        # 任意线程安全
```

- 公开方法:`key`、`theme`、`locale`、`direction`、`size`、`scale`、`shortcut`、`announce`、`local`、`focusBind` 等。
- `Context` 不暴露 `engine`;控件实现通过内部 `node(e)` 访问。

### 2.2 `Element`

16 字节受检句柄:

```nim
type
  ElementOwner = object
    engine: ptr Engine
    generation: uint32
  Element* = object
    owner: ptr ElementOwner
    slot: uint32
    generation: uint32
```

- 零值(`owner == nil`)= 不存在。
- `lookup` 检查:owner 非空、owner.engine 非空、`generation == owner.generation`、engine 正在 build、slot 在 arena 内。
- 失败:开发构建/Tester panic;生产返回 nil,查询方法返回零值。
- `valid` 不触发诊断;用于可选控件。
- owner 在窗口关闭时 `engine = nil`;保存的 Element 自动失效。
- 不把 `Element` 放进 `ref object` 形成环;它是值类型。

### 2.3 `Node`

真实节点。为避免每帧清理一个巨大的 variant 对象,拆成几个部分:

```nim
type
  Node = object
    id: uint64
    parent, first, last, next: uint32   # arena 索引,不是指针
    kind: NodeKind
    flags: set[NodeFlag]
    layout: LayoutStyle
    text: TextStyle
    textContent: string
    paint: PaintStyle
    state: uint32                        # state 表键
    # ... 几何、命中、无障碍字段
```

- arena 用 chunked `seq[seq[Node]]`(chunk=32),保证节点地址稳定;不要用 `ptr Node` 指向 `seq` 元素(扩容会移动)。
- 每 pass `used = 0`,`epoch += 1`;节点重置时显式清空 string/seq/closure 字段。
- 元素树链接用 `uint32` 索引,避免 `ref` 环与 RC 开销。
- 稀有字段(渐变、阴影、rich spans、editor)放旁路表:`Table[uint32, ref PaintExtra]`,按需分配。

### 2.4 Arena 与 state

- 每个窗口一个 arena;build pass 分配,`finish` 回收未引用节点。
- `state` 按 `id` 保留跨帧状态:布局缓存、文本布局、指针/键盘/滚动、editor、`local`、动画、transition、快捷键。
- `Table[uint64, ref State]`;每帧标记使用,prune 未使用项。
- ID:
  - 默认 = `mix(parent.id, index + kind << 56)`。
  - `Context.key(...)` = `keyedID(parent, key)`;支持 string/int/pointer;重复 key 在开发/Tester 中 panic。
  - 自定义 `hash`/`==`,不要用 `$` 回退。

---

## 3. 构建语义

### 3.1 控件构造器

```nim
type Counter = ref object
  n: int

proc view(s: Counter, c: Context) =
  column(c).fill().center().gap(16).children(proc() =
    text(c, $s.n).fontSize(56).bold()
    row(c).gap(8).children(proc() =
      if button(c.key("increment"), "+").clicked():
        inc s.n
    )
  )
```

- `column(c)` 立即创建 `kindColumn` 节点,设置父级,返回 `Element`。
- 链式 setter 返回 `Element`,内部 `node(e)` 为空则忽略。
- `children(proc() = ...)` 保存/恢复 parent;Nim 可用模板避免闭包分配(见 §3.4)。
- 值绑定控件(`checkbox(c, addr s.flag)`)在构造器返回时应用输入;下一条语句能读到新值。

### 3.2 输入队列与多 pass

- 输入事件先排队,记录入队时的 build 深度。
- `beginBuild`/`endBuild` 包围每个公开构造器;`endBuild` 只 finalize 深度不大于当前深度的条目。
- 容器(如 RadioGroup)的输入等其构造器返回后再生效。
- `clicked`/`changed`/`submitted` 查询前先应用输入。
- 每帧最多 3 个 build pass:如果构造期间消费的输入改变了已构建元素,重新构建。
- Nim 用 `try/finally` 保证异常时 parent/深度恢复。

### 3.3 焦点与 key

- `Context.key(...)` 在状态初始化前提供稳定 ID。
- 同一父级重复 key 在开发/Tester 中 panic;生产保留第一个/忽略重复。
- `Handle` 保存持久控件身份(焦点、bounds、快捷键),与 `Element` 分离;每个窗口独立 binding。
- `FocusBind` 把期望焦点绑定到应用数据;`FocusedValue` 读实际焦点,不依赖隐藏控件的待定请求。

### 3.4 Nim 的闭包问题

MyGo 用 `Children(func())`,Go 闭包分配在堆上但可接受。Nim 的 `proc()` 闭包若捕获局部变量会分配 env,每帧每容器一次可能成为热点。建议提供模板:

```nim
template children*(e: Element, body: untyped) =
  let prev = e.ctx.parent
  e.ctx.parent = e
  try:
    body
  finally:
    e.ctx.parent = prev
```

- 公开 API 同时支持 `children(e, body)` 模板和 `children(e, proc() = ...)` 重载,后者用于动态构造。
- 不强制用户写 `proc`。

### 3.5 Facade 生成

MyGo 用 `internal/uigen` 解析 Go AST 生成 `api_gen.go`(8,888 行),为 123 个顶层构造器和 402 个方法提供 checked wrapper。Nim 用宏更直接:

```nim
macro widget*(name: untyped, body: untyped): untyped =
  # 生成:proc name*(c: Context, ...): Element
  #       构造时 beginBuild/endBuild
  #       fluent setter 表
```

- 第一版可以手写 P0 控件;P1 起用声明表 + 宏生成 setter,避免 271 个方法散落。
- 每个 setter 生成 `proc width*(e: Element, v: float32): Element` 形式;内部 nil 安全。
- 生成代码要可读,便于调试;不要过度宏化。

---

## 4. 布局

### 4.1 单位与样式

```nim
type
  Unit = enum uAuto, uPx, uPercent
  Length = object
    value: float32
    unit: Unit

  LayoutStyle = object
    kind: NodeKind
    direction: Direction       # row/column
    wrap, reverse: bool
    justify, align, alignSelf, alignContent: Align
    gap, gapX, gapY: float32
    padTop, padRight, padBottom, padLeft: float32
    margin*: array[4, float32]
    width, height, minW, minH, maxW, maxH: Length
    grow, shrink, basis: float32
    inset: array[4, Length]    # absolute
    aspect: float32
    grid: GridStyle
    # ...
```

- `Auto = +Inf` 用于自动 margin。
- 逻辑边(start/end)与 RTL 翻转;`direction` 在布局中生效。
- 用 `float32` 做布局/绘制(与 MyGo 一致);边界转换到 `float64`。

### 4.2 Flexbox

实现 CSS flexbox 子集:

1. 收集流内子节点,跳过 absolute/hidden。
2. flex base size:`basis` → 主轴显式尺寸 → 内容内在尺寸。
3. 自动最小尺寸:内容最小尺寸(不滚动/裁剪时),与 min/max/padding 取约束。
4. 换行(如果 `wrap` 且主轴有限)。
5. 每行解析 grow/shrink + min/max clamp(迭代)。
6. 交叉轴:自然高度/`fitWidth`;`Stretch` 填满行高;`Baseline` 按 baseline 对齐。
7. `alignContent` 放置多行。
8. 放置:justify、自动 margin、reverse/RTL 翻转、`alignSelf`、相对定位。

默认:

- `Column` 交叉轴 `Stretch`。
- `Row` 默认 `AlignItems(Center)`(与 MyGo 一致)。
- `Box` 等价于 `Column`。

### 4.3 Grid

- `Track = Fixed(v) | Fr(f) | FitContent()`。
- `GridCell = (col, row, colSpan, rowSpan)`;0 自动放置;负 span 到最后一条线。
- 放置顺序:双向显式项 → 单行显式项 → 其余按游标逐行搜索。
- 轨道尺寸:每类轨道 min/max 贡献;`Fr` 在未知尺寸下按内容比例;baseline 行。
- 对齐:RTL 从右开始。
- 第一版只做固定/`Fr`/`FitContent`;命名线/auto-placement 的边角后置。

### 4.4 测量

- Text:max-content/min-content;通过 `text` 模块的 `textWidths`。
- Image/Icon:内在尺寸 + fit。
- Input:默认 200px 宽。
- List:虚拟列表在布局期构建可见行;已知/估算行高。
- 每帧缓存 `measured`,避免重复测量。
- 高度测量带小缓存(4 槽)按 `(availW, h)`。

### 4.5 布局缓存

MyGo 的关键优化:view 每帧重建,无法 mark dirty,因此比较上一帧的布局输入。

```nim
type LayoutRecord = object
  style: LayoutStyle
  flags: set[NodeFlag]
  hidden: bool
  spansKey: string
  imageSize: Size
  parentId: uint64
  index, childCount: int
  measured: Size
  box: Rect
  contentW, contentH: float32
```

- `beginLayout` 递增 generation;文本系统 generation 变化时全部重算。
- `sameLayout(a, b)`:比较 style/flags/hidden/spans/image/placeOn/parent/index/childCount/grid tracks/text 继承样式;递归比较子树。
- 布局期会改变内容的节点(List/Form/Table/Toolbar/GridFit/带 inline 的 Text/Input/Attach)禁止复用。
- 可复用时恢复 `w/h`、文本布局、content 尺寸、子节点相对 box。
- 文本双层缓存:每元素保留最近两个宽度的 layout;文本系统自身按 `Params` LRU。
- 开发/测试可关闭缓存(`-d:nimiNoLayoutCache`)。

**验收测试**:随机树 + 有/无缓存对照,结果必须一致(移植 MyGo 的 `TestLayoutCacheMatches` 思路)。

---

## 5. 绘制与场景

### 5.1 绘制流程

`paint` 遍历元素,按绘制顺序:

1. hidden/lift 过滤;保存/恢复 transform/inline/theme。
2. `styleFn` / 颜色 transition。
3. `invisible`/背向 3D 跳过。
4. inline 文本。
5. `clip`(ClipInset/mask)push。
6. effect/blur/cache layer。
7. 透明度:disabled ×0.5、`opacity`、pose fade。
8. 外阴影 → 背景/边框 → WebView hole → 内阴影。
9. `draw` 回调(自定义绘制)。
10. 按 kind:Text/Image/Icon/Input。
11. 子节点:流内 → 绝对 → ghosts → matches。
12. divider、debug、滚动条、边框、`drawOver`、focus ring。

### 5.2 Scene IR

```nim
type
  SceneKind = enum
    skFill, skShadow, skGlyphs, skImage, skPushClip, skPopClip, skEffect, skHole

  Op = object
    kind: SceneKind
    rect: Rect
    transform: Affine
    radii: array[4, float32]
    continuous: bool
    paint: Paint
    color, color2: Color
    gradient: array[4, float32]
    border: array[4, float32]
    dashed: bool
    inset: bool
    blur: float32
    cast: Rect
    castRadii: array[4, float32]
    stops: Slice[int32]
    image: ImageId
    src: Rect
    opacity: float32
    wide: bool

  Glyph = object
    u, v, uw, vh: float32
    x, y, w, h: float32
    color: Color
    wide, colored, subpixel, thin: bool
    transform: Affine

  Scene = object
    width, height, scale, zoom: float32
    clear, background: Color
    ops: seq[Op]
    glyphs: seq[Glyph]
    stops: seq[Stop]
    effects: seq[Effect]
    maskAtlas, colorAtlas: Atlas
    images: Table[ImageId, Image]
    drawn: seq[Rect]
```

- **当前切片**:`scene/scene.nim` 已实现 `opRect`、`opText`、`opClip`/
  `opRestore`、`opImage`、`opImageQuad`、`opPolygon`;上表是目标 IR,尚未
  实现 glyph atlas、gradient、shadow、effect、damage。
- `Op` 用 variant object 或固定字段 + `case kind`;为了 damage diff,字段尽量是值类型。
- `Image` 用 ID + version,渲染器按 version 上传。
- `Atlas`:mask(1B/px)/color(4B/px);shelf 分配;transient 区;generation/version;`MaxAtlasSize=4096`。
- `Differ`:逐 op 比较;第一版可不做,但 IR 要可比较。

### 5.3 CPU raster

第一阶段可直接用 CoreGraphics 画到 `CGBitmapContext`;但要保留 `scene` IR,以便:

- headless/Tester 用独立 raster;
- Linux/Windows 用可移植 raster;
- 后续切 Metal 时行为一致。

可移植 raster 的最小集:

- 圆角矩形填充/边框(SDF 覆盖率)。
- 文本 glyph(从 atlas 采样)。
- push/pop clip(矩形 + 圆角)。
- 图片(双线性/最近邻)。
- 阴影(高斯近似)。
- 渐变(线性/径向/stops)。
- damage(整帧先;后续按矩形)。

### 5.4 渲染器接口

```nim
type
  Renderer* = ref object of RootObj
    method beginFrame*(r: Renderer, s: Surface, size: Size, scale: float32)
    method draw*(r: Renderer, scene: Scene)
    method endFrame*(r: Renderer)
    method present*(r: Renderer)
    method release*(r: Renderer)
```

- `cg`(macOS CPU)、`raster`(可移植 CPU)、`metal`、`gl`、`d3d11`。
- **当前切片**:`core/content.nim` 提供 `SceneRenderer` 注入点,
  `core/app.nim` 安装 `drawScene`;`render/metal.nim` 目前是碎纸专用
  mask/LayerEffect 渲染器,不是上述通用 `Renderer` 接口的完整实现。
- UI 层不直接 import 具体渲染器;由窗口 host 按平台/可用性选择。
- GPU 失败 → CPU 回退;连续失败指数退避;软件 GPU 可降级。

### 5.5 主题与颜色

- 主题 token:背景、表面、文本、次要文本、强调色、圆角、间距、字号、动画时长。
- 明暗跟随系统;`theme.isDark`、`theme.preferences`(accent/reduceMotion/reduceTransparency/highContrast/textScale)。
- 颜色:sRGB 基准;P3/wide color 用 `WideColors`;渐变用 Oklab(可选)。
- 禁用态透明度 ×0.5(与 MyGo 一致)。

---

## 6. 文本

### 6.1 职责划分

| 层 | 职责 |
|---|---|
| 平台引擎(CoreText/DirectWrite/Pango) | 字体选择、shaping、断行、glyph 栅格化 |
| Nimi `text/layout` | 段落/行/run 模型、对齐、justify、ellipsis、balance、缩进 |
| Nimi `text/caret` | caret 位置、移动、selection ranges、affinity |
| Nimi `ui` 文本控件 | 文本缓冲、编辑、撤销、IME、滚动 |

### 6.2 数据模型

```nim
type
  Style = object
    family: string
    size, weight: float32
    italic: bool
    lineHeight, letterSpacing: float32
    features: string
    lang: string

  Glyph = object
    font: FontId
    id: uint32
    size: float32
    x, y, advance: float32
    cluster: int32
    runes: Slice[int32]
    rtl: bool

  Line = object
    rect: Rect
    baseline, ascent, descent: float32
    runes: Slice[int32]
    rtl: bool
    glyphs: seq[Glyph]
    caretStops: seq[CaretStop]

  Layout = object
    params: Params
    runes: seq[Rune]
    lines: seq[Line]
    width, height: float32
    truncated: bool
```

- `Params` 包含文本、样式、spans、宽度、对齐、wrap、ellipsis、maxLines、lang、direction;用作缓存 key。
- `LayoutFrom` 旧宽度复用:若没有换行且新宽度仍容纳,只重新对齐,不重新 shape。
- 缓存:LRU + 内存预算;每元素 `heldText` 保留最近两个宽度。
- 字体 generation 变化时,UI 布局缓存全部失效。

### 6.3 平台实现

| 平台 | 方案 |
|---|---|
| macOS | `CTTypesetter` + `CTTypesetterSuggestLineBreak` + `CTLine`;字体回退用 `kCTFontCascadeListAttribute`;语言属性影响 Han 字形 |
| Windows | `IDWriteTextLayout` + `IDWriteTextRenderer`;RTL reading direction |
| Linux | Pango layout + `PangoGlyphItem`;补回行尾空格 advance |
| wasm(后续) | canvas `measureText` + go-text 的 segmenter/bidi |

**不要**自己逐字符测量;kerning、连字、复杂脚本、bidi 都会错。

### 6.4 Glyph 栅格化与 atlas

- 普通字体:8-bit alpha-only bitmap;彩色字体/emoji:BGRA 预乘。
- 按 `(font, glyph id, scale, subpixel x, shade, subpixel)` 缓存。
- 亚像素位置量化:CoreText 最多 5 个位置/像素,大字号 1 个;DirectWrite ClearType 有 gamma/contrast。
- atlas 满时:保留本帧使用的 glyph,repack/grow;失败则清空重排;paint 最多重画 2 次。
- `BeginFrame`/`EndFrame` 管理 transient;240 帧未用的 layout/font 淘汰。

### 6.5 编辑与 IME

- 文本缓冲:第一版用 `string`/`seq[Rune]`;大文档用 rope(后续)。
- 编辑器状态:buffer、graphemes、selection、compose、undo/redo、password 映射、value 指针。
- 每次 build 把 `*value` 同步进 buffer;编辑排队应用。
- 单行:`layoutInput` 维护 `scrollX` 使 caret 可见。
- 多行:只布局可见段落,估算其余高度。
- IME:实现 `TextInputClient` 风格的 UTF-16 查询接口;`Surface.setTextInput` 开关;composition 事件带 Replace/From/To。
- 第一版必须支持中文/日文 IME(目标用户);不要把它推到 P2。

### 6.6 富文本

- `RichText(c, spans)` 只显示:把 spans 拼成文本 + 编码样式 key;绘制时逐 span 颜色/背景/下划线。
- `ui/richtext` 可编辑富文本后置(P2);`ui/markdown`、`ui/editor` 后置。
- `ui/editor`(16.7k)是代码编辑器,建立在公开 UI API 上,不是内核;Nim 第一版不做,保留接口。

---

## 7. 输入、焦点与滚动

### 7.1 指针

- 入口:`engine.event(surfaceEvent)`,DIP → 内容坐标。
- `hitChain`:已提交的命中列表,按绘制顺序,后绘制者在上。
- `pointerDown`:hover、焦点切换、滚动条、菜单按钮、拖窗、按下状态、双击计数、文本选择。
- `pointerUp`:click/drag-end。
- `clicked`/`hovered`/`pressed`/`focused`/`dragged` 查询。

### 7.2 键盘

顺序:

1. 物理键位映射。
2. Inspector(开发)。
3. Escape 取消拖拽。
4. 自定义 `handleInput`。
5. `onTextKey`。
6. 上下文菜单键。
7. Editor/文本选择键。
8. Type-select(列表)。
9. 焦点组。
10. Tab。
11. 菜单按钮。
12. 按钮/链接的 Enter/Space。
13. 滚动键。
14. 作为快捷键留给下一次 build pass。

### 7.3 焦点

- Tab 顺序按树顺序 + `tabIndex`;隐藏控件不参与。
- 焦点环绘制在 `drawOver` 之后。
- `FocusBind` 使应用数据与焦点同步;`FocusedValue` 读实际焦点。
- 弹窗/模态限制焦点范围。

### 7.4 滚动

- 滚轮/触摸板:精确/非精确、惯性;鼠标滚轮 40 DIP/行。
- 滚动容器记录 `scrollX/Y`、内容尺寸、可见区域;布局时主轴/交叉轴传 `inf` 测量内容。
- 滚动条:自动隐藏、insets、可定制。
- 虚拟列表:只构建可见行;行高已知/估算;百万行不随行数增长内存。

### 7.5 快捷键

- 移植 MyGo `internal/accelerator`:解析 `CmdOrCtrl+Shift+K`,修饰键规范化,XKB/XDG 映射。
- `Context.shortcut(mods, key)` 在一次 build pass 内查询。
- 菜单 accelerator 与 UI 快捷键共用解析器。

---

## 8. 可访问性

- 每帧生成 `AccessTree`:pre-order 节点,字段:
  - `id, parent, role, label, value, description, placeholder`
  - `bounds`、`enabled/checked/expanded/selected/busy/readonly`
  - `min/max/now/step`、`selStart/selEnd`、`level`、`current`
  - `actions`、`announcements`
- `AccessAction` 回到 UI,按指针/键盘等价操作执行。
- 隐藏/忽略输入的节点:不进命中/Tab,但可保留在树中(取决于 `AccessHidden`/`IgnoreInput`)。
- 弹窗打开时只暴露 modal 层及以上。
- 第一版:role/label/value/bounds/action/announcement;表格/树/active descendant 后置。
- 平台桥:NSAccessibility(macOS)、ATK/AT-SPI(Linux)、UI Automation(Windows)。

---

## 9. 控件清单与优先级

### 9.1 全量分类(MyGo 当前 123 个顶层入口 / 402 个方法)

| 类别 | 控件 |
|---|---|
| 布局/容器 | Box, Column, Row, Spacer, Divider, Scroll, ScrollHorizontal, ScrollBoth, Grid, Split, SplitVertical, SplitPercent, SplitVerticalPercent, Toolbar, Themed, Overlay, Modal, Popover, PopoverBase |
| 表单/结构 | Form, Field, Fieldset, Tabs, TabsBase, Segmented, SegmentedBase, Collapsible, CollapsibleBase, Accordion, AccordionBase, AccordionItem, Sidebar, SidebarSection, SidebarItem, Tree, TreeBase, TreeItem |
| 动作/选择 | Button, PrimaryButton, Link, MenuButton, PopoverMenuButton, MenuBase, ContextMenuBase, Toggle, ToggleBase, ToggleGroup, Checkbox, CheckboxBase, CheckboxState, CheckboxStateBase, CheckboxGroup, Switch, SwitchBase, Radio, RadioBase, RadioGroup, Select, SelectBase, Combobox, ComboboxBase, Autocomplete, SearchField, TokenField |
| 数值/状态 | Slider, StepSlider, SliderBase, RangeSlider, Stepper, Rating, Progress, Spinner, Meter, Badge, Avatar, Breadcrumbs, AlertDialog |
| 文本 | Text, Textf, RichText, TextInput, TextArea, TextInputBase, TextAreaBase, TextInputBuffer, TextAreaBuffer, NumberInput, DecimalInput, DateInput, TimeInput, Calendar, ColorPicker, ColorWell, EditableText, FindBar |
| 集合 | List, Table, Tree, Outline, OutlineTable, GridView |
| 媒体 | Image, Icon, Video, WebView |
| 基础设施 | View, Render, NewTester, Local, DragOver, Drop, DropData, DataDragOver |

### 9.2 P0(第一个垂直切片)

- `Box/Column/Row/Spacer/Divider`
- `Width/Height/Fill/Grow/Padding/Gap/Align/Justify/Margin`
- `Scroll`(纵向)
- `Text/Textf`(单一样式、换行、ellipsis)
- `Button/PrimaryButton`
- `Checkbox/Radio/Switch`
- `TextInput`(单行、caret、selection、剪贴板、基础 IME)
- 主题:浅/深、spacing/fontSize/radius/accent
- `Tester` + `Render` + golden

### 9.3 P1(应用可用)

- `List`(虚拟化)、`ScrollBoth`、`Grid`
- `Toggle/ToggleGroup/RadioGroup/CheckboxGroup`
- `Tabs/Segmented/Select`
- `Tooltip`
- `Popover/Modal/Overlay/MenuButton`
- `Image/Icon(SVG)`
- `Spinner/Progress/Meter/Badge/Avatar`
- `Form/Field/Fieldset`
- `Split/Toolbar/Sidebar`
- `Collapsible/Accordion`
- `Combobox/SearchField/Autocomplete/TokenField`
- `Stepper/RangeSlider/Rating`
- `NumberInput/DecimalInput/DateInput/TimeInput/Calendar/ColorPicker`
- `Table/Tree/GridView`
- `Router/RichText/Toast/AlertDialog`
- 基础无障碍 + IME
- Transition/Animation(P1 末尾)

### 9.4 P2(后置)

- `Outline/OutlineTable/Breadcrumbs/ColorWell/EditableText/FindBar`
- `Video/GIF/WebView`
- `ui/editor`、`ui/richtext`、`ui/markdown`、`ui/chart`
- shader 效果、blur/backdrop、Material/vibrancy、宽色域
- Inspector、automation、拖放数据
- Motion/Timeline/Morph/ContentTransition/Exit transition/Match
- RTL 完善
- 高级无障碍(表格行、active descendant、announcement)

### 9.5 控件实现模板

每个控件至少包含:

1. 构造器:`proc button*(c: Context, labelText: string): Element`
2. base 变体(可复用外观):`proc buttonBase*(c: Context): Element`
3. 状态查询:`clicked(e)`, `hovered(e)`, `focused(e)`
4. 样式 setter:由宏/手写生成,返回 `Element`
5. 输入处理:pointer/keyboard/IME
6. 绘制:背景/边框/文本/图标
7. 无障碍:role/label/value/actions
8. 测试:至少一个 Tester 行为测试

---

## 10. Tester 与测试

### 10.1 Headless host

`Tester` 实现 `host` 接口:

- 内存尺寸/scale;确定性时钟。
- 离屏 raster;剪贴板/IME/无障碍/菜单/WebView 占位。
- `settle`:最多 20 帧直到 view 不再请求。
- `advance(d)`:按虚拟时间运行到期帧。

### 10.2 查询能力

- `click`/`clickAt`/`rightClick`/`press`/`release`
- `wheel`/`scroll`/`pinch`
- `key`/`type`/`compose`/`command`
- `menu`/`chooseMenuItem`
- `setSize`/`setScale`/`setZoom`/`setDark`/`setLocale`/`setDirection`
- `texts`/`hasText`/`find`/`focused`/`cursor`
- `clipboard`/`openedURLs`/`announcements`/`image`/`framePending`

- 按文本/标签查找控件;中心点必须命中该控件,避免被遮挡的假阳性。
- 点击/输入后自动 `settle`。

### 10.3 黄金测试

- `render(view, w, h, scale)` → PNG。
- 像素 diff;允许字体/平台的微小差异(阈值/感知 diff)。
- 每个 P0 控件至少一张 golden;主题明暗各一张。
- 文本 golden 要固定字体/语言,避免 CI 差异。

### 10.4 性能测试

| 指标 | 目标 |
|---|---|
| 空闲 CPU | ≈0%;不请求帧 |
| 点击→重绘 | 1 帧内(<16.7ms @60Hz) |
| 1000 个静态标签 | CPU 单核 <2ms/帧(初版可放宽) |
| 百万行列表 | 内存不随行数增长;滚动 60fps |
| 窗口关闭 | 无泄漏、无僵尸线程 |
| 启动时间 | <100ms(不含 webview) |

- 用 `Tester` 的计数/虚拟时钟,不依赖 wall clock。
- 真实窗口用 `internal/inputlatency` 等价物测输入→屏幕延迟。

---

## 11. 实现顺序(与路线图对齐)

| 阶段 | 内容 | 验收 |
|---|---|---|
| U0 | `Context/Element/arena/state`;Box/Column/Row;布局;scene;CPU fill/clip | 嵌套盒子正确;单元测试 |
| U1 | CoreText text;Text 换行;glyph atlas;CPU glyph | 多语言 golden |
| U2 | Button/Checkbox/Radio/Switch;hover/press/click;焦点/Tab;Tester | counter + 行为测试 |
| U3 | TextInput/TextArea;剪贴板;IME;Scroll | 表单可用;中文输入 |
| U4 | List 虚拟化;Theme;Image/Icon;Popover/Modal | 千行列表;主题切换 |
| U5 | P1 控件批量;无障碍;动画 | gallery 子集 |
| U6 | Metal 后端;damage;宽色域 | CPU/GPU 一致;60/120fps |
| U7 | 编辑器/富文本/Markdown/Chart | code-editor 子集 |

---

## 12. Nim 实现要点与坑

### 12.1 arena

- **不要**用 `ptr Node` 指向 `seq[Node]` 元素;扩容会移动。用 chunked `seq[seq[Node]]` 或索引。
- `Node` 含 string/seq/closure;每 pass 重置会触发析构。把热字段做成 POD,冷字段旁路表。
- `used`/`epoch` 用 `uint32`;generation 回绕前退役 owner(实际不可达)。
- `finish` 回收未引用节点;保留一个空 chunk。

### 12.2 闭包

- 公开 API 优先模板(`children(e, body)`),避免每帧闭包分配。
- 必须用 `proc` 时,尽量不捕获大对象;捕获 `Context`/`Element` 是小值。
- `defer` 用 `try/finally`;异常路径必须恢复 parent/depth。

### 12.3 布局

- 用 `float32`;`float64` 只在边界。
- 比较式缓存要逐字段;不要依赖 `==` 自动派生(string/seq 字段要显式比较)。
- 文本 width 用 `ceil`/`round` 与 CoreText 对齐;caret 位置用 `float32`。

### 12.4 文本

- CoreText 的 range 是 UTF-16;Nim 内部 UTF-8/rune;显式转换。
- 字体回退要设置 cascade list;否则中文/emoji 可能落到错误字体。
- glyph atlas 要在窗口 scale 变化时重建;P3/宽色域影响 color atlas。
- 文本缓存按 `Params` 哈希;哈希要稳定,避免每帧字符串拼接。

### 12.5 渲染

- CPU 先;Metal 后。scene IR 不要绑定 Metal 类型。
- GPU 管线创建不在首帧;预编译 metallib;general 回退。
- `nextDrawable` 不在主线程;presenter 线程。
- 窗口关闭时停 link、释放 drawable/纹理、移除 observer。

### 12.6 状态与生命周期

- `Element` 零值安全;旧句柄不别名;窗口关闭后失效。
- `Handle` 与 `Element` 分离;焦点/测试用 `Handle`。
- 菜单项/tray/通知用整数 ID + 显式表,不用弱引用。
- 动画/transition 用确定性时钟;测试可 advance。

---

## 13. 与 MyGo `ui` 的映射

| MyGo | Nimi | 说明 |
|---|---|---|
| `ui.Context` | `ui.Context` | 每窗口稳定 |
| `ui.Element` | `ui.Element` | 16 字节句柄 |
| `ui.View(view func(*Context))` | `uiView(view: proc(s: S, c: Context))` | 泛型/闭包 |
| `ui.Column(c).Fill()` | `column(c).fill()` | 小写/camelCase |
| `ui.Tester` | `Tester` | headless |
| `ui.Render` | `render` | offscreen |
| `internal/scene` | `scene` | display list |
| `internal/raster` | `render/raster` | CPU |
| `internal/gpu/metal` | `render/metal` | Metal |
| `internal/text` | `text` | 平台引擎 + layout |
| `ui/editor` | `ui/editor`(后置) | 代码编辑器 |
| `ui/richtext` | `ui/richtext`(后置) | 富文本 |
| `ui/markdown` | `ui/markdown`(后置) | Markdown |
| `ui/chart` | `ui/chart`(后置) | 图表 |

---

*本文档描述目标设计;控件 API 以 `docs/07-api-mapping.md` 为准,实施顺序以 `docs/05-roadmap.md` 为准。*
