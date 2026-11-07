# M5 切片:文档控制器

> 2026-11-06：整改、当前限制与验收级别见 [最新基线](28-remediation-status.md)。历史验证记录不代表完整能力已经验收。

> 日期:2026-11-05 · 对应 M5 文档生命周期

---

## 1. 已完成

- `Document`:
  - `path`, `text`, `dirty`, `conflict`, `modifiedAt`, `fileSize`
  - `openDocument(path)` / `newDocument(path)`
  - `setText`, `save`, `reload`, `close`
  - `onChanged` / `onConflict` / `onSaved`
- 外部变更:
  - 通过 FSEvents 监视文档所在目录
  - `checkExternal()` 比较 mtime + size
  - 未修改 → 自动 reload;有未保存修改 → conflict 事件
- 示例 `examples/document-native`:
  - TextArea 编辑
  - Save / Reload
  - 外部修改与冲突提示
- 测试 `tests/test_document.nim`:
  - open/edit/save/reload
  - external conflict
  - new document save

## 2. 关键决策

| 决策 | 原因 |
|---|---|
| 监视父目录而不是文件本身 | 原子替换/重命名时文件 inode 会变化 |
| mtime + size 判断变化 | 简单、跨文件系统;内容哈希后续再加 |
| dirty 时只报 conflict,不覆盖 | 不丢用户未保存内容 |
| 保存成功清除 conflict | 本地保存后用户已明确覆盖外部版本 |
| UI 状态留给应用 | TextArea/菜单/退出询问由 app 组合 |
| 暂无自动保存定时器 | 需要与主循环/失焦/退出策略一起设计 |

## 3. 验证

```sh
NIMI_DOC_PATH=/tmp/nimi-document-demo.txt NIMI_SMOKE=document \
  nim c -r --path:src examples/document-native/main.nim
# document saved: true
# document text: # Smoke /  / line two
# dirty: false conflict: false

./scripts/test.sh
# [OK] open, edit, save, reload
# [OK] external conflict detection
# [OK] new document save
```

## 4. 已知限制

- 没有自动保存定时器/失焦保存/退出询问
- 没有最近文档列表/恢复会话
- 没有原子写/备份/版本历史
- 冲突只通知,不提供 diff/合并 UI
- 外部删除文件时目前不会自动清空文档(后续补)
- 监视父目录会收到大量事件,尚未按路径过滤优化
- 没有文件关联/文档类型/窗口标题绑定

## 5. 下一步

1. 自动保存策略(debounce、失焦、退出前询问)。
2. 最近文档持久化 + File 菜单 role。
3. 原子写、备份、版本历史。
4. 冲突 diff/合并界面与文档类型注册。
