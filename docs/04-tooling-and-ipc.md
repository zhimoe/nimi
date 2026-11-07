# 工具链、IPC 与构建发布

> 2026-11-06 重评：本文包含目标设计，不能作为当前 API/线程安全/兼容性承诺。实现边界与后续验收以 [整改基线](28-remediation-status.md) 为准；历史工期不作为剩余工期。

> 状态:草案 · 日期:2026-11-04 · 关联:[架构](01-architecture.md)、[macOS 后端](02-macos-backend.md)、[路线图](05-roadmap.md)

---

## 1. CLI(`nimi`)

### 1.1 命令总览

| 命令 | 作用 | 优先级 |
|---|---|---|
| `nimi init [dir]` | 创建项目(web / native 模板) | M1 |
| `nimi generate` | 生成 TypeScript 客户端 | M1 |
| `nimi dev [dir]` | 开发模式:构建、启动、热重载 | M1 |
| `nimi build [dir]` | 生产构建 + 打包 | M1(macOS),M7(完整) |
| `nimi doctor` | 检查工具链/系统依赖 | M1 |
| `nimi keygen` | 生成更新签名密钥 | M7 |
| `nimi i18n check` | 检查消息目录 | M5 |
| `nimi migrate-ui` | 旧 API 迁移(如需要) | P2 |
| `nimi version` / `help` | 版本/帮助 | M1 |

### 1.2 `init`

- `-template web|native`、`-name`、`-module`、`-nimi <path>`(本地开发)。
- web 模板:Vite/TypeScript 前端 + `src/main.nim` + `nimi.json`。
- native 模板:`src/main.nim` + `nimi.json` + 测试。
- 生成 1024×1024 默认图标(纯 Nim 绘制:圆角方块 + 渐变 + 圆环)。
- 运行 `nimble install -d`(如需要)、`bun install`(web)、首次 `nimi generate`。

### 1.3 `generate`

```text
1. 读取 nimi.json
2. 用 nim c -d:nimiGenerate --out:.nimi/generate app.nim 编译(或 nim r)
3. 运行二进制,设置 NIMI_GENERATE=<bindings path>
4. app.run 检测环境变量 → 生成 TS → 退出,不初始化后端
5. 内容未变不重写;无绑定/事件不写文件
```

- 输出路径:`bindings` 字段;默认根据前端依赖推断。
- 生成内容:类型、服务对象、事件对象;与 MyGo 的形态一致。
- 文档注释:宏默认拿不到 `##`;用 `{.doc: "...".}` 或服务声明中的 `doc` 字段。

### 1.4 `dev`

```text
1. 生成 TS 客户端
2. 启动 devCommand(如 vite),等待 devUrl(默认 30s)
3. 构建开发版可执行文件到 .nimi/dev/<os>-<arch>/
4. 设置 NIMI_DEV_URL / NIMI_DEV=1 启动
5. 监听源文件/config/图标/资源/语言目录(250ms 去抖)
6. 变更 → 重新生成/构建 → 重启(SIGTERM,3s 后 SIGKILL)
7. 终端快捷键:r 重载、c 清屏、q 退出、h 帮助
```

- `-web`:wasm + SSE 热重载(后续)。
- 开发版 macOS 用真实 `.app`(`<Name> Dev`,`<id>.dev`),便于通知/登录项/权限测试。
- 退出码 75 表示"请求重启",dev 捕获后重启。

### 1.5 `build`

```text
1. 生成 i18n(如有)+ TS 客户端
2. 运行 buildCommand(前端)
3. 编译 Nim:--mm:atomicArc --threads:on -d:release -d:nimiProd
4. 生成资源模块(staticRead)或复制到 Resources/
5. 按平台组装 staging 目录
6. 签名/公证/打包
7. 整体替换输出目录(失败保留旧产物)
```

- `-platform`、`-debug`、`-sign`、`-skip-dmg`、`-skip-notarize`、`-skip-installer`、`-upload`。
- 输出默认 `dist/<os>-<arch>/`。
- 资源合并:项目 `resources/` + 配置 `resources`;平台目录 `resources/<os>`、`resources/<os>-<arch>`;`resourcesExclude` 支持 `path.Match` + `**`;点文件忽略;符号链接/权限保留;Mach-O/PE 逐个签名。
- 前端嵌入:CLI 生成 `nimi_assets.nim`:

