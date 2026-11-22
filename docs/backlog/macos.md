# macOS Backlog

> 当前 Preview 已覆盖 AppKit/WKWebView、原生 Surface、CoreGraphics/CoreText、
> 菜单/托盘/通知/快捷键/对话框/剪贴板、Now Playing、登录项与打包。
> 以下为尚未完成或仍需真实设备验收的部分。

## WebView 与 IPC

- 流式 IPC/Channel 与 AbortSignal 启停。
- preload、trusted/untrusted 页面、下载与权限回调、`WebViewAvailable`、GPU 进程 ID。
- Eval 返回值与页面导航失败回调。
- 自定义协议：多 scheme/多 root、CORS、Range/分块、缓存与 SPA fallback。

## 原生 UI 与输入

- 更多控件：List/Table/Tabs/Select/Radio、日期/时间/颜色选择、Tree/Grid、富文本/代码编辑器。
- 通用 Metal scene 合成器（当前只有碎纸专用 mask/LayerEffect）。
- transition/动画系统、可变行高虚拟列表与布局缓存。
- NSAccessibility/VoiceOver；RTL 与复杂文本排版仍需扩展。
- 真实拼音/日文/韩文输入法、Character Viewer 与候选窗人工验收。
- 系统托盘图标/模板图、快捷键冲突提示、多屏窗口迁移。

## 桌面 API

- 通知权限、点击回调、移除与前台展示策略（迁移到 UNUserNotificationCenter）。
- 剪贴板图片/文件与自定义格式；文件/文本/URL 拖放与窗口输入区域。
- Power/App Nap、Network 状态与代理、Keychain/Secrets。
- 最近文档、Jump List、文件关联、窗口状态恢复、Dock 菜单/徽标/弹跳/图标 API。
- 自动化 socket（兼容 MyGo `MYGO_AUTOMATION`）。
- 真实媒体键/控制中心验收；真实 `.app` 中的登录项注册与系统审批验收。
- 常开菜单、徽标对齐等 MyGo 菜单能力（Nimi 当前只有普通 NSMenu 项）。

## 打包与发布

- 自动更新（manifest/delta）、release workflow、Sparkle 风格更新窗口。
- DMG 背景/布局/Applications 链接。
- 实际 Developer ID 签名与 notarytool 公证验证。
- 崩溃日志 `crash.log` 与干净机器启动/升级回滚验收。

## 验证

- 真实 GUI E2E：窗口首次点击、菜单、托盘、通知、登录项。
- 真实输入法、媒体键、拖放和发布包人工验收。
- 性能与内存基线。

详见 [macOS 桌面 API](../14-macos-desktop-apis.md)、
[M3–M7 状态](../11-m3-m7-status.md) 与 [MyGo 能力对照](../30-mygo-alignment.md)。
