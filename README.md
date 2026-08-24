# vlc-harmony

`vlc-harmony` is a HarmonyOS media player built around libVLC. The application
UI is written in ArkTS/ArkUI, while media playback and video output are provided
through a C++ NAPI bridge, HarmonyOS `XComponent`/`NativeWindow`, and VLC native
plugins.

> Development status: active development on the `dev` branch. Core local
> audio/video playback works, but some VLC Android companion features are still
> incomplete or intentionally hidden.

## Features

- Local audio and video discovery
- Unified libVLC audio/video playback
- Playback queues, shuffle, repeat, per-track and global playback speed
- Audio, subtitle, and video track selection
- Chapter navigation and external subtitles
- Equalizer and renderer discovery interfaces
- Playback history, queue recovery, playlists, bookmarks, and favorites
- Background audio, system media session, and picture-in-picture integration
- Headset, audio interruption, call-state, and metered-network handling
- Hardware acceleration modes and HarmonyOS native video output

Known incomplete areas include online subtitle services, the full equalizer
preset repository, widget support, remote-access OTP, benchmark integration,
and some file/device-management flows.

## Requirements

- DevEco Studio with HarmonyOS SDK 6.0.1 (API 21)
- A HarmonyOS phone or emulator with `arm64-v8a` support
- Node.js/Hvigor supplied by DevEco Studio
- A local signing configuration when installing a signed HAP on a device

Only `arm64-v8a` is currently configured.

## Build

1. Clone the repository and switch to `dev`.
2. Open the repository root in DevEco Studio.
3. Let OHPM restore the project dependencies.
4. Configure automatic signing locally in DevEco Studio if device installation
   is required. Signing paths and passwords must not be committed.
5. Build the `entry` module with the `default` target.

The generated HAP is placed under:

```text
entry/build/default/outputs/default/
```

The repository already contains the native libraries needed by the app. To
rebuild or resynchronize those libraries, see [`ohos_vlc/README.md`](ohos_vlc/README.md)
and [`sync_native_libs.sh`](sync_native_libs.sh). Rebuilding libVLC requires a
Linux environment, an OpenHarmony/HarmonyOS native SDK, and the dependencies
installed by the prebuild script.

The reproducible native pipeline keeps the OHOS VLC 3.0.21 platform port and
builds it against FFmpeg 8.1.2 and OpenSSL 3.4.3. OHCodec output uses source
timestamps and the system's refresh-rate policy; the app does not force a
fixed 60 Hz or 120 Hz display cadence.

## Tests

Unit tests live in `entry/src/test` and device tests live in
`entry/src/ohosTest`. Run the `entry` local unit-test target or `ohosTest` from
DevEco Studio. The local test suite covers pure playback-history and time-input
logic and should be extended whenever new state-machine behavior is introduced.

GitHub Actions performs repository hygiene checks. A full HAP build is not run
on a generic GitHub runner because it requires a separately provisioned
HarmonyOS SDK and signing environment.

## Project layout

```text
AppScope/                         Application metadata and icon resources
entry/src/main/ets/pages/        ArkUI pages and dialogs
entry/src/main/ets/common/       Shared components, models, and services
entry/src/main/ets/libvlc/       ArkTS wrappers around native libVLC handles
entry/src/main/cpp/              NAPI bridge and XComponent/NativeWindow code
entry/libs/arm64-v8a/            Runtime native libraries and VLC plugins
ohos_vlc/                        Reproducible libVLC patches and build scripts
```

The main playback path is:

```text
ArkUI -> PlaybackService -> ArkTS libVLC wrappers -> C++ NAPI
      -> libVLC -> HarmonyOS video-output plugin -> NativeWindow
```

## Development guidelines

- Do not commit signing files, passwords, machine-local SDK paths, or generated
  build output.
- Keep platform APIs out of pure model modules so their behavior can be unit
  tested.
- Add lifecycle regression coverage for player stop/release/recreation changes.
- Treat warnings introduced by a change as defects; the existing warning debt
  should be reduced incrementally.
- Preserve third-party copyright and license notices when updating native
  libraries or assets.

## License

Original project code is licensed under the [MIT License](LICENSE).
Bundled third-party components retain their own licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the license resources
included in the application.
