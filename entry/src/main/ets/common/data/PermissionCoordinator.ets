import { Settings } from './Settings';
import { MediaLibrary } from './MediaLibrary';
import { MediaWrapper } from '../models/MediaModels';
import { abilityAccessCtrl, bundleManager, common } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { AppContext } from './AppContext';

/**
 * PermissionCoordinator / StreamsCoordinator / StorageCoordinator
 *
 * 聚合文件:把 VLC 安卓端 8 个 Headless / Delegate(无 UI → 纯逻辑)Fragment 迁移成鸿蒙侧的
 * ArkTS 工具类骨架。无 UI、无 build(),纯逻辑。
 *
 * 覆盖的 8 个安卓 delegate:
 *   1. BaseHeadlessFragment         → 抽象基类语义(retainInstance/exit)+ PermissionViewmodel
 *                                     (CompletableDeferred<Boolean>)三态。落到本文件
 *                                     `PermissionViewModel`(activity 级共享状态管理者)。
 *   2. NotificationDelegate         → PermissionCoordinator.askNotificationPermission()
 *   3. OtgAccess                    → PermissionCoordinator.askOtgAccess()(OTG/USB 文档树选择)
 *   4. PinCodeDelegate              → PermissionCoordinator.askPinCode()(安全模式 PIN 校验)
 *   5. StoragePermissionsDelegate   → PermissionCoordinator.askStoragePermission()(读/写媒体权限)
 *   6. WriteExternalDelegate        → PermissionCoordinator.askWritePermission()(SD 卡写权限/目录树)
 *   7. StreamsFragmentDelegate      → StreamsCoordinator(rename/remove/append 网络流)
 *   8. StorageFragmentDelegate      → StorageCoordinator(addRoot/removeRoot/banFolder 媒体库根)
 *
 * 保真边界:系统权限/文档树选择器/媒体库根事件 API 在鸿蒙侧无 1:1 等价物,统一 try/catch
 * 返回 boolean 并标 TODO(契约)指明对应安卓 delegate 的真实系统交互,不臆造实现。
 *
 * 数据层:Settings(异步 get/put)、MediaLibrary(媒体库扫描/根)均为非 mock 真实实现。
 */

/** 安卓 `Permissions.showAppSettingsPage` 秒回检测阈值(StoragePermissionsDelegate)。 */
const PROMPT_INSTANT_THRESHOLD_MS: number = 300;

/** 鸿蒙权限名(对应安卓 Manifest.permission.*)。 */
const PERMISSION_NOTIFICATION: string = 'ohos.permission.NOTIFICATION';
const PERMISSION_READ_MEDIA: string = 'ohos.permission.READ_IMAGEVIDEO';
const PERMISSION_WRITE_MEDIA: string = 'ohos.permission.WRITE_IMAGEVIDEO';

/** checkAccessToken 参数所需权限名联合(系统 Permissions 类型的子集,不用 string 避免类型不符)。 */
type OhPermissionName =
  'ohos.permission.READ_AUDIO'
  | 'ohos.permission.READ_IMAGEVIDEO'
  | 'ohos.permission.READ_MEDIA'
  | 'ohos.permission.WRITE_IMAGEVIDEO';

/**
 * PermissionViewModel —— 安卓 `BaseHeadlessFragment.PermissionViewmodel`(activity 作用域,
 * `activityViewModels()`)的鸿蒙等价物。承载一次性授权结果 `CompletableDeferred<Boolean>` 的三态
 * (permissionPending / isCompleted),与 rationale 防重复弹标志。
 *
 * 鸿蒙无 Kotlin 协程 `CompletableDeferred`,用「可手动 resolve 的 Promise holder + 完成回调」模拟。
 */
@ObservedV2
export class PermissionViewModel {
  /** 是否已向用户展示过权限说明(rationale);授权流程完成回调里复位为 false。 */
  @Trace permissionRationaleShown: boolean = false;

  private resolveFn: ((value: boolean) => void) | null = null;
  private rejectFn: ((reason: string) => void) | null = null;
  private done: boolean = false;

