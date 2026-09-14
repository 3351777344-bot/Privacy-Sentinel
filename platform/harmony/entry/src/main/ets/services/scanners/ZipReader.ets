/**
 * L1 — read-only ZIP central-directory reader.
 *
 * Parses structure only. The central directory holds the declared compressed
 * and uncompressed sizes, which is everything needed to spot a zip bomb, a
 * path-traversal entry or an encrypted payload *before* a single byte is
 * decompressed. That ordering is the whole point: never let a hostile archive
 * decide how much memory the scanner allocates.
 */

import { decodeUtf8 } from './TextExtract';

export const ZIP_LOCAL_HEADER_SIGNATURE: number = 0x04034b50;
export const ZIP_CENTRAL_SIGNATURE: number = 0x02014b50;
export const ZIP_EOCD_SIGNATURE: number = 0x06054b50;

export const ZIP_METHOD_STORED: number = 0;
export const ZIP_METHOD_DEFLATE: number = 8;
export const ZIP_METHOD_DEFLATE64: number = 9;
export const ZIP_METHOD_BZIP2: number = 12;
export const ZIP_METHOD_LZMA: number = 14;
export const ZIP_METHOD_AES: number = 99;

/** Unix st_mode bits stored in the high half of the external attributes. */
const UNIX_FILE_TYPE_MASK: number = 0xF000;
const UNIX_SYMLINK: number = 0xA000;

export interface ZipEntry {
  name: string;
  method: number;
  flags: number;
  crc32: number;
  compressedSize: number;
  uncompressedSize: number;
  localHeaderOffset: number;
  encrypted: boolean;
  /** AES / strong encryption (method 99 or GPBF bit 6). */
  strongEncryption: boolean;
  symlink: boolean;
  directory: boolean;
  /** Ratio of uncompressed to compressed size; 0 when nothing is compressed. */
  ratio: number;
}

export interface ZipDirectory {
  ok: boolean;
  entries: ZipEntry[];
  error: string;
  /** Entry table exceeded the parse limit — itself a hostile signal. */
  entryLimitHit: boolean;
  /** Sum of every declared uncompressed size. */
  declaredTotal: number;
  /** Sum of every declared compressed size. */
  compressedTotal: number;
  /** Offset where the central directory starts. */
  centralOffset: number;
  comment: string;
}

export const MAX_ZIP_ENTRIES: number = 20000;

function readUint16LE(data: Uint8Array, offset: number): number {
  if (offset + 2 > data.length) {
    return -1;
  }
  return data[offset] | (data[offset + 1] << 8);
}

function readUint32LE(data: Uint8Array, offset: number): number {
  if (offset + 4 > data.length) {
    return -1;
  }
  const value: number =
    data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16) | (data[offset + 3] << 24);
  return value >>> 0;
}

/** Decode a ZIP name honouring the UTF-8 flag, falling back to Latin-1. */
export function decodeZipName(bytes: Uint8Array, utf8: boolean): string {
  if (utf8) {
    return decodeUtf8(bytes);
  }
  let out: string = '';
  for (let i = 0; i < bytes.length; i++) {
    out += String.fromCharCode(bytes[i]);
  }
  return out;
}

/** Locate the end-of-central-directory record by scanning backwards. */
export function findEndOfCentralDirectory(data: Uint8Array): number {
  const minimumEocd: number = 22;
  if (data.length < minimumEocd) {
    return -1;
  }
  const lowest: number = data.length - minimumEocd - 65535;
  const start: number = lowest > 0 ? lowest : 0;
  for (let i = data.length - minimumEocd; i >= start; i--) {
    if (readUint32LE(data, i) === ZIP_EOCD_SIGNATURE) {
      return i;
    }
  }
  return -1;
}

/** True when the buffer starts with a ZIP local-file or empty-archive header. */
export function looksLikeZip(data: Uint8Array): boolean {
  if (data.length < 4) {
    return false;
  }
  const signature: number = readUint32LE(data, 0);
  return signature === ZIP_LOCAL_HEADER_SIGNATURE ||
    signature === ZIP_EOCD_SIGNATURE ||
    signature === 0x08074b50;
}

