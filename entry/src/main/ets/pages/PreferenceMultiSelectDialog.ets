import { PreferenceItem } from '../common/models/PreferenceModels';

/**
 * PreferenceMultiSelectDialog —— MultiSelectListPreference 多选弹窗(@ComponentV2 纯展示)。
 * 来源:MultiSelectListPreferenceDialogFragmentCompat(无布局 XML,系统 AlertDialog.setMultiChoiceItems)。
 * 标题 + 复选框列表(entries × 初始勾选态)+ 底部 取消/确定。
 * 维护 newValues/preferenceChanged;确定且 preferenceChanged → onConfirm(newValues);取消 → onDismiss。
 * 异常保护:options/optionValues 缺失 → 抛 IllegalStateException(源码强约束)。
 */
@ComponentV2
export struct PreferenceMultiSelectDialog {
  @Param title: ResourceStr = '';
  @Param item: PreferenceItem = new PreferenceItem({});
  @Event onConfirm: (values: string[]) => void = () => {};
  @Event onDismiss: () => void = () => {};

  @Local checked: boolean[] = [];
  @Local newValues: string[] = [];
  @Local preferenceChanged: boolean = false;
  @Local initialized: boolean = false;

  aboutToAppear(): void {
    const it = this.item;
    if (!it.options || !it.optionValues) {
      throw new Error('MultiSelectListPreference requires an entries array and an entryValues array.');
    }
    // 基线 = defaultSelected(当前持久化 values)。
    const baseline: string[] = it.defaultSelected ? it.defaultSelected.slice() : [];
    this.newValues = baseline.slice();
    const arr: boolean[] = [];
    for (let i = 0; i < it.optionValues.length; i++) {
      arr.push(baseline.indexOf(it.optionValues[i]) >= 0);
    }
    this.checked = arr;
    this.initialized = true;
  }

  onCheckChange(index: number, isChecked: boolean): void {
    // 整体 reassign 满足 @Trace 数组更新(此处 checked 为 @Local,同样整体 reassign)
    const next: boolean[] = this.checked.slice();
    next[index] = isChecked;
    this.checked = next;
    const values: string[] = this.newValues.slice();
    const v: string = this.item.optionValues![index];
    const pos: number = values.indexOf(v);
    if (isChecked && pos < 0) {
      values.push(v);
    } else if (!isChecked && pos >= 0) {
      values.splice(pos, 1);
    }
    this.newValues = values;
    this.preferenceChanged = true;
  }

  build(): void {
    Column() {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1F1F1F')
        .margin({ bottom: 8 })

      List() {
        ForEach(this.item.options ?? [], (entry: ResourceStr, index: number) => {
          ListItem() {
            Row() {
              Text(entry)
                .fontSize(16)
                .fontColor('#1F1F1F')
              Toggle({ type: ToggleType.Checkbox, isOn: this.checked[index] })
                .onChange((on: boolean) => this.onCheckChange(index, on))
            }
            .width('100%')
            .height(48)
            .padding({ right: 8 })
            .alignItems(VerticalAlign.Center)
            .justifyContent(FlexAlign.SpaceBetween)
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Row() {
        Text($r('app.string.cancel'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FF8800')
          .padding(8)
          .onClick(() => this.onDismiss())
        Text($r('app.string.ok'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FF8800')
          .margin({ left: 8 })
          .padding(8)
          .onClick(() => {
            if (this.preferenceChanged) {
              this.onConfirm(this.newValues);
            } else {
              this.onDismiss();
            }
          })
      }
      .width('100%')
      .height(52)
      .padding({ left: 8, right: 8 })
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
    }
    .width(280)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .padding({ top: 24, bottom: 0, left: 0, right: 0 })
  }
}
