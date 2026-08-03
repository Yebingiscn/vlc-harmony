import { PreferenceItem } from '../models/PreferenceModels';
import { Settings } from '../data/Settings';
import { promptAction } from '@kit.ArkUI';

/**
 * PreferenceRow —— 通用偏好项单行渲染(@ComponentV2)。
 * 按 item.type 条件渲染右侧控件:toggle→Toggle+Text;list→Text(summary,点击弹选择器)/右箭头;
 * nav→Text(title)+右箭头(回调 onNav);numberpicker→Text+数字(右箭头);seekbar→Slider+Text;
 * checkbox→Checkbox+Text;color→色块+右箭头;click/info→仅文本。
 * 点击读写 Settings(key)。外部可选回调 onNav(跳转) / onListSelect(弹选择器) / onNumberPicker(弹数字) /
 * onMultiselect(弹多选) / onTextEdit(弹文本) / onColorPick(弹颜色)覆盖默认行为。
 */
@ComponentV2
export struct PreferenceRow {
  @Param item: PreferenceItem = new PreferenceItem({});
  /** 父依赖开关当前值(决定 disabled 置灰);未设 dependency 时恒 true。 */
  @Param dependencyEnabled: boolean = true;
  /** 二级偏好页可隐藏右侧箭头，以匹配 Android 的 ListPreference 样式。 */
  @Param showTrailingIndicator: boolean = true;
  /** 条目上下内边距；界面设置页使用 Android 对应的较高条目。 */
  @Param verticalPadding: number = 14;
  /** Android 的界面设置页只在分组之间显示分隔线。 */
  @Param showDivider: boolean = true;
  /** 行点击统一回调(用于 nav/click 等非值切换)。 */
  @Event onNav: (item: PreferenceItem) => void = () => {};
  /** list 类型点击回调(由父页弹单选,回写后刷新)。 */
  @Event onListSelect: (item: PreferenceItem) => void = () => {};
  /** numberpicker 类型点击回调。 */
  @Event onNumberPicker: (item: PreferenceItem) => void = () => {};
  /** multiselect 类型点击回调。 */
  @Event onMultiselect: (item: PreferenceItem) => void = () => {};
  /** text 类型点击回调。 */
  @Event onTextEdit: (item: PreferenceItem) => void = () => {};
  /** color 类型点击回调。 */
  @Event onColorPick: (item: PreferenceItem) => void = () => {};
  /**
   * toggle/checkbox 切换前的拦截回调(由父页实现)。
   * 返回 true 表示父页已接管此次切换(自行决定是否写 Settings,通常是先弹确认框),本行不再自动 put;
   * 返回 false(默认)表示父页未接管,本行走原有直接 put 逻辑。
   * @param newValue 即将写入的目标值(取反后的值)
   */
  @Event onToggleChange: (item: PreferenceItem, newValue: boolean) => boolean = () => false;

  @Local boolValue: boolean = false;
  @Local strValue: string = '';
  @Local numValue: number = 0;
  @Local multiselectValues: string[] = [];
  @Local initialized: boolean = false;

  aboutToAppear(): void {
    this.loadValue();
  }

  async loadValue(): Promise<void> {
    const it = this.item;
    if (it.type === 'toggle' || it.type === 'checkbox') {
      this.boolValue = await Settings.getBoolean(it.key, typeof it.defaultValue === 'boolean' ? it.defaultValue : false);
    } else if (it.type === 'list' || it.type === 'text') {
      this.strValue = await Settings.getString(it.key, typeof it.defaultValue === 'string' ? it.defaultValue : '');
    } else if (it.type === 'seekbar') {
      this.numValue = await Settings.getInt(it.key, typeof it.defaultValue === 'number' ? it.defaultValue : 0);
    } else if (it.type === 'numberpicker') {
      this.numValue = await Settings.getInt(it.key, typeof it.defaultValue === 'number' ? it.defaultValue : 0);
    } else if (it.type === 'multiselect') {
      // 多选:无原生 stringSet,落 Settings string(逗号拼接,对齐 PreferencesPage.onMultiConfirm 的 values.join(','))。
      // 读存储串 split(',') 还原;空串(未设)→ 回退默认选中集。
      const stored: string = await Settings.getString(it.key, '');
      if (stored.length > 0) {
        this.multiselectValues = stored.split(',');
      } else {
        const sel: string[] = it.defaultSelected ? it.defaultSelected.slice() : [];
        this.multiselectValues = sel;
      }
    }
    this.initialized = true;
  }

  /** list 类型当前选中项的显示文案(由 optionValues 映射到 options)。 */
  currentListLabel(): ResourceStr {
    const it = this.item;
    if (!it.options || !it.optionValues) {
      return '';
    }
    const idx = it.optionValues.indexOf(this.strValue);
    if (idx >= 0 && idx < it.options.length) {
      return it.options[idx];
    }
    return '';
  }

