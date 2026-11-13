# Nimi Environment Manager

Windows 环境变量编辑工具，使用 Nimi 的 Win32 后端、原生 UI、GDI 渲染和注册表存储。首版已交叉编译；尚未通过 Windows 实机运行验收。

Windows 上安装 Nim 2.4 后，在仓库根目录构建：

```powershell
nim c --passL:-Wl,--subsystem,windows -o:NimiEnvironment.exe examples/environment/main.nim
.\NimiEnvironment.exe
```

这里用链接器参数 `-Wl,--subsystem,windows` 选择 GUI 子系统，以避开 Nim 2.4.0 的 `--app:gui` / `MessageBoxA` 声明顺序问题。

macOS 上安装 Nim 和 Zig 后运行 `./scripts/windows-cross-build.sh`。程序输出为 `dist/windows-tests/NimiEnvironment.exe`，不依赖 WebView2。交叉编译不能代替运行验收。

- User / System 分别管理当前用户与系统变量；系统写入需要管理员权限，程序不会自动提权。
- 选择变量编辑原始值；新建变量用 New variable。展开类型由复选框控制；已有变量保留原类型。
- PATH 既可整体编辑，也可分项添加、替换、删除和调整顺序；空项和重复项不会自动清理。分项输入修改后需用 add / replace 应用；Save 会阻止遗漏的分项草稿，未应用草稿可用 Discard entry draft 放弃。
- 保存前检测外部修改，检测到冲突则拒绝覆盖。该比较不是注册表原子事务。
- 每次保存、删除或恢复前都写入 JSON 恢复记录，默认目录为 `%LOCALAPPDATA%\Nimi\Environment\backups`。记录包含原始值，应按变量本身的敏感程度保管。
- 将记录路径填入 Backup / restore 并点击 Restore backup。恢复会比较当前值与记录中的操作后值；不会强制覆盖后续外部修改，恢复前也会生成新记录。
- 空字符串与删除是不同操作。Delete 有确认；切换变量、作用域、刷新和关窗会确认丢弃未保存内容。
- 保存后发送环境变更通知；已运行的程序通常需要重新启动才能取得新值。

当前限制：GDI 基础渲染，不包含图像/多边形、完整字体 shaping 或无障碍；中文/emoji 的 UTF-16 输入桥已实现，但 IME 组合与候选窗位置、高 DPI、多显示器、真实键鼠操作均需 Windows 验收。尚无签名和安装器。

测试：`tests/test_environment*.nim` 覆盖业务与注册表，`tests/test_windows_host.nim` / `tests/test_windows_surface.nim` 覆盖窗口生命周期及原生绘制链。Windows CI 已配置但尚未取得运行结果。共享视图还通过本机 UI 测试验证 PATH 操作、未保存确认和窄窗口滚动；这不代替 Windows/GDI 实机测试。
