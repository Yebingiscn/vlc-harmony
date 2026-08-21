import { NavController } from '../common/data/NavController';
import { Settings } from '../common/data/Settings';
import { AppColors } from '../common/constants/AppConstants';

enum OnboardingStep {
  WELCOME = 0,
  THEME = 1,
}

/**
 * OnboardingPage —— OnboardingActivity(首启引导)。
 * 2 步状态机(WELCOME/THEME)。背景/文字使用资源引用,跟随系统深浅色。
 */
@ComponentV2
export struct OnboardingPage {
  @Local step: OnboardingStep = OnboardingStep.WELCOME;
  @Event onDone: () => void = () => {
  };

  next(): void {
    switch (this.step) {
      case OnboardingStep.WELCOME:
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
            .type(ButtonType.Normal)
            .borderRadius(4)
            .backgroundColor($r('app.color.card_background'))
            .borderWidth(1)
            .borderColor($r('app.color.card_border'))
            .fontColor($r('app.color.list_title'))
            .fontSize(14)
            .layoutWeight(1)
            .margin({ right: 8 })
            .onClick(() => this.skip())
          Button(this.step === OnboardingStep.THEME ? $r('app.string.ok') : $r('app.string.next_step'))
            .type(ButtonType.Normal)
            .borderRadius(4)
            .backgroundColor(AppColors.orange500)
            .fontColor('#FFFFFF')
            .fontSize(14)
            .layoutWeight(1)
            .onClick(() => this.next())
        }
        .width('100%')
        .padding(24)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_default'))
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
      Text($r('app.string.welcome_title')).fontSize(24).fontColor($r('app.color.list_title')).fontWeight(FontWeight.Bold)
      Text($r('app.string.welcome_subtitle'))
        .fontSize(14)
        .fontColor($r('app.color.list_subtitle'))
        .margin({ top: 12 })
        .textAlign(TextAlign.Center)
    }.alignItems(HorizontalAlign.Center)
  }

  @Builder
  themeContent() {
    Column() {
      Image($r('app.media.ic_theme')).width(80).height(80).fillColor(AppColors.orange500).margin({ bottom: 24 })
      Text($r('app.string.onboarding_theme_title')).fontSize(20).fontColor($r('app.color.list_title')).fontWeight(FontWeight.Medium)
      Row() {
        Image($r('app.media.ic_theme_dark')).width(64).height(64).fillColor($r('app.color.list_title')).margin({ right: 24 })
        Image($r('app.media.ic_theme_daynight')).width(64).height(64).fillColor(AppColors.orange500)
      }.margin({ top: 24 })
    }.alignItems(HorizontalAlign.Center)
  }
}
