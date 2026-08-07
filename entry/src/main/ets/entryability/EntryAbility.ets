import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppContext } from '../common/data/AppContext';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 注入全局 Context(供数据层 Preferences / MediaLibrary 使用)
    AppContext.set(this.context);
    const params = want.parameters;
    AppContext.setFormatTestMode(params?.['formatTest'] === true || params?.['formatTest'] === 'true');
    const limit = Number(params?.['formatLimit']);
    AppContext.setFormatTestLimit(Number.isFinite(limit) && limit > 0 ? Math.floor(limit) : 0);
    const start = Number(params?.['formatStart']);
    AppContext.setFormatTestStart(Number.isFinite(start) && start >= 0 ? Math.floor(start) : 0);
    const videoTimeout = Number(params?.['formatVideoTimeoutMs']);
    AppContext.setFormatVideoTimeoutMs(Number.isFinite(videoTimeout) && videoTimeout > 0
      ? Math.floor(videoTimeout) : 15000);
    const audioTimeout = Number(params?.['formatAudioTimeoutMs']);
    AppContext.setFormatAudioTimeoutMs(Number.isFinite(audioTimeout) && audioTimeout > 0
      ? Math.floor(audioTimeout) : 8000);
    const parseTimeout = Number(params?.['formatParseTimeoutMs']);
    AppContext.setFormatParseTimeoutMs(Number.isFinite(parseTimeout) && parseTimeout > 0
      ? Math.floor(parseTimeout) : 10000);
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      // 设置全屏沉浸式布局
      const mainWindow = windowStage.getMainWindowSync();
      if (mainWindow) {
        mainWindow.setWindowLayoutFullScreen(true);
      }
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    AppContext.notifyAppBackground();
  }
}
