import { VlcToolbar } from '../common/components/VlcToolbar';
import { NavController } from '../common/data/NavController';
import { AppContext } from '../common/data/AppContext';
import { AppColors, AppDimens } from '../common/constants/AppConstants';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';

/**
 * DebugLogActivityPage —— 调试日志采集页(DebugLogActivity)。
 * 角色:pushed(由 PreferencesAdvanced 高级设置项进入)。
 * 结构:状态栏保真条 + 顶部标题栏("Debug log" + 返回箭头)+ 主体 padding 16vp(2x2 OutlinedButton Start/Stop, Clear, Copy, Save + 日志 List 等宽行)。
 * 采集:DebugLogService.Client(start/stop/clear/save) → TODO(契约,infra);日志 List 行 monospace 13fp。
 */
@ObservedV2
export class DebugLogVM {
  @Trace logList: string[] = [];
  @Trace isStarted: boolean = false;
  @Trace optionsEnabled: boolean = false;

  toggleStart(): void {
    // TODO(契约,infra): DebugLogService.Client.start()/stop()(foregroundServiceType=specialUse 服务 :logger)
    this.isStarted = !this.isStarted;
    if (this.isStarted) {
      // onStarted: logList 填充,optionsEnabled=true
      this.logList = this.logList.concat(['Starting collecting logs...']);
      this.optionsEnabled = true;
    }
  }

  clear(): void {
    // TODO(契约,infra): client.clear()
    this.logList = [];
    this.optionsEnabled = false;
  }

  async copy(): Promise<void> {
    // @ohos.pasteboard: setPrimaryClip
    const buffer: string = this.logList.join('\n');
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, buffer);
    const mgr = pasteboard.getSystemPasteboard();
    await mgr.setData(pasteData);
    promptAction.showToast({ message: 'Copied log to clipboard.' });
  }

  async save(): Promise<void> {
    // 把当前 logList 导出到应用 filesDir 下的真实 .log 文件(@ohos.file.fs,非 mock)。
    // 注:真实 logcat 抓取需 DebugLogService(foregroundServiceType=specialUse :logger)——鸿蒙无等价
    // 开放 API,此处置换为「导出已采集的日志缓冲」到文件(可分享/查看)。
    try {
      const ctx = AppContext.get();
      const dir: string = ctx.filesDir;
      const path: string = `${dir}/vlc_debug_${Date.now()}.log`;
      const buffer: string = this.logList.join('\n');
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, buffer);
      fs.closeSync(file);
      promptAction.showToast({ message: `Logcat dumped to ${path}` });
    } catch (e) {
      promptAction.showToast({ message: 'Failed to dump logcat.' });
    }
  }
}

@ComponentV2
export struct DebugLogActivityPage {
  @Local vm: DebugLogVM = new DebugLogVM();

  @Builder
  OutlinedIconButton(text: string, enabled: boolean, onClick: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: enabled }) {
      Text(text)
        .fontSize(14)
        .fontColor(enabled ? AppColors.orange800 : AppColors.grey500)
    }
    .height(60)
    .layoutWeight(1)
    .borderWidth(1)
    .borderColor(AppColors.orange800)
    .backgroundColor(AppColors.transparent)
    .enabled(enabled)
    .onClick(() => onClick())
  }

  @Builder
  LogItem(text: string) {
    Text(text)
      .width('100%')
      .fontSize(13)
      .fontColor(AppColors.grey900)
      .fontFamily('HarmonyOS Sans Mono')
      .textAlign(TextAlign.Start)
  }

  build() {
    NavDestination() {
      Column() {
        // 顶部标题栏
        VlcToolbar({ title: $r('app.string.debug_logs'), showBack: true, onBack: () => NavController.pop() })

        // 主体(padding 16vp)
        Column() {
          // 第 1 行:start_log / clear_log
          Row() {
            this.OutlinedIconButton(
              this.vm.isStarted ? 'Stop logging' : 'Start logging', true, () => this.vm.toggleStart())
            Blank().width(AppDimens.kl_normal)
            this.OutlinedIconButton('Clear log', this.vm.optionsEnabled, () => this.vm.clear())
          }
          .width('100%')

          // 第 2 行:copy_to_clipboard / save_to_file
          Row() {
            this.OutlinedIconButton('Copy to clipboard', this.vm.optionsEnabled, () => this.vm.copy())
            Blank().width(AppDimens.kl_normal)
            this.OutlinedIconButton('Dump logcat log', this.vm.optionsEnabled, () => this.vm.save())
          }
          .width('100%')
          .margin({ top: AppDimens.kl_normal })

          // 日志列表(paddingTop 10vp)
          List() {
            ForEach(this.vm.logList, (line: string, idx: number) => {
              ListItem() {
                this.LogItem(line)
              }
            }, (line: string, idx: number) => `${idx}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ top: 10 })
          .scrollBar(BarState.Auto)
        }
        .width('100%')
        .layoutWeight(1)
        .padding(AppDimens.kl_normal)
        .backgroundColor(AppColors.white)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.white)
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      // TODO(契约,infra): client.release() 释放服务绑定。
      NavController.pop();
      return true;
    })
  }
}
