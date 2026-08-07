import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const LOG_DOMAIN: number = 0x0001;
const LOG_TAG: string = 'VLC';

/**
 * 网络计费状态管理(对齐 Android NetworkConnectionManager):
 * - isMetered():查询当前默认网络是否按流量计费(能力集缺失 NET_CAPABILITY_NOT_METERED 即计费);
 * - start():监听网络能力变化(WiFi/流量切换等),变化时回调订阅者。
 */
export class NetworkConnectionManager {
  private static listeners: Array<(metered: boolean) => void> = [];
  private static listening: boolean = false;
  private static netConnection: connection.NetConnection | null = null;

  static onMeteredChange(listener: (metered: boolean) => void): void {
    if (!NetworkConnectionManager.listeners.includes(listener)) {
      NetworkConnectionManager.listeners.push(listener);
    }
  }

  static offMeteredChange(listener: (metered: boolean) => void): void {
    NetworkConnectionManager.listeners = NetworkConnectionManager.listeners.filter(
      (l: (metered: boolean) => void) => l !== listener);
  }

  /** 当前默认网络是否按流量计费;查询失败时保守返回 true。 */
  static async isMetered(): Promise<boolean> {
    try {
      const netHandle: connection.NetHandle = await connection.getDefaultNet();
      const caps: connection.NetCapabilities = await connection.getNetCapabilities(netHandle);
      const capsList: connection.NetCap[] | undefined = caps.networkCap;
      return capsList === undefined || !capsList.includes(connection.NetCap.NET_CAPABILITY_NOT_METERED);
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] isMetered query failed: %{public}s',
        (e as Error).message ?? String(e));
      return true;
    }
  }

  /** 启动网络能力变化监听(幂等;SDK 未提供 off,进程内只注册一次)。 */
  static start(): void {
    if (NetworkConnectionManager.listening) {
      return;
    }
    NetworkConnectionManager.listening = true;
    try {
      const netConnection: connection.NetConnection = connection.createNetConnection();
      NetworkConnectionManager.netConnection = netConnection;
      netConnection.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo) => {
        const capsList: connection.NetCap[] | undefined = info.netCap.networkCap;
        const metered: boolean = capsList === undefined ||
          !capsList.includes(connection.NetCap.NET_CAPABILITY_NOT_METERED);
        NetworkConnectionManager.notify(metered);
      });
      netConnection.register((err: BusinessError) => {
        if (err) {
          hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] netConnection register failed: %{public}s',
            err.message ?? String(err));
        }
      });
      hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] NetworkConnectionManager listening');
    } catch (e) {
      NetworkConnectionManager.listening = false;
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] netCapabilitiesChange listen failed: %{public}s',
        (e as Error).message ?? String(e));
    }
  }

  private static notify(metered: boolean): void {
    const copy: Array<(metered: boolean) => void> = NetworkConnectionManager.listeners.slice();
    for (const listener of copy) {
      try {
        listener(metered);
      } catch (e) {
        // 单个监听器异常不影响其它监听器
      }
    }
  }
}
