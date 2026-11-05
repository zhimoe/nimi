# M6 切片:基础 TextArea

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
- 示例 `examples/form-native` 增加 Notes TextArea,并参与保存/加载
- 冒烟:合成 AppKit 键盘事件输入 `hello` + Enter + `world`

## 2. 关键决策

| 决策 | 原因 |
|---|---|
| 复用 `nkInput` + `multiline` 标记 | 单行/多行共享输入、焦点、hits 逻辑 |
| 复用 `layoutText` 做换行 | 布局与 CoreText 绘制一致 |
| TextArea 固定高度 | 先不做滚动条/自动增高;后续加 scroll |
| caret 行/列通过 `lines` 粗略映射 | 换行文本准确;自动换行位置是近似值 |
| Enter 仅在 multiline 插入换行 | 单行 TextInput 保持原行为 |
| 仍无 selection/IME/scroll | 这些需要键盘修饰键与 NSTextInputClient |

## 3. 验证

```sh
NIMI_SMOKE=textarea nim c -r --path:src examples/form-native/main.nim
# form notes: hello
# world

./scripts/test.sh
# [OK] text area multiline typing
```

实际截图确认 Notes 区域、placeholder 和多行绘制。

## 4. 已知限制

- 没有选择区、Shift+方向键、复制/剪切/粘贴
- 没有撤销/重做
- 没有滚动条;内容超过固定高度时只显示前几行
- 没有 IME/候选窗;中文输入仍走单字符路径
- caret 在自动换行处的位置是近似映射
- 没有 Tab 插入制表符(保持焦点切换)
- 没有视觉行号/软换行标记

## 5. 下一步

1. 选择区 + Selection 绘制 + copy/cut/paste(需要键盘修饰键)。
2. ScrollView/滚动条与 caret 自动滚动。
3. NSTextInputClient/IME 与候选窗定位。
4. Undo/Redo 栈与文档模型结合。
