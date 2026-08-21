import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { fileIo as fs, fileShare } from '@kit.CoreFileKit';
import { AppContext } from './AppContext';

/**
 * 文件选择器 URI 的长期访问管理。
 *
 * 普通导入只保存源文件 URI，不复制媒体本体；FILE_ACCESS_PERSIST 仅用于在应用
 * 重启后恢复用户通过 DocumentViewPicker 主动授予的文件访问权。
 */
export class DocumentPermission {
  private static readonly FILE_ACCESS_PERSIST: Permissions = 'ohos.permission.FILE_ACCESS_PERSIST';
  private static runtimePermissionReady: boolean = false;
  private static readonly activeUris: Set<string> = new Set<string>();

  private static async ensureRuntimePermission(): Promise<boolean> {
    if (DocumentPermission.runtimePermissionReady) {
      return true;
    }
    try {
      const manager = abilityAccessCtrl.createAtManager();
      const result = await manager.requestPermissionsFromUser(
        AppContext.get(), [DocumentPermission.FILE_ACCESS_PERSIST]);
      DocumentPermission.runtimePermissionReady = result.authResults.length > 0 && result.authResults[0] === 0;
      return DocumentPermission.runtimePermissionReady;
    } catch (e) {
      return false;
    }
  }

  static async persist(uri: string): Promise<boolean> {
    if (uri.length === 0 || DocumentPermission.activeUris.has(uri)) {
      return uri.length > 0;
    }
    if (!(await DocumentPermission.ensureRuntimePermission())) {
      return false;
    }
    try {
      const policies: fileShare.PolicyInfo[] = [{
        uri: uri,
        operationMode: fileShare.OperationMode.READ_MODE,
      }];
      await fileShare.persistPermission(policies);
      DocumentPermission.activeUris.add(uri);
      return true;
    } catch (e) {
      return false;
    }
  }

  static async activate(uri: string): Promise<boolean> {
    if (uri.length === 0) {
      return false;
    }
    if (DocumentPermission.activeUris.has(uri)) {
      return true;
    }
    if (DocumentPermission.canOpen(uri)) {
      DocumentPermission.activeUris.add(uri);
      return true;
    }
    try {
      const policies: fileShare.PolicyInfo[] = [{
        uri: uri,
        operationMode: fileShare.OperationMode.READ_MODE,
      }];
      const persisted = await fileShare.checkPersistentPermission(policies);
      if (persisted.length > 0 && persisted[0]) {
        await fileShare.activatePermission(policies);
      }
      if (DocumentPermission.canOpen(uri)) {
        DocumentPermission.activeUris.add(uri);
        return true;
      }
    } catch (e) {
      return false;
    }
    return false;
  }

  private static canOpen(uri: string): boolean {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      return true;
    } catch (e) {
      return false;
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (e) {
          // 文件可读性已经确认，关闭失败不影响判断。
        }
      }
    }
  }
}
