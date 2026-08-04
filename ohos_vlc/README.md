# ohos_vlc 本地修改补丁归档

本目录归档 `ohos_vlc/` 工作区对 libVLC 源码的本地修改（补丁 + 构建脚本），
供 vlc-harmony 应用构建时复现使用。原始修改位于工作区 `ohos_vlc/`，此处为版本化副本。

## 补丁列表（按应用顺序）

| 补丁 | 内容 |
|------|------|
| `0001-avcodec-respect-disabled-hardware-decoding.patch` | avcodec 解码器尊重 `:avcodec-hw=none`（禁硬解时不再尝试硬件） |
| `0002-avcodec-fallback-to-software-on-hw-start-failure.patch` | 硬解启动失败回退软解 |
| `0003-vcd-mode1-2048-iso.patch` | VCD access 支持 CUE `MODE1/2048` 的 ISO9660 镜像（修复 2352/2048 扇区错位花屏） |
| `0004-bluray-seek-fix.patch` | libbluray seek 定位修复 |
| `0005-vcd-iso9660-no-cue.patch` | VCD 无 .cue 时自动解析 ISO9660 定位 `MPEGAV/AVSEQ*.DAT` 作为视频轨（单文件播放） |
| `vlc-hpkbuild-apply-local-patches.patch` | 修改 HPKBUILD 的 `prepare()`，自动应用上面 0001–0005 |
| `vlc-hpkbuild-build-dvbpsi.patch` | 修改 HPKBUILD 构建 dvbpsi 依赖 |

## 应用方式

`prebuild.sh` 的 `install_vlc_patches()` 会把补丁复制到 Lycium 的 vlc recipe 目录，
并用 `vlc-hpkbuild-apply-local-patches.patch` 让 HPKBUILD 在构建时按序应用。

手动应用（在 vlc 源码根目录）：

```bash
for p in 0001-*.patch 0002-*.patch 0003-*.patch 0004-*.patch 0005-*.patch; do
  patch -p1 < patches/$p
done
patch -p1 < patches/vlc-hpkbuild-apply-local-patches.patch
patch -p1 < patches/vlc-hpkbuild-build-dvbpsi.patch
```

## 与远端构建主机同步

构建主机（`w00417029@192.168.8.65`）的源码树：
`~/code/vlc_project/openharmony_tpc_samples/ohos_vlc/tpc_c_cplusplus/thirdparty/vlc/vlc-ohos-3.0.21/`

修改补丁后需在主机上重新应用并增量重编对应插件（见工作区 AGENTS.md 的远程构建说明）。
