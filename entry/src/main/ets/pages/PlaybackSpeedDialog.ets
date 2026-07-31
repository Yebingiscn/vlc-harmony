import { AppColors } from '../common/constants/AppConstants';

/** 保存动作载荷。 */
export interface PlaybackSpeedAction {
  speed: number;
  scope: 'this' | 'all';
}

/**
 * PlaybackSpeedDialog —— 「回放速度」弹窗。
 *
 * 布局:顶部拖动条 + 标题,中间 Tabs→步进→滑块→预设,底部固定保存按钮。
 */

@ComponentV2
export struct PlaybackSpeedDialog {
  @Event onClose: () => void = () => {};
  @Event onConfirm: (action: PlaybackSpeedAction) => void = () => {};

  @Param currentSpeed: number = 1.0;

  readonly cPanelBg: string = '#D91C1C1C';
  readonly cHeaderBg: string = '#E61C1C1C';
  readonly cAccent: string = '#FF8800';
  readonly cDim: string = '#B3FFFFFF';
  readonly cBorder: string = '#33FFFFFF';
  readonly cIconBtn: string = '#2A2A2A';

  @Local scope: 'this' | 'all' = 'this';
  @Local speed: number = 1.0;
  @Local sliderValue: number = 50; // 0..100

  aboutToAppear(): void {
    this.speed = this.currentSpeed > 0 ? this.currentSpeed : 1.0;
    this.sliderValue = this.rateToSlider(this.speed);
  }

  private rateToSlider(r: number): number {
    return Math.round(Math.log(r / 0.25) / Math.log(32) * 100);
  }

  private sliderToRate(v: number): number {
    return Math.round(0.25 * Math.pow(32, v / 100) * 100) / 100;
  }

  private step(delta: number): void {
    const r: number = Math.max(0.25, Math.min(8.0, Math.round((this.speed + delta) * 100) / 100));
    this.speed = r;
    this.sliderValue = this.rateToSlider(r);
  }

  private applyPreset(r: number): void {
    this.speed = r;
    this.sliderValue = this.rateToSlider(r);
  }

  private onSliderChange(v: number): void {
    this.sliderValue = Math.round(v);
    this.speed = this.sliderToRate(this.sliderValue);
  }