```nim
const assets* = {
  "index.html": staticRead("frontend/index.html"),
  "assets/app.js": staticRead("frontend/assets/app.js"),
  ...
}
```

  或生成单个归档 + 索引(大资源更省编译时间)。
- 版本/标识注入:生成 `nimi_build.nim`(`const version = "..."`),避免 `-d` 字符串转义问题。
- 生产关闭 Inspector、断言、调试符号;strip。

### 1.6 `doctor`

检查:

- Nim >= 2.4、nimble、C 编译器(clang/gcc)、macOS SDK。
- 可选 Bun/Node(web 模板)。
- macOS:`xcode-select`、`codesign`、`notarytool`、Developer ID 身份。
- Linux:`ldconfig -p` 查 GTK3/WebKitGTK(如果 `linux.webview=true`)。
- Windows:WebView2 Runtime、NSIS、signtool/osslsigncode。
- 输出安装建议。

---

## 2. 配置

### 2.1 格式

优先 `nimi.json`(简单、可被任何工具读取);后续可支持 `nimi.config.nims`(NimScript 求值)。

```json
{
  "name": "My App",
  "slug": "my-app",
  "identifier": "com.example.myapp",
  "version": "0.1.0",
  "main": "src/main.nim",
  "out": "dist",
  "bindings": "frontend/src/nimi.ts",
  "devUrl": "http://localhost:5173",
  "devCommand": "bun run dev",
  "buildCommand": "bun run build",
  "frontendDist": "frontend/dist",
  "icon": "resources/icon.png",
  "resources": ["resources"],
  "resourcesExclude": ["**/*.go"],
  "urlSchemes": ["myapp"],
  "fileAssociations": [
    {"ext": "note", "name": "Note", "mimeType": "application/x-myapp-note", "role": "Editor"}
  ],
  "macos": {
    "minimumSystemVersion": "12.0",
    "signingIdentity": "-",
    "entitlements": "build/entitlements.plist",
    "notarize": false,
    "dmgTitle": "My App"
  },
  "windows": {
    "displayName": "My App",
    "installDirName": "My App",
    "timestampUrl": "http://timestamp.digicert.com"
  },
  "linux": {
    "maintainer": "Ada <ada@example.com>",
    "categories": ["Utility"],
    "depends": [],
    "webview": true,
    "command": "my-app"
  },
  "updates": {
    "publicKey": "...",
    "github": "owner/repo",
    "tagPrefix": "v",
    "deltas": 3
  }
}
```

`resources` 在 `nimi build` 时复制到 `.app/Contents/Resources/<name>`;运行时可用
`getAppDir()/../Resources/<name>` 定位。`resourcesExclude` 尚未实现。

### 2.2 默认值

| 字段 | 默认 |
|---|---|
| `name` | 目录名 |
| `slug` | name 的 kebab-case |
| `identifier` | `com.nimi.<slug>` |
| `version` | `0.1.0` |
| `main` | `src/main.nim` |
| `out` | `dist` |
| `icon` | `resources/icon.png`(存在时) |
| `macos.minimumSystemVersion` | `12.0` |
| `macos.signingIdentity` | `-`(ad-hoc) |
| `linux.maintainer` | package.json author |
| `linux.webview` | `true` |
| `linux.command` | slug |
| `bindings` | 根据前端依赖推断 |

### 2.3 校验

- `name`/`slug`/`identifier` 非空;identifier 反向 DNS。
- URL scheme 不含保留 scheme;文件扩展名不含点。
- `macos.provisioningProfile` 与 ad-hoc 签名冲突报错。
- `updates.publicKey` 是合法 Ed25519 公钥(base64)。
- `resourcesExclude` 是合法 glob。
- 配置与 `nimi.config.nims` 同时存在时报错。

### 2.4 `nimi.config.nims`(后续)

NimScript 可执行,能引用环境变量/计算路径。求值后转成同一 `Config` 对象。Nim 可直接 `nim e` 执行,不需要 Bun/Node。

---

## 3. 模板

### 3.1 web 模板

