# 项目回检:架构、文档与测试

> 日期:2026-11-05 · 范围:整个仓库(macOS 切片)
> 结论:可以继续迭代;本轮修复了渲染器耦合、Metal 可移植性、动画语义、
> 测试入口与多处过期文档,没有做大规模重写。

---

## 1. 回检方法

- 通读 `src/nimi/` 的模块依赖、平台契约、渲染路径与示例;
- 运行 `nim check`、`./scripts/test.sh`、全部 examples 编译;
- 检查 docs 内部链接、状态表、路线图与网站文案;
- 对碎纸功能做原生 CG / Metal / WebGL 三条路径的冒烟与截图复核。

---

## 2. 发现与处理

| 发现 | 严重度 | 处理 |
|---|---|---|
| `core/window.nim` 直接 import `render/cg.nim`,core 与具体渲染器耦合,与设计文档“渲染器可替换”冲突 | 高 | 新增 `SceneRenderer` 注入点;`core/window` 只调用 `content.drawContent`;`core/app` 作为 composition root 安装 CoreGraphics 渲染器 |
| `render/metal.nim` 无条件 import Darwin ObjC,非 macOS 导入即失败 | 中 | 用 `when defined(macosx)` 隔离实现;非 macOS 只提供带 `error` 的 stub,模块可编译 |
| `Window.startAnimation` 在已运行时修改 fps 不重启 timer,且启动后要等下一 tick 才重绘 | 中 | fps 变化时重启 timer;启动时立即 `invalidate()`;改用单调时钟计算 dt |
| 动画 API 没有测试;`SceneRenderer` 注入没有测试 | 中 | `tests/test_ui.nim` 新增 timer 启动/重启/停止与 renderer 注入测试 |
| `nimi.nimble` 的 `test` 任务只跑 4 个测试文件,与 `scripts/test.sh` 不一致 | 中 | `nimble test` 直接调用 `scripts/test.sh`,单一入口 |
| Metal demo 有未使用 import,`encodeLayer` 有冗余 vertex bytes 设置 | 低 | 清理 |
| `docs/11` 的 M3/M6 剩余项、`docs/05` 状态、`docs/14` 的“尚未实现 Metal/TextArea/IME”过期 | 中 | 按 2026-11-05 实际状态更新,并加交叉链接 |
| `docs/README`、`docs/01` 日期/模块树/依赖图与现状不一致;`docs/01` 有重复 `d3d11.nim` 行 | 中 | 更新日期、补 `effects/`、补现状提示、修重复行、写清 renderer 注入硬规则 |
| 官网仍写“TextArea/IME/选择待补”“完整 Metal 未做” | 中 | 更新 `site/index.html` 与 `site/docs.html`,补 25/26 文档入口与碎纸示例 |
| README 状态行/目录树/下一步未包含原生效果与 Metal | 低 | 同步更新 |

---

## 3. 本轮架构改动

### 3.1 渲染器注入

之前:

```text
core/window.nim ──► render/cg.nim (具体 Darwin 渲染器)
```

现在:

```text
core/window.nim ──► content.drawContent
                         │
                         ├─ Content.renderer(可选,按内容覆盖)
                         └─ defaultContentRenderer(composition root 安装)
                                  │
                                  └─ render/cg.drawScene(macOS)
```

- `core/content.nim` 定义 `SceneRenderer = proc(ctx: pointer, scene: Scene)`;
- `core/window.nim` 不再 import 任何 `render/*`;
- `core/app.nim` 在 macOS 启动路径安装 CoreGraphics 默认渲染器;
- 应用可用 `content.renderer` 或全局 `defaultContentRenderer` 替换渲染器;
- `renderContent` 仍保留,测试/Tester/离屏渲染不依赖窗口。

这仍是“单 renderer 默认值”,不是完整的 `Renderer` 接口/多后端注册表;
但已经消除了 core→具体后端的反向依赖,给后续 Metal scene 合成器留出入口。

### 3.2 Metal 可移植性

`render/metal.nim` 现在:

- macOS:`import platform/darwin/objc`,编译并链接 Metal;
- 其他平台:不加载 Darwin 库,定义最小 `Id`/`NSUInteger` 别名,
  `newMetalShred` 返回 `error = "Metal is only available on macOS"` 的 stub;