  /**
   * setupDeferred —— 新建一个一次性授权结果 Promise,完成时清 permissionRationaleShown。
   * (源:`PermissionViewmodel.setupDeferred()` 新建 CompletableDeferred +
   *  `invokeOnCompletion { permissionRationaleShown = false }`)。
   */
  setupDeferred(): Promise<boolean> {
    this.done = false;
    this.permissionRationaleShown = false;
    return new Promise<boolean>((resolve: (v: boolean) => void, reject: (r: string) => void): void => {
      this.resolveFn = resolve;
      this.rejectFn = reject;
    });
  }

  /** permissionPending(派生):已初始化 && 未完成。 */
  get permissionPending(): boolean {
    return this.resolveFn !== null && !this.done;
  }

  /** isCompleted(派生):已初始化 && 已完成。 */
  get isCompleted(): boolean {
    return this.resolveFn !== null && this.done;
  }

  /**
   * complete —— 把授权结果 true/false resolve 进当前 Promise,并复位 rationale 标志。
   * (源:`complete(value)`:`if (::deferredGrant.isInitialized) deferredGrant.complete(value)`,
   *  complete 成功后触发 invokeOnCompletion → permissionRationaleShown = false)。
   */
  complete(value: boolean): void {
    if (this.resolveFn !== null && !this.done) {
      this.done = true;
      this.resolveFn(value);
      this.permissionRationaleShown = false;
    }
  }

  /** 释放(等价 BaseHeadlessFragment.exit():解除挂起 + 清引用)。 */
  cancel(reason: string): void {
    if (this.rejectFn !== null && !this.done) {
      this.done = true;
      this.rejectFn(reason);
      this.permissionRationaleShown = false;
    }
  }
}

/**
 * PermissionCoordinator —— 权限请求协调器(无 UI 工具类)。
 *
 * 把安卓端 4 个 headless delegate(NotificationDelegate / OtgAccess / PinCodeDelegate /
 * StoragePermissionsDelegate / WriteExternalDelegate)的「进入即弹系统授权框 → 回调 →
 * PermissionViewModel.complete → exit 自移除」流程塌缩为对外静态异步方法,统一 try/catch
 * 返回 boolean(true=已授权 / false=拒绝或失败)。
 */
export class PermissionCoordinator {
  /** activity 级共享状态(对齐 `activityViewModels<PermissionViewmodel>()` 单实例)。 */
  private static model: PermissionViewModel = new PermissionViewModel();

  static getModel(): PermissionViewModel {
    return PermissionCoordinator.model;
  }

  /**
   * askNotificationPermission —— 对应 NotificationDelegate。
   *
   * 安卓:onCreate(savedInstanceState==null)→ requestPermission():
   *   - checkSelfPermission(POST_NOTIFICATIONS) == GRANTED / shouldShowRationale / else
   *     三分支,最终 launch(POST_NOTIFICATIONS)→ onPermissionResult(isGranted) →
   *     model.deferredGrant.complete(isGranted) → exit()。
   *   - companion getNotificationPermission(): suspend 入口,await deferredGrant。
   *
   * 鸿蒙:shouldShowRequestPermissionRationale 无直接对等,塌缩为「未授权即请求」单一
   * 路径,用 @ohos.abilityAccessCtrl.requestPermissionsFromUser(ohos.permission.NOTIFICATION)。
   *
   * TODO(契约):系统权限 API —— 用 abilityAccessCtrl / 系统通知授权弹框的真实 API 替换占位。
   */
  static async askNotificationPermission(): Promise<boolean> {
    try {
      if (!AppContext.isReady()) {
        return false;
      }
      const ctx: common.UIAbilityContext = AppContext.get();
      // 鸿蒙通知授权走 notificationManager.requestEnableNotification(弹系统授权开关)。
      // resolve → 已开启通知;reject → 用户拒绝。返回 void,以成功/异常判定授权。
      await notificationManager.requestEnableNotification(ctx);
      return true;
    } catch (e) {
      // 用户拒绝或系统拒绝 → 视为未授权。
      return false;
    }
  }

