import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { ShareOutService } from './ShareOutService';
import { image } from '@kit.ImageKit';
import { QrImageReport, QrRect } from './QrRules';
import { PixelMask } from './PixelMask';
import { GuardianApi } from './GuardianApi';

export class ProcessedImageService {
  static async maskLocal(context: common.UIAbilityContext, uri: string, report: QrImageReport): Promise<string> {
    if (report.status !== 'decoded' || report.codes.some((code): boolean => code.rect === undefined)) {
      throw new Error('没有全部二维码的可靠坐标，无法自动遮挡；请手动编辑原图。');
    }
    const data = await GuardianApi.readSelectedFile(uri, 10 * 1024 * 1024);
    const source = image.createImageSource(data);
    const packer = image.createImagePacker();
    let pixels: image.PixelMap | undefined = undefined;
    try {
      const info = await source.getImageInfo();
      if (info.size.width * info.size.height > 16000000) { throw new Error('本地遮挡限制1600万像素，请先缩小图片。'); }
      pixels = await source.createPixelMap({ editable: true, desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      const buffer = new ArrayBuffer(info.size.width * info.size.height * 4);
      await pixels.readPixelsToBuffer(buffer);
      const regions: QrRect[] = report.codes.map((code): QrRect => code.rect as QrRect);
      PixelMask.apply(new Uint8Array(buffer), info.size.width, info.size.height, regions);
      await pixels.writeBufferToPixels(buffer);
      const encoded = await packer.packing(pixels, { format: 'image/png', quality: 100 });
      return await ProcessedImageService.cache(context, encoded);
    } finally {
      if (pixels !== undefined) { await pixels.release(); }
      await packer.release();
      await source.release();
    }
  }

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

  static async saveBufferToGallery(
    context: common.UIAbilityContext,
    imageData: ArrayBuffer,
    title: string
  ): Promise<void> {
    const cachedUri = await ProcessedImageService.cache(context, imageData);
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      await helper.showAssetsCreationDialog(
        [cachedUri],
        [{
          title: title,
          fileNameExtension: 'png',
          photoType: photoAccessHelper.PhotoType.IMAGE
        }]
      );
    } catch (error) {
      const typedError = error as Error;
      throw new Error(typedError.message || '系统相册保存失败。');
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
    // Delegated so every gate channel opens the share panel the same way.
    await ShareOutService.shareFile(context, cachedUri, 'guardianhub-safe-image.png');
  }
}
