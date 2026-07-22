from detector.privacy_detector import findings_from_ocr
from detector.privacy_detector import _detect_qr_codes


BOX = [[10, 10], [300, 10], [300, 50], [10, 50]]


def test_ocr_privacy_findings_are_located_and_redacted() -> None:
    items = findings_from_ocr(
        ["手机号：13812345678", "邮箱：student@example.edu.cn", "二维码区域示意"],
        [BOX, BOX, [[900, 40], [1100, 40], [1100, 80], [900, 80]]],
        [0.99, 0.95, 0.99],
        1200,
        800,
        "img_000000000000",
    )
    assert [item.type for item in items] == ["phone", "email", "qr_code"]
    assert items[0].text == "138****5678"
    assert items[1].text == "st***@example.edu.cn"
    assert items[2].text == "二维码内容已隐藏"
    assert items[0].box.width > 0
    assert items[2].box.width >= 96
    assert items[2].box.height >= 96


def test_low_confidence_ocr_text_is_ignored() -> None:
    items = findings_from_ocr(
        ["13812345678"], [BOX], [0.2], 400, 200, "img_000000000000"
    )
    assert items == []


def test_qr_detection_supports_unicode_paths(tmp_path) -> None:
    import cv2
    from PIL import Image

    unicode_dir = tmp_path / "中文路径"
    unicode_dir.mkdir()
    image_path = unicode_dir / "qr.png"
    params = cv2.QRCodeEncoder_Params()
    params.version = 2
    encoder = cv2.QRCodeEncoder_create(params)
    qr = encoder.encode("guardianhub-qr-demo")
    Image.fromarray(qr).save(image_path)

    items = _detect_qr_codes(str(image_path), qr.shape[1], qr.shape[0], "img_000000000000")
    assert [item.type for item in items] == ["qr_code"]
