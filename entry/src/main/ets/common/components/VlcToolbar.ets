/**
 * VlcToolbar —— MaterialToolbar(actionBarSize≈56vp,elevation=0)。
 * 返回箭头(非根页显示)+ VLC 标题(20fp Bold colorPrimary)+ 可选隐身图标。
 */
@ComponentV2
export struct VlcToolbar {
  @Param title: Resource | string = $r('app.string.app_name');
  @Param showBack: boolean = false;
  @Param showIncognito: boolean = false;
  @Event onBack: () => void = () => {
  };
  @Event onSearch: () => void = () => {
  };
  @Param showSearch: boolean = false;
  @Param showMore: boolean = false;
  @Param currentTab: string = 'video';
  @Param incognitoMode: boolean = false;
  @Local moreOpen: boolean = false;
  @Event onMoreSettings: () => void = () => {
  };
  @Event onMoreIncognito: () => void = () => {
  };
  @Event onMoreDisplayAsList: () => void = () => {
  };
  @Event onMoreBrowseNetwork: () => void = () => {
  };
  @Event onMoreFavoriteServer: () => void = () => {
  };
  @Event onMoreRefresh: () => void = () => {
  };
  @Event onResumePlayback: () => void = () => {
  };
  @Event onAudioDisplaySettings: () => void = () => {
  };

  build() {
    Row() {
      if (this.showBack) {
        Image($r('app.media.ic_arrow_back'))
          .width(28)
          .height(28)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.list_title'))
          .margin({ left: 4 })
          .onClick(() => this.onBack())
      }
      if (!this.showBack) {
        // 主屏工具栏:无痕模式开启时显示 ic_incognito,否则显示 VLC 交通锥 logo。
        Image(this.incognitoMode ? $r('app.media.ic_incognito') : $r('app.media.ic_default_cone'))
          .width(30)
          .height(30)
          .objectFit(ImageFit.Contain)
          .margin({ left: 12 })
      }
      Text(this.title)
        .fontSize(20)
        .fontColor($r('app.color.list_title'))
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)
        .margin({ left: 8 })
        .maxLines(1)
      if (this.showIncognito) {
        Image($r('app.media.ic_incognito'))
          .width(32)
          .height(32)
          .objectFit(ImageFit.Contain)
          .margin({ right: 8 })
      }
      if (this.showSearch) {
        Image($r('app.media.ic_search'))
          .width(28)
          .height(28)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.list_title'))
          .margin({ right: 8 })
          .onClick(() => this.onSearch())
      }
      // 视频 tab:继续播放按钮
      if (this.currentTab === 'video') {
        Image($r('app.media.ic_resume_playback'))
          .width(28)
          .height(28)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.list_title'))
          .margin({ right: 8 })
          .onClick(() => this.onResumePlayback())
      }
      // 音频 tab:显示设置按钮
      if (this.currentTab === 'audio') {
        Image($r('app.media.ic_display_settings'))
          .width(28)
          .height(28)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.list_title'))
          .margin({ right: 8 })
          .onClick(() => this.onAudioDisplaySettings())
      }
      if (this.showMore) {
        Image($r('app.media.ic_more'))
          .width(28)
          .height(28)
          .objectFit(ImageFit.Contain)
          .margin({ right: 4 })
          .onClick(() => this.moreOpen = true)
          .bindMenu(this.moreOpen, this.moreMenu(), {
            placement: Placement.BottomRight,
            showInSubWindow: true,
            backgroundColor: '#FFFFFF',
            onDisappear: () => this.moreOpen = false,
          })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 4, right: 4, top: 32, bottom: 8 })
    .backgroundColor($r('app.color.background_actionbar'))
    .alignItems(VerticalAlign.Center)
  }

  /** 右上角 … 菜单:内容随当前 tab 变化。视频 tab 显示设置;浏览 tab 显示无痕/以列表形式显示/浏览网络/收藏服务器/刷新;音频/播放列表/更多 tab 仅无痕/刷新。 */
  @Builder
  moreMenu() {
    if (this.currentTab === 'video') {
      this.videoMoreMenu()
    } else if (this.currentTab === 'browse') {
      this.browseMoreMenu()
    } else {
      this.simpleMoreMenu()
    }
  }

  @Builder
  videoMoreMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.menu_display_settings'),
        startIcon: $r('app.media.ic_display_settings'),
      })
        .onClick(() => {
          this.moreOpen = false;
          this.onMoreSettings();
        })
      MenuItem({
        content: $r('app.string.incognito_mode'),
        startIcon: $r('app.media.ic_incognito'),
      })
        .onClick(() => {
          this.moreOpen = false;
          this.onMoreIncognito();
        })
      MenuItem({
        content: $r('app.string.menu_refresh'),
        startIcon: $r('app.media.ic_refresh'),
      })
        .onClick(() => {
          this.moreOpen = false;
          this.onMoreRefresh();
        })
    }
  }

  @Builder
  browseMoreMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.incognito_mode'),
        startIcon: $r('app.media.ic_incognito'),
      })
        .onClick(() => {
          this.moreOpen = false;
          this.onMoreIncognito();
        })
      MenuItem({
        content: $r('app.string.menu_display_as_list'),
        startIcon: $r('app.media.ic_view_list'),
      })
        .onClick(() => {
          this.moreOpen = false;
          this.onMoreDisplayAsList();
        })
      MenuItem({
        content: $r('app.string.menu_browse_network'),
        startIcon: $r('app.media.ic_network_big'),
      })
        .onClick(() => {
          this.moreOpen = false;
          this.onMoreBrowseNetwork();
        })
      MenuItem({
        content: $r('app.string.menu_favorite_server'),
        startIcon: $r('app.media.ic_favorite'),
      })
        .onClick(() => {
          this.moreOpen = false;
          this.onMoreFavoriteServer();
        })
      MenuItem({
        content: $r('app.string.menu_refresh'),
        startIcon: $r('app.media.ic_refresh'),
      })
        .onClick(() => {
          this.moreOpen = false;
          this.onMoreRefresh();
        })
    }
  }

  @Builder
  simpleMoreMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.incognito_mode'),
        startIcon: $r('app.media.ic_incognito'),
      })
        .onClick(() => {
          this.moreOpen = false;
          this.onMoreIncognito();
        })
      MenuItem({
        content: $r('app.string.menu_refresh'),
        startIcon: $r('app.media.ic_refresh'),
      })
        .onClick(() => {
          this.moreOpen = false;
          this.onMoreRefresh();
        })
    }
  }
}
