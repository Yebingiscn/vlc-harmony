# Third-party notices

The MIT license in [`LICENSE`](LICENSE) applies to the original source code of
this repository unless a file states otherwise. It does not replace or modify
the licenses of bundled third-party software, source code, patches, media, or
binary libraries.

The application package includes libVLC, VLC plugins, FFmpeg, and other native
dependencies. Those components remain subject to their respective licenses and
notice requirements. The license information presented by the application is
stored in:

- `entry/src/main/resources/rawfile/vlc_license.txt`
- `entry/src/main/resources/rawfile/libraries.json`
- `entry/src/main/resources/rawfile/authors.json`

Some files under `ohos_vlc/`, imported headers, generated files, and bundled
assets contain their own copyright or license notices. Those notices take
precedence for the corresponding files.

The native build recipes target VLC 3.0.24 with OpenHarmony patches,
FFmpeg 9.0.2, OpenSSL 3.5.9 LTS (Apache-2.0), dav1d 1.5.5 (BSD-2-Clause),
and zlib 1.4 (Zlib). Checked-in packages may still carry the previous versions
until the native artifact is rebuilt and synchronized. The FFmpeg OHCodec patch subset is derived from
`Yebingiscn/libmpv-ohos-ErBW_s-5en` at commit
`54f298cddd162f459ed49e58974e3b8e763db177`; each imported patch retains its
upstream authorship and license terms. VLC's FFmpeg compatibility changes are
derived from the official VLC 3.0.x history at the commit pinned in
`ohos_vlc/recipes/vlc-ffmpeg9.HPKBUILD`.

Before distributing an application package, review the exact native plugins
and libraries included in that package and satisfy their source-code,
attribution, relinking, and notice obligations. The VLC name and traffic-cone
logo may also be subject to trademark rules independent of copyright licenses.
