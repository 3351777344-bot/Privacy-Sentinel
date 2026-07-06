import { useEffect, useRef, useState } from 'react';
import type { PrivacyItem } from '../types/privacy';
import { riskText } from './RiskSummary';

interface ImagePreviewProps {
  imageUrl?: string;
  items?: PrivacyItem[];
  title: string;
  emptyText: string;
}

export default function ImagePreview({ imageUrl, items = [], title, emptyText }: ImagePreviewProps) {
  const imageRef = useRef<HTMLImageElement>(null);
  const [size, setSize] = useState({ width: 0, height: 0, naturalWidth: 1, naturalHeight: 1 });

  useEffect(() => {
    const image = imageRef.current;
    if (!image) return;

    const syncSize = () => {
      setSize({
        width: image.clientWidth,
        height: image.clientHeight,
        naturalWidth: image.naturalWidth || 1,
        naturalHeight: image.naturalHeight || 1
      });
    };

    syncSize();
    const observer = new ResizeObserver(syncSize);
    observer.observe(image);
    return () => observer.disconnect();
  }, [imageUrl]);

  const scaleX = size.width / size.naturalWidth;
  const scaleY = size.height / size.naturalHeight;

  return (
    <section className="card image-card">
      <div className="section-title">
        <span>02</span>
        <div>
          <h3>{title}</h3>
          <p>敏感区域会随图片显示比例同步缩放。</p>
        </div>
      </div>
      {imageUrl ? (
        <div className="image-stage">
          <img
            ref={imageRef}
            src={imageUrl}
            alt="待检测图片"
            onLoad={() => {
              const image = imageRef.current;
              if (!image) return;
              setSize({
                width: image.clientWidth,
                height: image.clientHeight,
                naturalWidth: image.naturalWidth || 1,
                naturalHeight: image.naturalHeight || 1
              });
            }}
          />
          {items.map((item) => (
            <div
              className={`detect-box ${item.riskLevel}`}
              key={item.id}
              style={{
                left: item.box.x * scaleX,
                top: item.box.y * scaleY,
                width: item.box.width * scaleX,
                height: item.box.height * scaleY
              }}
            >
              <span>{item.label} · {riskText[item.riskLevel]}</span>
            </div>
          ))}
        </div>
      ) : (
        <div className="empty-preview">
          <div className="mock-screen">
            <span className="mock-line wide" />
            <span className="mock-line" />
            <span className="mock-line short" />
            <span className="mock-qr" />
          </div>
          <p>{emptyText}</p>
        </div>
      )}
    </section>
  );
}
