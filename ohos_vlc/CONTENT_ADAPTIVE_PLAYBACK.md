# OHCodec 智能倍速与视频可变帧率

## 策略

- 智能倍速：API 26 参数运行时可用且实际为硬件解码时，H.264/H.265/H.266 在 Configure 阶段启用 ADAPTIVE 与 1.0 倍速，为系统初始化 MV 信息输出。Start 后、首个输入包前切回 FULL；大于 1 倍速再启用 ADAPTIVE，恢复正常/慢速切回 FULL。不使用 UNIFORM，也不设置固定保留比例。
- Configure 拒绝智能参数时销毁未启动的解码器，重建并使用普通配置。运行态开启失败停用该优化；FULL 恢复失败每 250ms 重试，后续用户速度/跳转请求可打断等待。原有解码和音画时钟不被替换。
- 可变帧率：只在实际硬件解码、直接 Surface 输出、源帧率已知且大于 30fps、正常速度、UI 允许的场景请求。Buffer/间接 Surface、慢速、倍速、未知帧率不启用。
- UI 允许条件：播放器处于前台全屏且播放中，无控制栏、半模态、菜单、手势 HUD、拖动、长按倍速、方向弹窗或画中画。开启前等待 800ms；旋转/尺寸变化额外等待 1200ms。交互和退出立即撤销允许状态。
- `OH_MD_KEY_FRAME_RATE` 使用源视频的真实有理数帧率（例如 60000/1001），不乘倍速、不猜测 60，不设置屏幕刷新范围。系统自行决定刷新率，且成功接收配置不代表硬件一定实际启用能力。
- 时间戳：智能丢帧不应导致把有效输出 PTS 改成旧输入 PTS。保留有效设备时间戳，仅对缺失/全零的厂商时间戳使用原有映射回退；此类厂商异常无法确定被保留帧的真实位置，检测后停用可选丢帧能力并恢复 FULL，优先保证音画同步。保留 2 秒重排窗口并清理更旧的映射，队列满时只移除最旧一项。seek 的原有清理保留。

## 开关与诊断

`entry/src/main/ets/common/data/VideoRefreshPolicy.ets` 中的 `ENABLE_VIDEO_VARIABLE_REFRESH` 是代码开关，不新增设置页入口。关闭后保留系统默认刷新策略。

原生 `[OHCodecPolicy]` 日志包含 MV 初始化、ADAPTIVE/FULL 请求、VRR on/off、源帧率与错误/重试状态。`requested=ok` 表示配置已接受，不表示已确认设备存在 MV/VRR 硬件收益。日志仍由已有 `ENABLE_PLAYBACK_DIAGNOSTICS` 开关控制。

NAPI 使用 `dlsym` 查找新 VLC 函数，允许 HAP 在旧原生库上安全运行；旧库不会实际启用新增能力。需要重新构建并替换 VLC/FFmpeg 原生库后才能验证完整效果。

## 验证

- `node ohos_vlc/test_codec_policy.cjs <patched-ffmpeg-tree> <host-clang> <temporary-directory>`：运行实际策略与时间戳函数，覆盖初始化/降级、2→1 倍速、恢复重试、Surface/Buffer/软解/旧系统限制和丢帧 PTS。
- `node entry/src/test/video-refresh-policy.cjs <typescript.js>`：检查场景等待、立即关闭、取消过期任务、旋转等待和退出清理。
- 云端 `validate_native_patchset.sh` 在耗时编译前应用并验证 0030→0031 与 FFmpeg 补丁链，同时运行策略测试。产物校验增加新策略标记，防止缓存旧库被误当成更新。
- 真机重点：60fps H.264/HEVC 正常播放，长按 2/3 倍速后恢复，字幕切换，控制栏/半模态弹出，连续拖动，横竖屏，分屏，PiP，以及 Buffer 对照。需观察实际掉帧、功耗和音画同步，不能仅凭 SetParameter 成功判定优化有效。

## 官方参考

- [智能流畅倍速解码](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/video-smart-fluency-decoding)
- [视频可变帧率](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/video-variable-refreshrate)
