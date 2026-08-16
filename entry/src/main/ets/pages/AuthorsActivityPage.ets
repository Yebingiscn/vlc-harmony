import { NavController } from '../common/data/NavController';
import { RawData } from '../common/data/RawData';
import { AppColors, AppDimens } from '../common/constants/AppConstants';

/** 作者列表项(对应 authors.json 的 String,样例数据)。 */
export class AuthorEntry {
  name: string;

  constructor(name: string) {
    this.name = name;
  }
}

/**
 * AuthorsActivityPage —— 作者名列表(AuthorsActivity)。
 * 角色:pushed(从「关于」页 push 进入)。
 * 结构:AppBar(返回关闭图标 ic_close_up + ic_incognito + "VLC" + "Authors" 标题) + 作者 List(ic_author 24vp + 名字 16fp)。
 * 数据:rawfile authors.json(30 项 String 数组) → RawData.loadAuthors() 解析。
 */
@ObservedV2
export class AuthorsVM {
  @Trace authors: AuthorEntry[] = [];

  loadAuthors(): void {
    // 读 rawfile authors.json(30 项 String 数组),解析后映射为 AuthorEntry[]。
    RawData.loadAuthors().then((names: string[]) => {
      const list: AuthorEntry[] = [];
      for (const n of names) {
        list.push(new AuthorEntry(n));
      }
      this.authors = list;
    }).catch(() => {
      this.authors = [];
    });
  }
}

@ComponentV2
export struct AuthorsActivityPage {
  @Local vm: AuthorsVM = new AuthorsVM();

  aboutToAppear(): void {
    // 生命周期加载:launchWhenStarted → loadAuthors() 读 raw 资源 JSON 解析。
    this.vm.loadAuthors();
  }

  @Builder
  AuthorItem(name: string) {
    Row() {
      Image($r('app.media.ic_author'))
        .width(24)
        .height(24)
        .fillColor(AppColors.grey700)
        .margin({ left: AppDimens.kl_normal, top: AppDimens.default_margin, bottom: AppDimens.default_margin })
      Text(name)
        .fontSize(16)
        .fontColor(AppColors.grey900)
        .margin({ left: 32 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppColors.white)
  }

  build() {
    NavDestination() {
      Column() {
        // AppBar(toolbar.xml):height 56vp,background_actionbar=#FFFFFF,elevation=0
        Row() {
          Image($r('app.media.ic_close_up'))
            .width(24)
            .height(24)
            .fillColor(AppColors.grey700)
            .margin({ left: 12 })
            .onClick(() => NavController.pop())
          Image($r('app.media.ic_incognito'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
          Text('VLC')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.grey700)
            .margin({ left: AppDimens.kl_normal, right: AppDimens.kl_normal })
          Text($r('app.string.about'))
            .fontSize(20)
            .fontColor(AppColors.orange800)
            .margin({ left: AppDimens.default_margin })
        }
        .width('100%')
        .height(56)
        .backgroundColor(AppColors.white)
        .alignItems(VerticalAlign.Center)

        // 作者列表(纵向滚动,layoutWeight1,paddingBottom 54vp)
        List() {
          Repeat(this.vm.authors).each((itemRepeatItem: RepeatItem<AuthorEntry>) => {
            ListItem() {
              this.AuthorItem(itemRepeatItem.item.name)
            }
          }).key((item: AuthorEntry) => item.name).virtualScroll()
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ bottom: 54 })
        .scrollBar(BarState.Auto)
        .backgroundColor(AppColors.white)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.white)
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
