import { AppColors } from '../common/constants/AppConstants';

/**
 * NetworkServerDialog —— 添加/编辑网络服务器 BottomSheet。
 * URL 预览行 + 分隔线 + 协议 Select(FTP/FTPS/FTPES/SFTP/SMB/NFS)+ Port 输入(右)
 * + 地址/用户名/文件夹/显示名 4 个 OutlinedBox.Dense 输入框 + [Cancel][OK] 文字按钮(Save 默认禁用,address 空时)。
 * SMB→用户名隐藏+hint 切 share_hint;NFS→用户名+端口隐藏。SFTP 用户名聚焦时 folder=/home/+username。
 * TODO(契约): saveServer() → browserFavRepository.addNetworkFavItem(uri,name,null)(编辑模式先 deleteBrowserFav)后 dismiss;
 *   onDismiss → MainActivity.forceRefresh();updateUrl() 拼接协议小写://[用户名@]地址[:端口][/路径]。
 */
@ComponentV2
export struct NetworkServerDialog {
  @Event onClose: () => void = () => {};

  readonly protocols: string[] = ['FTP', 'FTPS', 'FTPES', 'SFTP', 'SMB', 'NFS'];
  @Local protocolIndex: number = 0;
  @Local address: string = '';
  @Local port: string = '';
  @Local folder: string = '';
  @Local username: string = '';
  @Local servername: string = '';
  @Local portEnabled: boolean = true;
  @Local userEnabled: boolean = true;
  @Local url: string = '';

  get canSave(): boolean {
    return this.address.length > 0;
  }

  get addressHint(): Resource {
    const p: string = this.protocols[this.protocolIndex];
    return p === 'SMB' || p === 'NFS' ? $r('app.string.server_share_hint') : $r('app.string.server_domain_hint');
  }

  getDefaultPort(p: string): string {
    if (p === 'FTP') return '21';
    if (p === 'FTPS') return '990';
    if (p === 'FTPES') return '21';
    if (p === 'SFTP') return '22';
    return '';
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

  build() {
    Scroll() {
      Column() {
        // URL 预览
        Text(this.url || 'ftp://foo@127.0.0.1:21/path')
          .fontSize(16)
          .fontColor('#FFFFFF')
          .width('100%')
          .padding(4)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 16, right: 16, top: 8 })

        Divider().color(AppColors.grey800).strokeWidth(1).width('100%').margin({ top: 8 })

        // 协议 + Port 行
        Row() {
          Select(this.protocols.map((v: string): SelectOption => ({ value: v })))
            .selected(this.protocolIndex)
            .value(this.protocols[this.protocolIndex])
            .margin({ left: 16 })
            .onSelect((idx: number) => this.onProtocolSelected(idx))
          if (this.portEnabled) {
            Text($r('app.string.server_port')).fontSize(14).fontColor('#FFFFFF').margin({ left: 8 })
          }
          if (this.portEnabled) {
            TextInput({ text: this.port })
              .type(InputType.Number)
              .width(80)
              .margin({ right: 16 })
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor(AppColors.grey850)
              .onChange((v: string) => { this.port = v; this.updateUrl(); })
          }
          Blank().layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ top: 8 })

        // 地址
        TextInput({ text: this.address, placeholder: this.addressHint })
          .width('100%')
          .margin({ left: 16, right: 16, top: 8 })
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor(AppColors.grey850)
          .onChange((v: string) => { this.address = v; this.updateUrl(); })

        // 用户名(SMB/NFS 隐藏)
        if (this.userEnabled) {
          TextInput({ text: this.username, placeholder: $r('app.string.server_username_hint') })
            .width('100%')
            .margin({ left: 16, right: 16, top: 8 })
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor(AppColors.grey850)
            .onChange((v: string) => { this.username = v; this.updateUrl(); })
        }

        // 文件夹
        TextInput({ text: this.folder, placeholder: $r('app.string.server_folder_hint') })
          .width('100%')
          .margin({ left: 16, right: 16, top: 8 })
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor(AppColors.grey850)
          .onChange((v: string) => { this.folder = v; this.updateUrl(); })

        // 显示名
        TextInput({ text: this.servername, placeholder: $r('app.string.server_servername_hint') })
          .width('100%')
          .margin({ left: 16, right: 16, top: 8 })
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor(AppColors.grey850)

        // 按钮行
        Row() {
          Button($r('app.string.cancel'))
            .type(ButtonType.Normal)
            .fontColor(AppColors.orange500)
            .backgroundColor(AppColors.transparent)
            .margin({ right: 16 })
            .onClick(() => this.onClose())
          Button($r('app.string.ok'))
            .type(ButtonType.Normal)
            .fontColor(AppColors.orange500)
            .backgroundColor(AppColors.transparent)
            .enabled(this.canSave)
            .onClick(() => {
              // TODO(契约): saveServer() → addNetworkFavItem / deleteBrowserFav 后 dismiss + forceRefresh。
              this.onClose();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: 24, bottom: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
