import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

// Pin the publisher's DER SubjectPublicKeyInfo Ed25519 public key at release.
// Empty means production feeds are disabled; never trust a key in a downloaded feed.
const TRUSTED_PUBLIC_KEY_BASE64: string = '';

export class SignedFeedVerifier {
  static async verify(csv: string, version: string, expiresAt: number, signature: string): Promise<void> {
    if (!TRUSTED_PUBLIC_KEY_BASE64 || !/^\d+$/.test(version) || Number(version) <= 0 ||
      !Number.isSafeInteger(expiresAt) || expiresAt <= Date.now() || csv.length > 2 * 1024 * 1024) {
      throw new Error('情报库未配置可信公钥、已过期或格式无效。');
    }
    const codec = new util.Base64Helper();
    const generator = cryptoFramework.createAsyKeyGenerator('Ed25519');
    const key = await generator.convertKey({ data: codec.decodeSync(TRUSTED_PUBLIC_KEY_BASE64) }, null);
    const verifier = cryptoFramework.createVerify('Ed25519');
    await verifier.init(key.pubKey);
    const data = new util.TextEncoder().encodeInto(`${version}\n${expiresAt}\n${csv}`);
    if (!await verifier.verify({ data: data }, { data: codec.decodeSync(signature) })) {
      throw new Error('情报库签名无效，保留原版本。');
    }
  }
}
