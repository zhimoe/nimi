# M5 切片:WebView Cookie 访问

> 2026-11-06：整改、当前限制与验收级别见 [最新基线](28-remediation-status.md)。历史验证记录不代表完整能力已经验收。

> 日期:2026-11-05 · 对应 M5 Cookie 部分

---

## 1. 已完成

- 核心 API:
  - `cookies(fn: proc(cookies: seq[Cookie]))`
  - `clearCookies(fn: proc() = nil)`
  - `Cookie` 字段:`name/value/domain/path/secure/httpOnly`
- Darwin 后端:
  - `WKWebsiteDataStore.defaultDataStore.httpCookieStore`
  - `getAllCookies:` 全局 Objective-C block
  - `removeDataOfTypes:modifiedSince:completionHandler:` 清理 cookies
  - 回调在主队列执行

## 2. 关键决策

| 决策 | 原因 |
|---|---|
| 异步回调而不是阻塞 | WKHTTPCookieStore 的 completion 是异步的;阻塞主线程会死锁 |
| 先用全局 block | 不需要捕获;当前只保留一个 pending 查询/清理回调 |
| 暂时只覆盖默认数据存储 | 临时 Session 的 non-persistent store 需要把 store 句柄暴露到窗口/会话层 |
| 清理使用默认 store 的 cookies 类型 | 与 getter 对齐;站点数据完整清理后续扩展 |
| 不提供 setCookie | 页面可以通过 `document.cookie` 写入;HTTP-only 需要后续原生 setter |

## 3. 验证

```sh
# 空 cookie 集合 + 清理
nim c -r --path:src /tmp/cookie_test.nim
# cookies: 0
# cookies cleared
```

`./scripts/test.sh` 中的 `cookie delegates` 验证核心层映射。

## 4. 已知限制

- 只查询默认 `WKWebsiteDataStore`;临时 Session 不可查
- 同一时间只支持一个 pending cookie 查询/清理;并发调用会覆盖回调
- 没有 `setCookie/deleteCookie/addObserver`
- 没有按 URL/domain 过滤;调用方拿到全部 cookies 后自行筛选
- 没有站点数据清理 UI/策略
- HTTP-only/secure 只读展示,不能通过 API 写入

## 5. 下一步

1. 把 data store 句柄放进 `Session` 对象,支持 per-window cookies。
2. `setCookie/deleteCookie` 与 completion 回调。
3. 并发请求队列化,而不是单一 pending 回调。
4. 站点数据清理 API 与设置界面。