```text
my-app/
├── nimi.json
├── package.json
├── src/main.nim
├── frontend/
│   ├── index.html
│   ├── src/main.ts
│   ├── src/style.css
│   ├── tsconfig.json
│   └── vite.config.ts
└── resources/icon.png
```

`src/main.nim`:

```nim
import nimi

type
  Greeter = ref object

proc greet(self: Greeter, name: string): string {.rpc.} =
  "Hello " & name & ", from Nim!"

let greeter = Greeter()
bindService(greeter, greet)

nimi.app.whenReady(proc() =
  discard nimi.newWindow(WindowOptions(
    title: "My App",
    width: 800,
    height: 600,
    url: "/"
  ))
)

nimi.app.run()
```

`frontend/src/main.ts`:

```ts
import { Greeter } from "./nimi";

document.querySelector("#app")!.textContent =
  await Greeter.greet("world");
```

### 3.2 native 模板

```text
my-app/
├── nimi.json
├── src/main.nim
├── tests/test_main.nim
└── resources/icon.png
```

`src/main.nim`:

```nim
import nimi
import nimi/ui

type
  App = ref object
    name: string

proc view(s: App, c: Context) =
  column(c).fill().center().gap(12).children(proc() =
    text(c, "Hello, " & s.name).fontSize(24).bold()
    textInput(c, addr s.name).width(240)
    if primaryButton(c, "Say hello").clicked():
      discard
  )

let s = App(name: "world")
nimi.app.whenReady(proc() =
  discard nimi.newWindow(WindowOptions(
    title: "My App",
    width: 480,
    height: 320,
    content: uiView(proc(c: Context) = s.view(c))
  ))
)
nimi.app.run()
```

### 3.3 模板维护

- 模板文件用 `{{name}}` 占位符;CLI 渲染。
- 模板测试:`nimi init` 到临时目录 → `nimi build` → 运行 `hello` 断言。
- 模板与文档保持同步;CI 跑模板测试。

---

## 4. IPC 与 TypeScript 生成

> 2026-11-07：当前实现中，`bindService` 方法在 UI 线程同步执行，耗时方法可用
> `bindBackgroundService` 注册到有界工作池。线程模型、背压和关闭语义见
> [异步 IPC 与工作池](29-async-ipc.md)；本节其余内容保留为目标协议设计。

### 4.1 协议(与 MyGo 对齐)

详见 `01-architecture.md` §7.1。要点:

- 页面 → Nim:`{"t":"call","id":N,"k":token,"m":"Service.Method","a":[...]}`。
- Nim → 页面:reply/event/chan;每轮主循环合并为一次 `__nimi.receive([...])`。
- secret 前缀;每页 token;untrusted 限制;DOM ready 前事件保留 1024 条。
- Channel 1 MiB 窗口 + 半窗口 ack;页面 close 取消调用。

### 4.2 服务声明

```nim
type
  Note* = object
    id*: int
    title*: string
    body*: string

  Notes* = ref object
    items: seq[Note]

proc add*(self: Notes, title: string): Note {.rpc.} =
  result = Note(id: self.items.len + 1, title: title)
  self.items.add result

proc list*(self: Notes, limit: int = 100): seq[Note] {.rpc.} =
  self.items[0 ..< min(limit, self.items.len)]

let notes = Notes()
bindService(notes, add, list)
```

- `{.rpc.}` 标记可被页面调用。
- `bindService(instance, procs...)` 接收服务实例与显式 proc 列表(Nim 无法按 `{.rpc.}` 枚举类型的所有方法),生成:
  - `ServiceDef`(名称取自实例类型、方法、参数名/类型、返回类型、doc)
  - `dispatch`(JSON 解码 → 调用 → 编码)
  - `tsDescriptor`
- 重载解析:宏在 `ClosedSymChoice` 中选出第一个参数类型与服务实例类型匹配的 proc;同一 `self` 类型有多个重载时仍然歧义,需要改名或显式绑定唯一 proc。
- `{.rpc.}` 是可选标记,用于校验/文档;不参与枚举。
- `bindServiceAs("Store", instance, procs...)` 自定义服务名。
- 第一个参数是 `self`;TS 客户端不暴露它。
- 可选首参 `ctx: CallContext`;同样不暴露。
- `Channel[T]` 参数由宏识别;页面传 `Channel` 对象(其 `toJSON` 返回 id)。

