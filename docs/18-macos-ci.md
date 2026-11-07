# macOS CI 与构建产物

> 2026-11-06：整改、当前限制与验收级别见 [最新基线](28-remediation-status.md)。历史验证记录不代表完整能力已经验收。

> 日期:2026-11-05 · 对应 M7 CI 部分

---

## 1. 已完成

`.github/workflows/macos.yml`:

- 在 `macos-14` runner 上安装 Nim 2.4.0
- 运行 `./scripts/test.sh`
- 编译 CLI
- 构建并校验五个示例的 `.app` + DMG:
  - `desktop-native`
  - `protocol-native`
  - `notes`
  - `shred-native`
  - `shred-metal`
- 上传 DMG artifact(保留 7 天)
- 支持 `workflow_dispatch`、`push`、`pull_request`

另外,`nimi build` 的输出目录现在按真实 CPU 架构生成:

```text
examples/.../dist/darwin-arm64/
examples/.../dist/darwin-amd64/
```

## 2. 验证

本地等价命令:

```sh
./scripts/test.sh
nim c -d:release --hints:off -o:nimi src/nimi/cli.nim
./nimi build examples/desktop-native
./nimi build examples/protocol-native
./nimi build examples/notes
./nimi build examples/shred-native
./nimi build examples/shred-metal
for dmg in examples/*/dist/*/*.dmg; do hdiutil verify "$dmg"; done
```

GitHub Actions 结果在仓库 **Actions → macOS CI** 查看。

## 3. 已知限制

- 没有 release 发布 workflow(标签触发、上传 GitHub Release、更新 feed)
- 没有真正的 Developer ID 签名/公证(需要 secrets)
- 没有缓存 Nim 编译产物/ccache
- macOS runner 的架构取决于 GitHub 提供的 `macos-14` 镜像;产物目录会反映实际架构
- 没有 benchmark、UI 截图回归、崩溃日志收集

## 4. 下一步

1. `release.yml`:tag → 构建 arm64/amd64 → 签名/公证 → GitHub Release。
2. Nim/ccache 缓存。
3. 用 App Store Connect API key 完成实际 notarytool 验证。
4. 自动更新 manifest 与 Sparkle 风格更新窗口。
