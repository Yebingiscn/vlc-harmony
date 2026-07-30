import { NavController } from '../common/data/NavController';
import { AppColors, AppDimens } from '../common/constants/AppConstants';

/** FilePicker 入参(对应 KEY_MEDIA / KEY_PICKER_TYPE)。 */
export class FilePickerParam {
  /** KEY_PICKER_TYPE(int,默认 0)。 */
  pickerType: number = 0;
  /** KEY_MEDIA(MediaWrapper 的 mrl,可空)。 */
  mediaUri: string = '';
}

/**
 * FilePickerActivityPage —— 文件选择对话框外壳(FilePickerActivity)。
 * 角色:弹窗 / 底部贴边对话框宿主。
 * 结构:底部贴边壳(宽 300vp,minHeight 320vp,背景 background_default_darker)+ 顶部关闭按钮 + 文件列表占位区。
 * 真正的文件/目录列表由 FilePickerFragment 子页渲染 → TODO(契约): 子页契约,本外壳只画关闭按钮 + 占位区。
 */
@ComponentV2
export struct FilePickerActivityPage {
  @Param param: FilePickerParam = new FilePickerParam();
  @Local currentPath: string = '/storage/Users/currentUser';

  build() {
    NavDestination() {
      Column() {
        // 底部贴边壳(宽 300vp,minHeight 320vp)
        Column() {
          // 顶部行:右侧关闭按钮(贴右贴顶)
          Row() {
            Image($r('app.media.ic_close_small'))
              .width(24)
              .height(24)
              .fillColor(AppColors.grey900)
              .margin({ top: AppDimens.default_margin, right: AppDimens.default_margin })
              .onClick(() => {
                // onCloseClick → finish()
                NavController.pop();
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.End)

          // 内容占位区(fragment_placeholder):文件列表占位(FilePickerFragment 子页)
          Column() {
            // TODO(契约): FilePickerFragment 子页渲染真实文件/目录列表(BrowserModel TYPE_PICKER / DirectoryRepository)。
            // 此处为占位:渲染当前目录的文件列表占位项。
            Text(this.currentPath)
              .fontSize(13)
              .fontColor(AppColors.grey700)
              .margin({ left: AppDimens.default_margin, top: AppDimens.default_margin })
            List() {
              ForEach([0, 1, 2, 3, 4], (i: number) => {
                ListItem() {
                  Row() {
                    Image($r('app.media.ic_folder'))
                      .width(24)
                      .height(24)
                      .fillColor(AppColors.grey700)
                      .margin({ right: AppDimens.default_margin })
                    Text(`folder ${i}`)
                      .fontSize(AppDimens.audio_item_title_size)
                      .fontColor(AppColors.grey900)
                      .layoutWeight(1)
                  }
                  .width('100%')
                  .padding(AppDimens.default_margin)
                  .alignItems(VerticalAlign.Center)
                }
              }, (i: number) => `${i}`)
            }
            .width('100%')
            .layoutWeight(1)
            .margin({ top: AppDimens.default_margin })
          }
          .width('100%')
          .layoutWeight(1)
          .margin({ top: AppDimens.default_margin })
        }
        .width(300)
        .constraintSize({ minHeight: 320 })
        .backgroundColor(AppColors.grey200) // background_default_darker(Light)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.Center)
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      // 系统返回:根目录 → finish();非根目录 → browseUp()。TODO(契约): 子页 browseUp。
      NavController.pop();
      return true;
    })
  }
}
