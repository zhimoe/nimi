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
  - `attributedSubstringForProposedRange:actualRange:`(返回 NSAttributedString)
  - `validAttributesForMarkedText`(空数组)
  - `firstRectForCharacterRange:actualRange:`(caret 位置 → 屏幕坐标)
  - `characterIndexForPoint:`
  - `doCommandBySelector:`
- NSTextInputContext 缓存
- UI:
  - `insertText`、`setMarkedText`、`unmarkText`
  - `TextRange` 使用 UTF-16 offset,并在 UI 内转换为 UTF-8 byte offset
  - `replacementRange` 在提交和组合替换时生效
  - `markedRange`/`selectedRange` 返回组合文本在文档中的真实位置
  - `attributedSubstringForProposedRange` 返回组合中的显示文本
  - `characterIndexForPoint` 映射到 UTF-16 索引
  - marked text 参与排版、换行、滚动跟随和候选窗定位
  - grapheme cluster 光标移动/删除/命中测试(UAX #29 子集)
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
| 用虚拟显示文本映射组合区 | 文档保持不变,但排版、滚动、range 查询都基于“文档 + marked text” |
| candidate rect 使用 caretRect + AppKit 坐标转换 | 候选窗跟随光标 |
| `selectedRange`/`markedRange` 使用真实 UTF-16 范围 | 输入法可正确替换组合文本和定位候选窗 |

## 3. 验证

```sh
NIMI_SMOKE=type nim c -r --path:src examples/form-native/main.nim
# form name: Ada

NIMI_SMOKE=textarea nim c -r --path:src examples/form-native/main.nim
# form notes: hello
# world

nim c -r --hints:off --path:src tests/test_unicode.nim
nim c -r --hints:off --path:src tests/test_ime.nim

# 人工输入法验收时打开候选/提交/组合日志:
nim c -r -d:nimiImeDebug --path:src examples/form-native/main.nim
```

- 合成事件路径通过 fallback 验证
- 合成 IME 序列覆盖:组合显示、提交替换、selection 替换、replacementRange、
  markedRange/selectedRange、UTF-16 emoji 范围、换行与滚动跟随、取消组合
- 真实中文/日文输入法仍需在桌面会话中人工确认:
  - 组合文本是否显示
  - 候选窗是否跟随 caret
  - 回车/选词后是否正确提交
  - Escape 是否正确取消组合
  - 连续重转换/替换选中文本是否与原生控件一致

## 4. 已知限制

- 未在真实拼音/日文输入法下完成端到端人工验证
- UAX #29 是实用子集,不是完整 Unicode 属性表;罕见文字/预置字符可能仍按码点切分
- 组合区与远端输入法的复杂重转换语义只覆盖常见 replace 路径
- `attributedSubstringForProposedRange:` 返回纯文本属性,不提供富文本上下文
- 没有 IME 候选窗主题/位置微调
- 没有语音/手写/表情等特殊输入源测试

## 5. 下一步

1. 真实 macOS 输入法人工测试矩阵:拼音、双拼、日文、表情。
2. 根据人工测试补齐罕见 grapheme 属性和重转换边界。
3. 可访问性(NSAccessibility)与 IME 组合状态协同。
