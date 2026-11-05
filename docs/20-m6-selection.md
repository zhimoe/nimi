# M6 切片:选择与剪贴板

> 日期:2026-11-05 · 对应 M6 选择/copy/paste

---

## 1. 已完成

- 键盘修饰键:
  - `KeyShift/KeyControl/KeyAlt/KeyCommand`
  - Darwin `NSEvent.modifierFlags` → UI `modifiers: uint32`
- TextInput/TextArea 选择:
  - Shift + 左右/上下/Home/End 扩展选择
  - 鼠标按下/拖动设置 anchor 与 caret
  - `Cmd+A` 全选
  - 选择区绘制
- 剪贴板:
  - `Cmd+C` 复制选择
  - `Cmd+X` 剪切
  - `Cmd+V` 粘贴;单行输入会把换行替换成空格
  - Engine 通过 `clipboardRead/clipboardWrite` hook 注入平台剪贴板
- 原生菜单:
  - NimiSurfaceView 实现 `copy:/cut:/paste:/selectAll:`
  - Edit 菜单 role 在激活窗口的首响应者上生效
- Undo/Redo:
  - 每个输入控件独立 undo/redo 栈(最多 100 步)
  - `Cmd+Z` / `Shift+Cmd+Z` / `Cmd+Y`
  - 菜单 `undo:/redo:` responder 已接入
- 测试:
  - headless `Tester` 选择/copy/paste、undo/redo
  - form-native `NIMI_SMOKE=select`、`NIMI_SMOKE=undo`

## 2. 关键决策

| 决策 | 原因 |
|---|---|
| modifier 位用 `uint32` 共享常量 | 平台契约与 UI 引擎解耦;不引入枚举 set ABI |
| caret + selectionAnchor | 与常见编辑器模型一致;anchor 固定,caret 移动 |
| Engine 持有剪贴板 hook | Tester/无后端测试可注入;不把 platform 依赖塞进 UI |
| Cmd+V 单行替换换行 | 单行 TextInput 不产生多行文本 |
| 菜单使用 responder 方法 | 原生用户按键走 AppKit 菜单/首响应者链,和系统行为一致 |
| 保留直接 keyDown 路径 | 无菜单或合成事件时引擎仍能处理快捷键 |
| undo 栈按输入 key 隔离 | 多个输入框互不污染;切换焦点后仍可撤销 |
| 只在文本实际变化时记录 snapshot | 纯 caret 移动不产生 undo 噪声 |

## 3. 验证

```sh
./scripts/test.sh
# [OK] selection and clipboard

NIMI_SMOKE=select nim c -r --path:src examples/form-native/main.nim
# clipboard: hello world
# form name after paste: hello worldhello world

NIMI_SMOKE=undo nim c -r --path:src examples/form-native/main.nim
# after undo:
# after redo: hello
```

说明:菜单态 copy/paste 依赖窗口为 key window;headless 测试覆盖引擎和剪贴板 hook,
实际交互仍需在激活的 app 中验证。

## 4. 已知限制

- 没有双击选词/三击选段
- 没有拖拽文本
- 没有富文本/格式
- 自动换行处的选择区间为近似映射
- 菜单快捷键在窗口非激活/无 key window 时不会触发 responder
- 没有滚动;选择不可见区域不可选

## 5. 下一步

1. 双击选词、三击选段、拖拽移动文本。
2. ScrollView + caret 自动滚动。
3. IME/候选窗与选择区协同。
4. 富文本/格式化与命令式编辑。
