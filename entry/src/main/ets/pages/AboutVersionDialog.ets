import { AppColors } from '../common/constants/AppConstants';

/** 标签 + 值 两列行(标签列固定宽 140vp 近似 Barrier 对齐)。 */
@ComponentV2
struct VersionRow {
  @Param label: ResourceStr = '';
  @Param value: ResourceStr = '';
  @Param marginTop: number = 8;

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontColor(AppColors.grey500)
        .width(140)
      Text(this.value)
        .fontSize(14)
        .fontColor('#FFFFFF')
        .margin({ left: 24 })
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: this.marginTop })
  }
}

/**
 * AboutVersionDialog —— 「关于版本」BottomSheet。
 * 18fp Medium 版本号标题 + 12fp light 构建时间 + 14fp Changelog(• 替换 *)+ 右对齐 More 文字按钮
 * + 编译信息(Revision/Compiled by/Signed by)+ 分隔线 + libvlcjni/VLC/libvlc 版本 + 分隔线
 * + Remote access version/hash。标签列 14fp grey,值列 14fp 白。
 * 运行时值(BuildConfig.VLC_VERSION_NAME / build_* / changelog / 签名 SHA1 指纹→签名者)由调用方注入。
 */
@ComponentV2
export struct AboutVersionDialog {
  @Event onClose: () => void = () => {};
  @Event onOpenWhatsNew: () => void = () => {};

  aboutToAppear(): void {
    // TODO(契约): 版本/构建/签名信息由 BuildConfig + Gradle resValue + APK 签名指纹计算后注入:
    //   version=BuildConfig.VLC_VERSION_NAME; buildTime=$r(build_time); changelog=$r(changelog).replace('*','•');
    //   revision/build_vlc_revision/build_libvlc_revision/build_host(resValue); libvlcVersion=BuildConfig.LIBVLC_VERSION;
    //   remoteAccessVersion/Revision = resIdByName(...,"string") ?: unknown;
    //   signedBy = computeSigner()(SHA1 指纹→VideoLAN nightly/Google/VideoLAN/Amazon/F-Droid,默认 unknown)。
  }

  build() {
    Scroll() {
      Column() {
        // 版本号标题(运行时占位)
        Text('3.6.0')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 构建时间(12fp light)
        Text('2026-07-29')
          .fontSize(12)
          .fontColor(AppColors.grey500)

        // Changelog(• 替换 *)
        Text('• Bug fixes\n• Crash fixes')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .margin({ top: 16 })

        // More 文字按钮(右对齐)
        Row() {
          Text($r('app.string.more'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.orange500)
            .padding({ left: 8, right: 8, top: 8, bottom: 8 })
            .onClick(() => {
              this.onOpenWhatsNew();
              this.onClose();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: 8 })

        // ── 编译信息区 ──
        VersionRow({ label: $r('app.string.revision'), value: 'cb3c6284d', marginTop: 24 })
        VersionRow({ label: $r('app.string.is_compiled_by'), value: 'Gitlab runner' })
        VersionRow({ label: $r('app.string.is_signed_by'), value: $r('app.string.unknown') })

        Divider().color(AppColors.grey800).strokeWidth(1).width('100%').margin({ top: 8 })

        VersionRow({ label: 'libvlcjni', value: '3.6.0' })
        VersionRow({ label: 'VLC', value: '4.0.0-dev' })
        VersionRow({ label: 'libvlc', value: '4.0.0-dev' })

        Divider().color(AppColors.grey800).strokeWidth(1).width('100%').margin({ top: 8 })

        VersionRow({ label: $r('app.string.remote_access_version_title'), value: $r('app.string.unknown') })
        VersionRow({ label: $r('app.string.remote_access_hash_title'), value: $r('app.string.unknown'), marginTop: 8 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
