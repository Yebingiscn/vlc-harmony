import { NavController } from '../common/data/NavController';
import { Settings } from '../common/data/Settings';
import { PlaybackHistory } from '../common/data/PlaybackHistory';
import { AppDimens, RouteName } from '../common/constants/AppConstants';

enum PageState {
  SETTINGS,
  CREATE_PIN,
  CREATE_CONFIRM,
  VERIFY_PIN,
  VERIFY_WRONG,
  CHANGE_VERIFY,
  CHANGE_NEW,
  CHANGE_CONFIRM,
  CHANGE_NO_MATCH,
  CREATE_NO_MATCH,
}

export enum ParentalControlAction {
  MANAGE,
  OPEN_SETTINGS,
  CLEAR_HISTORY,
  DELETE_HISTORY_ENTRY,
}

export class ParentalControlParam {
  action: ParentalControlAction = ParentalControlAction.MANAGE;
  historyUri: string = '';
}

@ObservedV2
class PinVM {
  @Trace pin1: string = '';
  @Trace pin2: string = '';
  @Trace pin3: string = '';
  @Trace pin4: string = '';

  get canSubmit(): boolean {
    return this.pin1.length > 0 && this.pin2.length > 0 && this.pin3.length > 0 && this.pin4.length > 0;
  }

  get pin(): string {
    return this.pin1 + this.pin2 + this.pin3 + this.pin4;
  }

  clearAll(): void {
    this.pin1 = '';
    this.pin2 = '';
    this.pin3 = '';
    this.pin4 = '';
  }
}

@ComponentV2
export struct ParentalControlPage {
  @Param param: ParentalControlParam = new ParentalControlParam();
  @Local state: PageState = PageState.VERIFY_PIN;
  @Local vm: PinVM = new PinVM();
  @Local restrictSettings: boolean = false;
  @Local safeMode: boolean = false;
  @Local pinInput: string = '';
  private pendingPin: string = '';

  async aboutToAppear(): Promise<void> {
    this.restrictSettings = await Settings.getBoolean('restrict_settings', false);
    this.safeMode = await Settings.getBoolean('safe_mode', false);
    this.clearPinInput();
    this.state = this.param.action === ParentalControlAction.MANAGE ? PageState.SETTINGS : PageState.VERIFY_PIN;
  }

  private isPinState(): boolean {
    return this.state !== PageState.SETTINGS;
  }

  private isCreateFlow(): boolean {
    return this.state === PageState.CREATE_PIN || this.state === PageState.CREATE_CONFIRM ||
      this.state === PageState.CREATE_NO_MATCH;
  }

  private isChangeFlow(): boolean {
    return this.state === PageState.CHANGE_VERIFY || this.state === PageState.CHANGE_NEW ||
      this.state === PageState.CHANGE_CONFIRM || this.state === PageState.CHANGE_NO_MATCH;
  }

  private getReasonText(): Resource {
    if (this.isCreateFlow()) return $r('app.string.pin_code_reason_create');
    if (this.isChangeFlow()) return $r('app.string.pin_code_reason_modify');
    return $r('app.string.pin_code_reason_check');
  }

  private getInstruction(): Resource {
    switch (this.state) {
      case PageState.CREATE_PIN: return $r('app.string.safe_mode_new_pin');
      case PageState.CREATE_CONFIRM: return $r('app.string.safe_mode_re_pin');
      case PageState.CREATE_NO_MATCH: return $r('app.string.safe_mode_no_match');
      case PageState.VERIFY_PIN: return $r('app.string.safe_mode_pin');
      case PageState.VERIFY_WRONG: return $r('app.string.safe_mode_invalid_pin');
      case PageState.CHANGE_VERIFY: return $r('app.string.safe_mode_pin');
      case PageState.CHANGE_NEW: return $r('app.string.safe_mode_new_pin');
      case PageState.CHANGE_CONFIRM: return $r('app.string.safe_mode_re_pin');
      case PageState.CHANGE_NO_MATCH: return $r('app.string.safe_mode_no_match');
      default: return $r('app.string.safe_mode_pin');
    }
  }

