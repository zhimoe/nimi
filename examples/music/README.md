# Nimi Music

Nimi 自绘音乐播放器示例，通过 `nimi/audio` 接入 macOS AVAudioPlayer 与 Linux GStreamer。Windows 音频后端待实现。

```sh
nim c -r --path:src examples/music/main.nim
./nimi build examples/music
```

当前支持本地文件导入、自动/手动队列切换、顺序/单曲/列表循环、随机播放、历史返回、退出恢复、播放/暂停、进度拖动和音量。本地文件格式取决于系统解码器或已安装的 GStreamer 插件。自动化测试使用生成的无声 WAV，真实输出设备和完整格式矩阵另需验证。

会话保存在 `getConfigDir()/nimi-music/session.json`，版本 2 保存每首歌的路径、标题、歌手、专辑、来源、远程 ID、封面 ID 和时长；仍能读取版本 1 的纯路径会话并迁移为本地曲目。恢复队列、进度、音量与模式但不自动播放。正常退出保存，崩溃恢复与周期性检查点尚未实现。

播放器从 macOS delegate 或 Linux GStreamer 接收结束事件。暂停不触发自动切歌。播放器须在主线程使用并显式关闭。切歌时先确认新文件可加载，再关闭旧播放器。大文件的加载延迟尚待测量。

远程歌曲的封面通过后台 `getCoverArt` 下载，缓存到 `getCacheDir()/nimi-music/covers`，当前播放区显示封面；会话保存封面路径。macOS 通过 `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` 集成 Now Playing，Linux 通过 MPRIS2 集成系统媒体控制：系统媒体控制显示标题/歌手/专辑/进度，播放/暂停/seek/上一首/下一首/停止回传到应用。待完成：流式播放、服务登录与 Keychain、真实媒体键人工验收、视觉和交互对齐参考应用。真实媒体键与发布验收见 [平台清单](../../docs/backlog/README.md)。

曲库使用固定行高虚拟列表；Now playing 将当前歌曲定位到可见区域。一万行构建数量和点击行为已有自动测试，真实大曲库性能尚待测量。

已接入同名 `.lrc` 后台加载和当前行显示，支持多时间戳与 offset。切歌取消旧任务的交付，关闭等待后台任务完成。尚不支持逐字歌词与翻译。

## Subsonic 开发接入

Server search 通过后台任务查询前 100 首歌曲；连接参数使用 `NIMI_SUBSONIC_URL`、`NIMI_SUBSONIC_USER`、`NIMI_SUBSONIC_PASSWORD` 环境变量，仅作为开发入口。应用不将这些值写入会话或日志；系统 curl 通过 stdin 接收认证 URL，参数不进入进程命令行。正式账号 UI/Keychain 尚未接入。HTTP 可用于私有网络，HTTPS 使用系统 curl 的默认证书校验，不允许跳过验证。

请求有 15 秒最大耗时和 8 MiB 响应上限，不跟随重定向。点击服务器结果可后台下载并加入播放队列，尚无分页按钮、歌单操作和服务端收藏。测试用临时本地 HTTP 服务验证认证及结果，无真实账号连通性验收。

远程播放采用完整下载后播放：单文件 128 MiB、60 秒超时、总缓存 1 GiB；缓存按服务器/用户名/歌曲 ID 区分，位于 `getCacheDir()/nimi-music/audio`。空间满时拒绝新下载，不自动删除队列引用的文件。成功传输后才发布缓存，JSON/XML 协议错误和失败临时文件会清理。实际解码仍由系统决定；缓存文件名是不透明哈希，但歌曲标题/歌手/专辑/封面 ID 会随队列和会话保存。

下载使用独立的容量 2 后台执行器，避免阻塞歌词和搜索。切换本地歌曲、再次选远程歌曲、暂停会取消旧下载的播放回调；取消会轮询并终止 curl，退出时 `close(100)` 有界等待。封面单独缓存、单文件上限 8 MiB、总预算 256 MiB；真实流式播放与缓存管理 UI 仍待开发。
