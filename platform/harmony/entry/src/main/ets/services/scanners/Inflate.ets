/**
 * L1 — minimal raw-DEFLATE decoder (RFC 1951).
 *
 * Why hand-rolled instead of `@ohos.zlib`: the archive scanner must inspect the
 * *contents* of compressed entries while keeping a hard ceiling on how many
 * bytes it will ever materialise. `@ohos.zlib` only decompresses to disk, which
 * both pollutes the sandbox and gives a zip bomb a free path to fill storage.
 * Decoding into a capped in-memory buffer lets us detect the bomb instead of
 * suffering it — and keeps this file free of any ArkTS API so it is unit
 * testable in plain Node.
 */

/** Hard ceiling on decoded bytes. Exceeding it is itself a bomb signal. */
export const DEFAULT_MAX_OUTPUT: number = 32 * 1024 * 1024;

const MAX_BITS: number = 15;

const LENGTH_BASE: number[] = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
  35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
];
const LENGTH_EXTRA: number[] = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
  3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
];
const DIST_BASE: number[] = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
  257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
];
const DIST_EXTRA: number[] = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
  7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
];
/** Order in which the code-length alphabet is transmitted. */
const CODE_LENGTH_ORDER: number[] = [
  16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
];

export interface InflateResult {
  ok: boolean;
  data: Uint8Array;
  error: string;
  /** Output hit `maxOutput`; decoding stopped early. Strong bomb indicator. */
  truncated: boolean;
}

class DeflateError extends Error {
}

class BitReader {
  private readonly data: Uint8Array;
  private pos: number = 0;
  private bitBuf: number = 0;
  private bitCnt: number = 0;

  constructor(data: Uint8Array) {
    this.data = data;
  }

  /** Read `need` bits, least-significant bit first. */
  bits(need: number): number {
    let value: number = this.bitBuf;
    while (this.bitCnt < need) {
      if (this.pos >= this.data.length) {
        throw new DeflateError('压缩流提前结束');
      }
      value |= this.data[this.pos] << this.bitCnt;
      this.pos++;
      this.bitCnt += 8;
    }
    this.bitBuf = value >>> need;
    this.bitCnt -= need;
    if (need === 0) {
      return 0;
    }
    return value & ((1 << need) - 1);
  }

  /** Discard bits up to the next byte boundary (used by stored blocks). */
  alignToByte(): void {
    this.bitBuf = 0;
    this.bitCnt = 0;
  }

  readByte(): number {
    if (this.pos >= this.data.length) {
      throw new DeflateError('压缩流提前结束');
    }
    const value: number = this.data[this.pos];
    this.pos++;
    return value;
  }

  readUint16LE(): number {
    const low: number = this.readByte();
    const high: number = this.readByte();
    return low | (high << 8);
  }
}

/** Canonical Huffman decoder using zlib's `puff` counting scheme. */
class Huffman {
  count: number[] = [];
  symbol: number[] = [];

  static build(lengths: number[], count: number): Huffman {
    const huffman: Huffman = new Huffman();
    const counts: number[] = [];
    for (let i = 0; i <= MAX_BITS; i++) {
      counts.push(0);
    }
    for (let i = 0; i < count; i++) {
      counts[lengths[i]]++;
    }
    counts[0] = 0;

    const offsets: number[] = [];
    let total: number = 0;
    for (let len = 0; len <= MAX_BITS; len++) {
      offsets.push(total);
      total += counts[len];
    }
    if (total !== count) {
      // Incomplete code; tolerated as long as decoding never needs the gap.
    }

    const symbols: number[] = [];
    for (let i = 0; i < count; i++) {
      symbols.push(0);
    }
    for (let i = 0; i < count; i++) {
      if (lengths[i] !== 0) {
        symbols[offsets[lengths[i]]] = i;
        offsets[lengths[i]]++;
      }
    }

    huffman.count = counts;
    huffman.symbol = symbols;
    return huffman;
  }

  decode(reader: BitReader): number {
    let code: number = 0;
    let first: number = 0;
    let index: number = 0;
    for (let len = 1; len <= MAX_BITS; len++) {
      code |= reader.bits(1);
      const slot: number = this.count[len];
      if (code - slot < first) {
        return this.symbol[index + (code - first)];
      }
      index += slot;
      first += slot;
      first <<= 1;
      code <<= 1;
    }
    throw new DeflateError('非法霍夫曼编码');
  }
}

let FIXED_LITERAL: Huffman | undefined = undefined;
let FIXED_DISTANCE: Huffman | undefined = undefined;

function fixedTables(): Huffman[] {
  if (FIXED_LITERAL === undefined || FIXED_DISTANCE === undefined) {
    const literalLengths: number[] = [];
    for (let i = 0; i < 288; i++) {
      if (i < 144) {
        literalLengths.push(8);
      } else if (i < 256) {
        literalLengths.push(9);
      } else if (i < 280) {
        literalLengths.push(7);
      } else {
        literalLengths.push(8);
      }
    }
    const distanceLengths: number[] = [];
    for (let i = 0; i < 30; i++) {
      distanceLengths.push(5);
    }
    FIXED_LITERAL = Huffman.build(literalLengths, 288);
    FIXED_DISTANCE = Huffman.build(distanceLengths, 30);
  }
  return [FIXED_LITERAL, FIXED_DISTANCE];
}

/** Growable output buffer with a hard cap. */
class OutputBuffer {
  private buf: Uint8Array;
  private length: number = 0;
  readonly cap: number;
  truncated: boolean = false;

  constructor(cap: number) {
    this.cap = cap;
    const initial: number = cap < 65536 ? cap : 65536;
    this.buf = new Uint8Array(initial);
  }

