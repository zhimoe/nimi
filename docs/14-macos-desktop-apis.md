# macOS 桌面 API(M4 批次)

> 日期:2026-11-05 · 对应 M4 剩余项
>
> 2026-11-09：MyGo v0.8.3 的桌面面已扩展到 Now Playing/媒体键、Power、Network/Proxy、Secrets、Downloads、权限、拖放、最近文档、Jump List、窗口状态、vibrancy、SetInputRegion 等。本文只记录 Nimi 已实现切片，差距与优先级见 [MyGo 能力对照](30-mygo-alignment.md)。

---

## 1. 本轮完成

| 能力 | API | 说明 |
|---|---|---|
| 显示器 | `screens()`, `primaryDisplay()`, `cursorPosition()`, `onScreensChanged()` | 多屏、工作区、缩放、光标位置;使用左上原点 |
| 主题 | `themeInfo()`, `isDark()`, `accentColor()`, `onThemeChanged()` | 跟随系统明暗与强调色 |
| 窗口焦点 | `focusedWindow()`, `Window.focused`, `onFocusChanged()` | NSWindow key/main 事件;新建窗口乐观设为焦点 |
| 窗口控制 | `center/minimize/deminimize/zoom/toggleFullScreen/isFullScreen/setSize/setPosition/setResizable/setAlwaysOnTop/hide/focus/isFocused` | 内容尺寸、屏幕位置、浮动层级 |
| 动态菜单 | `app.setMenuItemEnabled/Checked`, `app.refreshMenu`, `Menu.findItem/setEnabled/setChecked` | 菜单项状态修改后重建 NSMenu |
| 托盘 | `newTray(TrayOptions)`, `Tray.setTitle/setTooltip/setMenu/remove` | NSStatusItem + NSMenu;当前用文字作为托盘标题 |
| 通知 | `notify(title, body)`, `notify(NotificationOptions)` | NSUserNotification;后续迁移 UserNotifications |
| 全局快捷键 | `registerGlobalShortcut`, `unregisterGlobalShortcut`, `unregisterAllGlobalShortcuts` | Carbon `RegisterEventHotKey`;无需 Input Monitoring |
| 文件对话框 | `dialog.open(... filters)`, `dialog.save(... defaultExtension, filters)` | 扩展名过滤、默认扩展名 |
| 消息框 | `dialog.message(title, text, buttons)`, `dialog.confirm(title, text)` | 多按钮;返回 0-based 按钮索引 |

示例:`examples/desktop-native`

```sh
nim c -r --path:src examples/desktop-native/main.nim
NIMI_SMOKE=desktop nim c -r --path:src examples/desktop-native/main.nim
```

示例展示显示器、主题、强调色、光标、焦点事件、窗口控制、动态菜单、
状态栏托盘、通知和全局快捷键。

## 2. 实现决策

| 决策 | 原因 |
|---|---|
| 屏幕坐标统一为左上原点 | 与 native UI scene 一致;AppKit 的 bottom-left 在 Darwin 后端转换 |
| 主屏取 `NSScreen.screens[0]` | 菜单栏所在屏幕;工作区扣除菜单栏/Dock |
| 主题观察 AppKit + 分布式通知兜底 | `NSApplicationDidChangeEffectiveAppearanceNotification` 不可用时仍能收到系统主题变化 |
| 菜单 target 按实例存 handler | 应用菜单与托盘菜单共用 NSMenu 构建逻辑但回调隔离 |
| 动态菜单重建而不是原地修改 | 当前菜单规模小;避免维护 AppKit item 指针表 |
| 托盘先用文字标题 | 不引入图片加载/模板图标;后续补 `NSImage` 与 template |
| 通知先用 NSUserNotification | 实现简单;API 已过时,后续迁移 UNUserNotificationCenter 以支持权限与点击回调 |
| 全局快捷键用 Carbon | 系统级热键最直接,不需要辅助功能/输入监控权限 |
| 新建窗口乐观标记 focused | 从终端直接启动时 AppKit 可能不发送首个 key-window 通知;后续 blur/focus 事件会纠正 |
| 对话框返回 0-based 按钮索引 | 屏蔽 NSAlert 的 1000/1001 返回值,便于调用方判断 |

