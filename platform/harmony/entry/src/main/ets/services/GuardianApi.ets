import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { NetworkConsent } from './NetworkConsent';
import { API_BASE_URL } from './ApiConfig';
import { ProcessingMode, TransferSession } from './ScanPolicy';
import { ArchiveReview } from './ArchiveReview';
import { ThreatScanner } from './ThreatScanner';
import { CodeAnalyzeResponse, DetectResponse, DocCheckResponse, LinkCheckResponse, PrivacyProcessResponse } from '../models/SecurityModels';
export { API_BASE_URL } from './ApiConfig';

/**
 * One masking operation is two HTTP round trips (ask the server to mask the
 * already-uploaded image, then fetch the result). They share a single consent
 * text so the user approves the whole operation once, not once per request.
 */
/** Result of one masking operation: the server record plus the masked image bytes. */
export interface MaskedImageResult {
  response: PrivacyProcessResponse;
  image: ArrayBuffer;
}

export class GuardianApi {
  private static async dispatch(path: string, options: http.HttpRequestOptions): Promise<Object> {
    const request = http.createHttp();
    try {
      const headers = (options.header ?? {}) as Record<string, string>;
      headers['X-Guardian-Consent'] = 'explicit';
      options.header = headers;
      options.expectDataType = options.expectDataType ?? http.HttpDataType.STRING;
      options.connectTimeout = 15000;
      // The server may spend up to its own 60s model timeout and then still
      // answer with a usable fallback, so the client must wait longer than that;
      // matching 60s made every slow model call look like a network failure.
      options.readTimeout = 150000;
      let response: http.HttpResponse;
      try {
        response = await request.request(`${API_BASE_URL}${path}`, options);
      } catch (networkError) {
        // Connection-level failure: keep the platform code so a timeout is
        // distinguishable from a refused connection or a TLS problem.
        const typedError = networkError as BusinessError;
        const code: number = typedError.code !== undefined ? typedError.code : -1;
        const detail: string = typedError.message ? typedError.message : '无详情';
        if (code === 2300028) {
          throw new Error('请求超时：网络较慢或服务端处理未及时返回，请重试或先用本地检测。');
        }
        throw new Error(`网络请求失败（错误码 ${code}）：${detail}`);
      }
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`服务端返回 HTTP ${response.responseCode}：${GuardianApi.responseDetail(response.result)}`);
      }
      return response.result as Object;
    } finally { request.destroy(); }
  }

  /**
   * Turn an error body into a short, showable reason. FastAPI answers with
   * ``{"detail": "..."}``; anything else is truncated rather than pasted whole
   * into a dialog.
   */
  private static responseDetail(result: Object | string | undefined): string {
    const raw: string = typeof result === 'string' ? result : '';
    if (raw.length === 0) {
      return '无响应正文';
    }
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>;
      const detail = parsed.detail;
      if (typeof detail === 'string' && detail.length > 0) {
        return detail;
      }
    } catch (_) {
      // Fall through to the raw body.
    }
    return raw.length > 120 ? `${raw.substring(0, 120)}…` : raw;
  }

  private static async send<T>(path: string, options: http.HttpRequestOptions,
    transfer: TransferSession, disclosure: string,
    decode: (result: Object) => T = (result: Object): T => JSON.parse(result as string) as T): Promise<T> {
    return transfer.run<T>(
      async (): Promise<void> => { await NetworkConsent.require(disclosure); },
      (): Promise<T> => GuardianApi.dispatch(path, options).then((result: Object): T => decode(result))
    );
  }

  static analyzeCodeText(code: string, language: string,
    mode: ProcessingMode = 'local_only', transfer: TransferSession = new TransferSession(mode),
    disclosure: string = '将你填写的代码片段发送到在线服务进行安全分析。请先删除代码中的密码、密钥和个人信息。'): Promise<CodeAnalyzeResponse> {
    return GuardianApi.send<CodeAnalyzeResponse>('/api/code/analyze', {
      method: http.RequestMethod.POST, header: { 'Content-Type': 'application/json' },
      extraData: JSON.stringify({ language: language, code: code, processingMode: 'online' })
    }, transfer, disclosure);
  }

  static async analyzeCodeArchive(uri: string, name: string,
    mode: ProcessingMode = 'local_only', transfer: TransferSession = new TransferSession(mode)): Promise<CodeAnalyzeResponse> {
    const bytes = new Uint8Array(await GuardianApi.readSelectedFile(uri, 10 * 1024 * 1024));
    const report = ThreatScanner.scanFile(name, bytes);
    const preview = ArchiveReview.inspect(bytes, report);
    if (!preview.canEnhance) { throw new Error('压缩包结构无效或条目过多，仅保留本地结果。'); }
    return GuardianApi.analyzeCodeText(preview.summary, 'auto', mode, transfer,
      `将发送项目包的本地检查摘要（${preview.fileCount} 个文件），不发送 ZIP 原文件或源代码。在线分析只解释检查摘要，不会运行项目代码。`);
  }

  static checkLink(url: string, source: string,
    transfer: TransferSession = new TransferSession()): Promise<LinkCheckResponse> {
    return GuardianApi.send<LinkCheckResponse>('/api/link/check', {
      method: http.RequestMethod.POST, header: { 'Content-Type': 'application/json' },
      extraData: JSON.stringify({ url: url, source: source })
    }, transfer, '将完整链接（包括链接参数）和你填写的来源信息发送到在线服务，检查可疑链接。链接参数可能包含个人信息，请先确认。');
  }

  static async checkDocuments(requirement: string, uris: string[], names: string[],
    transfer: TransferSession = new TransferSession()): Promise<DocCheckResponse> {
    if (names.some((name: string): boolean => /\.(zip|rar|7z)$/i.test(name))) {
      throw new Error('不上传原始压缩包。请在代码页使用ZIP摘要增强；其他材料可单独选择。');
    }
    const form: http.MultiFormData[] = [{ name: 'requirement_text', contentType: 'text/plain', data: requirement }];
    let bytes = 0;
    for (let index = 0; index < uris.length; index++) {
      const data = await GuardianApi.readSelectedFile(uris[index], 10 * 1024 * 1024);
      bytes += data.byteLength;
      if (bytes > 30 * 1024 * 1024) { throw new Error('增强材料总量超过30 MB，请分批选择。'); }
      form.push({ name: 'files', contentType: GuardianApi.documentContentType(names[index]),
        remoteFileName: names[index], data: data });
    }
    return GuardianApi.send<DocCheckResponse>('/api/doc/check', {
      method: http.RequestMethod.POST, header: { 'Content-Type': 'multipart/form-data' }, multiFormDataList: form
    }, transfer, `将你选择的 ${uris.length} 份材料、文件名和填写的提交要求发送到在线服务，进行安全分析。`);
  }

  static async detectPrivacy(uri: string, name: string, mode: ProcessingMode = 'local_only',
    transfer: TransferSession = new TransferSession(mode)): Promise<DetectResponse> {
    const data = await GuardianApi.readSelectedFile(uri, 10 * 1024 * 1024);
    return GuardianApi.send<DetectResponse>('/api/detect', {
      method: http.RequestMethod.POST, header: { 'Content-Type': 'multipart/form-data' },
      multiFormDataList: [
        { name: 'processing_mode', contentType: 'text/plain', data: 'online' },
        { name: 'file', contentType: GuardianApi.imageContentType(name), remoteFileName: 'image' + name.substring(name.lastIndexOf('.')), data: data }
      ]
    }, transfer, '将原始图片发送到在线服务，检查图片中的文字和隐私信息。生成遮挡图片时，还会发送图片编号和遮挡方式，并取回处理后的图片。');
  }

  /**
   * Ask the server to mask an already-uploaded image and fetch the result as one
   * user-visible operation: one consent dialog, one transfer session, no retry.
   * Both requests are dispatched only after that single explicit approval, so
   * there is no unmetered GET path around the transfer policy.
   */
  static async processAndDownloadImage(imageId: string, maskType: string, mode: ProcessingMode,
    transfer: TransferSession = new TransferSession(mode)): Promise<MaskedImageResult> {
    return transfer.runFollowUp<MaskedImageResult>(
      async (): Promise<MaskedImageResult> => {
        const processed = await GuardianApi.dispatch('/api/privacy/process', {
          method: http.RequestMethod.POST, header: { 'Content-Type': 'application/json' },
          extraData: JSON.stringify({ imageId: imageId, scope: 'all', maskType: maskType, itemIds: [] })
        });
        const response = JSON.parse(processed as string) as PrivacyProcessResponse;
        const image = await GuardianApi.dispatch(response.processedImageUrl, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER
        });
        if (!(image instanceof ArrayBuffer) || image.byteLength === 0) {
          throw new Error('服务端未返回有效的处理图，请重新生成安全预览。');
        }
        const result: MaskedImageResult = { response: response, image: image as ArrayBuffer };
        return result;
      }
    );
  }

  private static imageContentType(fileName: string): string {
    const lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.png')) {
      return 'image/png';
    }
    if (lowerName.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  private static documentContentType(fileName: string): string {
    const lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (lowerName.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lowerName.endsWith('.png')) {
      return 'image/png';
    }
    if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lowerName.endsWith('.zip')) {
      return 'application/zip';
    }
    return 'text/plain';
  }

  /**
   * Read a picker URI into memory so a caller can scan it locally.
   * Public so the on-device scanner can reuse the same bounded reader.
   */
  static async readSelectedFile(uri: string, maxBytes: number): Promise<ArrayBuffer> {
    let selectedFd = -1;
    try {
      const selectedFile = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      selectedFd = selectedFile.fd;
      const fileStat = await fileIo.stat(selectedFd);
      if (fileStat.size <= 0) {
        throw new Error('所选文件为空。');
      }
      if (fileStat.size > maxBytes) {
        const maxMegabytes = Math.floor(maxBytes / (1024 * 1024));
        throw new Error(`所选文件超过 ${maxMegabytes} MB 限制。`);
      }

      const output = new ArrayBuffer(fileStat.size);
      const outputView = new Uint8Array(output);
      let totalRead = 0;
      while (totalRead < fileStat.size) {
        const chunkSize = Math.min(1024 * 1024, fileStat.size - totalRead);
        const chunk = new ArrayBuffer(chunkSize);
        const bytesRead = await fileIo.read(selectedFd, chunk);
        if (bytesRead <= 0) {
          break;
        }
        outputView.set(new Uint8Array(chunk, 0, bytesRead), totalRead);
        totalRead += bytesRead;
      }
      if (totalRead !== fileStat.size) {
        throw new Error('文件读取不完整，请重新选择后再试。');
      }
      return output;
    } catch (error) {
      const typedError = error as Error;
      throw new Error(typedError.message || '无法读取所选文件。');
    } finally {
      if (selectedFd >= 0) {
        try {
          await fileIo.close(selectedFd);
        } catch (_) {
        }
      }
    }
  }
}
