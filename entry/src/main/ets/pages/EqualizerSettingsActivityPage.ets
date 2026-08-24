import { UiFeedback } from '../common/utils/UiFeedback';
import { NavController } from '../common/data/NavController';
import { AppColors, AppDimens } from '../common/constants/AppConstants';
import { EqualizerPreset } from '../common/models/MediaModels';
import { LengthMetrics } from '@kit.ArkUI';
import {
  DividerShowType,
  hdsMaterial,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';

/** 点击类型(对应 EqualizerSettingsAdapter.ClickType)。 */
export enum EqClickType {
  EQUALIZER_CHANGE_CURRENT,
  EQUALIZER_ENABLE,
  EQUALIZER_DISABLE,
  EQUALIZER_DELETE,
  EQUALIZER_EXPORT,
}

/** 均衡器条目(对应 EqualizerWithBands;TODO(契约): schema 不在本页)。 */
export class EqualizerEntry {
  id: number;
  name: string;
  presetIndex: number; // -1=自定义,其它=内置预设序号
  isDisabled: boolean;
  bands: number[]; // 各频段增益 dB(用于缩略图波形绘制)

  constructor(id: number, name: string, presetIndex: number, isDisabled: boolean, bands: number[]) {
    this.id = id;
    this.name = name;
    this.presetIndex = presetIndex;
    this.isDisabled = isDisabled;
    this.bands = bands;
  }
}

/**
 * EqualizerSettingsActivityPage —— 均衡器预设管理页(EqualizerSettingsActivity)。
 * 角色:pushed(从 EqualizerDialog 齿轮/设置入口推入)。
 * 结构:Toolbar(ic_close_up 关闭 + Equalizer 标题 + 右上 ic_options_equalizer/ic_import 菜单)
 *   + 覆盖命名弹层卡片(条件渲染) + 预设 List(每项 40vp 波形缩略图 + 名称 + enable/disable/delete/export 图标)。
 * 数据:EqualizerRepository 预设数组 → TODO(契约);用 EqualizerPreset 样例数组占位。
 */
@ObservedV2
export class EqualizerSettingsVM {
  @Trace entries: EqualizerEntry[] = [];
  @Trace currentId: number = -1;
  @Trace overwriteDialogVisible: boolean = false;
  @Trace renameText: string = '';
  @Trace renameError: string = '';
  @Trace overwriteEnabled: boolean = true;
  @Trace overwriteButtonText: string = 'Overwrite';

  load(): void {
    // TODO(契约): equalizerRepository.equalizerEntriesUnfiltered Flow → adapter.update(it)。schema/Repository 不在本页。
    // 用 EqualizerPreset 样例数组占位:内置预设 presetIndex>=0 + 自定义预设 presetIndex==-1。
    const presets: EqualizerPreset[] = [
      new EqualizerPreset(0, 'Flat', [0, 0, 0, 0, 0]),
      new EqualizerPreset(1, 'Classical', [0, 0, 0, 0, 0]),
      new EqualizerPreset(2, 'Club', [0, 0, 5, 5, 5]),
      new EqualizerPreset(3, 'Dance', [8, 6, 2, 0, 0]),
      new EqualizerPreset(4, 'Full Bass', [8, 6, 0, 0, 0]),
      new EqualizerPreset(5, 'Full Treble', [0, 0, 0, 6, 8]),
    ];
    const list: EqualizerEntry[] = [];
    for (let i = 0; i < presets.length; i++) {
      const p = presets[i];
      list.push(new EqualizerEntry(p.id, p.name, i, false, p.bands));
    }
    // 一个自定义预设(presetIndex==-1,可删除/导出)。
    list.push(new EqualizerEntry(100, 'My Preset', -1, false, [3, 2, 0, 2, 4]));
    this.entries = list;
    this.currentId = list.length > 0 ? list[0].id : -1;
  }
}

@ComponentV2
export struct EqualizerSettingsActivityPage {
  @Local vm: EqualizerSettingsVM = new EqualizerSettingsVM();
  private readonly strokeColor: string = AppColors.grey300; // default_divider 预设笔色/外描边
  private readonly customColor: string = '#86FF8800'; // orange500focus 自定义预设笔色

  aboutToAppear(): void {
    // 生命周期加载:observe vm.equalizerUnfilteredEntries + currentEqualizerIdLive。
    this.vm.load();
  }

  onItemClick(item: EqualizerEntry, type: EqClickType): void {
    switch (type) {
      case EqClickType.EQUALIZER_CHANGE_CURRENT:
        // vm.currentEqualizerId = item.id + vm.updateEqualizer()(apply 到 PlaybackService.equalizer)
        // TODO(契约): SP KEY_CURRENT_EQUALIZER_ID + PlaybackService.equalizer StateFlow 不在本页。
        this.vm.currentId = item.id;
        break;
      case EqClickType.EQUALIZER_ENABLE:
        // TODO(契约): vm.enable(item)(isDisabled=false)
        item.isDisabled = false;
        this.vm.entries = this.vm.entries.slice();
        break;
      case EqClickType.EQUALIZER_DISABLE:
        // TODO(契约): vm.disable(item)(isDisabled=true)
        item.isDisabled = true;
        this.vm.entries = this.vm.entries.slice();
        break;
      case EqClickType.EQUALIZER_DELETE:
        // TODO(契约): vm.delete(item) + 撤销 snackbar(equalizer_deleted/undo)
        this.vm.entries = this.vm.entries.filter((e: EqualizerEntry) => e.id !== item.id);
        UiFeedback.showToast({ message: 'The equalizer has been deleted' });
        break;
      case EqClickType.EQUALIZER_EXPORT:
        // TODO(契约): vm.export(item)(生成 vlc_<name>.json 写公共目录 + share)
        UiFeedback.showToast({ message: 'Export equalizer' });
        break;
      default:
        break;
    }
  }

  @Builder
  OverwriteCard() {
    Column() {
      Text($r('app.string.equalizer_overwrite_warning')) // "This equalizer already exists"
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.grey900)
        .margin({ left: AppDimens.default_margin, top: AppDimens.default_margin, right: AppDimens.default_margin })
      TextInput({ text: this.vm.renameText, placeholder: $r('app.string.equalizer_name') })
        .width('100%')
        .margin({ left: AppDimens.default_margin, top: AppDimens.kl_normal, right: AppDimens.default_margin })
        .onChange((s: string) => {
          this.vm.renameText = s;
          // TODO(契约): vm.checkForbidden/isNameAllowed 校验逻辑不在本页。
          this.vm.renameError = '';
          this.vm.overwriteEnabled = s.length > 0;
          this.vm.overwriteButtonText = s.length > 0 ? 'Rename' : 'Overwrite';
        })
      if (this.vm.renameError.length > 0) {
        Text(this.vm.renameError)
          .fontSize(12)
          .fontColor(AppColors.red)
          .margin({ left: AppDimens.default_margin })
      }
      Row() {
        Button($r('app.string.cancel'))
          .type(ButtonType.Normal)
          .backgroundColor(AppColors.transparent)
          .fontColor(AppColors.grey700)
          .margin({ right: AppDimens.default_margin })
          .enabled(this.vm.overwriteEnabled)
          .onClick(() => {
            this.vm.overwriteDialogVisible = false;
          })
        Button(this.vm.overwriteButtonText)
          .type(ButtonType.Normal)
          .backgroundColor(AppColors.transparent)
          .fontColor(AppColors.orange800)
          .margin({ right: AppDimens.default_margin })
          .enabled(this.vm.overwriteEnabled)
          .onClick(() => {
            // TODO(契约): vm.insert(改名后的 eq) → 隐藏卡片。
            this.vm.overwriteDialogVisible = false;
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 24, bottom: AppDimens.default_margin })
    }
    .width('100%')
    .margin({ left: AppDimens.kl_normal, right: AppDimens.kl_normal, top: AppDimens.kl_normal })
    .border({ width: 1, color: AppColors.grey300 })
  }

  @Builder
  SettingItem(item: EqualizerEntry) {
    Row() {
      // 左:缩略图(40dp,叠当前项对勾)
      Stack() {
        EqualizerThumbnail({
          bands: item.bands,
          isCustom: item.presetIndex === -1,
          strokeColor: this.strokeColor,
          customColor: this.customColor
        })
        if (item.id === this.vm.currentId) {
          Stack() {
            Image($r('app.media.ic_check_large_white'))
              .width(24)
              .height(24)
              .fillColor(AppColors.white)
          }
          .width(40)
          .height(40)
          .backgroundColor(AppColors.blacktransparent)
          .padding(AppDimens.half_default_margin)
        }
      }
      .width(40)
      .height(40)
      .margin({ left: AppDimens.default_margin, top: AppDimens.default_margin, bottom: AppDimens.default_margin })

      // 名称
      Text(item.name)
        .fontSize(16)
        .fontColor(item.isDisabled ? AppColors.grey500 : AppColors.grey900)
        .layoutWeight(1)
        .margin({ left: AppDimens.kl_normal, right: AppDimens.default_margin })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // 右侧操作图标组
      Row() {
        // disable(可见:!current && presetIndex!=-1 && !isDisabled)— ic_visible
        if (item.id !== this.vm.currentId && item.presetIndex !== -1 && !item.isDisabled) {
          Image($r('app.media.ic_visible'))
            .width(24)
            .height(24)
            .fillColor(AppColors.grey600)
            .padding(12)
            .margin(
              { right: AppDimens.default_margin, top: AppDimens.default_margin, bottom: AppDimens.default_margin })
            .onClick(() => this.onItemClick(item, EqClickType.EQUALIZER_DISABLE))
        }
        // enable(可见:!current && presetIndex!=-1 && isDisabled)— ic_invisible
        if (item.id !== this.vm.currentId && item.presetIndex !== -1 && item.isDisabled) {
          Image($r('app.media.ic_invisible'))
            .width(24)
            .height(24)
            .fillColor(AppColors.grey600)
            .padding(12)
            .margin(
              { right: AppDimens.default_margin, top: AppDimens.default_margin, bottom: AppDimens.default_margin })
            .onClick(() => this.onItemClick(item, EqClickType.EQUALIZER_ENABLE))
        }
        // delete(可见:!current && presetIndex==-1)— ic_delete
        if (item.id !== this.vm.currentId && item.presetIndex === -1) {
          Image($r('app.media.ic_delete'))
            .width(24)
            .height(24)
            .fillColor(AppColors.grey600)
            .padding(12)
            .margin({ right: AppDimens.default_margin })
            .onClick(() => this.onItemClick(item, EqClickType.EQUALIZER_DELETE))
        }
        // export(可见:presetIndex==-1)— ic_export
        if (item.presetIndex === -1) {
          Image($r('app.media.ic_export'))
            .width(24)
            .height(24)
            .fillColor(AppColors.grey600)
            .padding(12)
            .margin({ right: AppDimens.default_margin })
            .onClick(() => this.onItemClick(item, EqClickType.EQUALIZER_EXPORT))
        }
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .backgroundColor(item.id === this.vm.currentId ? '#0a000000' : AppColors.transparent)
    .onClick(() => {
      if (!item.isDisabled && item.id !== this.vm.currentId) {
        this.onItemClick(item, EqClickType.EQUALIZER_CHANGE_CURRENT);
      }
    })
  }

  build() {
    HdsNavDestination() {
      Column() {
        // 内容区
        Column() {
          if (this.vm.overwriteDialogVisible) {
            this.OverwriteCard()
          }
          // 预设列表
          List() {
            Repeat(this.vm.entries).each((itemRepeatItem: RepeatItem<EqualizerEntry>) => {
              ListItem() {
                this.SettingItem(itemRepeatItem.item)
              }
            }).key((item: EqualizerEntry) => `${item.id}`).virtualScroll()
          }
          .width('100%')
          .layoutWeight(1)
          .margin({ top: AppDimens.default_margin })
          .padding({ bottom: 48 })
          .scrollBar(BarState.Auto)
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_default'))
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      padding: {
        start: LengthMetrics.vp(5),
        end: LengthMetrics.vp(5)
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20)
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: $r('sys.color.ohos_id_color_background')
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('sys.color.font_primary'),
              subTitleColor: $r('sys.color.font_secondary')
            },
            menuStyle: {
              backgroundColor: $r('sys.color.comp_background_tertiary'),
              iconColor: $r('sys.color.icon_primary')
            },
            backIconStyle: {
              backgroundColor: $r('sys.color.comp_background_tertiary'),
              iconColor: $r('sys.color.icon_primary')
            }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: $r('sys.color.ohos_id_color_background_transparent')
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('sys.color.font_primary'),
              subTitleColor: $r('sys.color.font_secondary')
            },
            menuStyle: {
              backgroundColor: $r('sys.color.comp_background_tertiary'),
              iconColor: $r('sys.color.icon_primary')
            },
            backIconStyle: {
              backgroundColor: $r('sys.color.comp_background_tertiary'),
              iconColor: $r('sys.color.icon_primary')
            }
          }
        }
      },
      content: {
        title: {
          mainTitle: $r('app.string.equalizer')
        },
        backIcon: {
          icon: $r('app.media.ic_arrow_back'),
          label: '返回',
          action: () => NavController.pop()
        },
        menu: {
          value: [
            {
              content: {
                icon: $r('app.media.ic_equalizer'),
                label: 'Show',
                action: () => {
                  UiFeedback.showToast({ message: 'Show equalizer' });
                }
              }
            },
            {
              content: {
                icon: $r('app.media.ic_import'),
                label: 'Import',
                action: () => {
                  UiFeedback.showToast({ message: 'Import equalizer' });
                }
              }
            }
          ],
          maxCount: 3
        },
        divider: {
          showType: DividerShowType.AUTO
        }
      }
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}

/**
 * EqualizerThumbnail —— 均衡器频段波形缩略图(Canvas 自绘)。
 * 复刻 getBitmap:画布 72dp/步进 8dp/圆角 8;自定义=橙笔,预设=灰笔;各频段竖条 heightPc=(bandValue+20)/40。
 */
@ComponentV2
export struct EqualizerThumbnail {
  @Param bands: number[] = [];
  @Param isCustom: boolean = false;
  @Param strokeColor: string = '#E0E0E0';
  @Param customColor: string = '#86FF8800';
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  build() {
    Canvas(this.context)
      .width(40)
      .height(40)
      .onReady(() => {
        const ctx = this.context;
        const imageSize = 40;
        const step = imageSize / Math.max(this.bands.length, 1);
        const barWidth = step * 0.7;
        ctx.clearRect(0, 0, imageSize, imageSize);
        // 圆角裁剪
        ctx.save();
        ctx.beginPath();
        const r = 6;
        ctx.moveTo(r, 0);
        ctx.arcTo(imageSize, 0, imageSize, imageSize, r);
        ctx.arcTo(imageSize, imageSize, 0, imageSize, r);
        ctx.arcTo(0, imageSize, 0, 0, r);
        ctx.arcTo(0, 0, imageSize, 0, r);
        ctx.closePath();
        ctx.clip();
        const color = this.isCustom ? this.customColor : this.strokeColor;
        ctx.fillStyle = color;
        for (let i = 0; i < this.bands.length; i++) {
          const v = this.bands[i];
          const heightPc = (v + 20) / 40; // (bandValue+20)/40
          const barHeight = Math.max(imageSize * 0.1, imageSize * heightPc);
          const x = i * step + (step - barWidth) / 2;
          const y = imageSize - barHeight;
          ctx.fillRect(x, y, barWidth, barHeight);
        }
        ctx.restore();
        // 外描边 default_divider
        ctx.strokeStyle = this.strokeColor;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(r, 0);
        ctx.arcTo(imageSize, 0, imageSize, imageSize, r);
        ctx.arcTo(imageSize, imageSize, 0, imageSize, r);
        ctx.arcTo(0, imageSize, 0, 0, r);
        ctx.arcTo(0, 0, imageSize, 0, r);
        ctx.closePath();
        ctx.stroke();
      })
  }
}
