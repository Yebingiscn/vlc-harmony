# ohos_vlc 本地修改补丁归档

本目录归档 `ohos_vlc/` 工作区对 libVLC 源码的本地修改（补丁 + 构建脚本），
供 vlc-harmony 应用构建时复现使用。原始修改位于工作区 `ohos_vlc/`，此处为版本化副本。

## 补丁列表（按应用顺序）

| 补丁                                                            | 内容                                                               |
|---------------------------------------------------------------|------------------------------------------------------------------|
| `0001-avcodec-respect-disabled-hardware-decoding.patch`       | avcodec 解码器尊重 `:avcodec-hw=none`（禁硬解时不再尝试硬件）                     |
| `0002-avcodec-fallback-to-software-on-hw-start-failure.patch` | 硬解启动失败回退软解                                                       |
| `0003-vcd-mode1-2048-iso.patch`                               | VCD access 支持 CUE `MODE1/2048` 的 ISO9660 镜像（修复 2352/2048 扇区错位花屏） |
| `0004-bluray-seek-fix.patch`                                  | libbluray seek 定位修复                                              |
| `0005-vcd-iso9660-no-cue.patch`                               | VCD 无 .cue 时自动解析 ISO9660 定位 `MPEGAV/AVSEQ*.DAT` 作为视频轨（单文件播放）     |
| `0006-ohosavcodec-seek-safety-and-input-pacing.patch`         | FFmpeg OHCodec：Flush 代数隔离、回调队列清理、大访问单元分片和输入/输出交错推进            |
| `0007-vlc-ohos-surface-clocked-present.patch`                 | VLC Surface 帧按播放时钟上屏；预滚/损坏帧只解码不显示，消除 seek 旧帧闪回             |
| `ffmpeg-hpkbuild-apply-local-patches.patch`                   | 修改 FFmpeg-surface-dev HPKBUILD，自动应用 0006                         |
| `vlc-hpkbuild-apply-local-patches.patch`                      | 修改 VLC HPKBUILD 的 `prepare()`，自动应用 0001–0005、0007               |
| `vlc-hpkbuild-build-dvbpsi.patch`                             | 修改 HPKBUILD 构建 dvbpsi 依赖                                         |

## 应用方式

`prebuild.sh` 会分别把 0006 注入 Lycium 的 `community/FFmpeg-surface-dev`
recipe，把其余补丁注入 `thirdparty/vlc` recipe，然后构建并同步新的 FFmpeg/VLC
动态库。只重新编译 HAP 不会让 0006、0007 生效，修改这两份补丁后必须重新运行
`ohos_vlc/prebuild.sh`（Linux 环境、API 18 SDK）。构建成功后脚本会自动调用项目根目录的
`sync_native_libs.sh`，把新库同步到 `entry/libs/arm64-v8a` 和 NAPI 链接目录。

## GitHub Actions 构建

仓库中的 `.github/workflows/build-native-vlc.yml` 提供了与 `libmpvNative`
类似的 Linux 云端构建流程。它会下载并校验 HarmonyOS 5.1.0 Release 的 API 18
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
for p in 0001-*.patch 0002-*.patch 0003-*.patch 0004-*.patch 0005-*.patch 0007-*.patch; do
  patch -p1 < patches/$p
done
```

0006 需要在 FFmpeg `ohosdecoder_surface_dev` 分支源码根目录单独应用：

```bash
patch -p1 < patches/0006-ohosavcodec-seek-safety-and-input-pacing.patch
```
