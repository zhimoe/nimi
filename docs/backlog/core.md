# Core and Tooling Backlog

> 跨平台的 IPC、原生 UI、工具链、测试和示例工作。

## IPC 与 WebView

- 流式 IPC/Channel、批处理与 AbortSignal 启停。
- preload、trusted/untrusted、页面下载/权限、`WebViewAvailable`。
- 复杂类型的自动 TypeScript 映射；当前基础标量之外为 `unknown`。
- 自定义协议异步/流式响应、Range、CORS、缓存与多 scheme/多 root。

## 原生 UI

- 更多控件：List/Table/Tree/Grid/Tabs/Select/Radio、日期/时间/颜色选择、
  Combobox/Autocomplete、Tooltip/Popover/Modal/Toast。
- 富文本/代码编辑器、Markdown 渲染、图表与视频组件。
- 通用 Metal/D3D11/GL scene 合成器与跨渲染器 golden 测试。
- transition/动画系统、可变行高虚拟列表、布局缓存与滚动惯性。
- 无障碍（NSAccessibility/AT-SPI/UIA）、RTL、复杂文本排版。
- 真实输入法矩阵（拼音、双拼、日文、韩文）与候选窗人工验收。

## 工具链与发布

- `nimi init` 模板、`nimi dev` 热重载边界与更完整的 `doctor`。
- 自动更新（manifest/delta/签名）、release workflow、更新窗口。
- macOS 实际公证、Windows 安装器、Linux PKGBUILD/AppImage。
- 崩溃日志、干净机器启动、升级/回滚验收。
- 无窗口 Tester 与真实 GUI E2E 的覆盖边界说明；性能/内存基线。

## 应用与示例

- Nimi Notes：SQLite/FTS、多窗口、原生确认框、生成的 TS 接入打包。
- Music：缓存淘汰 UI、流式播放、真实 Subsonic 账号与媒体键验收。
- CloudMusic demo：评估音频、列表/滚动、图片与网络能力后单独排期。
- 自动化 socket（MyGo `MYGO_AUTOMATION` 兼容）。

## i18n 与文档

- locale 匹配、消息目录、CLDR 复数/日期/数字、pseudo locale。
- 新 API 的 README/官网示例与迁移说明。
- 多页文档与站内搜索;Windows/Linux 与浅色主题截图。
- Pages workflow 前的链接检查/HTML 校验;继续保持零第三方脚本。
- 许可证文件与自身许可定稿（当前 `nimi.nimble` 标注 MIT）。

详见 [实施路线图](../05-roadmap.md) 与 [整改基线](../28-remediation-status.md)。
