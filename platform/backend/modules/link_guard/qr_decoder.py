from io import BytesIO

from PIL import Image, UnidentifiedImageError


def decode_qr_image(content: bytes, max_pixels: int) -> list[str]:
    """Decode QR payloads locally without contacting any decoded URL."""
    try:
        with Image.open(BytesIO(content)) as image:
            image.verify()
        with Image.open(BytesIO(content)) as image:
            if image.width * image.height > max_pixels:
                raise ValueError("图片像素尺寸过大，请压缩后重试。")
    except (Image.DecompressionBombError, UnidentifiedImageError, OSError) as exc:
        raise ValueError("二维码图片无法识别。") from exc

    try:
        import cv2
        import numpy as np

        image = cv2.imdecode(np.frombuffer(content, dtype=np.uint8), cv2.IMREAD_COLOR)
        if image is None:
            raise ValueError("二维码图片无法识别。")

        detector = cv2.QRCodeDetector()
        decoded: list[str] = []
        try:
            detected, values, _points, _straight = detector.detectAndDecodeMulti(image)
            if detected:
                decoded.extend(value.strip() for value in values if value and value.strip())
        except (AttributeError, cv2.error):
            pass

        if not decoded:
            value, _points, _straight = detector.detectAndDecode(image)
            if value and value.strip():
                decoded.append(value.strip())
        if not decoded:
            # Screenshots and generated QR codes sometimes omit the required quiet zone.
            # Upscaling tiny images and adding a white border improves decoding without altering the payload.
            scale = max(1, min(8, 160 // max(1, min(image.shape[:2]))))
            enlarged = cv2.resize(image, None, fx=scale, fy=scale, interpolation=cv2.INTER_NEAREST)
            border = 4 * scale
            bordered = cv2.copyMakeBorder(
                enlarged, border, border, border, border, cv2.BORDER_CONSTANT, value=(255, 255, 255)
            )
            value, _points, _straight = detector.detectAndDecode(bordered)
            if value and value.strip():
                decoded.append(value.strip())
        return list(dict.fromkeys(decoded))
    except ImportError as exc:
        raise RuntimeError("本地二维码引擎未安装。") from exc
