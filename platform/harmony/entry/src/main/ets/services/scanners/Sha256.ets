/**
 * L1 — self-contained SHA-256.
 *
 * Implemented in pure TypeScript rather than through
 * `@ohos.security.cryptoFramework` for three reasons: the digest is needed
 * synchronously inside the scan pipeline, the same implementation runs in the
 * Node test harness (so device and test results are comparable byte for byte),
 * and it removes an async API from the hot path of a file scan.
 */

const K: number[] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

const HEX_TABLE: string = '0123456789abcdef';

function rotr(value: number, shift: number): number {
  return ((value >>> shift) | (value << (32 - shift))) >>> 0;
}

/** Compute the SHA-256 digest of `data` as a lower-case hex string. */
export function sha256Hex(data: Uint8Array): string {
  const h: number[] = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
  ];

  const messageLength: number = data.length;
  // Pad with 0x80, then zeros, then a 64-bit big-endian bit length, so that the
  // total is the *smallest* multiple of 64 that can hold message + 1 + 8 bytes.
  // Using a larger multiple would move the length field and change the digest.
  const blockCount: number = Math.floor((messageLength + 8) / 64) + 1;
  const totalLength: number = blockCount * 64;
  const buffer: Uint8Array = new Uint8Array(totalLength);
  buffer.set(data, 0);
  buffer[messageLength] = 0x80;

  const bitLength: number = messageLength * 8;
  const bitLengthHigh: number = Math.floor(bitLength / 4294967296);
  const bitLengthLow: number = bitLength >>> 0;
  buffer[totalLength - 8] = (bitLengthHigh >>> 24) & 0xFF;
  buffer[totalLength - 7] = (bitLengthHigh >>> 16) & 0xFF;
  buffer[totalLength - 6] = (bitLengthHigh >>> 8) & 0xFF;
  buffer[totalLength - 5] = bitLengthHigh & 0xFF;
  buffer[totalLength - 4] = (bitLengthLow >>> 24) & 0xFF;
  buffer[totalLength - 3] = (bitLengthLow >>> 16) & 0xFF;
  buffer[totalLength - 2] = (bitLengthLow >>> 8) & 0xFF;
  buffer[totalLength - 1] = bitLengthLow & 0xFF;

  const w: number[] = [];
  for (let i = 0; i < 64; i++) {
    w.push(0);
  }

  for (let chunk = 0; chunk < totalLength; chunk += 64) {
    for (let i = 0; i < 16; i++) {
      const offset: number = chunk + i * 4;
      w[i] = ((buffer[offset] << 24) | (buffer[offset + 1] << 16) |
        (buffer[offset + 2] << 8) | buffer[offset + 3]) >>> 0;
    }
    for (let i = 16; i < 64; i++) {
      const s0: number = (rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3)) >>> 0;
      const s1: number = (rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10)) >>> 0;
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }

    let a: number = h[0];
    let b: number = h[1];
    let c: number = h[2];
    let d: number = h[3];
    let e: number = h[4];
    let f: number = h[5];
    let g: number = h[6];
    let hh: number = h[7];

    for (let i = 0; i < 64; i++) {
      const s1: number = (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) >>> 0;
      const ch: number = ((e & f) ^ (~e & g)) >>> 0;
      const temp1: number = (hh + s1 + ch + K[i] + w[i]) >>> 0;
      const s0: number = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) >>> 0;
      const maj: number = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
      const temp2: number = (s0 + maj) >>> 0;

      hh = g;
      g = f;
      f = e;
      e = (d + temp1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) >>> 0;
    }

    h[0] = (h[0] + a) >>> 0;
    h[1] = (h[1] + b) >>> 0;
    h[2] = (h[2] + c) >>> 0;
    h[3] = (h[3] + d) >>> 0;
    h[4] = (h[4] + e) >>> 0;
    h[5] = (h[5] + f) >>> 0;
    h[6] = (h[6] + g) >>> 0;
    h[7] = (h[7] + hh) >>> 0;
  }

  let out: string = '';
  for (let i = 0; i < 8; i++) {
    const value: number = h[i];
    out += HEX_TABLE.charAt((value >>> 28) & 0xF);
    out += HEX_TABLE.charAt((value >>> 24) & 0xF);
    out += HEX_TABLE.charAt((value >>> 20) & 0xF);
    out += HEX_TABLE.charAt((value >>> 16) & 0xF);
    out += HEX_TABLE.charAt((value >>> 12) & 0xF);
    out += HEX_TABLE.charAt((value >>> 8) & 0xF);
    out += HEX_TABLE.charAt((value >>> 4) & 0xF);
    out += HEX_TABLE.charAt(value & 0xF);
  }
  return out;
}
