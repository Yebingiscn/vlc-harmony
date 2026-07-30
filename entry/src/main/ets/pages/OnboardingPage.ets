import { NavController } from '../common/data/NavController';
import { Settings } from '../common/data/Settings';
import { AppColors } from '../common/constants/AppConstants';
import { promptAction } from '@kit.ArkUI';

enum OnboardingStep {
  WELCOME = 0,
  ASK_PERMISSION = 1,
  SCAN = 2,
  NO_PERMISSION = 3,
  NOTIFICATION_PERMISSION = 4,
  THEME = 5,
}

/**
 * OnboardingPage —— OnboardingActivity(首启引导)。
 * 6 步状态机(WELCOME/ASK_PERMISSION/SCAN/NO_PERMISSION/NOTIFICATION_PERMISSION/THEME)。
 * 深蓝灰 #011422 背景 + 底部 Next/Skip 按钮 + 选择态(选中 scale1.0+圆角框 / 未选中 scale0.8)。
 */
@ComponentV2
export struct OnboardingPage {
  @Local step: OnboardingStep = OnboardingStep.WELCOME;
  @Event onDone: () => void = () => {};

  next(): void {
    switch (this.step) {
      case OnboardingStep.WELCOME:
        this.step = OnboardingStep.ASK_PERMISSION;
        break;
      case OnboardingStep.ASK_PERMISSION:
        this.step = OnboardingStep.SCAN;
        break;
      case OnboardingStep.SCAN:
        this.step = OnboardingStep.NOTIFICATION_PERMISSION;
        break;
      case OnboardingStep.NO_PERMISSION:
        this.step = OnboardingStep.SCAN;
        break;
      case OnboardingStep.NOTIFICATION_PERMISSION:
        this.step = OnboardingStep.THEME;
        break;
      case OnboardingStep.THEME:
        this.done();
        break;
    }
  }

  skip(): void {
    this.done();
  }

  done(): void {
    Settings.put(Settings.NOTIFICATION_PERMISSION_ASKED, true);
    Settings.put(Settings.INITIAL_PERMISSION_ASKED, true);
    this.onDone();
  }

  build() {
    NavDestination() {
      Column() {
        // 内容区
        Column() {
          if (this.step === OnboardingStep.WELCOME) {
            this.welcomeContent()
          } else if (this.step === OnboardingStep.ASK_PERMISSION) {
            this.permissionContent()
          } else if (this.step === OnboardingStep.SCAN) {
            this.scanContent()
          } else if (this.step === OnboardingStep.NO_PERMISSION) {
            this.noPermissionContent()
          } else if (this.step === OnboardingStep.NOTIFICATION_PERMISSION) {
            this.notificationContent()
          } else {
            this.themeContent()
          }
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding(24)

        // 底部 Next / Skip 按钮
        Row() {
          Button($r('app.string.cancel'))
            .type(ButtonType.Normal).borderRadius(4)
            .backgroundColor('#33011422').borderWidth(1).borderColor('#33FFFFFF')
            .fontColor('#FFFFFF').fontSize(14).layoutWeight(1).margin({ right: 8 })
            .onClick(() => this.skip())
          Button(this.step === OnboardingStep.THEME ? $r('app.string.ok') : $r('app.string.next_step'))
            .type(ButtonType.Normal).borderRadius(4)
            .backgroundColor(AppColors.orange500).fontColor('#FFFFFF').fontSize(14).layoutWeight(1)
            .onClick(() => this.next())
        }
        .width('100%')
        .padding(24)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.onboarding_grey)
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }

  @Builder
  welcomeContent() {
    Column() {
      Image($r('app.media.ic_about_logo')).width(96).height(96).objectFit(ImageFit.Contain).margin({ bottom: 24 })
      Text($r('app.string.welcome_title')).fontSize(24).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
      Text($r('app.string.welcome_subtitle')).fontSize(14).fontColor('#B3FFFFFF').margin({ top: 12 }).textAlign(TextAlign.Center)
    }.alignItems(HorizontalAlign.Center)
  }

  @Builder
  permissionContent() {
    Column() {
      Image($r('app.media.ic_permission_big')).width(80).height(80).fillColor('#FFFFFF').margin({ bottom: 24 })
      Text($r('app.string.permission_media')).fontSize(16).fontColor('#FFFFFF').textAlign(TextAlign.Center).margin({ top: 16 })
      Text($r('app.string.permission_expanation_allow')).fontSize(12).fontColor('#B3FFFFFF').margin({ top: 12 })
      Text($r('app.string.permission_expanation_no_allow')).fontSize(12).fontColor('#B3FFFFFF').margin({ top: 8 })
    }.alignItems(HorizontalAlign.Center)
  }

  @Builder
  scanContent() {
    Column() {
      Image($r('app.media.ic_onboarding_scan')).width(80).height(80).fillColor('#FF8800').margin({ bottom: 24 })
      Text($r('app.string.onboarding_scan_title')).fontSize(20).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
      Text($r('app.string.medialibrary_scan_explanation')).fontSize(13).fontColor('#B3FFFFFF')
        .margin({ top: 12 }).textAlign(TextAlign.Center)
    }.alignItems(HorizontalAlign.Center)
  }

  @Builder
  noPermissionContent() {
    Column() {
      Image($r('app.media.ic_onboarding_no_permission')).width(80).height(80).fillColor('#FFFFFF').margin({ bottom: 24 })
      Text($r('app.string.permission_not_granted')).fontSize(16).fontColor('#FFFFFF').textAlign(TextAlign.Center)
    }.alignItems(HorizontalAlign.Center)
  }

  @Builder
  notificationContent() {
    Column() {
      Image($r('app.media.ic_onboarding_notification')).width(80).height(80).fillColor('#FFFFFF').margin({ bottom: 24 })
      Text($r('app.string.notification_permission')).fontSize(18).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
      Text($r('app.string.notification_permission_explanation')).fontSize(12).fontColor('#B3FFFFFF')
        .margin({ top: 12 }).textAlign(TextAlign.Center)
    }.alignItems(HorizontalAlign.Center)
  }

  @Builder
  themeContent() {
    Column() {
      Image($r('app.media.ic_theme')).width(80).height(80).fillColor('#FF8800').margin({ bottom: 24 })
      Text($r('app.string.onboarding_theme_title')).fontSize(20).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
      Row() {
        Image($r('app.media.ic_theme_dark')).width(64).height(64).fillColor('#FFFFFF').margin({ right: 24 })
        Image($r('app.media.ic_theme_daynight')).width(64).height(64).fillColor('#FF8800')
      }.margin({ top: 24 })
    }.alignItems(HorizontalAlign.Center)
  }
}
