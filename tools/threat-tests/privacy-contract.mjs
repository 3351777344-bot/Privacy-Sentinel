import assert from 'node:assert/strict';
import fs from 'node:fs';

const built = new URL('./.build/', import.meta.url);
const { TransferSession, ScanPolicy } = await import(new URL('services/ScanPolicy.ts', built));
const { QrRules } = await import(new URL('services/QrRules.ts', built));
const { PixelMask } = await import(new URL('services/PixelMask.ts', built));
const { ArchiveReview } = await import(new URL('services/ArchiveReview.ts', built));
const { ThreatScanner } = await import(new URL('services/ThreatScanner.ts', built));

let consent = 0;
let sent = 0;
const local = new TransferSession('local_only');
await assert.rejects(local.run(async () => { consent++; }, async () => { sent++; return 1; }));
assert.equal(consent, 0);
assert.equal(sent, 0);
assert.equal(local.state, 'not_sent');

const rejected = new TransferSession('hybrid');
await assert.rejects(rejected.run(async () => { consent++; throw new Error('reject'); }, async () => { sent++; return 1; }));
assert.equal(rejected.state, 'rejected');
assert.equal(sent, 0);

const failed = new TransferSession('online');
await assert.rejects(failed.run(async () => { consent++; }, async () => { sent++; throw new Error('timeout'); }));
assert.equal(failed.state, 'failed');
assert.equal(sent, 1);
assert.match(failed.describe(), /可能已到达/);
await assert.rejects(failed.run(async () => {}, async () => 1), /重新授权/);

const ok = new TransferSession('hybrid');
assert.equal(await ok.run(async () => { consent++; }, async () => { sent++; return 7; }), 7);
assert.equal(ok.state, 'sent');
assert.equal(sent, 2);

const raw = 'https://example.com/login?token=secret123&next=%2Fpay';
const qr = QrRules.analyze([
  { payload: raw, rect: { left: 1, top: 1, right: 2, bottom: 2 } },
  { payload: 'https://safe.example/path', rect: { left: 0, top: 0, right: 1, bottom: 1 } }
]);
assert.equal(qr.status, 'decoded');
assert.equal(qr.codes.length, 2);
assert.equal(qr.codes[0].url, raw);
assert.ok(!qr.codes[0].text.includes('secret123'));
assert.equal(qr.uploadBlocked, true);
assert.equal(QrRules.analyze([]).status, 'not_found');
assert.equal(QrRules.analyze([], true).status, 'failed');

const pixels = new Uint8Array(4 * 4 * 4).fill(255);
PixelMask.apply(pixels, 4, 4, [{ left: 1, top: 1, right: 2, bottom: 2 }]);
for (let i = 0; i < pixels.length; i += 4) {
  assert.deepEqual(Array.from(pixels.slice(i, i + 4)), [0, 0, 0, 255]);
}
const original = new Uint8Array(16).fill(9);
assert.throws(() => PixelMask.apply(original, 2, 2, [{ left: -1, top: 0, right: 1, bottom: 1 }]));
assert.deepEqual(Array.from(original), new Array(16).fill(9));

function inspect(name) {
  const bytes = new Uint8Array(fs.readFileSync(new URL(`fixtures/${name}`, import.meta.url)));
  return ArchiveReview.inspect(bytes, ThreatScanner.scanFile(name, bytes));
}
const normal = inspect('normal.zip');
assert.equal(normal.canEnhance, true);
assert.ok(normal.fileCount > 0);
function zipWithName(name) {
  const n = Buffer.from(name);
  const local = Buffer.alloc(30 + n.length);
  local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(n.length, 26); n.copy(local, 30);
  const central = Buffer.alloc(46 + n.length);
  central.writeUInt32LE(0x02014b50, 0); central.writeUInt16LE(n.length, 28); n.copy(central, 46);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(1, 8); end.writeUInt16LE(1, 10);
  end.writeUInt32LE(central.length, 12); end.writeUInt32LE(local.length, 16);
  return new Uint8Array(Buffer.concat([local, central, end]));
}
const secretZip = zipWithName('private/.env');
const sensitive = ArchiveReview.inspect(secretZip, ThreatScanner.scanFile('secrets.zip', secretZip));
assert.ok(sensitive.sensitiveFiles.length > 0);
assert.ok(!sensitive.summary.includes(sensitive.sensitiveFiles[0]));
assert.match(ArchiveReview.describe(sensitive), /不发送原ZIP、路径、源码或凭据/);

assert.equal(ScanPolicy.score([{ title: '', evidence: '', suggestion: '', riskLevel: 'high' }]), 72);
const sourceRoot = new URL('../../platform/harmony/entry/src/main/ets/', import.meta.url);
const readSource = name => fs.readFileSync(new URL(name, sourceRoot), 'utf8');
const shareSource = readSource('pages/ShareCheckPage.ets');
assert.ok(!shareSource.includes('本次仅检测第一个'));
assert.ok(shareSource.includes('for (let index = 0; index < total; index++)'));
assert.ok(!shareSource.includes('decodeImage'));
assert.ok(!readSource('pages/DocPage.ets').includes('if (!enhance)'));
assert.ok(readSource('pages/LinkPage.ets').includes('private rawQrUrls: string[]'));
console.log('Harmony privacy contracts: 40 assertions passed.');
