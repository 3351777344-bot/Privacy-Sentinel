import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';

import App from './App';

describe('App navigation', () => {
  afterEach(() => vi.unstubAllGlobals());

  function mockFetch() {
    vi.stubGlobal('fetch', vi.fn((url: string) => {
      if (url.includes('/api/history') && !url.includes('module-averages')) {
        return Promise.resolve({ ok: true, json: async () => ({ records: [], total: 0, offset: 0, limit: 100 }) });
      }
      if (url.includes('/api/history/module-averages')) {
        return Promise.resolve({ ok: true, json: async () => ({}) });
      }
      return Promise.resolve({ ok: true, json: async () => [] });
    }));
  }

  it('navigates into a tool page and back to the dashboard', async () => {
    mockFetch();
    const user = userEvent.setup();
    render(<App />);

    expect(screen.getByRole('heading', { name: '安全中心', level: 1 })).not.toBeNull();
    await user.click(screen.getByRole('button', { name: 'Link Guard 链接卫士' }));
    expect(screen.getByRole('heading', { name: 'Link Guard 链接卫士', level: 1 })).not.toBeNull();

    await user.click(screen.getByRole('button', { name: '返回安全中心' }));
    expect(screen.getByRole('heading', { name: '安全中心', level: 1 })).not.toBeNull();
  });
});
