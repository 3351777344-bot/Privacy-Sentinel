import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import {
  CodeAnalyzeResponse,
  DetectResponse,
  DocCheckResponse,
  LinkCheckResponse,
  PrivacyProcessResponse,
  QrDecodeResponse
} from '../models/SecurityModels';

// DevEco phone emulator reaches the development computer through 10.0.2.2.
// Replace this with the computer's LAN HTTPS address when testing on a device.
export const API_BASE_URL: string = 'http://10.0.2.2:8000';

interface ApiErrorEnvelope {
  detail?: string;
}

export class GuardianApi {
  private static async send<T>(path: string, options: http.HttpRequestOptions): Promise<T> {
    const request = http.createHttp();
    try {
      options.expectDataType = http.HttpDataType.STRING;
      options.connectTimeout = 15000;
      options.readTimeout = 60000;
      const response = await request.request(`${API_BASE_URL}${path}`, options);
      const responseText = response.result as string;
      if (response.responseCode < 200 || response.responseCode >= 300) {
        let detail = `服务返回 ${response.responseCode}`;
        try {
          const errorBody = JSON.parse(responseText) as ApiErrorEnvelope;
          detail = errorBody.detail ?? detail;
        } catch (_) {
        }
        throw new Error(detail);
      }
      return JSON.parse(responseText) as T;
    } catch (error) {
      const typedError = error as Error;
      throw new Error(typedError.message || '无法连接 GuardianHub 服务。');
    } finally {
      request.destroy();
    }
  }

  static async analyzeCodeArchive(fileUri: string, fileName: string): Promise<CodeAnalyzeResponse> {
    const fileData = await GuardianApi.readSelectedFile(fileUri, 10 * 1024 * 1024);
    return GuardianApi.send<CodeAnalyzeResponse>('/api/code/analyze', {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'multipart/form-data'
      },
      multiFormDataList: [
        {
          name: 'processing_mode',
          contentType: 'text/plain',
          data: 'local'
        },
        {
          name: 'file',
          contentType: 'application/zip',
          remoteFileName: fileName,
          data: fileData
        }
      ]
    });
  }

  static checkLink(url: string, source: string): Promise<LinkCheckResponse> {
    return GuardianApi.send<LinkCheckResponse>('/api/link/check', {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json'
      },
      extraData: JSON.stringify({
        url: url,
        source: source
      })
    });
  }

  static async decodeQr(fileUri: string, fileName: string): Promise<QrDecodeResponse> {
    const fileData = await GuardianApi.readSelectedFile(fileUri, 10 * 1024 * 1024);
    return GuardianApi.send<QrDecodeResponse>('/api/link/qr/decode', {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'multipart/form-data'
      },
      multiFormDataList: [
        {
          name: 'file',
          contentType: GuardianApi.imageContentType(fileName),
          remoteFileName: fileName,
          data: fileData
        }
      ]
    });
  }

  static async checkDocuments(requirementText: string, fileUris: string[],
    fileNames: string[]): Promise<DocCheckResponse> {
    const formData: http.MultiFormData[] = [
      {
        name: 'requirement_text',
        contentType: 'text/plain; charset=utf-8',
        data: requirementText
      }
    ];
    for (let index = 0; index < fileUris.length; index++) {
      const fileData = await GuardianApi.readSelectedFile(fileUris[index], 10 * 1024 * 1024);
      formData.push({
        name: 'files',
        contentType: GuardianApi.documentContentType(fileNames[index]),
        remoteFileName: fileNames[index],
        data: fileData
      });
    }
    return GuardianApi.send<DocCheckResponse>('/api/doc/check', {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'multipart/form-data'
      },
      multiFormDataList: formData
    });
  }

  static async detectPrivacy(fileUri: string, fileName: string): Promise<DetectResponse> {
    const fileData = await GuardianApi.readSelectedFile(fileUri, 10 * 1024 * 1024);
    return GuardianApi.detectPrivacyData(fileData, fileName);
  }

  static async detectPrivacyDemo(): Promise<DetectResponse> {
    const fileName = 'privacy_sentinel_demo_qr.png';
    const fileData =
      await GuardianApi.downloadProcessedImage('/static/samples/privacy_sentinel_demo_qr.png');
    return GuardianApi.detectPrivacyData(fileData, fileName);
  }

  private static detectPrivacyData(fileData: ArrayBuffer,
    fileName: string): Promise<DetectResponse> {
    return GuardianApi.send<DetectResponse>('/api/detect', {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'multipart/form-data'
      },
      multiFormDataList: [
        {
          name: 'processing_mode',
          contentType: 'text/plain',
          data: 'local'
        },
        {
          name: 'file',
          contentType: GuardianApi.imageContentType(fileName),
          remoteFileName: fileName,
          data: fileData
        }
      ]
    });
  }

  static processPrivacy(imageId: string, maskType: string): Promise<PrivacyProcessResponse> {
    return GuardianApi.send<PrivacyProcessResponse>('/api/privacy/process', {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json'
      },
      extraData: JSON.stringify({
        imageId: imageId,
        scope: 'all',
        maskType: maskType,
        itemIds: []
      })
    });
  }

  static async downloadProcessedImage(path: string): Promise<ArrayBuffer> {
    const request = http.createHttp();
    try {
      const response = await request.request(`${API_BASE_URL}${path}`, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 60000
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`处理图下载失败，服务返回 ${response.responseCode}`);
      }
      return response.result as ArrayBuffer;
    } catch (error) {
      const typedError = error as Error;
      throw new Error(typedError.message || '无法下载处理后的图片。');
    } finally {
      request.destroy();
    }
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

  private static async readSelectedFile(uri: string, maxBytes: number): Promise<ArrayBuffer> {
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
