# M6 切片:IME(NSTextInputClient)

> 2026-11-06：整改、当前限制与验收级别见 [最新基线](28-remediation-status.md)。历史验证记录不代表完整能力已经验收。

> 日期:2026-11-05 · 对应 M6 输入法支持

---

## 1. 已完成

- `WindowOptions.ime = true` 开启原生 IME 路径
- NimiSurfaceView 实现 NSTextInputClient 核心方法:
  - `insertText:replacementRange:`
  - `setMarkedText:selectedRange:replacementRange:`
  - `unmarkText`
  - `hasMarkedText` / `markedRange` / `selectedRange`
  - `attributedSubstringForProposedRange:actualRange:`(返回 nil)
  - `validAttributesForMarkedText`(空数组)
  - `firstRectForCharacterRange:actualRange:`(caret 位置 → 屏幕坐标)
  - `characterIndexForPoint:`
  - `doCommandBySelector:`
- NSTextInputContext 缓存
- UI:
  - `insertText`、`setMarkedText`、`unmarkText`
  - marked text 覆盖绘制 + 下划线
  - `caretRect()` 供候选窗定位
  - doCommand 选择器映射到方向/删除/回车/Tab/剪贴板/undo
- 安全回退:
  - 若 `interpretKeyEvents` 没有任何客户端回调,回退到原 `keyDown` 路径
  - 合成事件/非 IME 键仍可用;真实输入法走 IME
- 示例 `examples/form-native`、`examples/document-native` 开启 `ime = true`

## 2. 关键决策

| 决策 | 原因 |
|---|---|
| IME 作为 opt-in `WindowOptions.ime` | 不破坏现有原生控件的原始键盘路径 |
| 提供 `inputContext` | `interpretKeyEvents` 需要 NSTextInputContext 才能分发 |
| 回调 + fallback | 合成事件或未映射 selector 不丢键 |
| marked text 不直接写入文档 | 组合期间不触发 onText/undo;提交时 insertText |
| candidate rect 使用 caretRect + AppKit 坐标转换 | 候选窗跟随光标 |
| `selectedRange`/`markedRange` 先返回近似范围 | 先保证组合/提交路径;精确编辑语义后续补 |

## 3. 验证

```sh
NIMI_SMOKE=type nim c -r --path:src examples/form-native/main.nim
# form name: Ada

NIMI_SMOKE=textarea nim c -r --path:src examples/form-native/main.nim
# form notes: hello
# world
```

- 合成事件路径通过 fallback 验证
- 真实中文/日文输入法需要在桌面会话中人工确认:
  - 组合文本是否显示
  - 候选窗是否跟随 caret
  - 回车/选词后是否正确提交
  - Escape 是否正确取消组合

## 4. 已知限制

- 未在真实拼音/日文输入法下完成端到端人工验证
- `selectedRange`/`markedRange` 为近似值;复杂组合/替换范围未完整支持
- `attributedSubstringForProposedRange:` 返回 nil;某些输入法可能依赖富文本上下文
- `characterIndexForPoint:` 返回 0;鼠标选词在组合态下不完整
- marked text 覆盖绘制,但没有做换行宽度/滚动跟随
- 没有 IME 候选窗主题/位置微调
- 没有语音/手写/表情等特殊输入源测试

## 5. 下一步

1. 真实 macOS 输入法人工测试矩阵:拼音、双拼、日文、表情。
2. 精确 `selectedRange`/`markedRange` 与 replacementRange 语义。
3. marked text 的换行/滚动/caret 跟随。
4. 可访问性(NSAccessibility)与 IME 组合状态协同。
