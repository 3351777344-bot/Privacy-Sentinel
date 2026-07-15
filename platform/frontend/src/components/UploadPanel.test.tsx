import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';

import UploadPanel from './UploadPanel';

describe('UploadPanel', () => {
  const onDetect = vi.fn().mockResolvedValue(undefined);

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('renders upload box and detect button', () => {
    render(<UploadPanel loading={false} onDetect={onDetect} />);
    expect(screen.getByText(/点击选择本地图片/)).not.toBeNull();
    expect(screen.getByText('开始隐私检测')).not.toBeNull();
  });

  it('disables detect button when no file selected', () => {
    render(<UploadPanel loading={false} onDetect={onDetect} />);
    const button = screen.getByText('开始隐私检测').closest('button');
    expect(button?.disabled).toBe(true);
  });

  it('shows error for unsupported file type (mismatched MIME)', async () => {
    const user = userEvent.setup();
    render(<UploadPanel loading={false} onDetect={onDetect} />);

    // Use .png extension (passes accept attr) but text/plain MIME (fails type check)
    const file = new File(['content'], 'test.png', { type: 'text/plain' });
    const input = screen.getByLabelText('选择图片文件');
    await user.upload(input, file);

    expect(screen.getByText(/不支持的文件格式/)).not.toBeNull();
    const button = screen.getByText('开始隐私检测').closest('button');
    expect(button?.disabled).toBe(true);
  });

  it('shows error for oversized file', async () => {
    const user = userEvent.setup();
    render(<UploadPanel loading={false} onDetect={onDetect} />);

    // Create a file larger than 10 MB limit with valid image type
    const largeContent = new ArrayBuffer(11 * 1024 * 1024);
    const file = new File([largeContent], 'large.png', { type: 'image/png' });
    const input = screen.getByLabelText('选择图片文件');
    await user.upload(input, file);

    expect(screen.getByText(/超过/)).not.toBeNull();
    const button = screen.getByText('开始隐私检测').closest('button');
    expect(button?.disabled).toBe(true);
  });

  it('clears error when a valid file replaces an invalid one', async () => {
    const user = userEvent.setup();
    render(<UploadPanel loading={false} onDetect={onDetect} />);

    // First upload an invalid file (wrong MIME type)
    const input = screen.getByLabelText('选择图片文件');
    const badFile = new File(['content'], 'test.png', { type: 'text/plain' });
    await user.upload(input, badFile);
    expect(screen.getByText(/不支持的文件格式/)).not.toBeNull();

    // Then upload a valid file
    const goodFile = new File(['valid-content'], 'photo.png', { type: 'image/png' });
    await user.upload(input, goodFile);
    expect(screen.queryByText(/不支持的文件格式/)).toBeNull();
    expect(screen.getByText('photo.png')).not.toBeNull();
  });

  it('enables button when valid file selected', async () => {
    const user = userEvent.setup();
    render(<UploadPanel loading={false} onDetect={onDetect} />);

    const file = new File(['valid-content'], 'photo.jpg', { type: 'image/jpeg' });
    const input = screen.getByLabelText('选择图片文件');
    await user.upload(input, file);

    const button = screen.getByText('开始隐私检测').closest('button');
    expect(button?.disabled).toBe(false);
  });
});