/** Parse the central directory. Never decompresses anything. */
export function readZipDirectory(data: Uint8Array): ZipDirectory {
  const empty: ZipDirectory = {
    ok: false,
    entries: [],
    error: '',
    entryLimitHit: false,
    declaredTotal: 0,
    compressedTotal: 0,
    centralOffset: 0,
    comment: ''
  };

  const eocdOffset: number = findEndOfCentralDirectory(data);
  if (eocdOffset < 0) {
    empty.error = '未找到 ZIP 中央目录（损坏或被清除）';
    return empty;
  }

  let totalEntries: number = readUint16LE(data, eocdOffset + 10);
  let centralSize: number = readUint32LE(data, eocdOffset + 12);
  let centralOffset: number = readUint32LE(data, eocdOffset + 16);
  const commentLength: number = readUint16LE(data, eocdOffset + 20);

  // ------------------------------------------------------------- ZIP64 upgrade
  if (centralOffset === 0xFFFFFFFF || totalEntries === 0xFFFF || centralSize === 0xFFFFFFFF) {
    const zip64: Zip64Locator | undefined = findZip64Locator(data, eocdOffset);
    if (zip64 !== undefined) {
      centralOffset = zip64.centralOffset;
      centralSize = zip64.centralSize;
      totalEntries = zip64.totalEntries;
    }
  }

  if (centralOffset < 0 || centralOffset >= data.length) {
    empty.error = '中央目录偏移越界';
    return empty;
  }

  const entries: ZipEntry[] = [];
  let cursor: number = centralOffset;
  let entryLimitHit: boolean = false;
  let declaredTotal: number = 0;
  let compressedTotal: number = 0;

  while (cursor + 46 <= data.length) {
    const signature: number = readUint32LE(data, cursor);
    if (signature !== ZIP_CENTRAL_SIGNATURE) {
      break;
    }
    if (entries.length >= MAX_ZIP_ENTRIES) {
      entryLimitHit = true;
      break;
    }

    const flags: number = readUint16LE(data, cursor + 8);
    let method: number = readUint16LE(data, cursor + 10);
    const crc32: number = readUint32LE(data, cursor + 16);
    let compressedSize: number = readUint32LE(data, cursor + 20);
    let uncompressedSize: number = readUint32LE(data, cursor + 24);
    const nameLength: number = readUint16LE(data, cursor + 28);
    const extraLength: number = readUint16LE(data, cursor + 30);
    const entryCommentLength: number = readUint16LE(data, cursor + 32);
    const externalAttributes: number = readUint32LE(data, cursor + 38);
    let localHeaderOffset: number = readUint32LE(data, cursor + 42);

    const nameStart: number = cursor + 46;
    const nameEnd: number = nameStart + nameLength;
    if (nameEnd > data.length) {
      empty.error = '文件名越过缓冲区边界';
      return empty;
    }
    const utf8: boolean = (flags & 0x800) !== 0;
    const name: string = decodeZipName(data.subarray(nameStart, nameEnd), utf8);

    // ZIP64 extended information extra field.
    if (compressedSize === 0xFFFFFFFF || uncompressedSize === 0xFFFFFFFF ||
      localHeaderOffset === 0xFFFFFFFF) {
      const extraStart: number = nameEnd;
      const sizes: number[] | undefined =
        readZip64Extra(data, extraStart, extraLength, uncompressedSize === 0xFFFFFFFF,
          compressedSize === 0xFFFFFFFF, localHeaderOffset === 0xFFFFFFFF);
      if (sizes !== undefined) {
        if (uncompressedSize === 0xFFFFFFFF) {
          uncompressedSize = sizes[0];
        }
        if (compressedSize === 0xFFFFFFFF) {
          compressedSize = sizes[1];
        }
        if (localHeaderOffset === 0xFFFFFFFF) {
          localHeaderOffset = sizes[2];
        }
      }
    }

    const encrypted: boolean = (flags & 0x1) !== 0 || method === ZIP_METHOD_AES;
    const strongEncryption: boolean = (flags & 0x40) !== 0 || method === ZIP_METHOD_AES;
    if (method === ZIP_METHOD_AES && (flags & 0x1) === 0) {
      // AES entries set bit 0 as well in practice; keep the flag explicit.
      method = ZIP_METHOD_AES;
    }
    const symlink: boolean = (externalAttributes >>> 16 & UNIX_FILE_TYPE_MASK) === UNIX_SYMLINK;
    const directory: boolean = name.endsWith('/');
    const ratio: number = compressedSize > 0 && uncompressedSize > 0
      ? uncompressedSize / compressedSize
      : 0;

    entries.push({
      name: name,
      method: method,
      flags: flags,
      crc32: crc32,
      compressedSize: compressedSize,
      uncompressedSize: uncompressedSize,
      localHeaderOffset: localHeaderOffset,
      encrypted: encrypted,
      strongEncryption: strongEncryption,
      symlink: symlink,
      directory: directory,
      ratio: ratio
    });

    declaredTotal += uncompressedSize;
    compressedTotal += compressedSize;
    cursor = nameEnd + extraLength + entryCommentLength;
  }

  if (entries.length === 0) {
    empty.error = '中央目录中存在 0 个有效条目';
    return empty;
  }

  let comment: string = '';
  if (commentLength > 0 && eocdOffset + 22 + commentLength <= data.length) {
    comment = decodeZipName(data.subarray(eocdOffset + 22, eocdOffset + 22 + commentLength), true);
  }

  return {
    ok: true,
    entries: entries,
    error: '',
    entryLimitHit: entryLimitHit,
    declaredTotal: declaredTotal,
    compressedTotal: compressedTotal,
    centralOffset: centralOffset,
    comment: comment
  };
}

