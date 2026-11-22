# Nimi Backlog

> 集中记录 Nimi Preview 阶段尚未完成的能力、平台差距和后续版本计划。
> README 与官网只描述当前可用能力；需要逐项核对进度时看这里。
>
> 更新日期：2026-11-22

## Preview 说明

Nimi 目前是开发者预览版：macOS、Windows、Linux 三平台后端都可运行，
WebView、类型化 IPC、自绘原生 UI、桌面 API 和打包链路已经打通。
Preview 阶段仍可能调整公开 API 和平台行为；已实现范围以源码与
[文档索引](../README.md) 为准。

本目录不是交付承诺，也不按“完成百分比”统计。每项工作仍以可运行示例、
自动测试和真实设备验收为边界；具体限制保留在各平台文档中。

## 里程碑与估算

| 里程碑 | 内容 | 状态 |
|---|---|---|
| M0 | 可行性原型 | ✅ 已完成 |
| M1 | Core + macOS WebView + IPC + `hello` | Preview |
| M2 | 原生 UI 基础 + `counter-native` | Preview |
| M3 | 控件/布局/滚动 + Metal 起步 | Preview |
| M4 | 桌面 API | Preview |
| M5 | 文档/会话/Cookie/协议/监视 | Preview |
| M6 | 文本编辑/IME/可访问性/Metal 完整 | Preview |
| M7 | 打包/签名/公证/更新 | Preview |
| M8 | Windows | Preview |
| M9 | Linux | Preview |
| M10 | 插件/i18n/音频/自动化/浏览器后端 | 持续 |

单人全职的原始工期估算仍保留在 [实施路线图](../05-roadmap.md)；
Preview 之后按实际需求重新排序，不再用旧工期推算发布日期。

## 平台 backlog

- [macOS](macos.md)：通知点击、托盘图标、拖放、凭据、Dock、真实 IME/媒体键验收。
- [Windows](windows.md)：D3D11/DirectComposition、Toast、实机 GUI 验收、登录项与安装器。
- [Linux](linux.md)：ATK、GL surface、Wayland portal、AppIndicator、下载/权限、打包。
- [核心与工具链](core.md)：流式 IPC、preload/trust、更多控件、自动更新、i18n、示例。

## 详细状态文档

这些文档保留实现记录、平台差异和验证细节；README 与官网不再逐项展开。

- [M3–M7 状态](../11-m3-m7-status.md)
- [整改基线](../28-remediation-status.md)
- [MyGo 能力对照](../30-mygo-alignment.md)
- [Windows 框架状态](../32-windows-framework.md)
- [Linux 后端](../33-linux-framework.md)
- [实施路线图](../05-roadmap.md)

## 验收规则

- 每个能力至少有一条可运行示例或自动测试。
- 真实窗口、输入法、通知、媒体键、签名与安装包需要人工/真机验收；
  合成事件或离屏测试不能替代。
- 新增未完成项先记录在本目录，再进入实现；首页不维护 TODO 清单。
