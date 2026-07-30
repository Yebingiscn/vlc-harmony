import { NavController } from '../common/data/NavController';
import { Settings } from '../common/data/Settings';
import { AppColors, AppDimens } from '../common/constants/AppConstants';

/** PIN 流程步骤(对应 SafeModeModel.PinStep)。 */
export enum PinStep {
  ENTER_EXISTING,
  INVALID,
  ENTER_NEW,
  RE_ENTER,
  NO_MATCH,
  LOGIN_SUCCESS,
  EXIT,
}

/** PIN 触发原因(对应 PinCodeReason)。 */
export enum PinCodeReason {
  FIRST_CREATION,
  MODIFY,
  CHECK,
  UNLOCK,
}

/** PIN 页入参。 */
export class PinCodeParam {
  reason: PinCodeReason = PinCodeReason.CHECK;
}

/**
 * PinCodeActivityPage —— 4 格密码输入页(PinCodeActivity)。
 * 角色:pushed(带 pin_code_reason 入参)。
 * 结构:reason 文案(16fp)+ title 文案(22fp Medium)+ 4 格 1:1 PIN 输入框 + 底部左 cancel/右 next。
 * 非门:4 格全填 → next 可点;finalStep/success 态文案改 Done;解锁成功切 success_group。
 */
@ObservedV2
export class PinCodeVM {
  @Trace reason: PinCodeReason = PinCodeReason.CHECK;
  @Trace step: PinStep = PinStep.ENTER_NEW;
  @Trace pin1: string = '';
  @Trace pin2: string = '';
  @Trace pin3: string = '';
  @Trace pin4: string = '';
  @Trace uiState: string = 'PIN'; // 'PIN' | 'SUCCESS'
  /** ENTER_NEW 阶段输入的 PIN 的 sha256Hex(供 RE_ENTER 二次确认比对)。非持久化。 */
  pendingHash: string = '';

  get canSubmit(): boolean {
    return this.pin1.length > 0 && this.pin2.length > 0 && this.pin3.length > 0 && this.pin4.length > 0;
  }

  get isFinalStep(): boolean {
    return this.step === PinStep.RE_ENTER || this.step === PinStep.NO_MATCH;
  }

  get reasonText(): string {
    switch (this.reason) {
      case PinCodeReason.FIRST_CREATION:
        return "First, let's create your PIN code";
      case PinCodeReason.MODIFY:
        return 'Change your PIN code';
      default:
        return 'Access restricted. Please enter your PIN code';
    }
  }

  get titleText(): Resource {
    switch (this.step) {
      case PinStep.ENTER_EXISTING:
      case PinStep.INVALID:
        return $r('app.string.safe_mode_pin');
      case PinStep.ENTER_NEW:
        return $r('app.string.safe_mode_new_pin');
      case PinStep.RE_ENTER:
      case PinStep.NO_MATCH:
        return $r('app.string.safe_mode_re_pin');
      default:
        return $r('app.string.safe_mode_pin');
    }
  }

  clearAll(): void {
    this.pin1 = '';
    this.pin2 = '';
    this.pin3 = '';
    this.pin4 = '';
  }
}

@ComponentV2
export struct PinCodeActivityPage {
  @Param param: PinCodeParam = new PinCodeParam();
  @Local vm: PinCodeVM = new PinCodeVM();

  aboutToAppear(): void {
    this.vm.reason = this.param.reason;
    // step 初始:Settings.getString(KEY_SAFE_MODE_PIN) 为空 → ENTER_NEW(首次创建);非空 → ENTER_EXISTING。
    this.initStep();
  }

  private async initStep(): Promise<void> {
    const stored: string = await Settings.getString(Settings.KEY_SAFE_MODE_PIN, '');
    // 首次创建 或 MODIFY/CHECK/UNLOCK 且已有 PIN → 输入既有 PIN。
    if (stored.length > 0 &&
      (this.vm.reason === PinCodeReason.CHECK || this.vm.reason === PinCodeReason.UNLOCK ||
        this.vm.reason === PinCodeReason.MODIFY)) {
      this.vm.step = PinStep.ENTER_EXISTING;
    } else {
      // 无 PIN(首次创建或未设)→ 直接进入新建。
      this.vm.step = PinStep.ENTER_NEW;
    }
  }

