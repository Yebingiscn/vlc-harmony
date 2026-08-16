import { MainPage } from './MainPage';
import { OnboardingPage } from './OnboardingPage';
import { VideoParam, VideoPlayerPage } from './VideoPlayerPage';
import { AudioPlayerPage } from './AudioPlayerPage';
import { InfoPage, InfoParam } from './InfoPage';
import { SecondaryPage } from './SecondaryPage';
import { SearchPage } from './SearchPage';
import { SecondaryParam } from '../common/models/MediaModels';
import { AppContext } from '../common/data/AppContext';
import { Settings } from '../common/data/Settings';
import { AppTheme } from '../common/data/AppTheme';
import { NavController } from '../common/data/NavController';
import { RouteName } from '../common/constants/AppConstants';
// Phase B 新增可导航页面。
import { HeaderMediaListActivityPage, HeaderMediaListParam } from './HeaderMediaListActivityPage';
import { LibrariesActivityPage } from './LibrariesActivityPage';
import { EqualizerSettingsActivityPage } from './EqualizerSettingsActivityPage';
import { PinCodeActivityPage, PinCodeParam } from './PinCodeActivityPage';
import { OTPCodeActivityPage } from './OTPCodeActivityPage';
import { AuthorsActivityPage } from './AuthorsActivityPage';
import { FeedbackActivityPage } from './FeedbackActivityPage';
import { BetaWelcomeActivityPage } from './BetaWelcomeActivityPage';
import { FilePickerActivityPage, FilePickerParam } from './FilePickerActivityPage';
import { PreferencesActivityPage } from './PreferencesActivityPage';
import { PreferenceSearchActivityPage } from './PreferenceSearchActivityPage';
import { DialogActivityPage } from './DialogActivityPage';
import { MiniPlayerConfigureActivityPage, MiniPlayerConfigureParam } from './MiniPlayerConfigureActivityPage';
import { DebugLogActivityPage } from './DebugLogActivityPage';
import { BenchActivityPage } from './BenchActivityPage';
import { PreferencesPage } from './PreferencesPage';
import { PreferenceSearchPage } from './PreferenceSearchPage';
import { AboutFragmentPage } from './AboutFragmentPage';
import { HistoryFragmentPage } from './HistoryFragmentPage';
import { BrowserMode, FileBrowserPage } from './FileBrowserPage';
import { MrlPanelPage } from './MrlPanelPage';
import { ParentalControlPage, ParentalControlParam } from './ParentalControlPage';
import { FormatCompatibilityTestPage } from './FormatCompatibilityTestPage';
import { HdsNavigation } from '@kit.UIDesignKit';

/**
 * Index —— 应用入口(@Entry)。承载 Navigation + PageMap(所有 NavDestination 路由)。
 * 启动逻辑(StartActivity 路由分发):首启 → Onboarding;否则 → Main。
 */
@Entry
@ComponentV2
struct Index {
  private pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    NavController.set(this.pathStack);
    this.bootstrap();
  }

  async bootstrap(): Promise<void> {
    if (AppContext.isFormatTestMode()) {
      this.pathStack.pushPathByName(RouteName.FormatCompat, '');
      return;
    }
    await Settings.init();
    // Settings 已就绪后立即应用保存的主题；同名 base/dark 资源由系统自动匹配。
    const appTheme: string = await Settings.getString(Settings.KEY_APP_THEME, AppTheme.FOLLOW_SYSTEM);
    AppTheme.apply(appTheme);
    const onboardingDone = await Settings.getBoolean(Settings.NOTIFICATION_PERMISSION_ASKED, false) &&
      await Settings.getBoolean(Settings.INITIAL_PERMISSION_ASKED, false);
    if (onboardingDone) {
      this.pathStack.pushPathByName(RouteName.Main, '');
    } else {
      this.pathStack.pushPathByName(RouteName.Onboarding, '');
    }
  }

  @Builder
  PageMap(name: string, param: object) {
    if (name === RouteName.FormatCompat) {
      FormatCompatibilityTestPage()
    } else if (name === RouteName.Onboarding) {
      OnboardingPage({ onDone: () => this.pathStack.replacePathByName(RouteName.Main, '') })
    } else if (name === RouteName.Main) {
      MainPage()
    } else if (name === RouteName.VideoPlayer) {
      VideoPlayerPage({ param: param as object as VideoParam })
    } else if (name === RouteName.AudioPlayer) {
      AudioPlayerPage()
    } else if (name === RouteName.Info) {
      InfoPage({ param: param as object as InfoParam })
    } else if (name === RouteName.Secondary) {
      SecondaryPage({ param: param as object as SecondaryParam })
    } else if (name === RouteName.Search) {
      SearchPage()
    } else if (name === RouteName.HeaderMediaList) {
      HeaderMediaListActivityPage({ param: param as object as HeaderMediaListParam })
    } else if (name === RouteName.Libraries) {
      LibrariesActivityPage()
    } else if (name === RouteName.EqualizerSettings) {
      EqualizerSettingsActivityPage()
    } else if (name === RouteName.PinCode) {
      PinCodeActivityPage({ param: param as object as PinCodeParam })
    } else if (name === RouteName.OTPCode) {
      OTPCodeActivityPage()
    } else if (name === RouteName.Authors) {
      AuthorsActivityPage()
    } else if (name === RouteName.Feedback) {
      FeedbackActivityPage()
    } else if (name === RouteName.BetaWelcome) {
      BetaWelcomeActivityPage()
    } else if (name === RouteName.FilePicker) {
      FilePickerActivityPage({ param: param as object as FilePickerParam })
    } else if (name === RouteName.Preferences) {
      PreferencesActivityPage()
    } else if (name === RouteName.PreferenceSearch) {
      PreferenceSearchActivityPage()
    } else if (name === RouteName.DialogHost) {
      // DialogActivityPage 入参为内联 @Param action/mediaUri;透传 object 仅供 aboutToAppear 读取。
      DialogActivityPage()
    } else if (name === RouteName.MiniPlayerConfigure) {
      MiniPlayerConfigureActivityPage({ param: param as object as MiniPlayerConfigureParam })
    } else if (name === RouteName.DebugLog) {
      DebugLogActivityPage()
    } else if (name === RouteName.Bench) {
      BenchActivityPage()
    } else if (name === RouteName.PreferencesScreen) {
      if (((param as Record<string, Object>)?.screenKey as string ?? '') === 'parental_control') {
        ParentalControlPage()
      } else {
        PreferencesPage({ screenKey: (param as Record<string, Object>)?.screenKey as string ?? '' })
      }
    } else if (name === RouteName.PreferenceSearchScreen) {
      PreferenceSearchPage()
    } else if (name === RouteName.About) {
      AboutFragmentPage()
    } else if (name === RouteName.History) {
      HistoryFragmentPage()
    } else if (name === RouteName.FileBrowser) {
      FileBrowserPage({ mode: ((param as Record<string, Object>)?.mode as BrowserMode) ?? 'file' })
    } else if (name === RouteName.MrlPanel) {
      MrlPanelPage()
    } else if (name === RouteName.ParentalControl) {
      ParentalControlPage({ param: param as object as ParentalControlParam })
    }
  }

  build() {
    HdsNavigation(this.pathStack) {
      // navBar 根(启动闪屏:VLC logo + 背景色)
      Column() {
        Image($r('app.media.ic_about_logo'))
          .width(96)
          .height(96)
          .objectFit(ImageFit.Contain)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.start_window_background'))
    }
    .navDestination(this.PageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideNavBar(true)
    .id('app_navigation')
  }
}
