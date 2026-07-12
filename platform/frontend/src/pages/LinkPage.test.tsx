import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';

import LinkPage from './LinkPage';

function renderPage(overrides: Partial<Parameters<typeof LinkPage>[0]> = {}) {
  const props: Parameters<typeof LinkPage>[0] = {
    url: '',
    source: '其他',
    qrFile: null,
    qrMessage: '',
    result: null,
    loading: false,
    loadingQr: false,
    onBack: vi.fn(),
    onUrlChange: vi.fn(),
    onSourceChange: vi.fn(),
    onQrUpload: vi.fn().mockResolvedValue(undefined),
    onCheck: vi.fn().mockResolvedValue(undefined),
    ...overrides
  };
  return { props, ...render(<LinkPage {...props} />) };
}

describe('LinkPage', () => {
  it('keeps checking disabled until a URL is present', () => {
    renderPage();
    expect((screen.getByRole('button', { name: '开始链接安全体检' }) as HTMLButtonElement).disabled).toBe(true);
  });

  it('submits a populated link', async () => {
    const onCheck = vi.fn().mockResolvedValue(undefined);
    renderPage({ url: 'https://example.com', onCheck });
    await userEvent.setup().click(screen.getByRole('button', { name: '开始链接安全体检' }));
    expect(onCheck).toHaveBeenCalledOnce();
  });

  it('passes a selected QR image to the local decoder handler', async () => {
    const onQrUpload = vi.fn().mockResolvedValue(undefined);
    renderPage({ onQrUpload });
    const file = new File(['image'], 'qr.png', { type: 'image/png' });
    await userEvent.setup().upload(screen.getByLabelText('二维码图片'), file);
    expect(onQrUpload).toHaveBeenCalledWith(file);
  });
});