### 4.3 事件

```nim
let noteAdded = newEvent[Note]("note-added")

proc add(self: Notes, title: string): Note {.rpc.} =
  result = ...
  noteAdded.broadcast(result)
```

- `newEvent[T]` 是宏:登记名称/类型/声明位置;生成 `Event[T]`。
- `emit(win, payload)`、`emitPage(page, payload)`、`broadcast(payload)`。
- 事件名保留前缀 `nimi:`;同名 panic。

### 4.4 TS 生成

```ts
// Code generated by `nimi generate`. DO NOT EDIT.

import { call, event } from "nimi-runtime";

/** A note. */
export interface Note {
  id: number;
  title: string;
  body: string;
}

/** Notes stores the user's notes. */
export const Notes = {
  /** Add creates a note and returns it. */
  add(title: string): Promise<Note> {
    return call("Notes.Add", title);
  },
  list(limit: number): Promise<Note[]> {
    return call("Notes.List", limit);
  },
} as const;

export const events = {
  noteAdded: event<Note>("note-added"),
} as const;
```

- 方法名 camelCase:`GetUserByID` → `getUserByID`;参数保留 Nim 名。
- 类型映射见 §4.5。
- 生成器不依赖运行时反射;宏在编译期产出描述符。
- 内容未变不重写,避免 dev server 无谓重载。

### 4.5 类型映射

| Nim | JSON / TS |
|---|---|
| `bool` | `boolean` |
| `string` | `string` |
| `int`, `int64`, `float`, `float64` | `number` |
| `seq[T]` | `T[]`;nil → `[]` |
| `array[N, T]` | `T[]` |
| `Option[T]` | `T \| null` |
| `Table[string, T]` | `Record<string, T>` |
| `object` / `ref object` | `interface` |
| `distinct string` + const | 字面量 union |
| `seq[byte]` | base64 `string` |
| `DateTime` | RFC 3339 `string` |
| `Duration` | `number`(纳秒) |
| `JsonNode` | `unknown` |

- 字段默认 camelCase;`{.json: "id".}` 覆盖;`{.jsonOmitIfDefault.}` / `Option[T]` 表示可选。
- 变体对象第一版只支持显式 `kind` 标注;复杂类型用自定义 codec。
- 与 MyGo 的 `encoding/json/v2` 规则保持 envelope 兼容;类型层允许差异。

### 4.6 JSON 实现

- 推荐 `jsony`(直接到对象,快 3–6 倍)。
- 宏生成 `toJson`/`fromJson` 或 `jsony` 的 `dumpHook`/`parseHook`,精确控制字段名/可选/枚举。
- 大整数 ID:超过 2^53 用 `string` 标注;不要静默丢精度。
- 错误:绑定方法抛异常 → reply `ok:false,e:...`;不把堆栈发给页面。

### 4.7 Bridge 复用

- 复用 MyGo `packages/bridge` 的 TypeScript 源码,构建 `bridge.js`;只改命名空间/配置字段。
- 保留 `window.mygo` 别名到 1.0;新代码用 `window.nimi`。
- `nimi-runtime` fork 自 `mygo-runtime`,保持 `call`/`event`/`Channel` 导出。
- 配置字段:`platform/windowId/version/secret/locale/dir/fit` 保持一致。

---

## 5. 打包与发布

### 5.1 macOS

```text
dist/darwin-arm64/MyApp.app/
dist/darwin-arm64/MyApp-0.1.0.dmg
```

流程:

1. 编译 `MyApp`。
2. 组装 `.app`(Info.plist、PkgInfo、图标、资源、可选 lproj)。
3. `codesign --force --deep --options runtime --sign <identity>`。
4. `xcrun notarytool submit --wait`(如配置)。
5. `xcrun stapler staple`。
6. `hdiutil` 生成 DMG(可自定义背景/布局)。
7. 签 DMG。

Universal:`nim c --cpu:arm64` + `nim c --cpu:amd64` + `lipo -create`。

### 5.2 Windows(M8)

