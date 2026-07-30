import { NavController } from '../common/data/NavController';
import { OpenLink } from '../common/data/OpenLink';
import { AppColors, AppDimens } from '../common/constants/AppConstants';
import { promptAction } from '@kit.ArkUI';

/** 反馈类型条目(对应 feedback_entries 数组)。 */
export class FeedbackTypeEntry {
  key: string;
  label: ResourceStr;
  constructor(key: string, label: ResourceStr) {
    this.key = key;
    this.label = label;
  }
}

/**
 * FeedbackActivityPage —— 反馈页(FeedbackActivity)。
 * 角色:pushed(从关于/设置 push 进入)。
 * 结构:AppBar(ic_close_up 关闭 + "Send feedback" 标题) + 可滚动区(4 卡片:Forum/Doc/Email/Rate)。
 *   Email 卡可展开表单(反馈类型下拉 + 主题/消息输入 + include_logs/include_medialib 复选框 + Send)。
 */
@ObservedV2
export class FeedbackVM {
  @Trace emailFormVisible: boolean = false;
  @Trace emailWarningVisible: boolean = false;
  @Trace rateCardVisible: boolean = true; // installSource != null
  @Trace showIncludes: boolean = false;
  @Trace feedbackTypeIndex: number = 0;
  @Trace includeLogs: boolean = false;
  @Trace includeMedialibrary: boolean = false;
  @Trace sendEnabled: boolean = true;
  @Trace subject: string = '';
  @Trace message: string = '';

  readonly feedbackEntries: FeedbackTypeEntry[] = [
    new FeedbackTypeEntry('get_help', $r('app.string.get_help')),
    new FeedbackTypeEntry('send_feedback_request', $r('app.string.send_feedback')),
    new FeedbackTypeEntry('report_a_bug', $r('app.string.report_a_bug')),
    new FeedbackTypeEntry('report_a_crash', 'Report a crash'),
  ];
  readonly forumUrl: string = 'https://forum.videolan.org/viewforum.php?f=35';
  readonly docUrl: string = 'https://docs.videolan.me/vlc-user/android/';

  onEmailCardClick(): void {
    // TODO(契约): isMailClientPresent()(Intent.ACTION_SENDTO resolveActivity)。
    // 有邮件客户端 → 展开表单;无 → 显示无邮件警告。
    this.emailWarningVisible = false;
    this.emailFormVisible = !this.emailFormVisible;
    this.updateFormIncludesVisibility();
  }

  onFeedbackTypeChange(idx: number): void {
    this.feedbackTypeIndex = idx;
    this.updateFormIncludesVisibility();
  }

  updateFormIncludesVisibility(): void {
    if (!this.emailFormVisible) {
      this.showIncludes = false;
      return;
    }
    const pos = this.feedbackTypeIndex;
    this.showIncludes = pos !== 1;
    if (pos === 2 || pos === 3) {
      this.includeMedialibrary = true;
      this.includeLogs = true;
    } else {
      this.includeMedialibrary = false;
      this.includeLogs = false;
    }
  }

