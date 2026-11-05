# M5 切片:自定义协议与本地 FileServer

> 日期:2026-11-05 · 对应 M5 协议/FileServer 部分

---

## 1. 已完成

- `FileServer`:
  - `newFileServer(root, scheme = "nimi")`
  - 安全的路径解析:拒绝 `..`、限制在 root 内
  - 目录自动回退到 `index.html`
  - MIME 映射(HTML/CSS/JS/JSON/SVG/PNG/WOFF2/WASM 等)
  - 404 结果
- `WindowOptions.files`:窗口启动时注册自定义 scheme
- Darwin `WKURLSchemeHandler`:
  - `nimi://app/index.html` 直接加载本地文件
  - CSS/JS/字体等同 scheme 资源
  - `NSURLResponse` 使用**裸 MIME**(如 `text/html`)+ `textEncodingName: utf-8`
  - 失败通过 `didFailWithError:` 返回
- 打包资源复制:
  - `nimi.json` 的 `resources` 现在会被复制到
    `MyApp.app/Contents/Resources/<name>`
  - CLI 已重新编译后生效
- 示例 `examples/protocol-native`:
  - 页面通过 `nimi://app/` 加载
  - 页面调用 Nim `Greeter.greet`
  - `NIMI_SMOKE=protocol` 自动验证后退出
- 深链:
  - `nimi.json` 的 `urlSchemes` 写入 `Info.plist` 的 `CFBundleURLTypes`
  - NSApplication delegate `application:openURLs:` → `app.onOpenURL`
  - LaunchServices 把 `nimiprotocol://...` 路由到已运行的实例
- Session 隔离:
  - `WindowOptions.session = smPersistent | smEphemeral`
  - persistent → `WKWebsiteDataStore.defaultDataStore`
  - ephemeral → `WKWebsiteDataStore.nonPersistentDataStore`

## 2. 关键决策

| 决策 | 原因 |
|---|---|
| 自定义 scheme 默认 `nimi` | 不与 http/https 冲突;WKWebView 要求自定义 scheme handler |
| root 用 `expandFilename` 规范化后再做前缀检查 | 防止 `../` 穿越;兼容 macOS `/var` → `/private/var` |
| MIME 字段使用裸类型,编码单独传 | 把 `text/html; charset=utf-8` 放进 `MIMEType` 会让 WebKit 回退成纯文本 |
| 同步读取文件 | demo/小资源足够简单;大文件/范围请求后续改为异步/流式 |
| `resources` 由 CLI 复制到 Contents/Resources | 打包后的 app 不依赖开发目录 |
| 每个窗口一个 scheme handler | 先覆盖最常见场景;多 scheme/多 root 后续扩展 |
| 深链走 Info.plist + application:openURLs | 让 LaunchServices 负责单实例路由;无需自建锁文件 |
| Session 用 WKWebsiteDataStore 默认/非持久化 | 每个窗口独立选择;无自建 cookie 存储 |

## 3. 验证

```sh
# 源码运行
NIMI_SMOKE=protocol nim c -r --path:src examples/protocol-native/main.nim
# protocol: Hello, WKURLSchemeHandler — served through nimi:// and decoded in Nim 2.4.0

# 单元测试
nim c -r --path:src tests/test_fileserver.nim
# [OK] serves index, mime types, and blocks traversal

# 打包
./nimi build examples/protocol-native
find ".../Nimi Protocol.app/Contents/Resources"
# frontend/index.html
# frontend/style.css
# frontend/app.js

# 从 /tmp 运行 bundle 内的二进制,确认使用 Resources/frontend
cd /tmp
NIMI_SMOKE=protocol ".../Nimi Protocol.app/Contents/MacOS/Nimi Protocol"
# protocol: Hello, ...

# 深链(应用运行中)
open -b com.example.nimi-protocol "nimiprotocol://hello?from=cli"
# open url: nimiprotocol://hello?from=cli
```

实际截图确认:

- HTML/CSS/JS 通过 `nimi://` 正常渲染
- `scheme=nimi`,`path=/index.html`
- IPC 返回 `Hello, WKURLSchemeHandler ...`

## 4. 尚未完成(M5 其余)

- 自定义 scheme 的多 root/多 scheme、CORS、分块/范围请求、缓存
- SPA fallback、dev server URL、内置 VFS
- Cookie 列表/设置/删除/清空
- ClearData/站点数据清理策略 UI
- 内容规则、认证、证书错误处理
- 文件监视(FSEvents/去抖/限额)
- 文档控制器(自动保存/冲突/最近文档/退出询问)
- 启动文件/文件关联、单实例边界情况
- i18n

## 5. 下一步

1. 把 FileServer 改成异步、支持流式响应与 `Range`。
2. 增加 `WindowOptions` 的多 scheme/多 root 配置。
3. 实现 Cookie 查询/设置/清理与站点数据清理。
4. 文件监视与文档控制器优先服务真实笔记/IDE 类应用。
