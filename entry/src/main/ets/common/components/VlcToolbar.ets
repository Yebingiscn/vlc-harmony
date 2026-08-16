/**
 * VlcToolbar —— MaterialToolbar(actionBarSize≈56vp,elevation=0)。
 * 返回箭头(非根页显示)+ VLC 标题(20fp Bold colorPrimary)+ 可选隐身图标。
 */
@ComponentV2
export struct VlcToolbar {
  @Param title: Resource | string = $r('app.string.app_name');
  /** 偏好设置二级页在 Android 中使用橙色标题，其余工具栏沿用默认颜色。 */
  @Param titleColor: ResourceColor | string = '';
  @Param showBack: boolean = false;
  @Param showIncognito: boolean = false;
  @Param showSearch: boolean = false;
  @Param searchMode: boolean = false;
  @Param searchQuery: string = '';
  @Param selectionMode: boolean = false;
  @Param selectionCount: number = 0;
  @Param showMore: boolean = false;
  @Param currentTab: string = 'video';
  @Param incognitoMode: boolean = false;
  @Local moreOpen: boolean = false;
  @Local input: string = '';

  @Event onBack: () => void = () => {
  };

  @Event onSearch: () => void = () => {
  };

  @Event onSearchQueryChange: (q: string) => void = () => {
  };

  @Event onSearchBack: () => void = () => {
  };

  @Event onSelectionBack: () => void = () => {
  };

  @Event onSelectionPlay: () => void = () => {
  };

  @Event onSelectionFav: () => void = () => {
  };

  @Event onSelectionDelete: () => void = () => {
  };

  @Monitor('searchMode')
  onSearchModeChange(): void {
    if (!this.searchMode) {
      this.input = '';
    }
  }

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
    Column() {
      if (this.searchMode) {
        // 搜索模式:更高的栏位,给 TextInput 留出足够高度
        Row() {
          Image($r('app.media.ic_arrow_back'))
            .width(28)
            .height(28)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.list_title'))
            .margin({ left: 4 })
            .onClick(() => this.onSearchBack())
          Row() {
            TextInput({ text: this.input, placeholder: $r('app.string.search_in_current_list') })
              .fontSize(16)
              .fontColor($r('app.color.list_title'))
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(4)
              .border({ width: 0.5, color: $r('app.color.card_border') })
              .height(40)
              .defaultFocus(true)
              .layoutWeight(1)
              .onChange((v: string) => {
                this.input = v;
                this.onSearchQueryChange(v);
              })
            if (this.input.length > 0) {
              Image($r('app.media.ic_close_small'))
                .width(20)
                .height(20)
                .fillColor($r('app.color.list_subtitle'))
                .margin({ left: 8 })
                .onClick(() => {
                  this.input = '';
                  this.onSearchQueryChange('');
                })
            }
          }
          .layoutWeight(1)
          .margin({ left: 12, right: 4 })
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height(92)
        .padding({
          left: 4,
          right: 4,
          top: 38,
          bottom: 4
        })
        .backgroundColor($r('app.color.background_actionbar'))
      } else if (this.selectionMode) {
        // 选择模式:返回箭头 + 选中数 + 播放/收藏/删除
        Row() {
          Image($r('app.media.ic_arrow_back'))
            .width(28)
            .height(28)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.list_title'))
            .margin({ left: 4 })
            .onClick(() => this.onSelectionBack())
          Text(`选中 ${this.selectionCount} 项`)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.list_title'))
            .layoutWeight(1)
            .textAlign(TextAlign.Start)
            .margin({ left: 8 })
          Image($r('app.media.ic_play_player'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.list_title'))
            .margin({ right: 16 })
            .onClick(() => this.onSelectionPlay())
          Image($r('app.media.ic_fav_add'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.list_title'))
            .margin({ right: 16 })
            .onClick(() => this.onSelectionFav())
          Image($r('app.media.ic_delete'))
            .width(24)
            .height(24)
            .fillColor('#F44336')
            .margin({ right: 12 })
            .onClick(() => this.onSelectionDelete())
        }
        .width('100%')
        .height(92)
        .padding({
          left: 4,
          right: 4,
          top: 38,
          bottom: 4
        })
        .backgroundColor($r('app.color.background_actionbar'))
      } else {
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
              .width(28)
              .height(28)
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
            SymbolGlyph($r('sys.symbol.dot_grid_1x2'))
              .fontSize(28)
              .fontColor([$r('sys.color.icon_primary')])
              .margin({ right: 4 })
              .onClick(() => this.moreOpen = true)
              .bindMenu(this.moreOpen, this.moreMenu(), {
                placement: Placement.BottomRight,
                showInSubWindow: true,
                backgroundColor: $r('app.color.bottom_sheet_background'),
                onDisappear: () => this.moreOpen = false,
              })
          }
        }
        .width('100%')
        .height(92)
        .padding({
          left: 4,
          right: 4,
          top: 38,
          bottom: 4
        })
        .backgroundColor($r('app.color.background_actionbar'))
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.background_actionbar'))
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
