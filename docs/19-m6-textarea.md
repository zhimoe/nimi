# M6 切片:基础 TextArea

> 2026-11-06：整改、当前限制与验收级别见 [最新基线](28-remediation-status.md)。历史验证记录不代表完整能力已经验收。

> 日期:2026-11-05 · 对应 M6 多行文本编辑

---

## 1. 已完成

- `ui.textArea(c, value, onText, key, placeholder, size, height)`
- 多行文本测量/换行复用 `layoutText`
- 支持:
  - 字符输入、空格、Backspace/Delete
  - Enter 插入换行
  - 左右移动、Home/End(按行)
  - 上下移动(按行,跨换行)
  - 鼠标点击定位 caret(按行)
  - 固定高度,超出区域不绘制
- 内部滚动:
  - 滚轮/Tester.scrollAt 调整 `scrollOffsets[key]`
  - PageUp/PageDown 以 viewport 为目标滚动
  - caret 编辑后自动滚动到可见区域
  - scene clip 裁剪文本/marked text/选择区
  - 右侧滚动条 thumb 可拖动,与 ScrollView 共用 offset
- 示例 `examples/form-native` 增加 Notes TextArea,并参与保存/加载
- 冒烟:合成 AppKit 键盘事件输入 `hello` + Enter + `world`

## 2. 关键决策

| 决策 | 原因 |
|---|---|
| 复用 `nkInput` + `multiline` 标记 | 单行/多行共享输入、焦点、hits 逻辑 |
| 复用 `layoutText` 做换行 | 布局与 CoreText 绘制一致 |
| TextArea 固定 viewport 高度 + 内部滚动 | 不自动增高;长文本通过 offset 滚动 |
| caret 行/列通过 `lines` 粗略映射 | 换行文本准确;自动换行位置是近似值 |
| Enter 仅在 multiline 插入换行 | 单行 TextInput 保持原行为 |
| TextArea 内部滚动用 Engine.scrollOffsets | 与 ScrollView 共用状态;不影响文档内容 |
| caret 自动可见 | 键入/撤销/粘贴后调整 offset;鼠标点击按 offset 反算 caret |

## 3. 验证

```sh
NIMI_SMOKE=textarea nim c -r --path:src examples/form-native/main.nim
# form notes: hello
# world

./scripts/test.sh
# [OK] text area multiline typing
```

实际截图确认 Notes 区域、placeholder 和多行绘制;内部滚动测试覆盖
`scrollOffsets`、内容高度和 caret 自动可见。

## 4. 已知限制

- 没有水平滚动/惯性/滚动到行 API
- 自动换行后的 caret/选择位置是近似映射
- 没有富文本/代码高亮
- IME 为 opt-in,真实输入法仍需人工验证
- 没有 Tab 插入制表符(保持焦点切换)
- 没有视觉行号/软换行标记

## 5. 下一步

1. TextArea 内部滚动条可拖动、滚动到行。
2. 自动换行处的精确 caret/selection 映射。
3. 富文本/代码编辑器与文档模型结合。
4. 真实 IME 端到端测试。
