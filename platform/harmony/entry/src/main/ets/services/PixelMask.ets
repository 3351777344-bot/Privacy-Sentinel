import { QrRect } from './QrRules';

/** Opaque fill, not blur: QR error correction must not recover masked credentials. */
export class PixelMask {
  static apply(bytes: Uint8Array, width: number, height: number, regions: QrRect[]): void {
    if (width <= 0 || height <= 0 || width * height > 16000000 || bytes.length !== width * height * 4) {
      throw new Error('图片尺寸或像素缓冲无效。');
    }
    if (regions.length === 0) { throw new Error('没有可靠的二维码坐标，无法自动遮挡。'); }
    // Validate every region before mutating any pixels.
    regions.forEach((r: QrRect) => {
      if (![r.left, r.top, r.right, r.bottom].every((v: number): boolean => Number.isFinite(v)) ||
        r.left < 0 || r.top < 0 || r.right > width || r.bottom > height || r.right <= r.left || r.bottom <= r.top) {
        throw new Error('二维码坐标与图片不匹配，未生成处理图。');
      }
    });
    regions.forEach((r: QrRect) => {
      const pad = Math.max(8, Math.ceil(Math.max(r.right - r.left, r.bottom - r.top) * 0.1));
      const left = Math.max(0, Math.floor(r.left) - pad);
      const top = Math.max(0, Math.floor(r.top) - pad);
      const right = Math.min(width, Math.ceil(r.right) + pad);
      const bottom = Math.min(height, Math.ceil(r.bottom) + pad);
      for (let y = top; y < bottom; y++) {
        for (let x = left; x < right; x++) {
          const offset = (y * width + x) * 4;
          bytes[offset] = 0; bytes[offset + 1] = 0; bytes[offset + 2] = 0; bytes[offset + 3] = 255;
        }
      }
    });
  }
}
