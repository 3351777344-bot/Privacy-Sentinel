/**
 * Share-path gate — outbound leg.
 *
 * The share gate receives content from the system share panel, inspects it and
 * then lets the user decide whether to continue sharing. `ProcessedImageService`
 * only ever carried a sanitized image, so this service generalises that last leg
 * to every gate channel:
 *
 *   link  -> the URL itself, as a hyperlink
 *   code  -> the inspected snippet, as source code
 *   doc   -> the original file, or a sandbox copy when the received URI cannot
 *            be re-shared (a share that arrives as a content:// URI is often not
 *            writable by the receiving app).
 *
 * Nothing here inspects content; it only hands the decision back to the user.
 */

import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';

const SHARE_UTD_TEXT: string = 'general.plain-text';
const SHARE_UTD_HYPERLINK: string = 'general.hyperlink';
const SHARE_UTD_SOURCE_CODE: string = 'general.source-code';
const SHARE_UTD_FILE: string = 'general.file';

/** Map a file name to a concrete UTD so receivers keep the original type. */
function utdForFileName(fileName: string): string {
  const lower: string = fileName.toLowerCase();
  if (lower.endsWith('.pdf')) {
    return 'com.adobe.pdf';
  }
  if (lower.endsWith('.docx')) {
    return 'org.openxmlformats.wordprocessingml.document';
  }
  if (lower.endsWith('.doc')) {
    return 'com.microsoft.word.doc';
  }
  if (lower.endsWith('.png')) {
    return 'general.png';
  }
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'general.jpeg';
  }
  if (lower.endsWith('.webp')) {
    return 'general.webp';
  }
  if (lower.endsWith('.md')) {
    return 'general.markdown';
  }
  if (lower.endsWith('.zip')) {
    return 'general.zip';
  }
  if (lower.endsWith('.txt')) {
    return 'general.plain-text';
  }
  return SHARE_UTD_FILE;
}

function errorMessage(error: Object, fallback: string): string {
  const typedError = error as Error;
  return typedError.message ? typedError.message : fallback;
}

export class ShareOutService {
  /**
   * Open the system share panel with one record.
   *
   * `utd` is required by SharedData, and at least one of `content` / `uri` must
   * be supplied.
   */
  private static async present(
    context: common.UIAbilityContext,
    utd: string,
    content: string,
    uri: string,
    title: string,
    description: string
  ): Promise<void> {
    let record: systemShare.SharedRecord;
    if (uri.length > 0) {
      record = {
        utd: utd,
        uri: uri,
        title: title,
        description: description
      };
    } else {
      record = {
        utd: utd,
        content: content,
        title: title,
        description: description
      };
    }
    try {
      const sharedData = new systemShare.SharedData(record);
      const controller = new systemShare.ShareController(sharedData);
      await controller.show(context, {});
    } catch (error) {
      throw new Error(errorMessage(error, '系统分享面板打开失败。'));
    }
  }

  /** Continue sharing an inspected URL. */
  static async shareLink(context: common.UIAbilityContext, url: string): Promise<void> {
    await ShareOutService.present(
      context,
      SHARE_UTD_HYPERLINK,
      url,
      '',
      'GuardianHub 链接安检',
      '已通过静态安全检查，访问前请再次确认来源。'
    );
  }

  /** Continue sharing an inspected code snippet. */
  static async shareCode(context: common.UIAbilityContext, code: string): Promise<void> {
    await ShareOutService.present(
      context,
      SHARE_UTD_SOURCE_CODE,
      code,
      '',
      'GuardianHub 代码安检',
      '已完成端侧静态扫描，请在接收方使用前复核。'
    );
  }

  /** Continue sharing an inspected file, copying it into the sandbox if needed. */
  static async shareFile(
    context: common.UIAbilityContext,
    sourceUri: string,
    fileName: string
  ): Promise<void> {
    const utd: string = utdForFileName(fileName);
    try {
      await ShareOutService.present(
        context,
        utd,
        '',
        sourceUri,
        fileName,
        '已通过 GuardianHub 安检，请在打开前再次复核。'
      );
      return;
    } catch (error) {
      // The received URI is often not re-shareable; fall through to a copy.
    }

    let cachedUri = '';
    try {
      const buffer: ArrayBuffer = await ShareOutService.readFile(context, sourceUri);
      cachedUri = await ShareOutService.cacheCopy(context, buffer, fileName);
    } catch (error) {
      throw new Error(errorMessage(error, '无法读取该文件，暂时不能继续分享。'));
    }
    await ShareOutService.present(
      context,
      utd,
      '',
      cachedUri,
      fileName,
      '已通过 GuardianHub 安检，请在打开前再次复核。'
    );
  }

  /**
   * Copy a buffer into the app cache with the original extension.
   * Public so callers can reuse the same bounded copy path.
   */
  static async cacheCopy(
    context: common.UIAbilityContext,
    data: ArrayBuffer,
    fileName: string
  ): Promise<string> {
    const safeName: string = ShareOutService.safeFileName(fileName);
    const stamp: string = `${Date.now()}`;
    const targetPath: string = `${context.cacheDir}/guardianhub-share-${stamp}-${safeName}`;
    let targetFd = -1;
    try {
      const targetFile = await fileIo.open(
        targetPath,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      targetFd = targetFile.fd;
      const written = await fileIo.write(targetFd, data);
      if (written !== data.byteLength) {
        throw new Error('文件写入不完整。');
      }
      return fileUri.getUriFromPath(targetPath);
    } catch (error) {
      throw new Error(errorMessage(error, '无法缓存该文件。'));
    } finally {
      if (targetFd >= 0) {
        try {
          await fileIo.close(targetFd);
        } catch (_) {
        }
      }
    }
  }

  /** Keep the extension (so the UTD stays meaningful) but drop path separators. */
  private static safeFileName(fileName: string): string {
    const base: string = fileName.substring(fileName.lastIndexOf('/') + 1);
    const cleaned: string = base.replace(/[\\:*?"<>|]/g, '_').trim();
    return cleaned.length > 0 ? cleaned : 'guardianhub-share.bin';
  }

  /** Bounded read of a received URI, mirroring GuardianApi.readSelectedFile. */
  private static async readFile(
    context: common.UIAbilityContext,
    uri: string
  ): Promise<ArrayBuffer> {
    const maxBytes: number = 12 * 1024 * 1024;
    let sourceFd = -1;
    try {
      const sourceFile = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      sourceFd = sourceFile.fd;
      const fileStat = await fileIo.stat(sourceFd);
      if (fileStat.size <= 0) {
        throw new Error('文件为空。');
      }
      if (fileStat.size > maxBytes) {
        throw new Error('文件超过 12 MB 限制。');
      }
      const output = new ArrayBuffer(fileStat.size);
      const outputView = new Uint8Array(output);
      let totalRead = 0;
      while (totalRead < fileStat.size) {
        const chunkSize = Math.min(1024 * 1024, fileStat.size - totalRead);
        const chunk = new ArrayBuffer(chunkSize);
        const bytesRead = await fileIo.read(sourceFd, chunk);
        if (bytesRead <= 0) {
          break;
        }
        outputView.set(new Uint8Array(chunk, 0, bytesRead), totalRead);
        totalRead += bytesRead;
      }
      if (totalRead !== fileStat.size) {
        throw new Error('文件读取不完整。');
      }
      return output;
    } finally {
      if (sourceFd >= 0) {
        try {
          await fileIo.close(sourceFd);
        } catch (_) {
        }
      }
    }
  }
}