## 3. 验证

```text
NIMI_SMOKE=desktop ./nimi_desktop
screen count: 1
primary: Built-in Retina Display 1512x982 @2.0x work=1512x894
theme: light accent=#007AFF
cursor: 541,457
always on top: true
focused window: true
window focused: true
tray: true
global shortcut: true
```

- `./scripts/test.sh` 全部通过
- 新增 `tests/test_desktop.nim`:screen/theme、监听器、菜单状态、快捷键委托
- `examples/desktop-native` 实际截图确认渲染
- 托盘状态项、通知调用、快捷键注册均有运行时冒烟

## 4. 已知限制

- 通知使用的是已弃用的 `NSUserNotification`;没有权限申请、点击回调、关闭回调
- 托盘只有文字标题,没有图标/模板图;没有点击弹出菜单之外的交互
- 全局快捷键没有冲突提示 UI;同一 accelerator 重复注册返回 false
- 屏幕变更事件只在主线程回调;没有做多屏坐标的窗口迁移
- 菜单位置/启用状态重建会丢失 AppKit 的临时高亮;菜单规模大时应改成按 item 更新
- 没有屏幕录制、剪贴板图片/文件、窗口状态恢复
- 本切片时尚未实现 Metal、TextArea/IME、M5 协议/Session、M7 更新/公证;
  这些已在后续切片补齐(见 [原生碎纸](26-native-shred.md)、
  [IME](24-m6-ime.md)、[FileServer](15-m5-file-server.md));仍缺
  自动更新与公证实际执行
- 通知/快捷键的真实用户交互仍需人工验证

## 5. 下一步

1. 用 `UNUserNotificationCenter` 替换 NSUserNotification,支持权限、点击和前台展示策略。
2. 托盘图标:NSImage + template image,支持点击行为与动态菜单勾选。
3. 全局快捷键冲突检测/提示;支持更多键位。
4. 剪贴板图片/文件类型与拖放。
5. 窗口状态保存/恢复、多窗口焦点记忆。
6. 继续 M5/M6/M7:协议/文件监视、TextArea/IME、更新/公证(其中
   协议/文件监视/TextArea/IME 已在后续切片落地)。

## 6. 与 MyGo v0.8.3 的后续差距

按对 Nimi 当前目标的价值排序，尚未实现：

1. Keychain/Secrets（Subsonic 凭据）。
2. Cookie 写入/删除、Session 隔离。
3. 通知权限、点击回调、移除。
4. 拖放（文件/文本/URL）、窗口输入区域。
5. Power/App Nap、Network 状态与代理。
6. 最近文档、Jump List、登录项、文件关联、窗口状态恢复。
7. 托盘图标/模板图、剪贴板图片/文件、自定义格式。
8. 自动化 socket（与 MyGo `MYGO_AUTOMATION` 兼容）。

这些不是 1.0 全部必需；优先级见 [30](30-mygo-alignment.md) 与 [28](28-remediation-status.md)。

## 7. Now Playing / 媒体键（2026-11-09）

- 新增 `core/nowplaying`：`NowPlayingInfo`（标题/歌手/专辑/时长/位置/播放状态/可用命令）与 `MediaCommand`（play/pause/toggle/stop/next/previous/seek）。
- Darwin 后端懒加载 `MediaPlayer.framework`，使用 `MPNowPlayingInfoCenter` 显示状态、`MPRemoteCommandCenter` 接收媒体键/系统媒体控制。
- 命令回调仍在主线程；`setNowPlaying`/`clearNowPlaying` 可在 `whenReady` 后调用。
- Music 已接入：切歌、播放/暂停、seek、下一首/上一首和停止会更新系统状态；退出/关窗清除。
- 未做：封面 artwork、真实媒体键人工验收、Windows/Linux 媒体控制。
