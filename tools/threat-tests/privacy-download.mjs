import assert from 'node:assert/strict';
import fs from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const root = new URL('../../platform/harmony/entry/src/main/ets/services/', import.meta.url);

// Execute the shipping service methods with only platform boundaries replaced.
function loadService(name, bindings = {}, exportName = name) {
  const source = fs.readFileSync(new URL(`${name}.ets`, root), 'utf8')
    .replace(/^import .*;\r?\n/gm, '')
    .replace(/^export \{.*\} from .*;\r?\n/gm, '')
    .replace(/^export /gm, '');
  return new Function(...Object.keys(bindings), `${stripTypeScriptTypes(source)}\nreturn ${exportName};`)(...Object.values(bindings));
}

const Session = loadService('ScanPolicy', {}, 'TransferSession');

function fixture({ rejectConsent = false, downloadStatus = 200, image = new Uint8Array([137, 80, 78, 71, 0, 255]).buffer } = {}) {
  const calls = [];
  let consent = 0;
  let destroyed = 0;
  const http = {
    RequestMethod: { POST: 'POST', GET: 'GET' },
    HttpDataType: { STRING: 0, ARRAY_BUFFER: 2 },
    createHttp: () => ({
      request: async (url, options) => {
        calls.push({ url, options });
        assert.equal(options.header['X-Guardian-Consent'], 'explicit');
        if (options.method === 'POST') {
          assert.equal(options.header['Content-Type'], 'application/json');
          assert.equal(options.expectDataType, http.HttpDataType.STRING);
          assert.equal(JSON.parse(options.extraData).imageId, 'synthetic-test');
          return { responseCode: 200, result: JSON.stringify({ processedImageUrl: '/static/processed/test.png' }) };
        }
        assert.equal(options.method, 'GET');
        assert.equal(options.expectDataType, http.HttpDataType.ARRAY_BUFFER);
        return { responseCode: downloadStatus, result: image };
      },
      destroy: () => { destroyed++; }
    })
  };
  const api = loadService('GuardianApi', {
    http, TransferSession: Session, API_BASE_URL: 'http://test.invalid',
    NetworkConsent: { require: async () => { consent++; if (rejectConsent) throw new Error('declined'); } }
  });
  const transfer = new Session('online');
  // Image selection + detection already completed under the image's one-time
  // authorization. Masking is a follow-up on that same session.
  transfer.state = rejectConsent ? 'rejected' : 'sent';
  return {
    run: () => api.processAndDownloadImage('synthetic-test', 'black', 'online', transfer),
    calls, transfer, image, consent: () => consent, destroyed: () => destroyed
  };
}

test('mask and download reuse the image consent without prompting again', async () => {
  const f = fixture();
  const result = await f.run();
  assert.equal(result.image, f.image);
  assert.equal(f.calls.length, 2);
  assert.equal(f.calls[1].url, 'http://test.invalid/static/processed/test.png');
  assert.equal(f.consent(), 0);
  assert.equal(f.destroyed(), 2);
  assert.equal(f.transfer.state, 'sent');
});

test('declining consent sends neither request', async () => {
  const f = fixture({ rejectConsent: true });
  await assert.rejects(f.run());
  assert.equal(f.calls.length, 0);
  assert.equal(f.transfer.state, 'rejected');
});

test('download failure preserves HTTP status and never retries', async () => {
  const f = fixture({ downloadStatus: 404 });
  await assert.rejects(f.run(), /HTTP 404/);
  assert.equal(f.calls.length, 2);
  assert.equal(f.destroyed(), 2);
  assert.equal(f.transfer.state, 'failed');
});

test('empty or text image bodies are rejected before caching', async () => {
  for (const image of [new ArrayBuffer(0), 'invalid image']) {
    const f = fixture({ image });
    await assert.rejects(f.run(), /未返回有效的处理图/);
    assert.equal(f.transfer.state, 'failed');
  }
});
