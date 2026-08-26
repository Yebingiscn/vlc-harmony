# ohos_vlc 本地修改补丁归档

本目录归档 `ohos_vlc/` 工作区对 libVLC 源码的本地修改（补丁 + 构建脚本），
供 vlc-harmony 应用构建时复现使用。原始修改位于工作区 `ohos_vlc/`，此处为版本化副本。

## 补丁列表（按应用顺序）

| 补丁                                                            | 内容                                                               |
|---------------------------------------------------------------|------------------------------------------------------------------|
| `0000-vlc-remove-legacy-ohos-chroma.patch`                    | 移除旧 FFmpeg OHOS 私有像素格式映射，为官方 OHCodec 接口迁移做准备                  |
| `0000-vlc-upstream-ffmpeg8-compat.patch`（构建时生成）          | 从 VLC 官方 3.0.x 固定提交提取 FFmpeg 8 兼容改动                              |
| `0001-avcodec-respect-disabled-hardware-decoding.patch`       | avcodec 解码器尊重 `:avcodec-hw=none`（禁硬解时不再尝试硬件）                     |
| `0002-avcodec-fallback-to-software-on-hw-start-failure.patch` | 硬解启动失败回退软解                                                       |
| `0003-vcd-mode1-2048-iso.patch`                               | VCD access 支持 CUE `MODE1/2048` 的 ISO9660 镜像（修复 2352/2048 扇区错位花屏） |
| `0004-bluray-seek-fix.patch`                                  | libbluray seek 定位修复                                              |
| `0005-vcd-iso9660-no-cue.patch`                               | VCD 无 .cue 时自动解析 ISO9660 定位 `MPEGAV/AVSEQ*.DAT` 作为视频轨（单文件播放）     |
| `0006-vlc-add-ffmpeg8-ohcodec-chroma.patch`                   | 为 FFmpeg 8 官方 `AV_PIX_FMT_OHCODEC` 恢复 VLC 像素格式映射                    |
| `0007-vlc-ohos-surface-clocked-present.patch`                 | VLC Surface 帧按播放时钟上屏；预滚/损坏帧只解码不显示，消除 seek 旧帧闪回             |
| `0008-vlc-ffmpeg8-ohcodec-device-context.patch`               | 使用 FFmpeg 8 的 `AVHWDeviceContext` 向 OHCodec 传递 NativeWindow          |
| `0009-vlc-forward-playback-speed-to-ohcodec.patch`            | 将 VLC 实际倍速传给 OHCodec，由系统按能力选择智能流畅策略                         |
| `0010-vlc-ohos-realtime-audio-ring.patch`                    | 音频输出改用预分配环形队列，移除实时回调中的逐块堆分配、链表遍历与高频日志，并拒绝 0 声道误启动 |
| `0011-vlc-ohos-system-refresh-low-latency-audio.patch`       | 移除 Surface 固定 60Hz 兜底，按媒体时钟提交并由系统控制刷新率；将音频软件排队限制为约 250ms |
| `0011-ffmpeg-ohcodec-system-refresh.patch`                   | 不再向 OHCodec 写入帧率或强制 VRR 参数，由 HarmonyOS 显示服务选择刷新率 |
| `vlc-hpkbuild-apply-local-patches.patch`                      | 修改 VLC HPKBUILD，按顺序应用兼容与本地功能补丁                                |
| `vlc-hpkbuild-build-dvbpsi.patch`                             | 修改 HPKBUILD 构建 dvbpsi 依赖                                         |

## 应用方式

`prebuild.sh` 会用 `recipes/ffmpeg-8.1.2.HPKBUILD` 替换 Lycium 的旧 FFmpeg
recipe，并从固定提交取得 libmpvnative 已验证的 OHCodec 补丁子集；同时从 VLC
官方固定提交生成 3.0.21 之后的 FFmpeg 兼容补丁，再注入 OHOS VLC recipe。
只重新编译 HAP 不会让原生改动生效，修改这些补丁后必须重新运行
`ohos_vlc/prebuild.sh`（Linux 环境、HarmonyOS 7.0 Beta1 API 26 SDK）。构建成功后脚本会自动调用项目根目录的
`sync_native_libs.sh`，把新库同步到 `entry/libs/arm64-v8a` 和 NAPI 链接目录。

当前原生版本基线：

- OHOS VLC：`ohos-3.0.21`（保留其 HarmonyOS 平台端口）
- FFmpeg：`n8.1.2`，提交 `38b88335f99e76ed89ff3c93f877fdefce736c13`
- OpenSSL：`3.4.3`
- OHCodec 补丁来源：libmpvnative 提交 `54f298cddd162f459ed49e58974e3b8e763db177`
- VLC FFmpeg 兼容基线：官方提交 `1089af38fc26293d0b93a9456adf7ae4a5b0b930`

没有设置固定 60 帧，也不向 OHCodec 请求特定 VRR 模式。可靠的视频时间戳仍用于
音画同步；时间戳缺失时立即交给 Surface，最终刷新率和上屏节奏由 HarmonyOS 显示
服务与设备能力决定。音频软件队列上限约为 250ms，防止长时间排队引发连续重采样。

## GitHub Actions 构建

仓库中的 `.github/workflows/build-native-vlc.yml` 提供了与 `libmpvNative`
类似的 Linux 云端构建流程。它会下载并校验 HarmonyOS 7.0 Beta1 的 API 26
原生 SDK，执行 `prebuild.sh`，然后上传
`vlc-harmony-native-arm64-<commit>` 构建产物。产物同时包含
`ohos_vlc/library/libs/arm64-v8a`、应用运行库目录和 NAPI 链接目录。
SDK 与编译结果分别缓存；补丁和构建脚本没有变化时会直接复用原生库缓存。

可在 GitHub 仓库的 **Actions → Build native VLC for HarmonyOS → Run workflow**
手动触发；推送到 `main` 或 `dev` 且 `ohos_vlc/**`、`sync_native_libs.sh`
发生变化时也会自动触发。该流程只构建原生库，不读取应用签名文件，也不生成
已签名 HAP。

手动应用（在 vlc 源码根目录）：

```bash
for p in 0001-*.patch 0002-*.patch 0003-*.patch 0004-*.patch 0005-*.patch 0007-*.patch 0008-*.patch 0009-*.patch; do
  patch -p1 < patches/$p
done
```

FFmpeg 8 与官方 VLC 兼容补丁由构建脚本按固定仓库提交生成和应用，建议不要手动
拼装，以免遗漏应用顺序。