  /**
   * askStoragePermission —— 对应 StoragePermissionsDelegate。
   *
   * 安卓:onCreate 决策树(分支 A:R+ 且 !canReadStorage/!hasAllAccess;
   *   分支 B:write==true)→ requestStorageAccess(write):
   *     - R+ 且 !askOnlyRead → ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION(intent);
   *     - 普通 → launch(READ/WRITE_EXTERNAL_STORAGE)。
   *   activityResultLauncher 回调:delay<300ms 秒回 → 跳应用设置页;否则按 askedPermission
   *   switch → storageAccessGranted.value = granted / model.complete(granted) → exit()。
   *   companion getStoragePermission(write, withDialog, onlyMedia): suspend,幂等 + pending 复用。
   *
   * 鸿蒙:READ/WRITE_EXTERNAL_STORAGE → READ_IMAGEVIDEO / WRITE_IMAGEVIDEO;MANAGE_EXTERNAL_STORAGE
   * 无等价(删该分支或请求文件类权限 + 设置引导)。300ms 秒回检测常量保留。
   *
   * TODO(契约):系统权限 API —— abilityAccessCtrl.requestPermissionsFromUser(文件/媒体权限)
   *   的真实 authResults;PermissionListDialog / showStoragePermissionDialog /
   *   showAppSettingsPage 等独立弹窗由调用页承载。
   */
  static async askStoragePermission(write: boolean = false,
    withDialog: boolean = true, onlyMedia: boolean = false): Promise<boolean> {
    try {
      if (!AppContext.isReady()) {
        return false;
      }
      const ctx: common.UIAbilityContext = AppContext.get();
      const mgr: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      // requestPermissionsFromUser 弹系统授权框;返回 authResults(0=已授予)。
      const res = await mgr.requestPermissionsFromUser(ctx,
        write ? ['ohos.permission.WRITE_IMAGEVIDEO'] : ['ohos.permission.READ_IMAGEVIDEO']);
      void withDialog;
      void onlyMedia;
      void PERMISSION_READ_MEDIA;
      void PERMISSION_WRITE_MEDIA;
      void PROMPT_INSTANT_THRESHOLD_MS;
      let granted: boolean = false;
      if (res && res.authResults && res.authResults.length > 0) {
        granted = res.authResults[0] === 0; // 0 = PERMISSION_GRANTED
      }
      // 记录「已请求过权限」标志(源 StoragePermissionsDelegate getStoragePermission 步骤 2)。
      await Settings.put(Settings.INITIAL_PERMISSION_ASKED, true);
      return granted;
    } catch (e) {
      return false;
    }
  }

  /**
   * askWritePermission —— 对应 WriteExternalDelegate(SD 卡写权限)。
   *
   * 安卓:showDialog() 弹「SD 卡写权限」AlertDialog(标题/正文/OK + Show me 帮助向导);
   *   OK → launchDocumentTreePicker(ACTION_OPEN_DOCUMENT_TREE, EXTRA_INITIAL_URI=storage,
   *   requestCode=42);onActivityResult(42):
   *     - RESULT_OK → Settings.putSingle("tree_uri_$storage", treeUri.toString());
   *       takePersistableUriPermission(treeUri, READ|WRITE) → model.complete(true) → exit();
   *     - 旧权限存在 → releasePersistableUriPermission → model.complete(false) → exit();
   *     - 取消 → model.complete(false) → exit()。
   *   companion needsWritePermission(uri) / askForExtWrite(activity, uri, cb)。
   *
   * 鸿蒙:ACTION_OPEN_DOCUMENT_TREE / DocumentFile / 持久化 URI 权限无直接等价。
   *
   * TODO(契约):系统权限 API —— @ohos.file.picker.DocumentSelectPicker /
   *   @ohos.file.fs + abilityAccessCtrl 的目录树授权 API;KEY_STORAGE_PATH="VLC/storage_path"
   *   与动态 key "tree_uri_$storage" 的真实持久化(Settings.put)。
   */
  static async askWritePermission(storagePath: string | null = null): Promise<boolean> {
    try {
      // TODO(契约): WriteExternalDelegate —— model.setupDeferred() → 弹 CustomDialog(主对话框
      //   + 帮助向导 img_tips_sdcard 320x420 / objectFit=Contain)→ OK 拉起 DocumentSelectPicker
      //   (requestCode=42)→ 回调里写 Settings.put(`tree_uri_${storagePath}`, treeUri) 并 complete。
      const _storagePath: string | null = storagePath;
      void _storagePath;
      // 占位:返回 false(未授权 / 取消)。
      return false;
    } catch (e) {
      return false;
    }
  }

