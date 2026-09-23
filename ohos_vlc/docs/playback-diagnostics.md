# Playback diagnostics

The application-side switch is `ENABLE_PLAYBACK_DIAGNOSTICS` in
`entry/src/main/ets/libvlc/LibVLC.ets`. It is currently enabled for investigation.
Set it to `false` for normal/release builds. There is no settings UI.

Changing this constant requires rebuilding/reinstalling the HAP, **not** rebuilding
VLC/FFmpeg. The native stage probes below need to be included once in the native
artifact (patch 0026); an older native artifact will not have those probes.

Capture application HiLog from before opening a video until several seconds
after the stutter. Look for `PlaybackTrace`, `PlaybackStage`, `OHSurfaceTiming`,
`OHCodecStall`, `OHCodecQueue`, `OHCodecPTS`, and `Audio Delay`.

- `send`: compressed input submission taking >=5 ms, or backpressure/EAGAIN.
- `receive`: successful decoded outputs and calls taking >=5 ms, with PTS.
- `picture-pool`: Surface picture acquisition taking >=5 ms.
- `subtitle-render`: VLC subtitle composition taking >=5 ms.
- `display`: display callback duration, lateness and target deadline.
- `OHSurfaceTiming`: slow system Surface submission or an already-late frame.
- Existing FFmpeg records: output callback gaps, queue pressure, timestamp fallback.
- Existing audio records: queued PCM, estimated output delay and clock corrections.

Trace records include capture-time monotonic microseconds (`t`) and a producer
thread identifier (`tid`). HiLog delivery time can be later because output is
asynchronous. Do not equate media PTS with the monotonic display deadline.

The producer uses a try-lock, a 256-record queue and a 400-record/second budget.
`TraceBudget omitted=...` means records were intentionally omitted: missing trace
lines then do not prove the decoder stopped. Legacy per-frame pointer dumps stay
disabled. Normal warnings/errors remain available when diagnostics are off.

Logs may contain media names/paths from VLC. Review them before sharing publicly.
This is diagnostic instrumentation, not proof that all stutter is resolved.
