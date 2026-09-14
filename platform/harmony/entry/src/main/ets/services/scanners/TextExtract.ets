/**
 * L1 — text extraction helpers.
 *
 * Self-contained UTF-8 / UTF-16LE decoders are used instead of `TextDecoder`
 * so decoding behaves identically in ArkTS and in the Node test harness, and
 * so malformed input degrades to U+FFFD rather than throwing.
 */

const REPLACEMENT: string = '\uFFFD';

export interface PrintString {
  offset: number;
  value: string;
}

/** Decode UTF-8 bytes, substituting U+FFFD for malformed sequences. */
export function decodeUtf8(bytes: Uint8Array): string {
  let out: string = '';
  let i: number = 0;
  while (i < bytes.length) {
    const b0: number = bytes[i];
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
      i++;
      continue;
    }

    let needed: number = 0;
    let codePoint: number = 0;
    if ((b0 & 0xE0) === 0xC0) {
      needed = 1;
      codePoint = b0 & 0x1F;
    } else if ((b0 & 0xF0) === 0xE0) {
      needed = 2;
      codePoint = b0 & 0x0F;
    } else if ((b0 & 0xF8) === 0xF0) {
      needed = 3;
      codePoint = b0 & 0x07;
    } else {
      out += REPLACEMENT;
      i++;
      continue;
    }

    if (i + needed >= bytes.length) {
      out += REPLACEMENT;
      break;
    }

    let valid: boolean = true;
    for (let k = 1; k <= needed; k++) {
      const continued: number = bytes[i + k];
      if ((continued & 0xC0) !== 0x80) {
        valid = false;
        break;
      }
      codePoint = (codePoint << 6) | (continued & 0x3F);
    }
    if (!valid) {
      out += REPLACEMENT;
      i++;
      continue;
    }

    // Reject overlong encodings and surrogate halves.
    if ((needed === 1 && codePoint < 0x80) ||
      (needed === 2 && codePoint < 0x800) ||
      (needed === 3 && codePoint < 0x10000) ||
      (codePoint >= 0xD800 && codePoint <= 0xDFFF) ||
      codePoint > 0x10FFFF) {
      out += REPLACEMENT;
      i += needed + 1;
      continue;
    }

    if (codePoint <= 0xFFFF) {
      out += String.fromCharCode(codePoint);
    } else {
      const adjusted: number = codePoint - 0x10000;
      out += String.fromCharCode(0xD800 + (adjusted >> 10));
      out += String.fromCharCode(0xDC00 + (adjusted & 0x3FF));
    }
    i += needed + 1;
  }
  return out;
}

/** Decode little-endian UTF-16 bytes; an initial BOM is consumed. */
export function decodeUtf16Le(bytes: Uint8Array): string {
  let start: number = 0;
  if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
    start = 2;
  }
  let out: string = '';
  for (let i = start; i + 1 < bytes.length; i += 2) {
    out += String.fromCharCode(bytes[i] | (bytes[i + 1] << 8));
  }
  return out;
}

/** Decode big-endian UTF-16 bytes; an initial BOM is consumed. */
export function decodeUtf16Be(bytes: Uint8Array): string {
  let start: number = 0;
  if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
    start = 2;
  }
  let out: string = '';
  for (let i = start; i + 1 < bytes.length; i += 2) {
    out += String.fromCharCode((bytes[i] << 8) | bytes[i + 1]);
  }
  return out;
}

function isPrintableAscii(byte: number): boolean {
  return byte >= 0x20 && byte <= 0x7E;
}

function isControlCode(code: number): boolean {
  return code < 0x20 && code !== 0x09 && code !== 0x0A && code !== 0x0D;
}

export type TextEncoding = 'none' | 'utf8' | 'utf16le' | 'utf16be';

/** Ratio of characters that should not appear in prose. */
function qualityOf(decoded: string): number {
  if (decoded.length === 0) {
    return 0;
  }
  let bad: number = 0;
  for (let i = 0; i < decoded.length; i++) {
    const code: number = decoded.charCodeAt(i);
    if (code === 0xFFFD || isControlCode(code)) {
      bad++;
    }
  }
  return 1 - bad / decoded.length;
}

/**
 * Decide whether a buffer is text, and in which encoding.
 *
 * Decoding-based rather than byte-range-based on purpose: a document written in
 * Chinese is almost entirely multi-byte UTF-8 sequences, so a rule that counts
 * only printable ASCII bytes would classify every non-English document as
 * binary. What actually separates prose from machine code is how much of the
 * *decoded* result is invalid sequences or control characters — both are
 * abundant in executables, compressed data and images, and rare in text.
 */
