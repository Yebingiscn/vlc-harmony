# VLC 3.0.24 / OpenHarmony migration

- Base: official VideoLAN tag `3.0.24`, commit
  `6de05adcbaf2e8b85fe86aad4169393098628119`.
- FFmpeg remains `n8.1.2` (`38b88335f99e76ed89ff3c93f877fdefce736c13`)
  with the existing OHCodec patches, including the input/output wakeup fix.
- `0030-vlc-3.0.24-ohos.patch` replaces the former VLC 3.0.21 patch sequence.
  Historical patches remain for reference, but are no longer applied.

The migration uses a three-way comparison between upstream 3.0.21, the patched
OpenHarmony tree, and upstream 3.0.24. Upstream FFmpeg compatibility changes are
retained instead of reapplying older replacements. OpenHarmony threads, font
lookup, windowing, audio output, Surface/Buffer support, transparent OSD,
rate-transition fixes, SubRip support and playback diagnostics are retained.

Conflict resolutions preserve upstream dynamic audio channel allocation, newer
pixel-format mappings, VCD track parsing and end-track accounting. The local
Opus initialization guard, VCD MODE1/2048 geometry, and Blu-ray parser reset
behavior are retained; Blu-ray timestamp conversion uses the new upstream macro.

Local validation: patch applies to the pinned clean release; preflight feature
assertions pass; 7 audio queue and 6 decoder-wakeup scenarios pass. ARM64 SDK
syntax checks cover codec/audio/video adapters, avformat demux/mux, encoder,
Surface output, audio output, threads, clock, vout and VCD code using FFmpeg
8.1.2 headers. These do not substitute for full Linux CI compilation/linking or
device playback tests. Existing app binaries stay unchanged until the new
artifact is built and installed.