  /**
   * askOtgAccess —— 对应 OtgAccess(OTG/USB 文档树选择)。
   *
   * 安卓:onCreate(savedInstanceState==null)弹 AlertDialog(标题 "Allow OTG access" /
   *   正文 "Please select your OTG drive to allow access to VLC." / 单个 OK 按钮,可取消);
   *   onOk → startActivity(ACTION_OPEN_DOCUMENT_TREE, requestCode=85);onActivityResult(85):
   *     intent!=null → OtgAccess.otgRoot.value = intent.data(全局 companion StateFlow);
   *   catch ActivityNotFoundException → exit();onCancel → exit();末尾无条件 exit()。
   *
   * 鸿蒙:@ohos.file.picker 的文档目录选择器;返回用户选择的 OTG 根 Uri(写到全局
   *   `otgRoot`),失败/取消返回 null/false。
   *
   * TODO(契约):系统权限 API —— 鸿蒙 OTG/USB 存储 picker 的精确 API 与返回 Uri 形态需下游核实。
   */
  static otgRoot: string | null = null;

  static async askOtgAccess(): Promise<boolean> {
    try {
      // TODO(契约): OtgAccess —— 弹 CustomDialog(标题/正文/OK)→ onOk 调
      //   @ohos.file.picker.DocumentViewPicker(文件夹选择)→ 选中写入 PermissionCoordinator.otgRoot。
      //   catch (无可用选择器) / onCancel → 返回 false。占位:返回 false(未授权)。
      return false;
    } catch (e) {
      return false;
    }
  }

  /**
   * askPinCode —— 对应 PinCodeDelegate(安全模式 PIN 校验)。
   *
   * 安卓:onCreate 拉起 PinCodeActivity(reason=UNLOCK);pinCodeResult 回调:
   *   model.complete(resultCode == RESULT_OK);若 RESULT_OK && unlock → pinUnlocked.postValue(true);
   *   exit();(activity as? DialogActivity)?.finish()。
   *   companion checkPIN(unlock): 短路 `if (!Settings.safeMode) return true`;否则
   *   setupDeferred + add delegate → await deferredGrant。
   *
   * 鸿蒙:真实 PIN 输入 UI 由对端 PinCodeActivity 对应页承载(本协调器不画);此处提供
   *   checkPIN(unlock) 语义的短路 + await 骨架。
   *
   * TODO(契约):对端 PIN 页 NavPathStack 路由名;Settings.safeMode 派生值
   *   (KEY_SAFE_MODE + KEY_SAFE_MODE_PIN 非空判定);pinUnlocked 全局可观察通道。
   */
  static async askPinCode(unlock: boolean = false): Promise<boolean> {
    try {
      // 源 Settings.safeMode = KEY_SAFE_MODE(true) && KEY_SAFE_MODE_PIN 非空。
      const safeOn: boolean = await Settings.getBoolean(Settings.KEY_SAFE_MODE, false);
      if (!safeOn) {
        // 未开启安全模式 → 短路放行(源 checkPIN 第一行)。
        return true;
      }
      const pin: string = await Settings.getString(Settings.KEY_SAFE_MODE_PIN, '');
      if (pin.length === 0) {
        // 开关开但未设 PIN → 实际 safeMode=false → 放行。
        return true;
      }
      // 安全模式开启且已设 PIN → 真实校验需对端 PinCodeActivity 路由(本协调器无 UI)。
      // TODO(契约): 对端 PIN 页路由(PinCode UNLOCK)+ pinUnlocked 可观察通道。
      void unlock;
      return false;
    } catch (e) {
      return false;
    }
  }