  /** SHA-256 hex(input) —— 纯 ArkTS 实现(SHA-2 FIPS 180-4);输入为短 ASCII PIN,UTF-8 单字节即可。 */
  private async sha256Hex(input: string): Promise<string> {
    // 输入 → UTF-8 字节(PIN 仅 ASCII,逐字符取低 8 位即可)。
    const bytes: Uint8Array = new Uint8Array(input.length);
    for (let i = 0; i < input.length; i++) {
      bytes[i] = input.charCodeAt(i) & 0xFF;
    }
    // SHA-256 常量与处理。
    const K: number[] = [
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];
    const rotr = (x: number, n: number): number => ((x >>> n) | (x << (32 - n))) >>> 0;
    // 消息填充:0x80 + 0x00* + 8 字节大端位长度。
    const bitLen: number = bytes.length * 8;
    const withPad: Uint8Array = new Uint8Array(((bytes.length + 9 + 63) >>> 6) * 64);
    for (let i = 0; i < bytes.length; i++) {
      withPad[i] = bytes[i];
    }
    withPad[bytes.length] = 0x80;
    // 长度以 JS number(<=2^32 位)表达,高 32 位恒 0,写低 32 位到末 4 字节。
    withPad[withPad.length - 4] = (bitLen >>> 24) & 0xFF;
    withPad[withPad.length - 3] = (bitLen >>> 16) & 0xFF;
    withPad[withPad.length - 2] = (bitLen >>> 8) & 0xFF;
    withPad[withPad.length - 1] = bitLen & 0xFF;

    let h0: number = 0x6a09e667, h1: number = 0xbb67ae85, h2: number = 0x3c6ef372, h3: number = 0xa54ff53a;
    let h4: number = 0x510e527f, h5: number = 0x9b05688c, h6: number = 0x1f83d9ab, h7: number = 0x5be0cd19;
    const w: number[] = new Array<number>(64);
    for (let chunk = 0; chunk < withPad.length; chunk += 64) {
      for (let i = 0; i < 16; i++) {
        const j: number = chunk + i * 4;
        w[i] = ((withPad[j] << 24) | (withPad[j + 1] << 16) | (withPad[j + 2] << 8) | withPad[j + 3]) >>> 0;
      }
      for (let i = 16; i < 64; i++) {
        const s0: number = (rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3)) >>> 0;
        const s1: number = (rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10)) >>> 0;
        w[i] = ((w[i - 16] + s0 + w[i - 7] + s1) >>> 0);
      }
      let a: number = h0, b: number = h1, c: number = h2, d: number = h3;
      let e: number = h4, f: number = h5, g: number = h6, hh: number = h7;
      for (let i = 0; i < 64; i++) {
        const S1: number = (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) >>> 0;
        const ch: number = ((e & f) ^ ((~e) & g)) >>> 0;
        const t1: number = ((hh + S1 + ch + K[i] + w[i]) >>> 0);
        const S0: number = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) >>> 0;
        const maj: number = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
        const t2: number = ((S0 + maj) >>> 0);
        hh = g; g = f; f = e;
        e = ((d + t1) >>> 0);
        d = c; c = b; b = a;
        a = ((t1 + t2) >>> 0);
      }
      h0 = ((h0 + a) >>> 0); h1 = ((h1 + b) >>> 0); h2 = ((h2 + c) >>> 0); h3 = ((h3 + d) >>> 0);
      h4 = ((h4 + e) >>> 0); h5 = ((h5 + f) >>> 0); h6 = ((h6 + g) >>> 0); h7 = ((h7 + hh) >>> 0);
    }
    const H: number[] = [h0, h1, h2, h3, h4, h5, h6, h7];
    let hex: string = '';
    for (let i = 0; i < H.length; i++) {
      let part: string = (H[i] >>> 0).toString(16);
      while (part.length < 8) {
        part = '0' + part;
      }
      hex += part;
    }
    return hex;
  }

  /** 拼装当前 4 格 PIN 明文。 */
  private currentPin(): string {
    return `${this.vm.pin1}${this.vm.pin2}${this.vm.pin3}${this.vm.pin4}`;
  }

  private onPinChanged(): void {
    // 第4格填满且 4 格非空 → 自动 next()。
    if (this.vm.pin4.length > 0 && this.vm.canSubmit) {
      this.next();
    }
  }

  private next(): void {
    if (!this.vm.canSubmit) {
      return;
    }
    if (this.vm.step === PinStep.ENTER_EXISTING || this.vm.step === PinStep.INVALID) {
      // 校验既有 PIN:读存的 hash 与输入的 sha256Hex 比较。
      this.checkExistingPin();
    } else if (this.vm.step === PinStep.ENTER_NEW) {
      // 首次输入新 PIN → 记下 sha256Hex,进入 RE_ENTER 二次确认。
      this.captureNewPin();
    } else if (this.vm.step === PinStep.RE_ENTER || this.vm.step === PinStep.NO_MATCH) {
      // 二次确认:两次一致 → sha256Hex 后 Settings.put(KEY_SAFE_MODE_PIN, hash)。
      this.confirmNewPin();
    } else if (this.vm.reason === PinCodeReason.UNLOCK) {
      // 解锁成功 → showTips():uiState=SUCCESS,next→Done。
      this.vm.uiState = 'SUCCESS';
    } else {
      NavController.pop();
    }
  }

  /** ENTER_NEW:记下输入的 PIN 的 sha256Hex → 进入 RE_ENTER 二次确认。 */
  private async captureNewPin(): Promise<void> {
    this.vm.pendingHash = await this.sha256Hex(this.currentPin());
    this.vm.step = PinStep.RE_ENTER;
    this.vm.clearAll();
  }

  /** 校验既有 PIN:输入 sha256Hex 与 Settings 存的 hash 比较。 */
  private async checkExistingPin(): Promise<void> {
    const stored: string = await Settings.getString(Settings.KEY_SAFE_MODE_PIN, '');
    const hash: string = await this.sha256Hex(this.currentPin());
    if (hash === stored) {
      if (this.vm.reason === PinCodeReason.MODIFY) {
        // 旧 PIN 正确 → 进入新 PIN 输入。
        this.vm.step = PinStep.ENTER_NEW;
      } else {
        // CHECK / UNLOCK 校验通过。
        if (this.vm.reason === PinCodeReason.UNLOCK) {
          this.vm.uiState = 'SUCCESS';
        } else {
          NavController.pop();
        }
      }
      this.vm.clearAll();
    } else {
      // PIN 错误 → INVALID 态停留,清空重输。
      this.vm.step = PinStep.INVALID;
      this.vm.clearAll();
    }
  }

  /** 二次确认新 PIN:两次一致 → sha256Hex 后 Settings.put(KEY_SAFE_MODE_PIN, hash)。 */
  private async confirmNewPin(): Promise<void> {
    const hash: string = await this.sha256Hex(this.currentPin());
    if (hash === this.vm.pendingHash) {
      // 两次一致:存 hash。
      await Settings.put(Settings.KEY_SAFE_MODE_PIN, hash);
      NavController.pop();
    } else {
      // 两次不一致 → NO_MATCH 态,保留 pendingHash 让用户重新输入与首次一致。
      this.vm.step = PinStep.NO_MATCH;
      this.vm.clearAll();
    }
  }

  private nextLabel(): Resource {
    if (this.vm.uiState === 'SUCCESS' || this.vm.isFinalStep) {
      return $r('app.string.done');
    }
    return $r('app.string.next');
  }

  @Builder
  PinCell(text: string, onChange: (v: string) => void) {
    TextInput({ text: text })
      .type(InputType.Number)
      .maxLength(1)
      .textAlign(TextAlign.Center)
      .fontSize(22)
      .fontColor(AppColors.grey900)
      .layoutWeight(1)
      .aspectRatio(1)
      .backgroundColor(AppColors.transparent)
      .onChange((v: string) => onChange(v))
  }

  build() {
    NavDestination() {
      Column() {
        if (this.vm.uiState !== 'SUCCESS') {
          // pin_group:reason + title + 4 格 PIN 框
          Column() {
            Text(this.vm.reasonText)
              .fontSize(16)
              .fontColor(AppColors.grey900)
              .textAlign(TextAlign.Center)
              .margin({ top: 16, left: 32, right: 32 })

            Text(this.vm.titleText)
              .fontSize(22)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.white)
              .textAlign(TextAlign.Center)
              .margin({ top: 16, left: 32, right: 32 })

            // 4 格 PIN 输入框(1:1 正方形等宽,间隙 8vp,顶距 title 48vp)
            Row({ space: AppDimens.default_margin }) {
              this.PinCell(this.vm.pin1, (v: string) => { this.vm.pin1 = v; this.onPinChanged(); })
              this.PinCell(this.vm.pin2, (v: string) => { this.vm.pin2 = v; this.onPinChanged(); })
              this.PinCell(this.vm.pin3, (v: string) => { this.vm.pin3 = v; this.onPinChanged(); })
              this.PinCell(this.vm.pin4, (v: string) => { this.vm.pin4 = v; this.onPinChanged(); })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .margin({ top: 48, left: 32, right: 32 })
          }
          .width('100%')
        } else {
          // sucess_group:锁图标 + 解锁成功文案
          Column() {
            Text($r('app.string.pin_unlock_success'))
              .fontSize(16)
              .fontColor(AppColors.grey900)
              .textAlign(TextAlign.Center)
              .margin({ left: 16, right: 16 })
            Image($r('app.media.ic_pin_lock'))
              .width(24)
              .height(24)
              .fillColor(AppColors.grey600)
              .margin({ top: 16 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }

        // 底部按钮栏(锁底,左 cancel 右 next)
        Row() {
          if (this.vm.uiState !== 'SUCCESS') {
            Button($r('app.string.cancel'))
              .type(ButtonType.Normal)
              .backgroundColor(AppColors.transparent)
              .fontColor(AppColors.grey700)
              .margin({ left: 16 })
              .onClick(() => NavController.pop())
          }
          Button(this.nextLabel())
            .type(ButtonType.Normal)
            .backgroundColor(AppColors.transparent)
            .fontColor(AppColors.orange800)
            .enabled(this.vm.uiState === 'SUCCESS' || this.vm.canSubmit)
            .margin({ right: 16 })
            .onClick(() => this.next())
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .padding({ bottom: 16 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.white)
      .alignItems(HorizontalAlign.Start)
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
