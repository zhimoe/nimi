# M6 切片:ScrollView

> 日期:2026-11-05 · 对应 M6 滚动/裁剪

---

## 1. 已完成

- `ui.scrollView(c, key, height)`:
  - 固定高度 viewport
  - 垂直滚动 offset 存在 `Engine.scrollOffsets[key]`
  - 内容高度超过 viewport 时自动 clamp
- Scene 裁剪:
  - `opClip` / `opRestore`
  - CoreGraphics 渲染器使用 `CGContextSaveGState` / `ClipToRect` / `RestoreGState`
- 命中测试:
  - `Hit.clip` 视口裁剪
  - 滚出 viewport 的按钮不会误命中
- 事件:
  - macOS `scrollWheel:` → `SurfaceHandler.scroll(x, y, dy)`
  - `Tester.scrollAt(x, y, dy)`
- 示例 `examples/scroll-native`:40 行按钮列表,滚轮/测试滚动

## 2. 关键决策

| 决策 | 原因 |
|---|---|
| 场景层加 clip op | 渲染器和命中测试共用同一视口语义;不靠隐藏节点 |
| scroll offset 按 key 存 Engine | 视图每帧重建,offset 不丢;支持多个列表 |
| 内容先按无界高度测量 | 先知道 contentH,再 clamp offset |
| 滚动只改变子节点 y,不改布局树 | 与每帧 view 模型兼容 |
| 暂不做滚动条/惯性 | 先验证裁剪/命中/滚轮;视觉和动量后续补 |
| 命中区域带 clip 字段 | 嵌套滚动时求交集;避免滚出内容被点击 |

## 3. 验证

```sh
NIMI_SMOKE=scroll nim c -r --path:src examples/scroll-native/main.nim
# scroll rows: 40
# content height: 1040 viewport: 260
# offset: 120

./scripts/test.sh
# [OK] scroll view offsets and clips hits
```

截图确认 viewport 裁剪:只显示 Row 0–9,超出内容不绘制、不可点击。

## 4. 已知限制

- 只有垂直滚动;没有水平滚动
- 没有滚动条、滚动位置指示、惯性/回弹
- 没有 `scrollTo`/键盘 PageUp/PageDown
- 没有嵌套滚动的优先级策略(当前取最深区域)
- 没有 scroll anchoring/虚拟列表;40 行全量布局
- TextArea 自身还没有内部滚动;需放在 ScrollView 或后续做编辑器滚动
- 滚轮方向依赖自然滚动设置;需要实际设备确认

## 5. 下一步

1. 滚动条 thumb + 滚动位置/焦点自动跟随。
2. 水平滚动、`scrollTo`、键盘 PageUp/PageDown。
3. 虚拟列表/布局缓存,支持大列表。
4. TextArea 内部滚动与 caret 自动可见。
