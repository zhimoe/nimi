# Nim 实践参考

> 参考仓库:[planetis-m/skills](https://github.com/planetis-m/skills)
> 结论:**值得参考**。它不是框架代码,而是一组面向 Nim 库开发的工程规范;其中 C 绑定、回调、资源所有权和 API 设计几篇直接适用于 Nimi。

---

## 1. 采用了哪些

| Skill | 采用点 | Nimi 中的落点 |
|---|---|---|
| `nim-c-bindings` | 两层绑定:raw FFI 与 ergonomic 层分离;`bycopy`/字段顺序/ABI 类型;系统库用 `-l`、运行时库用 `dynlib`;不要混用 header 与 dynlib | `platform/darwin/objc.nim`(raw runtime 调用)vs `platform/darwin/app.nim`/`window.nim`(业务层) |
| `nim-c-wrappers` | C 回调只用 `{.cdecl.}` 顶层 proc;闭包状态走 userdata/`rawProc`+`rawEnv`+`GC_ref`;资源用 move-only/RC 包装;错误在边界转异常 | 运行时类方法、app delegate、window delegate 都是顶层 `{.cdecl.}`;状态经 `gState`/ID 表,不把 Nim 闭包传给 C |
| `nim-c-wrappers` | 不要在 C 边界混用 ARC 与手动 retain/release | ObjC 对象由 `objc.nim` 的 `retain`/`release`/`autorelease` 管理;Nim 堆与 ObjC 堆分离 |
| `nim-api-design` | 公开数据优先 `object`;`ref object` 仅用于身份/共享/句柄;`newX`/`initX` 命名;集合接口遵循 stdlib | `WindowOptions` 是值对象;`Window`/`App`/`Backend` 是 `ref object`;`newWindow`/`newEvent`/`newDarwinBackend` |
| `nim-code-organization` | 显式状态对象、窄导出、按职责分模块 | `platform/darwin/types.nim` 集中状态;`app`/`window`/`objc` 分离;`core` 不 import 具体后端 |
| `nim-debugging/arc_optimization` | 用 `--expandArc` 诊断热路径意外拷贝;`move` 用于 `var` 参数字段/循环索引元素 | 后续 UI/布局热路径的优化清单 |
| `atlas-package-cloner` | Atlas/Nimble 包管理与可复现依赖 | 后续 CLI/CI 的打包参考 |
| `nim-c-bindings` 的 CI/release 参考 | 三平台构建、发布 draft release | M7/M8/M9 的 CI 参考 |

## 2. 有意偏离的地方

| 规范 | 我们的做法 | 原因 |
|---|---|---|
| 优先 `importc` + `header` | macOS 用 `dlopen` + runtime `objc_msgSend` | 不依赖 ObjC 头文件/编译 `.m`;可在任意 macOS 构建机编译 |
| raw binding 尽量薄、只导出 C 名 | `objc.nim` 提供 `sendVoidId` 等 ergonomic helper | ObjC 消息发送没有统一 C 原型;按签名封装是必要的 |
| 回调带 userdata | 用全局 `gState` + 窗口 ID 表 | 单应用单后端;比给每个回调传 context 更简单;后续多实例时再改为显式 userdata |
| 不用 `set[Enum]` 表示 C bitflags | 我们在 Nim 侧用 `set[WindowStyle]` 等 | 这些是 Nim 内部风格,不是 C struct 字段;传给 C 前转成 `NSUInteger` |

## 3. 对后续里程碑的直接建议

1. **M2 Surface/输入**:运行时类方法继续用顶层 `{.cdecl.}`;窗口/视图 ID 走显式表,不捕获 Nim `ref` 到 C。
2. **ObjC 资源**:在 `objc.nim` 上增加 `Owned[T]`/`Borrowed[T]` 或 RC 包装,避免 `window`/`view`/`block` 生命周期散落。
3. **C 绑定 CI**:Windows/Linux 后端按 `nim-c-bindings` 的 CI 模板建三平台矩阵;Linux 使用 `dlopen` 时注意不要同时加 `header`。
4. **热路径**:布局/绘制/字形缓存用 `--expandArc` 检查闭包与 seq 拷贝;`children` 模板优先于 `proc` 闭包。
5. **API 评审**:公开类型先问"值还是身份";`WindowOptions`/`Cookie`/`AccessNode` 用值对象,`Window`/`Session`/`Tray` 用 ref。

## 4. 不适用/暂不采用

- `nim-fuzzing`、`nim-defect-analysis`、`nim-doc-comments` 等偏通用工程实践,后续按需。
- `atlas-package-cloner` 的具体 Atlas 工作流尚未采用;当前用 Nimble + 直接 `nim c`。M7 打包时再评估。
- 该仓库的 skill 是给"开发 Nim 库"的代理用的;我们不会把整个仓库 vendored 进 Nimi,只把它作为规范参考。

---

*参考仓库为第三方内容;此处只记录我们采用/偏离的工程决策,不复用其代码。*
