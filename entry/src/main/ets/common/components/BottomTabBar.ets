import { VLC_TABS, TabItem } from '../constants/AppConstants';

/**
 * BottomTabBar —— 底部 5 项导航栏(BottomNavigationView,menu=bottom_navigation)。
 * elevation=16dp,选中色 orange500#FF8800,未选中 grey。labelVisibilityMode=labeled。
 * ⚠️ Tab 内容状态保留用 visibility 切换(在宿主页),本组件仅画栏。
 */
@ComponentV2
export struct BottomTabBar {
  @Param currentTab: string = 'video';
  @Event onTabChange: (id: string) => void = () => {};

  @Builder
  tabItem(tab: TabItem) {
    Column() {
      Image(tab.icon)
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .fillColor(this.currentTab === tab.id ? '#FF8800' : $r('app.color.list_subtitle'))
      Text(tab.label)
        .fontSize(12)
        .fontColor(this.currentTab === tab.id ? '#FF8800' : $r('app.color.list_subtitle'))
        .margin({ top: 4 })
        .maxLines(1)
    }
    .layoutWeight(1)
    .padding({ top: 8, bottom: 8 })
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.onTabChange(tab.id))
  }

  build() {
    Row() {
      ForEach(VLC_TABS, (tab: TabItem) => {
        this.tabItem(tab)
      }, (tab: TabItem) => tab.id)
    }
    .width('100%')
    .backgroundColor($r('app.color.bottom_navigation_background'))
    .shadow({ radius: 16, color: '#33000000', offsetY: -2 })
    .padding({ bottom: 28 })
  }
}
