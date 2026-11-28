# Linux Backlog

> 当前 Preview 已覆盖 GTK3 窗口、WebKitGTK 页面/`nimi://`、Cairo/Pango
> 原生 UI、菜单/对话框/剪贴板、inotify、libnotify、GtkStatusIcon 托盘、
> X11 快捷键、MPRIS2、GStreamer、GtkIMContext、D-Bus 单实例与 `.deb`。
> 以下为尚未完成或仍需真实桌面验收的部分。

## 桌面与渲染

- ATK/AT-SPI 无障碍。
- GtkGLArea/EGL 的 GL surface；当前只有 Cairo CPU 路径。
- Wayland 全局快捷键（XDG desktop portal）。
- AppIndicator/StatusNotifier 托盘（GtkStatusIcon 在 GNOME/Wayland 可能隐藏）。
- HiDPI/Wayland 的窗口装饰、frame extents、CSD、全屏恢复。

## WebView 与输入

- 下载、权限请求、context menu、多窗口 `window.open`。
- IME `delete-surrounding`、真实中文/日文/韩文候选窗验收。
- 独立会话 Cookie 写入/删除；自定义协议多 root/Range/缓存。

## 桌面 API 与打包

- 登录项：XDG autostart 与 `--nimi-opened-at-login` 标记；当前 `setOpenAtLogin` 抛不支持。
- `WindowOptions.consumeActivationClick` 暂忽略。
- 拖放、剪贴板图片/文件、Power/Network/Secrets、最近文档。
- 在 GNOME/KDE 分别安装 `.deb` 并验证启动、系统依赖和 URL scheme 注册。
- PKGBUILD/AppImage、签名与自动更新。

详见 [Linux 后端](../33-linux-framework.md)。