  /* ─────────────────── 权限状态查询(供 PermissionsDialog 等 UI 使用) ─────────────────── */

  /** 查询当前应用是否已授予指定权限(AtManager.checkAccessToken,0=PERMISSION_GRANTED)。 */
  private static async checkGranted(permission: OhPermissionName): Promise<boolean> {
    try {
      const mgr: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const bundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const tokenId: number = bundleInfo.appInfo.accessTokenId;
      const status: number = await mgr.checkAccessToken(tokenId, permission);
      return status === 0;
    } catch (e) {
      return false;
    }
  }

  /** 通知权限是否已开启(对应安卓 canSendNotifications)。 */
  static async hasNotificationPermission(): Promise<boolean> {
    try {
      return await notificationManager.isNotificationEnabled();
    } catch (e) {
      return false;
    }
  }

  /** 音频读取权限是否已授予(对应安卓 hasAudioPermission)。 */
  static async hasAudioPermission(): Promise<boolean> {
    return PermissionCoordinator.checkGranted('ohos.permission.READ_AUDIO');
  }

  /** 视频读取权限是否已授予(对应安卓 hasVideoPermission)。 */
  static async hasVideoPermission(): Promise<boolean> {
    return PermissionCoordinator.checkGranted('ohos.permission.READ_IMAGEVIDEO');
  }

  /**
   * 完整文件访问(对应安卓 hasAllAccess / MANAGE_EXTERNAL_STORAGE)。
   * 鸿蒙无公开的「管理全部文件」运行时权限,以受限权限 ohos.permission.READ_MEDIA 判定,
   * 普通应用默认未授予;UI 层点击该项时跳系统设置页引导(见 openAppSettingsPage)。
   */
  static async hasAllAccess(): Promise<boolean> {
    return PermissionCoordinator.checkGranted('ohos.permission.READ_MEDIA');
  }

