import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';

export class ProcessedImageService {
  static async cache(context: common.UIAbilityContext, imageData: ArrayBuffer): Promise<string> {
    const fileName = `guardianhub-safe-${Date.now()}.png`;
    const filePath = `${context.cacheDir}/${fileName}`;
    let targetFd = -1;
    try {
      const targetFile = await fileIo.open(
        filePath,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      targetFd = targetFile.fd;
      const written = await fileIo.write(targetFd, imageData);
      if (written !== imageData.byteLength) {
        throw new Error('处理图写入不完整。');
      }
      return fileUri.getUriFromPath(filePath);
    } catch (error) {
      const typedError = error as Error;
      throw new Error(typedError.message || '无法缓存处理后的图片。');
    } finally {
      if (targetFd >= 0) {
        try {
          await fileIo.close(targetFd);
        } catch (_) {
        }
      }
    }
  }

  static async saveToGallery(context: common.UIAbilityContext, cachedUri: string): Promise<void> {
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      await helper.showAssetsCreationDialog(
        [cachedUri],
        [{
          title: 'GuardianHub安全图片',
          fileNameExtension: 'png',
          photoType: photoAccessHelper.PhotoType.IMAGE
        }]
      );
    } catch (error) {
      const typedError = error as Error;
      throw new Error(typedError.message || '系统相册保存失败。');
    }
  }

  static async share(context: common.UIAbilityContext, cachedUri: string): Promise<void> {
    try {
      const sharedData = new systemShare.SharedData({
        utd: 'general.png',
        uri: cachedUri,
        title: 'GuardianHub 安全图片',
        description: '已完成隐私脱敏，请在分享前再次复核。'
      });
      const controller = new systemShare.ShareController(sharedData);
      await controller.show(context, {});
    } catch (error) {
      const typedError = error as Error;
      throw new Error(typedError.message || '系统分享面板打开失败。');
    }
  }
}