  /** 拼装 mailto: URL(subject/body 经 encodeURIComponent)。 */
  mailtoUrl(): string {
    const subject = this.subject.length > 0 ? this.subject : 'VLC for Android feedback';
    const body = this.message;
    return `mailto:android@videolan.org?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
  }
}

@ComponentV2
export struct FeedbackActivityPage {
  @Local vm: FeedbackVM = new FeedbackVM();

  @Builder
  CardTitle(text: Resource) {
    Text(text)
      .fontSize(AppDimens.audio_item_title_size)
      .fontColor(AppColors.black)
      .maxLines(2)
  }

  @Builder
  CardSubtitle(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor(AppColors.grey600)
  }

  @Builder
  InfoCard(icon: Resource, title: Resource, subtitle: string, onClick: () => void) {
    Column() {
      Row() {
        Image(icon)
          .width(24)
          .height(24)
          .fillColor(AppColors.black)
          .margin({ right: AppDimens.kl_normal })
        Column() {
          this.CardTitle(title)
          this.CardSubtitle(subtitle)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: AppDimens.kl_normal, top: AppDimens.default_margin, bottom: AppDimens.default_margin, right: AppDimens.kl_normal })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .margin({ left: AppDimens.kl_normal, right: AppDimens.kl_normal, top: AppDimens.kl_normal })
    .border({ width: 1, color: AppColors.grey700 })
    .borderRadius(4)
    .backgroundColor(AppColors.white)
    .onClick(() => onClick())
  }

  @Builder
  WarningRow(text: Resource) {
    Row() {
      Image($r('app.media.ic_information'))
        .width(24)
        .height(24)
        .fillColor(AppColors.black)
        .margin({ right: AppDimens.kl_normal })
      Text(text)
        .fontSize(12)
        .fontColor(AppColors.black)
        .layoutWeight(1)
    }
    .width('100%')
    .padding(AppDimens.default_margin)
    .border({ width: 2, color: AppColors.orange_800_transparent_20 })
    .borderRadius(8)
    .margin({ left: AppDimens.kl_normal, right: AppDimens.kl_normal, top: AppDimens.default_margin })
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  EmailForm() {
    Column() {
      // 分隔线
      Divider().width('100%').height(1).color(AppColors.grey700).margin({ top: AppDimens.kl_normal })

      if (this.vm.emailWarningVisible) {
        // 无邮件客户端警告块
        Row() {
          Image($r('app.media.ic_warning_small'))
            .width(24)
            .height(24)
            .fillColor(AppColors.orange800)
            .padding(AppDimens.default_margin)
          Text($r('app.string.feedback_email_warning'))
            .fontSize(AppDimens.audio_item_title_size)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.orange800)
            .margin({ left: AppDimens.default_margin })
        }
        .width('100%')
        .margin({ top: AppDimens.default_margin })
        .alignItems(VerticalAlign.Center)
        Text($r('app.string.feedback_email_warning_explanation'))
          .fontSize(AppDimens.audio_item_title_size)
          .fontColor(AppColors.black)
          .margin({ left: AppDimens.kl_normal, right: AppDimens.kl_normal, top: 24, bottom: AppDimens.kl_normal })
        Row() {
          Button($r('app.string.feedback_email_warning_try_anyway'))
            .type(ButtonType.Normal)
            .backgroundColor(AppColors.transparent)
            .fontColor(AppColors.grey700)
            .margin({ right: AppDimens.default_margin })
            .onClick(() => {
              this.vm.emailWarningVisible = false;
              this.vm.emailFormVisible = true;
              this.vm.updateFormIncludesVisibility();
            })
          Button($r('app.string.feedback_email_warning_remote_action'))
            .type(ButtonType.Normal)
            .backgroundColor(AppColors.transparent)
            .fontColor(AppColors.orange800)
            .onClick(() => {
              // TODO(契约): PreferencesActivity.launchWithPref("enable_remote_access") / TV_PREFERENCE_ACTIVITY 不在本页。
              promptAction.showToast({ message: 'Open remote access settings' });
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: AppDimens.kl_normal })
      }

      // 反馈类型下拉
      Select(this.vm.feedbackEntries.map((e: FeedbackTypeEntry) => {
        const opt: SelectOption = { value: e.label };
        return opt;
      }))
        .selected(this.vm.feedbackTypeIndex)
        .value(this.vm.feedbackEntries[this.vm.feedbackTypeIndex].label)
        .width('100%')
        .margin({ left: AppDimens.kl_normal, right: AppDimens.kl_normal, top: AppDimens.default_margin })
        .onSelect((idx: number) => this.vm.onFeedbackTypeChange(idx))

      // 主题输入
      TextInput({ placeholder: $r('app.string.subject') })
        .width('100%')
        .margin({ left: AppDimens.kl_normal, right: AppDimens.kl_normal, top: AppDimens.default_margin })
        .onChange((v: string) => { this.vm.subject = v; })

      // 消息输入
      TextArea({ placeholder: $r('app.string.body') })
        .width('100%')
        .margin({ left: AppDimens.kl_normal, right: AppDimens.kl_normal, top: AppDimens.default_margin })
        .onChange((v: string) => { this.vm.message = v; })

      // include_logs 复选框
      if (this.vm.showIncludes) {
        Row() {
          Checkbox()
            .select(this.vm.includeLogs)
            .onChange((c: boolean) => { this.vm.includeLogs = c; })
          Text($r('app.string.include_logs'))
            .fontSize(AppDimens.audio_item_title_size)
            .margin({ left: AppDimens.default_margin })
        }
        .width('100%')
        .margin({ left: AppDimens.kl_normal, right: AppDimens.default_margin, top: AppDimens.default_margin })
        .alignItems(VerticalAlign.Center)
        if (this.vm.includeLogs) {
          this.WarningRow($r('app.string.logs_warning'))
        }
        // include_medialibrary 复选框
        Row() {
          Checkbox()
            .select(this.vm.includeMedialibrary)
            .onChange((c: boolean) => { this.vm.includeMedialibrary = c; })
          Text($r('app.string.include_medialib'))
            .fontSize(AppDimens.audio_item_title_size)
            .margin({ left: AppDimens.default_margin })
        }
        .width('100%')
        .margin({ left: AppDimens.kl_normal, right: AppDimens.default_margin, top: AppDimens.default_margin })
        .alignItems(VerticalAlign.Center)
        if (this.vm.includeMedialibrary) {
          this.WarningRow($r('app.string.ml_database_warning'))
        }
      }

      // Send 按钮
      Row() {
        Button($r('app.string.send'))
          .type(ButtonType.Normal)
          .backgroundColor(AppColors.transparent)
          .fontColor(AppColors.orange800)
          .enabled(this.vm.sendEnabled)
          .onClick(() => {
            // 拉起邮件应用(mailto:)。失败(无邮件客户端/拉起异常)→ 回退 toast 提示。
            // TODO(契约): 更深的 ACTION_SEND_MULTIPLE(带 logs/medialib 附件)由 FeedbackUtil.sendEmail 移植,此处仅 mailto。
            const ok = OpenLink.open(this.vm.mailtoUrl());
            if (!ok) {
              promptAction.showToast({ message: $r('app.string.developing') });
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ left: AppDimens.kl_normal })
      .margin({ top: AppDimens.kl_normal })
    }
    .width('100%')
  }

  @Builder
  EmailCard() {
    Column() {
      Row() {
        Image($r('app.media.ic_email'))
          .width(24)
          .height(24)
          .fillColor(AppColors.black)
          .margin({ right: AppDimens.kl_normal })
        Column() {
          this.CardTitle($r('app.string.email_support'))
          this.CardSubtitle('Send feedback • Get some help • Report a bug')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: AppDimens.kl_normal, top: AppDimens.default_margin, right: AppDimens.kl_normal })
      .alignItems(VerticalAlign.Center)

      if (this.vm.emailFormVisible) {
        this.EmailForm()
      }
    }
    .width('100%')
    .margin({ left: AppDimens.kl_normal, right: AppDimens.kl_normal, top: AppDimens.kl_normal })
    .padding({ bottom: AppDimens.default_margin })
    .border({ width: 1, color: AppColors.grey700 })
    .borderRadius(4)
    .backgroundColor(AppColors.white)
    .onClick(() => this.vm.onEmailCardClick())
  }

  build() {
    NavDestination() {
      Column() {
        // AppBar:height 56vp,background #FFFFFF
        Row() {
          Image($r('app.media.ic_close_up'))
            .width(24)
            .height(24)
            .fillColor(AppColors.grey700)
            .margin({ left: AppDimens.default_margin })
            .onClick(() => NavController.pop())
          Text($r('app.string.send_feedback'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.grey700)
            .margin({ left: AppDimens.default_margin })
        }
        .width('100%')
        .height(56)
        .backgroundColor(AppColors.white)
        .alignItems(VerticalAlign.Center)

        // 主体可滚动区
        Scroll() {
          Column() {
            // 卡片1:Feedback forum
            this.InfoCard($r('app.media.ic_forum'), $r('app.string.feedback_forum'),
              'Send feedback • Get some help', () => {
                // TODO(契约): openLinkIfPossible(forumUrl)
                promptAction.showToast({ message: this.vm.forumUrl });
              })
            // 卡片2:Read the documentation
            this.InfoCard($r('app.media.ic_documentation'), $r('app.string.read_doc'),
              'Get some help', () => {
                promptAction.showToast({ message: this.vm.docUrl });
              })
            // 卡片3:Email support(可展开表单)
            this.EmailCard()
            // 卡片4:Rate the app(installSource 非 null 时显示)
            if (this.vm.rateCardVisible) {
              this.InfoCard($r('app.media.ic_rate'), $r('app.string.rate_us'),
                'Google Play', () => {
                  // TODO(契约): openLinkIfPossible(installSource.first)
                  promptAction.showToast({ message: 'Rate the app' });
                })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: 54 })
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(AppColors.white)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.white)
      .alignItems(HorizontalAlign.Start)
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
