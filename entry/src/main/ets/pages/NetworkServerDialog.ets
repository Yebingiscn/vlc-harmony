import { AppColors } from '../common/constants/AppConstants';

/**
 * OutlinedInput -- 带焦点态边框变色的 outlined 输入框。
 */
@ComponentV2
struct OutlinedInput {
  @Param text: string = '';
  @Param placeholder: ResourceStr = '';
  @Local focused: boolean = false;
  @Event onChange: (v: string) => void = () => {
  };

  build() {
    TextInput({ text: this.text, placeholder: this.placeholder })
      .type(InputType.Normal)
      .backgroundColor(Color.Transparent)
      .border({ width: 1, color: this.focused ? AppColors.orange500 : AppColors.grey900, radius: 4 })
      .fontSize(16)
      .fontColor(AppColors.grey900)
      .placeholderColor(AppColors.grey400)
      .width('100%')
      .height(52)
      .padding({ left: 12, right: 12 })
      .onFocus(() => this.focused = true)
      .onBlur(() => this.focused = false)
      .onChange((v: string) => this.onChange(v))
  }
}

/**
 * NetworkServerDialog -- 添加/编辑网络服务器 BottomSheet。
 * 顶部 URL 预览 + 协议橙色圆形下拉 + 端口下划线(焦点态变色) + outlined 输入框(焦点态橙色边框) + 取消/确定按钮。
 */
@ComponentV2
export struct NetworkServerDialog {
  readonly protocols: string[] = ['FTP', 'FTPS', 'FTPES', 'SFTP', 'SMB', 'NFS'];
  @Local protocolIndex: number = 0;
  @Local protocolMenuOpen: boolean = false;
  @Local address: string = '';
  @Local port: string = '';
  @Local folder: string = '';
  @Local username: string = '';
  @Local servername: string = '';
  @Local portEnabled: boolean = true;
  @Local userEnabled: boolean = true;
  @Local url: string = '';
  @Local portFocused: boolean = false;

  get canSave(): boolean {
    return this.address.length > 0;
  }

  get addressHint(): Resource {
    const p: string = this.protocols[this.protocolIndex];
    return p === 'SMB' || p === 'NFS' ? $r('app.string.server_share_hint') : $r('app.string.server_domain_hint');
  }

  @Event onClose: () => void = () => {
  };

  getDefaultPort(p: string): string {
    if (p === 'FTP') {
      return '21';
    }
    if (p === 'FTPS') {
      return '990';
    }
    if (p === 'FTPES') {
      return '21';
    }
    if (p === 'SFTP') {
      return '22';
    }
    return '';
  }

  aboutToAppear(): void {
    this.port = this.getDefaultPort(this.protocols[this.protocolIndex]);
    this.updateUrl();
  }

  onProtocolSelected(idx: number): void {
    this.protocolIndex = idx;
    const p: string = this.protocols[idx];
    this.portEnabled = true;
    this.userEnabled = true;
    this.port = this.getDefaultPort(p);
    if (p === 'SMB') {
      this.userEnabled = false;
    } else if (p === 'NFS') {
      this.userEnabled = false;
      this.portEnabled = false;
    }
    this.updateUrl();
  }

  updateUrl(): void {
    let sb: string = this.protocols[this.protocolIndex].toLowerCase() + '://';
    if (this.userEnabled && this.username.length > 0) {
      sb = sb + this.username + '@';
    }
    sb = sb + this.address;
    if (this.portEnabled && this.port.length > 0) {
      const std: boolean = this.port === '21' || this.port === '22' || this.port === '80' || this.port === '443';
      if (!std) {
        sb = sb + ':' + this.port;
      }
    }
    if (this.folder.length > 0) {
      const f: string = this.folder.startsWith('/') ? this.folder : '/' + this.folder;
      sb = sb + f;
    }
    this.url = sb;
  }

  @Builder
  protocolMenu() {
    Menu() {
      ForEach(this.protocols, (p: string, idx: number) => {
        MenuItem({ content: p })
          .onClick(() => {
            this.protocolMenuOpen = false;
            this.onProtocolSelected(idx);
          })
      }, (p: string) => p)
    }
  }

  build() {
    Scroll() {
      Column() {
        // URL 预览
        Text(this.url)
          .fontSize(16)
          .fontColor(AppColors.grey900)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 16, bottom: 16 })

        Divider().color(AppColors.grey200).strokeWidth(1).width('100%')

        // 协议 + Port 行
        Row() {
          // 协议文本 + 橙色按钮(整体可点击拉起菜单)
          Row() {
            Text(this.protocols[this.protocolIndex])
              .fontSize(16)
              .fontColor(AppColors.grey900)
              .padding({ left: 16, right: 16 })

            Column() {
              Image($r('app.media.ic_collapse_arrow'))
                .width(24).height(24)
                .fillColor('#FFFFFF')
            }
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor(AppColors.orange500)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          .onClick(() => this.protocolMenuOpen = true)
          .bindMenu(this.protocolMenuOpen, this.protocolMenu(), {
            placement: Placement.BottomLeft,
            onDisappear: () => this.protocolMenuOpen = false,
          })

          Blank().layoutWeight(1)

          if (this.portEnabled) {
            Text('端口:')
              .fontSize(14)
              .fontColor(AppColors.grey600)
          }
          if (this.portEnabled) {
            TextInput({ text: this.port })
              .type(InputType.Number)
              .backgroundColor(Color.Transparent)
              .borderRadius(0)
              .padding(0)
              .border({ width: { bottom: 1 }, color: this.portFocused ? AppColors.orange500 : AppColors.grey900 })
              .fontSize(16)
              .fontColor(AppColors.grey900)
              .width(48)
              .textAlign(TextAlign.End)
              .onFocus(() => this.portFocused = true)
              .onBlur(() => this.portFocused = false)
              .onChange((v: string) => {
                this.port = v;
                this.updateUrl();
              })
          }
        }
        .width('100%')
        .height(56)
        .alignItems(VerticalAlign.Center)
        .margin({ top: 8 })

        // 表单输入框
        Column({ space: 16 }) {
          OutlinedInput({
            text: this.address,
            placeholder: this.addressHint,
            onChange: (v: string) => {
              this.address = v;
              this.updateUrl();
            },
          })

          if (this.userEnabled) {
            OutlinedInput({
              text: this.username,
              placeholder: $r('app.string.server_username_hint'),
              onChange: (v: string) => {
                this.username = v;
                this.updateUrl();
              },
            })
          }

          OutlinedInput({
            text: this.folder,
            placeholder: $r('app.string.server_folder_hint'),
            onChange: (v: string) => {
              this.folder = v;
              this.updateUrl();
            },
          })

          OutlinedInput({
            text: this.servername,
            placeholder: $r('app.string.server_servername_hint'),
            onChange: () => {
            },
          })
        }
        .width('100%')
        .margin({ top: 24 })

        // 按钮行
        Row() {
          Text($r('app.string.cancel'))
            .fontSize(16)
            .fontColor(AppColors.orange500)
            .onClick(() => this.onClose())

          Text($r('app.string.ok'))
            .fontSize(16)
            .fontColor(this.canSave ? AppColors.grey500 : AppColors.grey400)
            .margin({ left: 40 })
            .enabled(this.canSave)
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: 32, bottom: 8 })
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 16 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.PARENT_FIRST,
    })
  }
}