interface Zip64Locator {
  centralOffset: number;
  centralSize: number;
  totalEntries: number;
}

function findZip64Locator(data: Uint8Array, eocdOffset: number): Zip64Locator | undefined {
  const locatorSize: number = 20;
  const locatorOffset: number = eocdOffset - locatorSize;
  if (locatorOffset < 0 || readUint32LE(data, locatorOffset) !== 0x07064b50) {
    return undefined;
  }
  const zip64EocdOffset: number = readUint32LE(data, locatorOffset + 8);
  if (zip64EocdOffset < 0 || readUint32LE(data, zip64EocdOffset) !== 0x06064b50) {
    return undefined;
  }
  return {
    totalEntries: readUint32LE(data, zip64EocdOffset + 32),
    centralSize: readUint32LE(data, zip64EocdOffset + 40),
    centralOffset: readUint32LE(data, zip64EocdOffset + 48)
  };
}

function readZip64Extra(data: Uint8Array, start: number, length: number,
  wantUncompressed: boolean, wantCompressed: boolean,
  wantOffset: boolean): number[] | undefined {
  let cursor: number = start;
  const end: number = start + length;
  while (cursor + 4 <= end) {
    const headerId: number = readUint16LE(data, cursor);
    const dataSize: number = readUint16LE(data, cursor + 2);
    const bodyStart: number = cursor + 4;
    if (headerId === 0x0001) {
      let bodyCursor: number = bodyStart;
      let uncompressed: number = -1;
      let compressed: number = -1;
      let offset: number = -1;
      if (wantUncompressed && bodyCursor + 8 <= data.length) {
        uncompressed = readUint64LE(data, bodyCursor);
        bodyCursor += 8;
      }
      if (wantCompressed && bodyCursor + 8 <= data.length) {
        compressed = readUint64LE(data, bodyCursor);
        bodyCursor += 8;
      }
      if (wantOffset && bodyCursor + 8 <= data.length) {
        offset = readUint64LE(data, bodyCursor);
      }
      return [uncompressed < 0 ? 0 : uncompressed, compressed < 0 ? 0 : compressed,
        offset < 0 ? 0 : offset];
    }
    cursor = bodyStart + dataSize;
  }
  return undefined;
}

function readUint64LE(data: Uint8Array, offset: number): number {
  const low: number = readUint32LE(data, offset);
  const high: number = readUint32LE(data, offset + 4);
  // Values beyond 2^53 are rounded, which is acceptable for size heuristics.
  return high * 4294967296 + low;
}

/**
 * Extract the raw (still compressed) byte range of an entry using its local
 * header. Returns an empty view when the structure does not line up.
 */
export function readEntryCompressedData(data: Uint8Array, entry: ZipEntry): Uint8Array {
  const offset: number = entry.localHeaderOffset;
  if (offset < 0 || offset + 30 > data.length) {
    return new Uint8Array(0);
  }
  if (readUint32LE(data, offset) !== ZIP_LOCAL_HEADER_SIGNATURE) {
    return new Uint8Array(0);
  }
  const nameLength: number = readUint16LE(data, offset + 26);
  const extraLength: number = readUint16LE(data, offset + 28);
  const dataStart: number = offset + 30 + nameLength + extraLength;
  if (dataStart < 0 || dataStart > data.length) {
    return new Uint8Array(0);
  }
  const size: number = entry.compressedSize;
  const dataEnd: number = dataStart + size;
  if (dataEnd > data.length) {
    return data.subarray(dataStart, data.length);
  }
  return data.subarray(dataStart, dataEnd);
}