  pushByte(value: number): void {
    if (this.length >= this.cap) {
      this.truncated = true;
      throw new DeflateError('解压输出超过上限');
    }
    if (this.length >= this.buf.length) {
      const nextSize: number = this.buf.length * 2 > this.cap ? this.cap : this.buf.length * 2;
      const grown: Uint8Array = new Uint8Array(nextSize);
      grown.set(this.buf.subarray(0, this.length), 0);
      this.buf = grown;
    }
    this.buf[this.length] = value;
    this.length++;
  }

  copyBack(distance: number, length: number): void {
    if (distance <= 0 || distance > this.length) {
      throw new DeflateError('非法回溯距离');
    }
    for (let i = 0; i < length; i++) {
      const value: number = this.buf[this.length - distance];
      this.pushByte(value);
    }
  }

  /** Copy from a source buffer (used by stored blocks). */
  append(source: Uint8Array, offset: number, count: number): void {
    for (let i = 0; i < count; i++) {
      this.pushByte(source[offset + i]);
    }
  }

  toUint8Array(): Uint8Array {
    return this.buf.slice(0, this.length);
  }
}

function dynamicTables(reader: BitReader): Huffman[] {
  const hlit: number = reader.bits(5) + 257;
  const hdist: number = reader.bits(5) + 1;
  const hclen: number = reader.bits(4) + 4;

  if (hlit > 286 || hdist > 30) {
    throw new DeflateError('动态霍夫曼头部越界');
  }

  const codeLengths: number[] = [];
  for (let i = 0; i < 19; i++) {
    codeLengths.push(0);
  }
  for (let i = 0; i < hclen; i++) {
    codeLengths[CODE_LENGTH_ORDER[i]] = reader.bits(3);
  }
  const codeLengthTree: Huffman = Huffman.build(codeLengths, 19);

  const lengths: number[] = [];
  const total: number = hlit + hdist;
  while (lengths.length < total) {
    const symbol: number = codeLengthTree.decode(reader);
    if (symbol < 16) {
      lengths.push(symbol);
      continue;
    }
    let repeat: number = 0;
    let value: number = 0;
    if (symbol === 16) {
      if (lengths.length === 0) {
        throw new DeflateError('重复码长度缺少前值');
      }
      value = lengths[lengths.length - 1];
      repeat = 3 + reader.bits(2);
    } else if (symbol === 17) {
      value = 0;
      repeat = 3 + reader.bits(3);
    } else {
      value = 0;
      repeat = 11 + reader.bits(7);
    }
    for (let i = 0; i < repeat; i++) {
      lengths.push(value);
    }
  }
  if (lengths.length !== total) {
    throw new DeflateError('码长度数量不匹配');
  }

  const literalLengths: number[] = lengths.slice(0, hlit);
  const distanceLengths: number[] = lengths.slice(hlit, total);
  if (literalLengths[256] === 0) {
    throw new DeflateError('缺少块结束符');
  }
  return [
    Huffman.build(literalLengths, hlit),
    Huffman.build(distanceLengths, hdist)
  ];
}

/**
 * Decode a raw DEFLATE stream (no zlib / gzip wrapper).
 *
 * @param input compressed bytes
 * @param maxOutput hard ceiling on decoded size
 * @param expectedSize when known from the archive directory, used to abort
 *        early instead of allocating the full malicious payload
 */
export function inflateRaw(input: Uint8Array, maxOutput: number = DEFAULT_MAX_OUTPUT,
  expectedSize: number = -1): InflateResult {
  if (expectedSize > maxOutput) {
    return {
      ok: false,
      data: new Uint8Array(0),
      error: `声明解压大小 ${expectedSize} 字节超过上限`,
      truncated: true
    };
  }
  const output: OutputBuffer = new OutputBuffer(maxOutput);
  const reader: BitReader = new BitReader(input);

  try {
    let final: number = 0;
    do {
      final = reader.bits(1);
      const type: number = reader.bits(2);

      if (type === 0) {
        reader.alignToByte();
        const len: number = reader.readUint16LE();
        const nlen: number = reader.readUint16LE();
        if ((len ^ 0xFFFF) !== nlen) {
          throw new DeflateError('存储块长度校验失败');
        }
        for (let i = 0; i < len; i++) {
          output.pushByte(reader.readByte());
        }
      } else if (type === 1 || type === 2) {
        const tables: Huffman[] = type === 1 ? fixedTables() : dynamicTables(reader);
        const literalTree: Huffman = tables[0];
        const distanceTree: Huffman = tables[1];
        while (true) {
          const symbol: number = literalTree.decode(reader);
          if (symbol < 256) {
            output.pushByte(symbol);
            continue;
          }
          if (symbol === 256) {
            break;
          }
          const lengthIndex: number = symbol - 257;
          if (lengthIndex < 0 || lengthIndex >= LENGTH_BASE.length) {
            throw new DeflateError('非法长度码');
          }
          const matchLength: number =
            LENGTH_BASE[lengthIndex] + reader.bits(LENGTH_EXTRA[lengthIndex]);

          const distanceSymbol: number = distanceTree.decode(reader);
          if (distanceSymbol >= DIST_BASE.length) {
            throw new DeflateError('非法距离码');
          }
          const distance: number =
            DIST_BASE[distanceSymbol] + reader.bits(DIST_EXTRA[distanceSymbol]);
          output.copyBack(distance, matchLength);
        }
      } else {
        throw new DeflateError('未知的块类型');
      }
    } while (final === 0);
  } catch (error) {
    const typed: Error = error as Error;
    return {
      ok: false,
      data: output.toUint8Array(),
      error: typed.message !== undefined ? typed.message : '解压失败',
      truncated: output.truncated
    };
  }

  return {
    ok: true,
    data: output.toUint8Array(),
    error: '',
    truncated: false
  };
}
