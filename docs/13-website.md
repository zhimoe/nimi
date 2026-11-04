# 官网与 GitHub Pages

> 日期:2026-11-04 · 源目录 `site/` · 目标域名 `nimi.zhi.moe`

---

## 1. 目标

- 一个不依赖前端框架的静态官网,直接由 GitHub Pages 托管。
- 首页介绍 Nimi、Nim 语言优势、框架能力、架构、状态和 Nimi Notes 截图。
- `docs.html` 提供安装、IPC、原生 UI、平台状态与完整文档入口。
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
    └── nimi-notes.png  # Nimi Notes 实际窗口截图
```

没有构建步骤。GitHub Actions 直接把 `site/` 上传为 Pages artifact。

## 3. 内容决策

| 决策 | 原因 |
|---|---|
| 纯静态 HTML/CSS/JS | GitHub Pages 零依赖;不需要 Node 构建链 |
| 暗色暖色主题 | 与 Nimi Notes 应用视觉一致 |
| 首页先用 Nimi Notes 截图 | 用真实应用证明框架可用,而不是只放抽象图形 |
| “为什么 Nim”独立章节 | 明确项目不是 Go 兼容层,而是选择 Nim 的执行模型与 FFI |
| 状态区诚实标注切片 | 避免把 M3–M7 的部分实现写成完整完成 |
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

## 5. 当前状态(2026-11-04)

- 仓库已创建并公开:<https://github.com/zhimoe/nimi>。
- `Deploy website` workflow 已成功运行,artifact 从 `site/` 部署。
- Pages 已启用,Source 为 GitHub Actions,custom domain 已设为 `nimi.zhi.moe`。
- **DNS 仍待添加**:`nimi.zhi.moe` 目前为 NXDOMAIN,需要在 Cloudflare
  添加下面的 CNAME;添加前默认 Pages 地址会 301 到该域名。
- HTTPS 证书由 GitHub Pages 在 DNS 生效后自动签发,之后可开启 Enforce HTTPS。

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

- 首页包含 Nim 优势、框架能力与 Nimi Notes 截图。
- 移动端无横向溢出,导航可展开。
- 文档页侧边栏在桌面端 sticky,移动端折叠为顶部目录。
- 自定义域名 HTTPS 证书有效。

## 9. 已知限制 / 下一步

- 站点目前是中文单页 + 单文档页;后续可拆成多页文档与搜索。
- 截图是 macOS 暗色主题;可补浅色主题和原生 UI 示例截图。
- 没有 analytics;保持零第三方脚本。
- 自定义域名 DNS 由域名所有者配置;仓库侧已添加 CNAME 并配置 Pages。
- 未接入自动检查(链接检查、HTML 校验)。后续可在 Pages workflow 前加
  `lychee`/`html-validate`。