- 模块可以随 `nimi` 包在其他平台编译,不会被误当成可用 GPU 路径。

### 3.3 动画语义

`Window.startAnimation`:

- 添加一个帧监听器;
- 首次调用启动原生 timer 并立即重绘;
- 已运行时修改 fps 会重启 timer;
- `stopAnimation` 清空监听器并停止 timer;
- Darwin 用 `getMonoTime()` 计算 dt,避免系统时钟回拨;
- 窗口关闭时 backend 自动 invalidate timer。

限制仍然是 NSTimer,不是 CVDisplayLink;`Window` 关闭后没有专门的
“移除单个监听器”API,`stopAnimation` 是全部停止。

---

## 4. 验证

```sh
nim check --hints:off --path:src src/nimi.nim
./scripts/test.sh
```

通过:

- 全部原有 IPC/loop/UI/render/desktop/fileserver/document 测试;
- `test_shred`:纸带约束、固定步长、风场;
- `test_metal`:mask + LayerEffect 离屏渲染;
- 新增 `Window.startAnimation` 与 `SceneRenderer` 测试。

示例与打包:

```sh
for d in examples/*/; do nim c --hints:off --path:src "$d/main.nim"; done
./nimi build examples/shred-native
./nimi build examples/shred-metal
NIMI_SMOKE=live .../Nimi\ Shred\ Native
NIMI_SMOKE=metal-live .../Nimi\ Shred\ Metal
```

全部通过;碎纸截图见 `docs/assets/shred-native.png`、
`docs/assets/shred-metal.png`。

`nimble test` 任务已改为调用 `scripts/test.sh`;当前环境 nimble 在刷新
package list 时网络失败,因此以脚本结果为准(任务本身已被 `nimble tasks`
正确识别)。

---

## 5. 仍未解决的架构债务

按优先级:

1. **通用 Metal scene 合成器**:当前 `render/metal.nim` 只服务碎纸
   mask/LayerEffect,不是任意 scene op 的 renderer;也尚未接入
   `WindowOptions`/普通原生控件树。
2. **UI 引擎拆分**:`ui/context.nim` 仍承担构建、布局、绘制、输入、
   文本编辑、滚动、撤销,约 1.3k 行;目标布局里的 element/layout/
   paint/input/editor 尚未拆出。
3. **平台渲染绑定**:`render/cg.nim` 仍是 macOS 专用(即使不 import
   platform);Windows/Linux 需要 raster/GL/D3D11 后端。composition root
   注入机制已就绪,但还没有多后端实现。
4. **场景能力**:没有 glyph atlas、渐变、阴影、effect、damage;文本仍走
   CoreText 逐行绘制,Metalmask 也还没有边缘抗锯齿。
5. **测试**:仍是单元/离屏 PNG 为主,没有 golden 像素 diff、真实窗口
   e2e、性能基准;Metal 在 CI 上只在可用时执行。
6. **可访问性/IME 真实输入**:NSAccessibility 未实现;IME 仍需真实
   中文/日文输入法人工验证。
7. **Windows/Linux**:M8/M9 未开始,`platform/contract` 已有接口但无后端。
8. **文档历史切片**:08/10/14 等按当时状态写的限制,现在通过“后续切片”
   链接说明;没有逐条删除历史记录。
9. **许可证**:仓库没有 `LICENSE` 文件,README 写“MIT License(待定稿)”,
   `nimi.nimble` 已声明 MIT。发布/对外授权前需要确认并补正式 LICENSE。

这些不影响当前 macOS 切片继续开发,但在宣称“通用桌面框架”之前必须解决。

---

## 6. 后续建议

1. 先做 `WindowOptions` 级 renderer 选择(Metal/CG),把碎纸 Metal
   从独立 demo 推进为普通原生窗口能力。
2. 拆 `ui/context.nim` 之前先加布局/文本 golden 测试,避免大改回归。
3. 给 scene 增加 damage/atlas 前,先固定 `op` 的跨后端语义与测试。
4. 在 CI 增加 `nimble test` 与 examples 的全量编译;Metal 测试保留
   “不可用则 skip”的语义。
5. 网站与 README 的进度只在里程碑状态变化时更新,避免再次出现
   “文档比代码旧”的漂移。