  // ── 顶栏 ──────────────────────────────────────
  @Builder
  header() {
    Column() {
      Row()
        .width(36).height(4)
        .backgroundColor('#80FFFFFF')
        .borderRadius(2)
        .margin({ top: 8, bottom: 10 })
      Row() {
        Row() {
          Image($r('app.media.ic_arrow_back'))
            .width(28).height(28)
            .fillColor('#FFFFFF')
            .padding(2)
            .onClick(() => this.onClose())
        }
        .width(40)
        .justifyContent(FlexAlign.Start)

        Text('回放速度')
          .fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Row().width(40)
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 8 })
    }
    .width('100%')
    .backgroundColor(this.cHeaderBg)
  }

  // ── THIS VIDEO / ALL VIDEOS ────────────────────
  @Builder
  scopeTabs() {
    Row() {
      this.scopeTab('THIS VIDEO', this.scope === 'this')
      this.scopeTab('ALL VIDEOS', this.scope === 'all')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 14, bottom: 6 })
  }

  @Builder
  scopeTab(label: string, selected: boolean) {
    Row() {
      Text(label)
        .fontSize(12).fontWeight(FontWeight.Medium)
        .fontColor(selected ? '#FFFFFF' : this.cDim)
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .width('100%')
    .height(32)
    .justifyContent(FlexAlign.Center)
    .borderRadius(4)
    .border({ width: selected ? 0 : 1, color: this.cBorder })
    .backgroundColor(selected ? '#FF8800' : '#2A2A2A')
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
    .onClick(() => {
      if (!selected) {
        this.scope = this.scope === 'this' ? 'all' : 'this';
      }
    })
  }

  // ── "< 1.00x >" 步进 ──────────────────────────
  @Builder
  speedStepper() {
    Row() {
      Row() {
        Text('−')
          .fontSize(22).fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
      }
      .width(44).height(44)
      .borderRadius(22)
      .backgroundColor(this.cIconBtn)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .onClick(() => this.step(-0.05))

      Text(`${this.speed.toFixed(2)}x`)
        .fontSize(32).fontWeight(FontWeight.Bold)
        .fontColor(this.cAccent)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      Row() {
        Text('+')
          .fontSize(22).fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
      }
      .width(44).height(44)
      .borderRadius(22)
      .backgroundColor(this.cIconBtn)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .onClick(() => this.step(0.05))
    }
    .width('100%')
    .padding({ left: 28, right: 28, top: 12, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  // ── 可拖动滑块 ────────────────────────────────
  @Builder
  speedSlider() {
    Slider({
      value: this.sliderValue,
      min: 0,
      max: 100,
      step: 1,
      style: SliderStyle.OutSet,
    })
      .width('100%')
      .blockColor(this.cAccent)
      .selectedColor(this.cAccent)
      .trackColor('#3DFFFFFF')
      .trackThickness(4)
      .blockSize({ width: 22, height: 22 })
      .onChange((v: number, mode: SliderChangeMode) => {
        if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving || mode === SliderChangeMode.End) {
          this.onSliderChange(v);
        }
      })
  }

  // ── 范围行 ────────────────────────────────────
  @Builder
  rangeRow() {
    Row() {
      Text('0.25x').fontSize(11).fontColor(this.cDim)
      Blank()
      Text('8.00x').fontSize(11).fontColor(this.cDim)
    }
    .width('100%')
    .padding({ left: 28, right: 28, top: 4 })
  }

  // ── 预设 ───────────────────────────────────────
  @Builder
  presetRow() {
    Row() {
      ForEach([0.8, 1.0, 1.25, 1.5, 2.0], (p: number) => {
        Column() {
          Text(`${p.toFixed(p % 1 === 0 ? 0 : 2)}x`)
            .fontSize(12).fontWeight(FontWeight.Medium)
            .fontColor(Math.abs(this.speed - p) < 0.005 ? '#FFFFFF' : this.cDim)
        }
        .width(52).height(36)
        .borderRadius(18)
        .border({ width: 1, color: Math.abs(this.speed - p) < 0.005 ? this.cAccent : this.cBorder })
        .backgroundColor(Math.abs(this.speed - p) < 0.005 ? '#33FF8800' : Color.Transparent)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
        .onClick(() => this.applyPreset(p))
      }, (p: number) => `p${p}`)
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 14 })
    .justifyContent(FlexAlign.SpaceBetween)
  }

  build() {
    Column() {
      this.header()

      Column() {
        this.scopeTabs()

        Text(this.scope === 'this' ? '仅应用于此视频' : '应用于所有视频')
          .fontSize(12).fontColor(this.cDim)
          .width('100%')
          .padding({ left: 24, right: 24, bottom: 12 })

        this.speedStepper()

        Row() {
          this.speedSlider()
        }
        .width('100%')
        .padding({ left: 24, right: 24 })

        this.rangeRow()

        this.presetRow()
      }
      .width('100%')
      .layoutWeight(1)

      // 底部保存
      Column() {
        Row()
          .width('100%')
          .height(0.5)
          .backgroundColor(this.cBorder)
        Button('保存')
          .type(ButtonType.Capsule)
          .fontSize(15).fontWeight(FontWeight.Medium)
          .backgroundColor(this.cAccent)
          .fontColor('#FFFFFF')
          .width('100%')
          .height(46)
          .onClick(() => {
            this.onConfirm({ speed: this.speed, scope: this.scope });
            this.onClose();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 28 })
      .backgroundColor(this.cPanelBg)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.cPanelBg)
  }
}
