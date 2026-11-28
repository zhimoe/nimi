# M5 切片:WebView Cookie 访问

> 三平台均提供默认 WebView Cookie store 查询与清理。[Windows](32-windows-framework.md) 与 [Linux](33-linux-framework.md) 文档记录各自测试。

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
| Darwin 请求串行排队 | 查询和清理共用一个队列，完成后交付回调再执行下一项 |
| 暂时只覆盖默认数据存储 | 临时 Session 的 non-persistent store 需要把 store 句柄暴露到窗口/会话层 |
| 清理使用默认 store 的 cookies 类型 | 与 getter 对齐;站点数据完整清理后续扩展 |
| 不提供 setCookie | 页面可以通过 `document.cookie` 写入;HTTP-only 需要后续原生 setter |

## 3. 验证

运行 `./scripts/test.sh`，其中 `cookie delegates` 验证共享层映射。
Linux 的 `test_linux_webview` 覆盖真实默认 store 的查询、清理和临时会话，
Windows 的 `test_windows_webview_protocol` 覆盖 WebView2 默认 store。

## 4. 已知限制

- API 使用各后端的默认 Cookie store，临时 Session 不在查询范围。
- 没有 `setCookie/deleteCookie/addObserver`
- 没有按 URL/domain 过滤;调用方拿到全部 cookies 后自行筛选
- 没有站点数据清理 UI/策略
- HTTP-only/secure 只读展示,不能通过 API 写入

## 5. 下一步

1. 把 data store 句柄放进 `Session` 对象,支持 per-window cookies。
2. `setCookie/deleteCookie` 与 completion 回调。
3. 验证 WKWebView 默认 store 的多请求顺序和退出期间回调。
4. 站点数据清理 API 与设置界面。
