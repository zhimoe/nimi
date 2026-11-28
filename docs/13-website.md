# 官网与 GitHub Pages

> 更新于 2026-11-24。源目录 `site/`，官网域名 `nimi.zhi.moe`。

---

## 1. 目标

- 一个不依赖前端框架的静态官网,直接由 GitHub Pages 托管。
- 首页介绍 Nimi、Nim 语言优势、框架能力、三平台 Preview 状态和 Nimi Notes 截图。
- `docs.html` 提供 macOS/Linux 和 Windows PowerShell 快速开始、平台打包输出、IPC、原生 UI、示例与完整文档入口。
- 未完成项与平台差距不放在首页，统一链接到 `docs/backlog/`。
- 使用自定义域名 `https://nimi.zhi.moe/`;同时保留
  `https://zhimoe.github.io/nimi/` 作为 GitHub Pages 默认地址。

## 2. 站点结构

```text
site/
├── index.html          # 首页
├── docs.html           # 快速文档
├── styles.css          # 暗色主题、响应式布局
├── main.js             # 导航、滚动 reveal、复制按钮
├── CNAME               # nimi.zhi.moe
├── .nojekyll
├── robots.txt
├── sitemap.xml
├── 404.html
└── assets/
    ├── icon.png        # 应用图标
    ├── icon.svg
    ├── nimi-notes.png  # Nimi Notes 实际窗口截图
    └── fonts/          # Bricolage Grotesque(自托管,OFL)
```

没有构建步骤。GitHub Actions 直接把 `site/` 上传为 Pages artifact。

## 3. 内容决策

| 决策 | 原因 |
|---|---|
| 纯静态 HTML/CSS/JS | GitHub Pages 零依赖;不需要 Node 构建链 |
| 暗色暖色主题 | 与 Nimi Notes 应用视觉一致 |
| 首页先用 Nimi Notes 截图 | 用真实应用证明框架可用,而不是只放抽象图形 |
| “为什么 Nim”独立章节 | 明确项目不是 Go 兼容层,而是选择 Nim 的执行模型与 FFI |
| 首页只展示 Preview 能力 | 未完成项集中到 `docs/backlog/`，避免首页堆叠“待补/剩余”状态 |
| 标题英文使用 Bricolage Grotesque | 品牌/标题更有辨识度;中文自动回退到系统中文字体 |
| 字体自托管,不请求 Google Fonts | 无第三方请求、无隐私/可用性依赖;OFL 允许分发 |
| 文档链接指向 GitHub markdown | 文档持续更新,不在站点重复维护全文 |
| 自定义域名 + CNAME 文件 | Pages 设置与 artifact 都携带域名;便于迁移 |

## 4. 本地预览

```sh
python3 -m http.server 8765 --directory site
open http://127.0.0.1:8765/
```

截图/打印时可加 `?reveal=1`,让所有滚动 reveal 元素直接显示:

```text
http://127.0.0.1:8765/?reveal=1
```

## 5. 源码与线上版本

- 首页代码可单独编译，Notes 截图保留 macOS 来源说明。
- 文档页连接 [平台能力与 CI](28-remediation-status.md)、[当前执行计划](05-roadmap.md#当前执行计划) 和 [backlog](backlog/README.md)。
- 线上首页已通过 HTTPS 访问。最近一次部署是 2026-11-22 的 `babbeba2`。[Pages 运行记录](https://github.com/zhimoe/nimi/actions/runs/44989105116)

## 6. GitHub Pages 部署

工作流:`.github/workflows/pages.yml`

```text
push main (site/** 或 workflow 变更)
  → actions/configure-pages
  → actions/upload-pages-artifact (path: site)
  → actions/deploy-pages
```

仓库 Pages 设置需要:

- Source: **GitHub Actions**
- Custom domain: `nimi.zhi.moe`
- Enforce HTTPS: DNS 与证书就绪后开启

## 7. DNS(Cloudflare)

在 Cloudflare 的 `zhi.moe` zone 添加:

| Type | Name | Target | Proxy |
|---|---|---|---|
| CNAME | `nimi` | `zhimoe.github.io` | DNS only(灰云) |

说明:

- 先在 Cloudflare 使用 **DNS only**,让 GitHub 完成域名校验和 Let's Encrypt
  证书签发。证书就绪后可再评估是否开代理。
- 不要用 A 记录指向 GitHub Pages 的 IP;子域名用 CNAME 更直接。
- DNS 生效后,GitHub Pages 会自动签发 HTTPS 证书;可能需要几分钟到几十分钟。

## 8. 验证

```sh
# 首页与文档页
curl -I https://nimi.zhi.moe/
curl -I https://nimi.zhi.moe/docs.html

# 资源
curl -I https://nimi.zhi.moe/assets/nimi-notes.png

# 默认 Pages 地址(自定义域名生效前也可用)
curl -I https://zhimoe.github.io/nimi/
```

检查项:

- 首页的 WebView 代码与文档页的原生 UI 代码均能独立编译。
- 快速开始保留 Windows PowerShell 和 macOS/Linux 两套命令，Linux 依赖与分发说明可见。
- 校验 HTML 锚点、CSS/图片/字体路径和仓库链接。
- 移动端无横向溢出,导航可展开。
- 文档页侧边栏在桌面端 sticky,移动端折叠为顶部目录。
- 自定义域名 HTTPS 证书有效。

## 9. 限制与后续

站点保持零第三方脚本、无构建步骤;自定义域名由仓库内 `CNAME` 与 Pages 设置维护。
多页文档、站内搜索、其他平台截图以及链接检查/HTML 校验列入
[backlog](backlog/README.md)。
