import { NavController } from '../common/data/NavController';

/**
 * BenchActivityPage —— 透明宿主(BenchActivity 自动化基准测试)。
 * 角色:透明宿主,被外部拉起即自动跑完退出。
 * 视觉:复用 VideoPlayer 的全屏纯视频画面,强制隐藏所有 overlay/控件/手势。
 * 鸿蒙无 VLCBenchmark 跨 App 广播/PlaybackService.setBenchmark 等契约 → push 即 pop,
 * 仅保留「基准测试宿主,无用户交互」语义。外部运行时契约标 TODO。
 */
@ComponentV2
export struct BenchActivityPage {
  aboutToAppear(): void {
    // TODO(契约): 原始 BenchActivity 由 VLCBenchmark App 经 Intent 拉起自动播放/截图/测速后 setResult() 回传统计并 finish()。
    // 鸿蒙无对应跨 App 广播(ACTION_TRIGGER_SCREENSHOT/ACTION_CONTINUE_BENCHMARK)、PlaybackService.setBenchmark/setHardware、
    // libvlc VLCInstance.restart 等契约,且禁用一切用户输入。push 即 pop,说明为基准测试宿主。
    NavController.pop();
  }

  build() {
    NavDestination() {
      // 全屏纯视频画面层(复用 player_root),无任何 HUD/控制条/手势。
      Stack() {
        // 视频画面占位 —— TODO(契约): 实际视频画面由 PlaybackService/AVPlayer 注入;基准测试期间禁用一切交互。
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#000000')
      }
      .width('100%')
      .height('100%')
      .alignContent(Alignment.Center)
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