export function sniffTextEncoding(bytes: Uint8Array): TextEncoding {
  if (bytes.length === 0) {
    return 'none';
  }
  if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
    return 'utf16le';
  }
  if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
    return 'utf16be';
  }

  // Wide text without a BOM: low byte printable, high byte almost always zero.
  const probe: number = bytes.length > 512 ? 512 : bytes.length;
  const pairs: number = Math.floor(probe / 2);
  if (pairs >= 8) {
    let oddNulls: number = 0;
    let evenNulls: number = 0;
    for (let i = 0; i + 1 < probe; i += 2) {
      if (bytes[i] === 0x00) {
        evenNulls++;
      }
      if (bytes[i + 1] === 0x00) {
        oddNulls++;
      }
    }
    if (oddNulls / pairs > 0.6 && evenNulls / pairs < 0.1) {
      return 'utf16le';
    }
    if (evenNulls / pairs > 0.6 && oddNulls / pairs < 0.1) {
      return 'utf16be';
    }
  }

  const sample: Uint8Array = bytes.length > 8192 ? bytes.subarray(0, 8192) : bytes;
  if (qualityOf(decodeUtf8(sample)) >= 0.98) {
    return 'utf8';
  }
  return 'none';
}

/** True when the buffer plausibly holds readable text in any supported encoding. */
export function looksLikeText(bytes: Uint8Array): boolean {
  return sniffTextEncoding(bytes) !== 'none';
}

/** True when the payload carries an HTML/XML/script flavour. */
export function looksLikeMarkup(bytes: Uint8Array): boolean {
  const head: Uint8Array = bytes.subarray(0, bytes.length > 512 ? 512 : bytes.length);
  const text: string = decodeUtf8(head).trim().toLowerCase();
  return text.startsWith('<!doctype html') || text.startsWith('<html') ||
    text.startsWith('<?xml') || text.startsWith('<svg') ||
    text.indexOf('<script') >= 0 || text.indexOf('<?php') >= 0;
}

/**
 * Decode a payload using the sniffed encoding. Returns `''` when the buffer does
 * not look like text at all.
 */
export function decodeTextPayload(bytes: Uint8Array): string {
  const encoding: TextEncoding = sniffTextEncoding(bytes);
  if (encoding === 'utf16le') {
    return decodeUtf16Le(bytes);
  }
  if (encoding === 'utf16be') {
    return decodeUtf16Be(bytes);
  }
  if (encoding === 'utf8') {
    return decodeUtf8(bytes);
  }
  return '';
}

/**
 * Extract printable ASCII runs of at least `minLength` characters. Used for
 * pulling C2 URLs, downloader paths and debug strings out of binaries.
 */
export function extractAsciiStrings(bytes: Uint8Array, minLength: number,
  maxStrings: number): PrintString[] {
  const out: PrintString[] = [];
  let run: string = '';
  let runStart: number = 0;
  for (let i = 0; i < bytes.length; i++) {
    const b: number = bytes[i];
    if (isPrintableAscii(b)) {
      if (run.length === 0) {
        runStart = i;
      }
      run += String.fromCharCode(b);
    } else {
      if (run.length >= minLength) {
        out.push({ offset: runStart, value: run });
        if (out.length >= maxStrings) {
          return out;
        }
      }
      run = '';
    }
  }
  if (run.length >= minLength && out.length < maxStrings) {
    out.push({ offset: runStart, value: run });
  }
  return out;
}

/**
 * Extract UTF-16LE strings — the usual encoding for Windows resources.
 * Both byte parities are scanned because resource sections are not guaranteed
 * to start on an even offset relative to the container.
 */
export function extractUtf16Strings(bytes: Uint8Array, minLength: number,
  maxStrings: number): PrintString[] {
  const out: PrintString[] = [];
  for (let parity = 0; parity < 2; parity++) {
    let run: string = '';
    let runStart: number = 0;
    for (let i = parity; i + 1 < bytes.length; i += 2) {
      const low: number = bytes[i];
      const high: number = bytes[i + 1];
      if (high === 0x00 && isPrintableAscii(low)) {
        if (run.length === 0) {
          runStart = i;
        }
        run += String.fromCharCode(low);
      } else {
        if (run.length >= minLength) {
          out.push({ offset: runStart, value: run });
          if (out.length >= maxStrings) {
            return out;
          }
        }
        run = '';
      }
    }
    if (run.length >= minLength && out.length < maxStrings) {
      out.push({ offset: runStart, value: run });
    }
    if (out.length >= maxStrings) {
      break;
    }
  }
  return out;
}

/** Both ASCII and UTF-16 strings, de-duplicated by value. */
export function extractAllStrings(bytes: Uint8Array, minLength: number = 6,
  maxStrings: number = 4000): string[] {
  const seen: string[] = [];
  const ascii: PrintString[] = extractAsciiStrings(bytes, minLength, maxStrings);
  for (let i = 0; i < ascii.length; i++) {
    seen.push(ascii[i].value);
  }
  const wide: PrintString[] = extractUtf16Strings(bytes, minLength, maxStrings);
  for (let i = 0; i < wide.length; i++) {
    seen.push(wide[i].value);
  }
  return seen;
}

/** Join extracted strings into one searchable blob for regex scanners. */
export function stringsToCorpus(strings: string[], maxChars: number): string {
  let out: string = '';
  for (let i = 0; i < strings.length; i++) {
    if (out.length >= maxChars) {
      break;
    }
    out += strings[i];
    out += '\n';
  }
  return out;
}
