# macOS CI 与构建产物

> 更新于 2026-11-24。覆盖 M7 中的自动化测试和示例打包。

## 工作流

[macOS CI](../.github/workflows/macos.yml) 在 `macos-15` runner 上安装 Nim 2.4.0，运行
`./scripts/test.sh`，编译 CLI，并构建 `desktop-native`、`protocol-native`、
`notes`、`music`、`shred-native`、`shred-metal` 的 `.app` 与 DMG。
DMG 通过 `hdiutil verify` 后作为 `nimi-demo-dmgs` 上传，保留 7 天。

CLI 按构建架构使用 `dist/darwin-arm64/` 或 `dist/darwin-amd64/`。当前 workflow
使用单一 runner。发布版双架构、Developer ID 签名、公证与升级验证见 [macOS backlog](backlog/macos.md)。

## 验证结果

- 2026-11-24，本地 macOS arm64 / Nim 2.4.2 全量测试通过，共 192 项。CI 清单中的六个示例均重新构建并通过 DMG 校验。
- 2026-11-22，GitHub Actions 的测试与 CLI 构建通过。示例构建阶段执行
  `hdiutil verify` 检查 `nimi-protocol-0.1.0.dmg` 时返回 `Resource temporarily unavailable`，随后跳过 DMG 上传。
  [失败运行](https://github.com/zhimoe/nimi/actions/runs/44978676441)
- 最近一次完成 DMG 校验和上传的运行发生在此次回归之前。
  [成功运行](https://github.com/zhimoe/nimi/actions/runs/44969596878)

## 本地复核

```sh
./scripts/test.sh
nim c -d:release --hints:off -o:nimi src/nimi/cli.nim

for example in desktop-native protocol-native notes music shred-native shred-metal; do
  ./nimi build "examples/$example" || exit
done
for dmg in examples/*/dist/darwin-*/*.dmg; do
  hdiutil verify "$dmg" || exit
done
```

其他平台以及系统交互的验收入口见 [开发基线](28-remediation-status.md#自动化与实机验收)。