  private setPinInput(value: string): void {
    let digits = '';
    for (let i = 0; i < value.length && digits.length < 4; i++) {
      const char = value.charAt(i);
      if (char >= '0' && char <= '9') digits += char;
    }
    this.pinInput = digits;
    this.vm.pin1 = digits.charAt(0);
    this.vm.pin2 = digits.charAt(1);
    this.vm.pin3 = digits.charAt(2);
    this.vm.pin4 = digits.charAt(3);
  }

  private clearPinInput(): void {
    this.pinInput = '';
    this.vm.clearAll();
  }

  private onPinInput(value: string): void {
    this.setPinInput(value);
    this.trySubmit();
  }

  private focusPinInput(): void {
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus('pin-input');
      } catch (_) {
        // The destination may have been dismissed before the input is attached.
      }
    }, 50);
  }

  private async completeProtectedAction(): Promise<void> {
    if (this.param.action === ParentalControlAction.MANAGE) {
      this.state = PageState.SETTINGS;
      return;
    }
    if (this.param.action === ParentalControlAction.CLEAR_HISTORY) {
      await PlaybackHistory.clear();
    } else if (this.param.action === ParentalControlAction.DELETE_HISTORY_ENTRY) {
      await PlaybackHistory.removeEntry(this.param.historyUri);
    }
    const action = this.param.action;
    NavController.pop();
    if (action === ParentalControlAction.OPEN_SETTINGS) {
      setTimeout(() => NavController.push(RouteName.Preferences), 0);
    }
  }

  private trySubmit(): void {
    if (this.vm.canSubmit &&
      this.state !== PageState.CREATE_NO_MATCH && this.state !== PageState.CHANGE_NO_MATCH &&
      this.state !== PageState.VERIFY_WRONG) {
      this.handleSubmit();
    }
  }

  private async handleSubmit(): Promise<void> {
    const pinValue = this.vm.pin;
    this.clearPinInput();

    switch (this.state) {
      case PageState.CREATE_PIN:
        this.pendingPin = pinValue;
        this.state = PageState.CREATE_CONFIRM;
        break;
      case PageState.CREATE_CONFIRM:
        if (pinValue === this.pendingPin) {
          await this.savePin(pinValue);
          this.state = PageState.SETTINGS;
        } else {
          this.state = PageState.CREATE_NO_MATCH;
          this.pendingPin = '';
          setTimeout(() => { this.state = PageState.CREATE_PIN; }, 1500);
        }
        break;
      case PageState.VERIFY_PIN:
      case PageState.VERIFY_WRONG:
        if (await this.verifyPin(pinValue)) {
          await this.completeProtectedAction();
        } else {
          this.state = PageState.VERIFY_WRONG;
          setTimeout(() => { if (this.state === PageState.VERIFY_WRONG) this.state = PageState.VERIFY_PIN; }, 1500);
        }
        break;
      case PageState.CHANGE_VERIFY:
        if (await this.verifyPin(pinValue)) {
          this.state = PageState.CHANGE_NEW;
        } else {
          this.state = PageState.VERIFY_WRONG;
          setTimeout(() => { this.state = PageState.CHANGE_VERIFY; }, 1500);
        }
        break;
      case PageState.CHANGE_NEW:
        this.pendingPin = pinValue;
        this.state = PageState.CHANGE_CONFIRM;
        break;
      case PageState.CHANGE_CONFIRM:
        if (pinValue === this.pendingPin) {
          await this.savePin(pinValue);
          this.state = PageState.SETTINGS;
        } else {
          this.state = PageState.CHANGE_NO_MATCH;
          this.pendingPin = '';
          setTimeout(() => { this.state = PageState.CHANGE_NEW; }, 1500);
        }
        break;
    }
  }

  private async savePin(pinValue: string): Promise<void> {
    const hash = await this.sha256Hex(pinValue);
    await Settings.put(Settings.KEY_SAFE_MODE_PIN, hash);
  }

  private async verifyPin(pinValue: string): Promise<boolean> {
    const stored = await Settings.getString(Settings.KEY_SAFE_MODE_PIN, '');
    const hash = await this.sha256Hex(pinValue);
    return hash === stored;
  }

  // ── SHA-256 (同 PinCodeActivityPage) ─────────────────

  private async sha256Hex(input: string): Promise<string> {
    const bytes = new Uint8Array(input.length);
    for (let i = 0; i < input.length; i++) {
      bytes[i] = input.charCodeAt(i) & 0xFF;
    }
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
    const bitLen = bytes.length * 8;
    const withPad = new Uint8Array(((bytes.length + 9 + 63) >>> 6) * 64);
    for (let i = 0; i < bytes.length; i++) {
      withPad[i] = bytes[i];
    }
    withPad[bytes.length] = 0x80;
    withPad[withPad.length - 4] = (bitLen >>> 24) & 0xFF;
    withPad[withPad.length - 3] = (bitLen >>> 16) & 0xFF;
    withPad[withPad.length - 2] = (bitLen >>> 8) & 0xFF;
    withPad[withPad.length - 1] = bitLen & 0xFF;
    let h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
    let h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;
    const w = new Array<number>(64);
    for (let chunk = 0; chunk < withPad.length; chunk += 64) {
      for (let i = 0; i < 16; i++) {
        const j = chunk + i * 4;
        w[i] = ((withPad[j] << 24) | (withPad[j + 1] << 16) | (withPad[j + 2] << 8) | withPad[j + 3]) >>> 0;
      }
      for (let i = 16; i < 64; i++) {
        const s0 = (rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3)) >>> 0;
        const s1 = (rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10)) >>> 0;
        w[i] = ((w[i - 16] + s0 + w[i - 7] + s1) >>> 0);
      }
      let a = h0, b = h1, c = h2, d = h3;
      let e = h4, f = h5, g = h6, hh = h7;
      for (let i = 0; i < 64; i++) {
        const S1 = (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) >>> 0;
        const ch = ((e & f) ^ ((~e) & g)) >>> 0;
        const t1 = ((hh + S1 + ch + K[i] + w[i]) >>> 0);
        const S0 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) >>> 0;
        const maj = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
        const t2 = ((S0 + maj) >>> 0);
        hh = g; g = f; f = e;
        e = ((d + t1) >>> 0);
        d = c; c = b; b = a;
        a = ((t1 + t2) >>> 0);
      }
      h0 = ((h0 + a) >>> 0); h1 = ((h1 + b) >>> 0); h2 = ((h2 + c) >>> 0); h3 = ((h3 + d) >>> 0);
      h4 = ((h4 + e) >>> 0); h5 = ((h5 + f) >>> 0); h6 = ((h6 + g) >>> 0); h7 = ((h7 + hh) >>> 0);
    }
    const H = [h0, h1, h2, h3, h4, h5, h6, h7];
    let hex = '';
    for (let i = 0; i < H.length; i++) {
      let part = (H[i] >>> 0).toString(16);
      while (part.length < 8) {
        part = '0' + part;
      }
      hex += part;
    }
    return hex;
  }

  // ── Builder ──────────────────────────────────────────

  build() {
    NavDestination() {
      Column() {
        Row() {
          Image($r('app.media.ic_arrow_back'))
            .width(24).height(24).objectFit(ImageFit.Contain)
            .fillColor($r('app.color.list_title')).margin({ left: 12 })
            .onClick(() => NavController.pop())
          Text($r('app.string.parental_control'))
            .fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.orange500'))
            .margin({ left: AppDimens.kl_half })
            .layoutWeight(1).maxLines(1)
          Image($r('app.media.ic_search'))
            .width(28).height(28)
            .fillColor($r('app.color.list_title'))
            .margin({ right: 16 })
        }
        .width('100%').height(92).alignItems(VerticalAlign.Center)
        .padding({ left: 4, right: 4, top: 38, bottom: 4 })
        .backgroundColor($r('app.color.background_default'))

        if (this.isPinState()) {
          Column() {
            Text(this.getReasonText())
              .fontSize(16)
              .fontColor($r('app.color.list_subtitle'))
              .textAlign(TextAlign.Center)
              .margin({ top: 32, left: 32, right: 32 })

            Text(this.getInstruction())
              .fontSize(22)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.list_title'))
              .textAlign(TextAlign.Center)
              .margin({ top: 12, left: 32, right: 32 })

            Stack({ alignContent: Alignment.Center }) {
              Row({ space: 12 }) {
                Text(this.vm.pin1.length > 0 ? '•' : '')
                  .textAlign(TextAlign.Center).fontSize(30)
                  .fontColor($r('app.color.list_title'))
                  .layoutWeight(1).aspectRatio(1)
                  .backgroundColor($r('app.color.card_background')).borderRadius(8)
                Text(this.vm.pin2.length > 0 ? '•' : '')
                  .textAlign(TextAlign.Center).fontSize(30)
                  .fontColor($r('app.color.list_title'))
                  .layoutWeight(1).aspectRatio(1)
                  .backgroundColor($r('app.color.card_background')).borderRadius(8)
                Text(this.vm.pin3.length > 0 ? '•' : '')
                  .textAlign(TextAlign.Center).fontSize(30)
                  .fontColor($r('app.color.list_title'))
                  .layoutWeight(1).aspectRatio(1)
                  .backgroundColor($r('app.color.card_background')).borderRadius(8)
                Text(this.vm.pin4.length > 0 ? '•' : '')
                  .textAlign(TextAlign.Center).fontSize(30)
                  .fontColor($r('app.color.list_title'))
                  .layoutWeight(1).aspectRatio(1)
                  .backgroundColor($r('app.color.card_background')).borderRadius(8)
              }
              .width('100%')
              .padding({ left: 16, right: 16 })

              TextInput({ text: this.pinInput })
                .id('pin-input').type(InputType.NUMBER_PASSWORD).maxLength(4)
                .showPasswordIcon(false).defaultFocus(true)
                .width('100%').height('100%').opacity(0.01)
                .backgroundColor(Color.Transparent)
                .onAppear(() => this.focusPinInput())
                .onChange((value: string) => this.onPinInput(value))
            }
            .width('100%')
            .height(72)
            .margin({ top: 48 })

            Blank()

            Row() {
              Button($r('app.string.cancel'))
                .type(ButtonType.Normal)
                .backgroundColor(Color.Transparent)
                .fontColor($r('app.color.orange500'))
                .margin({ left: 16 })
                .onClick(() => NavController.pop())
              if (this.state === PageState.VERIFY_PIN || this.state === PageState.VERIFY_WRONG) {
                Button($r('app.string.skip'))
                  .type(ButtonType.Normal)
                  .backgroundColor(Color.Transparent)
                  .fontColor($r('app.color.orange500'))
                  .margin({ right: 16 })
                  .onClick(() => { this.state = PageState.SETTINGS; })
              }
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .padding({ bottom: 16 })
          }
          .width('100%')
          .layoutWeight(1)
        } else {
          Column() {
            // 更改密码
            Row() {
              Text($r('app.string.change_password'))
                .fontSize(16)
                .fontColor($r('app.color.list_title'))
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 32, bottom: 32 })
            .onClick(async () => {
              const stored = await Settings.getString(Settings.KEY_SAFE_MODE_PIN, '');
              this.state = stored.length > 0 ? PageState.CHANGE_VERIFY : PageState.CREATE_PIN;
              this.clearPinInput();
            })

            Row() {
              Text($r('app.string.restrict_settings_access'))
                .fontSize(16)
                .fontColor($r('app.color.list_title'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Checkbox, isOn: this.restrictSettings })
                .selectedColor($r('app.color.orange500'))
                .onChange((on: boolean) => {
                  this.restrictSettings = on;
                  Settings.put('restrict_settings', on);
                })
            }
            .width('100%')
            .padding({ left: 16, right: 12, top: 24, bottom: 32 })
            .alignItems(VerticalAlign.Center)

            Row() {
              Column() {
                Text($r('app.string.safe_mode'))
                  .fontSize(16)
                  .fontColor($r('app.color.list_title'))
                Text($r('app.string.safe_mode_summary'))
                  .fontSize(13)
                  .fontColor($r('app.color.list_subtitle'))
                  .margin({ top: 4 })
                  .maxLines(2)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Checkbox, isOn: this.safeMode })
                .selectedColor($r('app.color.orange500'))
                .margin({ left: 16 })
                .onChange((on: boolean) => {
                  this.safeMode = on;
                  Settings.put('safe_mode', on);
                })
            }
            .width('100%')
            .padding({ left: 16, right: 12, top: 24, bottom: 16 })
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_default'))
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
