import { detectBarcode, scanCore } from '@kit.ScanKit';
import { DecodedQr, QrClassification, QrImageReport, QrRules } from './QrRules';
export { QrClassification } from './QrRules';

export class QrContentService {
  static async decodeAll(imageUri: string): Promise<QrImageReport> {
    try {
      const results = await detectBarcode.decode({ uri: imageUri }, { scanTypes: [scanCore.ScanType.ALL] });
      const decoded: DecodedQr[] = results.map((result): DecodedQr => {
        if (result.scanCodeRect) {
          return {
            payload: result.originalValue || '',
            rect: {
              left: result.scanCodeRect.left,
              top: result.scanCodeRect.top,
              right: result.scanCodeRect.right,
              bottom: result.scanCodeRect.bottom
            }
          };
        }
        return { payload: result.originalValue || '' };
      });
      return QrRules.analyze(decoded);
    } catch (_) {
      return QrRules.analyze([], true);
    }
  }

  static classify(payload: string): QrClassification { return QrRules.classify(payload); }
}
