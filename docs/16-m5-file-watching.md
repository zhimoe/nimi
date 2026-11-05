# M5 切片:FSEvents 文件监视

> 日期:2026-11-05 · 对应 M5 文件监视部分

---

## 1. 已完成

- 核心 API:
  - `watch(path, fn)` 返回 `FileWatcher`
  - `FileEvent(path, kind)`,`kind` 为 `feCreated/feModified/feRemoved/feRenamed`
  - `close(watcher)`
- Darwin 后端:
  - `FSEventStreamCreate` + `kFSEventStreamCreateFlagFileEvents`
  - `FSEventStreamSetDispatchQueue` 到主队列
  - 解析 `ItemCreated/Removed/Renamed/Modified` 标志
  - 关闭时 `Stop → Invalidate → Release`
- 示例 `examples/watch-native`:
  - 文本显示监视目录、事件数、最后事件
  - "Touch file" 写入文件触发事件
  - `NIMI_SMOKE=watch` 自动写入并等待事件后退出

## 2. 关键决策

| 决策 | 原因 |
|---|---|
| 使用 FSEvents 而非轮询 | 系统级、低开销、能区分文件级事件 |
| 回调投递到主队列 | UI 状态更新无需额外线程同步 |
| 每次 watch 一个 stream | 简单、隔离;大量 watcher 可后续合并 |
| latency 0.12s | 合并短时间内的多次写入,避免 UI 抖动 |
| 目前不做去抖/过滤 | 由调用方决定;等真实文档/IDE 场景再加 |
| 事件路径为 FSEvents 返回的绝对路径 | 调用方可以自行做相对化 |

## 3. 验证

```sh
rm -rf /tmp/nimi-watch-demo
NIMI_WATCH_DIR=/tmp/nimi-watch-demo NIMI_SMOKE=watch \
  nim c -r --path:src examples/watch-native/main.nim
# watch: feCreated  /private/tmp/nimi-watch-demo/watched.txt

./scripts/test.sh
# desktop suite 包含 file watcher delegates events
```

实际截图确认 `examples/watch-native` 原生界面和目录信息。

## 4. 已知限制

- 未做递归/非递归配置;FSEvents 默认监视子树
- 未做去抖、事件合并策略、忽略规则
- 未提供同步快照/初始状态;调用方需要自己扫描
- 没有 `fsync`/原子写检测;写入中途可能收到多次 modified
- 监视路径不存在时 watcher 创建失败
- 未实现 FSEvents 历史事件持久化
- 与 App Sandbox 的路径权限需要在实际签名/沙盒配置后验证

## 5. 下一步

1. 去抖/批量事件 API,支持 `debounce(ms)`。
2. 忽略规则(`.git`、`node_modules`)与递归开关。
3. 初始快照和目录树 diff,服务文档/IDE 类应用。
4. 与文档控制器结合:外部修改冲突提示、自动重载。
