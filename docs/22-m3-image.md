# M3 切片:原生 Image 控件

> 日期:2026-11-05 · 对应 M3 基础绘制原语

---

## 1. 已完成

- Scene:`opImage` + `scene.image(path, rect)`
- CoreGraphics/ImageIO 渲染:
  - `CGImageSourceCreateWithURL`
  - `CGImageSourceCreateImageAtIndex`
  - `CGContextDrawImage`
  - 按路径缓存 `CGImage`
- Native UI:`ui.image(c, path, width, height)`
- 离屏 PNG 也可包含图片
- 示例 `examples/image-native`
- 测试 `test_render` 覆盖图片离屏渲染

## 2. 关键决策

| 决策 | 原因 |
|---|---|
| 用 ImageIO 解码 | 系统支持 PNG/JPEG/HEIC 等格式,无需第三方库 |
| Scene 增加 opImage | CPU/Metal 后续都从同一 display list 读取 |
| 按路径缓存 CGImage | 避免每帧重新解码;资源更新可后续加失效 |
| 控件要求显式尺寸 | 不引入 intrinsic size/异步测量;先支持图标/封面 |
| 不做裁剪/圆角 | 保持 scene op 简单;后续加 clip/圆角变体 |

## 3. 验证

```sh
NIMI_SMOKE=image nim c -r --path:src examples/image-native/main.nim
# image path: .../examples/notes/resources/icon.png
# png written: true

./scripts/test.sh
# [OK] image png
```

离屏 PNG 截图确认图片方向、尺寸和文字布局正确。

## 4. 已知限制

- 没有 aspect-fit/aspect-fill/裁剪/圆角
- 没有异步加载/网络图片/进度
- 路径变化不会自动清缓存
- 没有 SVG/PDF/视频帧
- 没有 Retina 多倍图选择
- 通用 Metal scene 渲染器尚未消费 opImage;`render/metal.nim` 目前是碎纸专用 mask/LayerEffect

## 5. 下一步

1. `ImageFit`(contain/cover/fill)与圆角裁剪。
2. 异步解码、内存/磁盘缓存、失败占位图。
3. 从资源 bundle / `nimi://` 加载图片。
4. Metal 纹理上传与 opImage 共用缓存。
