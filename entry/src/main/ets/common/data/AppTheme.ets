import { ConfigurationConstant } from '@kit.AbilityKit';
import { AppContext } from './AppContext';

/**
 * 应用主题与 HarmonyOS 色彩模式之间的唯一映射。
 *
 * `COLOR_MODE_NOT_SET` 表示不覆盖系统设置，系统在深浅色模式变化时会自动重选
 * `base` / `dark` 资源目录中的同名颜色；亮色和黑色主题则显式锁定应用色彩模式。
 */
export class AppTheme {
  static readonly FOLLOW_SYSTEM: string = '-1';
  static readonly LIGHT: string = '1';
  static readonly DARK: string = '2';

  /** 立即将设置页保存的值应用到整个应用进程。 */
  static apply(preferenceValue: string): void {
    let colorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (preferenceValue === AppTheme.LIGHT) {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else if (preferenceValue === AppTheme.DARK) {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }

    try {
      AppContext.get().getApplicationContext().setColorMode(colorMode);
    } catch (_) {
      // 不让主题切换失败影响设置保存；下次启动仍会再次应用该偏好。
    }
  }
}
