import { NavController } from '../common/data/NavController';
import { AppColors } from '../common/constants/AppConstants';

/**
 * OTPCodeActivityPage —— 远程访问登录验证页(OTPCodeActivity)。
 * 角色:pushed。居中显示 6 位 OTP 验证码;底部「It's not me」轮廓按钮撤销本次登录。
 * 结构:标题(24fp Medium) + 副标题(14fp Medium) + 6 个 56×56vp 圆角 8vp 灰底橙字方框(数字 34fp) + 底部按钮。
 */
@ObservedV2
export class OTPCodeVM {
  /** 当前 6 位 OTP(来自 RemoteAccessUtils.otpFlow,初始 null)。TODO(契约): otpFlow 产生端不在本页。 */
  @Trace code: string | null = null;
}

@ComponentV2
export struct OTPCodeActivityPage {
  @Local vm: OTPCodeVM = new OTPCodeVM();

  aboutToAppear(): void {
    // TODO(契约): 订阅 RemoteAccessUtils.otpFlow;流非 null 时填充 6 位码,流变 null 自动 finish()。
    // 无真实 OTP 推送端时用样例码占位。
    this.vm.code = '482915';
  }

  @Builder
  CodeDigit(idx: number) {
    Text(this.digit(idx))
      .fontSize(34)
      .fontColor(AppColors.orange800)
      .textAlign(TextAlign.Center)
      .width(56)
      .height(56)
      .borderRadius(8)
      .backgroundColor(AppColors.grey200)
      .margin({ left: idx > 0 ? 4 : 0 })
  }

  build() {
    NavDestination() {
      Column() {
        // 1) 标题
        Text($r('app.string.ra_otp_title')) // "Remote access login attempt"
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .margin({ left: 16, right: 16, top: 16 })
          .width('100%')

        // 2) 副标题
        Text($r('app.string.ra_otp_subtitle')) // "If it's you, enter this code on the other device"
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .margin({ left: 16, right: 16, top: 8 })
          .width('100%')

        // 上弹性区:把码组压向垂直中段
        Blank().layoutWeight(1)

        // 3) 6 位码(横向链,无间距相邻紧贴)
        Row() {
          this.CodeDigit(0)
          this.CodeDigit(1)
          this.CodeDigit(2)
          this.CodeDigit(3)
          this.CodeDigit(4)
          this.CodeDigit(5)
        }

        // 下弹性区:与上弹性对称 → 码组垂直居中
        Blank().layoutWeight(1)

        // 4) 「It's not me」OutlinedButton(底部居中)
        Button($r('app.string.ra_otp_not_me')) // "It's not me"
          .type(ButtonType.Normal)
          .fontColor(AppColors.orange800)
          .borderWidth(1)
          .borderColor(AppColors.orange800)
          .backgroundColor(AppColors.transparent)
          .margin({ bottom: 16 })
          .onClick(() => this.onCancel())
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.white)
      .alignItems(HorizontalAlign.Center)
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }

  private digit(idx: number): string {
    if (this.vm.code === null || idx >= this.vm.code.length) {
      return '';
    }
    return this.vm.code.charAt(idx);
  }

  private onCancel(): void {
    // onCancel(): RemoteAccessUtils.otpCodeRemoveFlow.emit(code) + otpFlow.emit(null) + finish()。
    // TODO(契约): otpCodeRemoveFlow 接收方/撤销登录逻辑在 remote-access-server 模块,不在本页。
    NavController.pop();
  }
}
