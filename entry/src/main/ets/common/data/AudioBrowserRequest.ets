/**
 * AudioBrowserRequest —— 跨页面"回到音频浏览器并定位到某艺人"请求(单例)。
 * 流程:AudioPlayerPage(转到艺人)写入请求 → NavController.popToMain() 弹回 Main →
 * MainPage.onShown 消费请求(切音频 tab + 派发 goToArtistName/Version)→ AudioBrowserPage
 * @Monitor 切到"艺术家"子 Tab 并滚动到对应歌手分组。
 */
export class AudioBrowserRequest {
  private static artistName: string = '';

  /** 写入待处理请求(转到艺人)。 */
  static requestGoToArtist(name: string): void {
    AudioBrowserRequest.artistName = name;
  }

  /** 取走并清空待处理请求;无请求返回 ''。 */
  static consumeArtist(): string {
    const name = AudioBrowserRequest.artistName;
    AudioBrowserRequest.artistName = '';
    return name;
  }
}
