/**
 * L1 — Shannon entropy analysis.
 *
 * Entropy separates "structured code and data" from "something deliberately
 * scrambled". Packed executables, encrypted payloads and nested compressed
 * streams all push a region toward 8.0 bits/byte, which is a cheap, format
 * independent signal that costs one linear pass to compute.
 */

export interface EntropyRegion {
  offset: number;
  length: number;
  entropy: number;
}

function zeroHistogram(): number[] {
  const out: number[] = [];
  for (let i = 0; i < 256; i++) {
    out.push(0);
  }
  return out;
}

/** Shannon entropy of a byte range, in bits per byte (0..8). */
export function shannonEntropy(data: Uint8Array, start: number, end: number): number {
  const from: number = start < 0 ? 0 : start;
  const to: number = end > data.length ? data.length : end;
  const length: number = to - from;
  if (length <= 0) {
    return 0;
  }
  const histogram: number[] = zeroHistogram();
  for (let i = from; i < to; i++) {
    histogram[data[i]]++;
  }
  let entropy: number = 0;
  for (let i = 0; i < 256; i++) {
    if (histogram[i] === 0) {
      continue;
    }
    const p: number = histogram[i] / length;
    entropy -= p * (Math.log(p) / Math.LN2);
  }
  return entropy;
}

export function entropyOf(data: Uint8Array): number {
  return shannonEntropy(data, 0, data.length);
}

/**
 * Locate contiguous regions whose local entropy stays above `threshold`.
 * Used to spot the encrypted blob inside an otherwise ordinary file.
 */
export function findHighEntropyRegions(data: Uint8Array, threshold: number = 7.5,
  windowSize: number = 256, minLength: number = 2048): EntropyRegion[] {
  const regions: EntropyRegion[] = [];
  if (data.length < minLength) {
    return regions;
  }
  const step: number = windowSize;
  let runStart: number = -1;
  let runEnd: number = 0;
  let entropySum: number = 0;
  let windowCount: number = 0;

  for (let offset = 0; offset + windowSize <= data.length; offset += step) {
    const local: number = shannonEntropy(data, offset, offset + windowSize);
    if (local >= threshold) {
      if (runStart < 0) {
        runStart = offset;
        entropySum = 0;
        windowCount = 0;
      }
      runEnd = offset + windowSize;
      entropySum += local;
      windowCount++;
    } else {
      if (runStart >= 0 && runEnd - runStart >= minLength) {
        regions.push({
          offset: runStart,
          length: runEnd - runStart,
          entropy: windowCount > 0 ? entropySum / windowCount : 0
        });
      }
      runStart = -1;
    }
  }
  if (runStart >= 0 && runEnd - runStart >= minLength) {
    regions.push({
      offset: runStart,
      length: runEnd - runStart,
      entropy: windowCount > 0 ? entropySum / windowCount : 0
    });
  }
  return regions;
}

/** Fraction of the buffer that sits in high-entropy regions. */
export function scrambledRatio(data: Uint8Array): number {
  if (data.length === 0) {
    return 0;
  }
  const regions: EntropyRegion[] = findHighEntropyRegions(data, 7.5, 256, 1024);
  let total: number = 0;
  for (let i = 0; i < regions.length; i++) {
    total += regions[i].length;
  }
  return total / data.length;
}

/** True when the blob is flat enough to be padding rather than payload. */
export function looksFlat(data: Uint8Array, start: number, end: number): boolean {
  if (end - start < 64) {
    return true;
  }
  const histogram: number[] = zeroHistogram();
  for (let i = start; i < end; i++) {
    histogram[data[i]]++;
  }
  let dominant: number = 0;
  for (let i = 0; i < 256; i++) {
    if (histogram[i] > dominant) {
      dominant = histogram[i];
    }
  }
  return dominant / (end - start) > 0.9;
}
