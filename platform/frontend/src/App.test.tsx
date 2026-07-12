import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';

import App from './App';

describe('App navigation', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('navigates into a tool page and back to the dashboard', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => [] }));
    const user = userEvent.setup();
    render(<App />);

    expect(screen.getByRole('heading', { name: '安全中心', level: 1 })).not.toBeNull();
    await user.click(screen.getByRole('button', { name: 'Link Guard 链接卫士' }));
    expect(screen.getByRole('heading', { name: 'Link Guard 链接卫士', level: 1 })).not.toBeNull();

    await user.click(screen.getByRole('button', { name: '返回安全中心' }));
    expect(screen.getByRole('heading', { name: '安全中心', level: 1 })).not.toBeNull();
  });
});
