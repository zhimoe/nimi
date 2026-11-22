# Windows Backlog

> 当前 Preview 已覆盖 Win32 窗口、WebView2/IPC、`nimi://`、GDI 渲染、
> 原生菜单/IME/托盘/通知、文件监视、Cookie 查询与 exe/manifest 打包。
> 以下为尚未完成或仍需实机验收的部分。

## 渲染与窗口

- D3D11/DirectComposition 呈现循环（当前为 GDI + `SetTimer`）。
- 圆角/透明窗口、缩略图工具栏、窗口状态恢复与多屏 DPI 专项。
- `WindowOptions.consumeActivationClick` 的 Windows 行为。

## 输入与桌面 API

- 微软拼音/日语输入法实机验证、候选窗多屏 DPI/滚动定位、TSF/重转换。
- WinRT Toast 与点击回调、Now Playing/媒体键。
- 登录项（注册表 Run 项或计划任务）尚未实现；`setOpenAtLogin` 抛不支持。
- 文件关联、下载、权限、独立会话 Cookie、拖放与剪贴板图片/文件。
- Power/Network/Secrets、最近文档与 Jump List。

## 打包与发布

- 安装器、签名、自动更新。
- 真实 Windows 11 x64/ARM64 的 GUI 验收矩阵。
- WebView2 Runtime 缺失/Loader 版本与真实页面视觉回归。

详见 [Windows 框架状态](../32-windows-framework.md)。
