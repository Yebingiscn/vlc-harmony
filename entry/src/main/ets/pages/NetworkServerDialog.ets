/**
 * NetworkServerDialog -- 添加/编辑网络服务器半模态(鸿蒙风格)。
 * 标题 + URL 预览 + 协议 Select + 端口输入 + 表单输入框 + [取消][确定] 按钮。
 * 主题色橙色保留;其余配色用 sys.color 系统色,自动适配深浅模式。
 */
@ComponentV2
export struct NetworkServerDialog {
  @Param title: ResourceStr = '添加服务器';
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

  build() {
    Scroll() {
      Column({ space: 20 }) {
        // 标题
        Text(this.title)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')

        // URL 预览
        Column() {
          Text('地址预览')
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
          Text(this.url)
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 协议 + 端口
        Row() {
          Text('协议')
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
          Select(this.protocols.map((v: string): SelectOption => ({ value: v })))
            .selected(this.protocolIndex)
            .value(this.protocols[this.protocolIndex])
            .fontColor($r('sys.color.font_primary'))
            .margin({ left: 8 })
            .layoutWeight(1)
            .onSelect((idx: number) => this.onProtocolSelected(idx))

          if (this.portEnabled) {
            Text('端口')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .margin({ left: 16 })
            TextInput({ text: this.port })
              .type(InputType.Number)
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
              .width(72)
              .onChange((v: string) => {
                this.port = v;
                this.updateUrl();
              })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // 表单输入框
        TextInput({ placeholder: this.addressHint })
          .type(InputType.Normal)
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
          .placeholderColor($r('sys.color.font_secondary'))
          .width('100%')
          .onChange((v: string) => {
            this.address = v;
            this.updateUrl();
          })

        if (this.userEnabled) {
          TextInput({ placeholder: $r('app.string.server_username_hint') })
            .type(InputType.Normal)
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
            .placeholderColor($r('sys.color.font_secondary'))
            .width('100%')
            .onChange((v: string) => {
              this.username = v;
              this.updateUrl();
            })
        }

        TextInput({ placeholder: $r('app.string.server_folder_hint') })
          .type(InputType.Normal)
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
          .placeholderColor($r('sys.color.font_secondary'))
          .width('100%')
          .onChange((v: string) => {
            this.folder = v;
            this.updateUrl();
          })

        TextInput({ placeholder: $r('app.string.server_servername_hint') })
          .type(InputType.Normal)
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
          .placeholderColor($r('sys.color.font_secondary'))
          .width('100%')
          .onChange(() => {
          })

        // 按钮行
        Row() {
          Text($r('app.string.cancel'))
            .fontSize(16)
            .fontColor($r('sys.color.font_secondary'))
            .padding({
              left: 12,
              right: 12,
              top: 8,
              bottom: 8
            })
            .onClick(() => this.onClose())

          Button($r('app.string.ok'))
            .type(ButtonType.Capsule)
            .backgroundColor($r('app.color.orange500'))
            .fontColor($r('app.color.colorOnPrimary'))
            .fontSize(16)
            .height(40)
            .padding({ left: 24, right: 24 })
            .margin({ left: 16 })
            .enabled(this.canSave)
            .onClick(() => this.onClose())
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({
        left: 24,
        right: 24,
        top: 8,
        bottom: 24
      })
      .alignItems(HorizontalAlign.Start)
    }
    .clip(false)
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.PARENT_FIRST,
    })
  }
}