  /** 请求媒体读取权限(READ_IMAGEVIDEO + READ_AUDIO,对应安卓 READ_MEDIA_VIDEO + READ_MEDIA_AUDIO)。 */
  static async requestMediaPermission(): Promise<boolean> {
    try {
      if (!AppContext.isReady()) {
        return false;
      }
      const ctx: common.UIAbilityContext = AppContext.get();
      const mgr: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const res = await mgr.requestPermissionsFromUser(ctx,
        ['ohos.permission.READ_IMAGEVIDEO', 'ohos.permission.READ_AUDIO']);
      // authResults 元素 0=PERMISSION_GRANTED;全部授予才算成功。
      if (res && res.authResults && res.authResults.length > 0) {
        for (let i = 0; i < res.authResults.length; i++) {
          if (res.authResults[i] !== 0) {
            return false;
          }
        }
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /**
   * 打开系统「应用信息 → 权限管理」页(对应安卓 showAppSettingsPage /
   * ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)。用户在系统页自行开关各项权限。
   */
  static async openAppSettingsPage(): Promise<void> {
    try {
      if (!AppContext.isReady()) {
        return;
      }
      const ctx: common.UIAbilityContext = AppContext.get();
      const bundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      await ctx.startAbility({
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'application_info_entry',
        parameters: { pushParams: { bundleName: bundleInfo.name } },
      });
    } catch (e) {
      // 无法拉起设置页时静默失败,不阻塞 UI。
    }
  }
}

/**
 * StreamsCoordinator —— 网络流列表项事件路由 + 上下文菜单动作(无 UI)。
 *
 * 对应安卓 StreamsFragmentDelegate(MRLPanelFragment 的流列表 Delegate):
 *   - 列表 item 单击 → playMedia(mw)(RTSP 进播放页 / 其余 openMedia);
 *   - 长按/溢出 → showContext(position) → ContextSheet(6 动作):
 *     CTX_RENAME / CTX_APPEND / CTX_ADD_TO_PLAYLIST / CTX_COPY / CTX_DELETE / CTX_ADD_SHORTCUT;
 *   - rename/remove/append 操作 StreamsModel.dataset(MediaWrapper[],网络历史流)。
 *
 * 此处只暴露 StreamsCoordinator 对媒体库样例流的 rename/remove/append 骨架;列表 UI、
 * ContextSheet、playMedia 的播放跳转由调用页/共享组件承载。
 */
export class StreamsCoordinator {
  /** 网络历史流列表(对应 StreamsModel.dataset;鸿蒙侧进程内 @Trace list)。 */
  private static streams: MediaWrapper[] = [];

  static getStreams(): MediaWrapper[] {
    return StreamsCoordinator.streams;
  }

  static setStreams(list: MediaWrapper[]): void {
    StreamsCoordinator.streams = list;
  }

  /**
   * renameStream —— 对应 onCtxAction(CTX_RENAME) → renameStream(position) → RenameDialog
   *   确认回调 renameStream(media, name) → StreamsModel.rename:
   *     IO 线程 media.rename(name) 后 refresh()。
   *
   * TODO(契约):MediaWrapper.rename 的真实持久化(medialibrary 域);refresh() 重扫。
   */
  static async renameStream(media: MediaWrapper, name: string): Promise<boolean> {
    try {
      const list: MediaWrapper[] = StreamsCoordinator.streams;
      for (let i = 0; i < list.length; i++) {
        if (list[i].id === media.id) {
          const copy: MediaWrapper[] = list.slice();
          const renamed: MediaWrapper = copy[i];
          renamed.displayName = name;
          renamed.title = name;
          // 整体 reassign(@Trace 数组改必须 concat/整体替换,禁 push/splice)
          StreamsCoordinator.streams = copy;
          break;
        }
      }
      // TODO(契约): StreamsModel.rename —— IO 线程 media.rename(name) 后 refresh()(重扫媒体库)。
      return true;
    } catch (e) {
      return false;
    }
  }

  /**
   * removeStream —— 对应 onCtxAction(CTX_DELETE):
   *   viewModel.deletingMedia = media → snackerWithCancel(确认 viewModel.delete() /
   *   撤销清空 + refresh())→ 外层 refresh()。
   *   StreamsModel.delete → context.getFromMl { removeExternalMedia(media.id) }(medialibrary 域)。
   *
   * TODO(契约):medialibrary.removeExternalMedia 的真实 schema/返回值。
   */
  static async removeStream(media: MediaWrapper): Promise<boolean> {
    try {
      const filtered: MediaWrapper[] = StreamsCoordinator.streams.filter(
        (m: MediaWrapper): boolean => m.id !== media.id);
      StreamsCoordinator.streams = filtered; // 整体 reassign
      // TODO(契约): StreamsModel.delete —— medialibrary.removeExternalMedia(media.id) + refresh()。
      return true;
    } catch (e) {
      return false;
    }
  }

  /**
   * appendStream —— 对应 onCtxAction(CTX_APPEND) → MediaUtils.appendMedia(context, media):
   *   追加该流到当前播放列表。
   *
   * TODO(契约):MediaUtils.appendMedia 内部契约(PlaybackService.append)。
   */
  static async appendStream(media: MediaWrapper): Promise<boolean> {
    try {
      const copy: MediaWrapper[] = StreamsCoordinator.streams.concat(media);
      StreamsCoordinator.streams = copy; // 整体 reassign
      // TODO(契约): MediaUtils.appendMedia —— 追加到 PlaybackService 当前播放列表。
      return true;
    } catch (e) {
      return false;
    }
  }
}

/**
 * StorageCoordinator —— 媒体库存储根目录增删 + 封禁(无 UI)。
 *
 * 对应安卓 StorageFragmentDelegate(StorageBrowserFragment 的逻辑委托):
 *   - checkBoxAction(view, mrl) 三分支:无读权限拦截 / Onboarding 预选 / 正常存储浏览;
 *   - checked → MedialibraryUtils.addDir(mrl)(启 MediaParsingService ACTION_DISCOVER + EXTRA_PATH)
 *     + Settings.getInt(KEY_MEDIALIBRARY_SCAN, -1)!=ML_SCAN_ON 则 putSingle(ML_SCAN_ON) +
 *     processEvent(禁用勾选框);
 *   - unchecked → MedialibraryUtils.removeDir(mrl)(IO removeFolder) + processEvent;
 *   - onRootBanned/onRootUnbanned → bannedFolderCallback(entryPoint, banned);
 *   - onRootRemoved/onDiscoveryCompleted → 恢复勾选框可点 + adapters.notifyDataSetChanged()。
 *
 * 此处暴露 addRoot/removeRoot/banFolder 操作 MediaLibrary 样例 + Settings 扫描模式开关的骨架;
 * 三态勾选框 UI、媒体库根事件回调注册(addRootsEventsCb/removeRootsCallback)由宿主页承载。
 */
export class StorageCoordinator {
  /** ML_SCAN_ON 常量值(Settings.KEY_MEDIALIBRARY_SCAN 的「开启扫描」值)。 */
  private static readonly ML_SCAN_ON: number = 0;

  /**
   * addRoot —— 对应 checkBoxAction 分支 C-checked:
   *   MedialibraryUtils.addDir(mrl)(启扫描服务)+ 若 KEY_MEDIALIBRARY_SCAN != ML_SCAN_ON 则
   *   putSingle(ML_SCAN_ON)。
   *
   * TODO(契约):MedialibraryUtils.addDir / MediaParsingService 启动(ACTION_DISCOVER + EXTRA_PATH)。
   */
  static async addRoot(mrl: string): Promise<boolean> {
    try {
      // 读当前扫描模式,非 ON 则开启(源 checkBoxAction C2)
      const current: number = await Settings.getInt(Settings.KEY_MEDIALIBRARY_SCAN, -1);
      if (current !== StorageCoordinator.ML_SCAN_ON) {
        await Settings.put(Settings.KEY_MEDIALIBRARY_SCAN, StorageCoordinator.ML_SCAN_ON);
      }
      // TODO(契约): StorageFragmentDelegate 分支 C1 —— MedialibraryUtils.addDir(mrl, appCtx):
      //   启动 MediaParsingService(ACTION_DISCOVER + EXTRA_PATH=mrl)前台扫描该目录;
      //   鸿蒙侧映射到 MediaLibrary.scan()(非 mock)。
      await MediaLibrary.scan();
      void mrl;
      return true;
    } catch (e) {
      return false;
    }
  }

  /**
   * removeRoot —— 对应 checkBoxAction 分支 C-unchecked:
   *   MedialibraryUtils.removeDir(mrl)(IO 线程 Medialibrary.removeFolder(mrl))。
   *
   * TODO(契约):medialibrary.removeFolder 的真实 API;勾选框「处理中」态(processEvent)。
   */
  static async removeRoot(mrl: string): Promise<boolean> {
    try {
      // TODO(契约): StorageFragmentDelegate 分支 C1' —— MedialibraryUtils.removeDir(mrl):
      //   IO 线程 Medialibrary.getInstance().removeFolder(mrl)。
      void mrl;
      return true;
    } catch (e) {
      return false;
    }
  }

  /**
   * banFolder —— 对应 onRootBanned/onRootUnbanned:
   *   bannedFolderCallback?.invoke(entryPoint, banned)(主线程投递回宿主)。
   *
   * TODO(契约):媒体库 banFolder/unbanFolder API;回调通过宿主注入的 bannedFolderCallback 通知。
   */
  static async banFolder(entryPoint: string, banned: boolean): Promise<boolean> {
    try {
      // TODO(契约): StorageFragmentDelegate onRootBanned/onRootUnbanned ——
      //   medialibrary.banFolder(entryPoint) / unbanFolder(entryPoint),
      //   主线程投递 bannedFolderCallback?.invoke(entryPoint, banned) 回宿主。
      void entryPoint;
      void banned;
      return true;
    } catch (e) {
      return false;
    }
  }
}
