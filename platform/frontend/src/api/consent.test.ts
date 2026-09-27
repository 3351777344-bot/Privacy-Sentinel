import { afterEach, describe, expect, it, vi } from 'vitest';
import { checkLink, analyzeCode, detectImage } from './privacyApi';

afterEach(() => vi.restoreAllMocks());

describe('per-request data transfer consent', () => {
  it('does not send content after rejection', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(false);
    const fetch = vi.spyOn(globalThis, 'fetch');
    await expect(checkLink('https://example.com', 'test')).rejects.toThrow('未授权');
    await expect(analyzeCode('auto', 'secret', 'local')).rejects.toThrow('未授权');
    await expect(detectImage(new File(['x'], 'x.png'), 'local')).rejects.toThrow('未授权');
    expect(fetch).not.toHaveBeenCalled();
  });
  it('sends explicit consent once and does not retry network failure', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true);
    const fetch = vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('offline'));
    await expect(checkLink('https://example.com', 'test')).rejects.toThrow('offline');
    expect(fetch).toHaveBeenCalledTimes(1);
    expect(confirm).toHaveBeenCalledTimes(1);
    const options = fetch.mock.calls[0][1];
    expect(new Headers(options?.headers).get('X-Guardian-Consent')).toBe('explicit');
  });
});