  /** multiselect summary:Enabled/Disabled 拼接。 */
  multiselectSummary(): string {
    const it = this.item;
    if (!it.options || !it.optionValues) {
      return '';
    }
    const enabled: string[] = [];
    const disabled: string[] = [];
    for (let i = 0; i < it.optionValues.length; i++) {
      const label = it.options[i] as string;
      if (this.multiselectValues.indexOf(it.optionValues[i]) >= 0) {
        enabled.push(label);
      } else {
        disabled.push(label);
      }
    }
    const e = enabled.length > 0 ? enabled.join(', ') : '-';
    const d = disabled.length > 0 ? disabled.join(', ') : '-';
    return `Enabled: ${e}\nDisabled: ${d}`;
  }

  onToggle(on: boolean): void {
    // 父页拦截(如禁用历史前弹确认框):返回 true 表示已接管,本行不自动写。
    if (this.onToggleChange(this.item, on)) {
      return;
    }
    this.boolValue = on;
    Settings.put(this.item.key, on);
  }

  onRowClick(): void {
    if (!this.dependencyEnabled) {
      return;
    }
    const t = this.item.type;
    if (t === 'toggle' || t === 'checkbox') {
      this.onToggle(!this.boolValue);
    } else if (t === 'list') {
      this.onListSelect(this.item);
    } else if (t === 'numberpicker') {
      this.onNumberPicker(this.item);
    } else if (t === 'multiselect') {
      this.onMultiselect(this.item);
    } else if (t === 'text') {
      this.onTextEdit(this.item);
    } else if (t === 'color') {
      this.onColorPick(this.item);
    } else if (t === 'nav' || t === 'click') {
      this.onNav(this.item);
    }
  }

  build() {
    Column() {
      Row() {
        if (this.item.icon) {
          Image(this.item.icon)
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.list_title'))
            .margin({ right: 32 })
        }
        Column() {
          Text(this.item.title)
            .fontSize(15)
            .fontColor(this.dependencyEnabled ? $r('app.color.list_title') : $r('app.color.grey700'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.item.summary) {
            Text(this.item.summary)
              .fontSize(12)
              .fontColor($r('app.color.list_subtitle'))
              .margin({ top: 2 })
          }
          // list/numberpicker/text 类型:右侧 summary 用动态当前值
          if ((this.item.type === 'list') && this.currentListLabel() !== '') {
            Text(this.currentListLabel())
              .fontSize(12)
              .fontColor($r('app.color.list_subtitle'))
              .margin({ top: 2 })
          }
          if (this.item.type === 'multiselect') {
            Text(this.multiselectSummary())
              .fontSize(12)
              .fontColor($r('app.color.list_subtitle'))
              .margin({ top: 2 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // 末尾控件:按 type
        if (this.item.type === 'toggle' || this.item.type === 'checkbox') {
          Toggle({
            type: this.item.type === 'checkbox' ? ToggleType.Checkbox : ToggleType.Switch,
            isOn: this.boolValue,
          })
            .selectedColor('#FF8800')
            .enabled(this.dependencyEnabled)
          // Toggle 的点击会冒泡到整行；统一由 Row.onClick 调用 onToggle，
          // 避免控件自身 onChange 与整行点击各切换一次而回到原值。
        } else if (this.item.type === 'seekbar') {
          Slider({
            value: this.numValue,
            min: this.item.min ?? 0,
            max: this.item.max ?? 100,
            step: this.item.step ?? 1,
          })
            .selectedColor('#FF8800')
            .trackColor($r('app.color.card_border'))
            .blockColor('#FF8800')
            .width(120)
            .enabled(this.dependencyEnabled)
            .onChange((v: number) => {
              this.numValue = v;
              Settings.put(this.item.key, v);
            })
        } else if (this.item.type === 'color') {
          // 色块预览 + 右箭头
          Row() {
            Column()
              .width(24)
              .height(24)
              .borderRadius(12)
              .backgroundColor(this.item.defaultValue as number >= 0 ? '#000000' : '#000000')
              .margin({ right: 8 })
            Image($r('app.media.ic_arrow_right'))
              .width(20)
              .height(20)
              .fillColor($r('app.color.list_subtitle'))
          }
        } else if ((
          this.item.type === 'list' ||
          this.item.type === 'nav' ||
          this.item.type === 'numberpicker' ||
          this.item.type === 'multiselect' ||
          this.item.type === 'text' ||
          this.item.type === 'click'
        ) && this.showTrailingIndicator) {
          Image($r('app.media.ic_arrow_right'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.list_subtitle'))
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.verticalPadding, bottom: this.verticalPadding })
      .alignItems(VerticalAlign.Center)
      .opacity(this.dependencyEnabled ? 1.0 : 0.4)
      .onClick(() => this.onRowClick())
      if (this.showDivider) {
        Divider()
          .color($r('app.color.divider'))
          .strokeWidth(0.5)
          .margin({ left: 16, right: 16 })
      }
    }
    .width('100%')
  }
}