- `-d:windowsgui`;资源(图标/manifest/版本)用生成的 `.rc`/`.res` 或直接嵌入。
- NSIS 安装器:用户级安装 `%LOCALAPPDATA%\Programs\<name>`;开始菜单/桌面快捷方式;卸载项;文件关联/URL scheme。
- 签名:signtool(Windows)/osslsigncode(其他平台);时间戳。
- WebView2 Runtime 检测/引导安装。

### 5.3 Linux(M9)

- 可执行文件 + `.desktop` + hicolor 图标 + MIME XML。
- `.deb`:纯 Nim 写 ar + control.tar.gz + data.tar.gz;安装 `/opt/<slug>`;`/usr/bin` 链接。
- `PKGBUILD`:Arch;依赖映射;`options=('!strip' '!debug')`。
- `install.sh`:POSIX sh;`~/.local/<name>.app`;desktop/MIME;依赖检查;Ed25519 更新验签。
- 依赖:GTK3 + WebKitGTK 4.1(可配置关闭)。

### 5.4 更新(M7)

- 清单 JSON:`version/notes/date/url/size/signature/deltas/previous`。
- Ed25519 签名 SHA-256;公钥嵌入 app。
- 归档 tar.gz;delta(bsdiff + 逐文件 SHA-256)。
- 安装:macOS 交换 `.app` 后重启;Linux 重命名替换;Windows 重命名旧 exe,下次启动清理。
- 包管理器安装的 app 禁用自更新。
- GitHub Releases / S3/R2 上传。

---

## 6. 插件模型

### 6.1 第一版:静态模块

- 插件是 Nim 包,`import nimi_plugin_xxx`;编译进 app。
- 注册:`use(plugin)`;服务名 `plugin:<name>`。
- 优点:简单、可静态分析、无 ABI 问题。
- 缺点:不能独立分发。

### 6.2 后续:动态库

- 插件编译为 `.dylib`/`.dll`/`.so`,导出 C ABI。
- 需要版本化 ABI、初始化/销毁、错误边界。
- 注意 Nim 运行时/GC 跨库问题;插件与宿主必须同一 MM/编译器版本,或插件只通过 C ABI 传值。
- 第一版不做;保留 `Plugin` 接口。

### 6.3 官方插件优先级

| 插件 | 优先级 |
|---|---|
| fetch / websocket / sqlite | P1(应用常用) |
| watch | P1(可先用 core 文件监视) |
| updater | M7 |
| terminal / glass / game / loading / sfsymbols / permissionflow / automation | P2 |

---

## 7. 测试与基准

### 7.1 Fake 后端

- 实现完整 `platform.Backend`/`Window`/`Surface`,无 GUI。
- 记录窗口、菜单、脚本、剪贴板、通知、Cookie、watch、hotkey 等。
- 可注入错误/延迟。
- 核心测试用它;测试不依赖 wall clock。

### 7.2 E2E

- 真实后端 + 测试页面。
- macOS:`CGEvent`/NSEvent 驱动;Linux:XTEST + Xvfb;Windows:SendMessage/mouse_event + WebView2 DevTools。
- 自动化 socket 协议:兼容 MyGo 的 `MYGO_AUTOMATION` 格式(或 `NIMI_AUTOMATION`),提供窗口/元素树/点击/输入/菜单/截图/Eval/idle。
- 测试规则:等待条件而非 sleep;超时只用于把挂起变失败。

### 7.3 黄金测试

- scene/raster/text PNG 对比;允许字体/平台差异。
- TS 输出黄金测试:复用 MyGo `tsgen` 测试用例,逐项对比(允许命名空间差异)。
- 布局缓存:随机树 + 有/无缓存对照。

### 7.4 基准

- 启动时间、空闲 CPU/内存、帧时间、输入延迟、二进制大小。
- 参考 MyGo 的 `scripts/bench.ts`:中位数、历史 JSON、CI 三平台。
- 应用大小基线:`hello`(webview)与 `counter-native`(原生 UI)。

---

## 8. 与其他文档的关系

- 平台细节:[02-macos-backend.md](02-macos-backend.md)、[06-windows-linux.md](06-windows-linux.md)
- UI 细节:[03-native-ui.md](03-native-ui.md)
- 实施顺序:[05-roadmap.md](05-roadmap.md)
- API 映射:[07-api-mapping.md](07-api-mapping.md)
