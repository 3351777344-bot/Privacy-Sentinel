from PIL import Image

from detector import privacy_detector
from detector.privacy_detector import findings_from_ocr
from detector.privacy_detector import _detect_qr_codes
from detector.privacy_detector import _run_ocr


BOX = [[10, 10], [300, 10], [300, 50], [10, 50]]


class _FakeOcrOutput:
    """Mimics rapidocr 3.x `RapidOCROutput`.

    The attributes are deliberately tuples/an ndarray and the object is *not*
    subscriptable, which is what the old tuple-style parser tripped over.
    """

    def __init__(self, txts, boxes, scores) -> None:
        self.txts = txts
        self.boxes = boxes
        self.scores = scores


def _install_fake_engine(monkeypatch, output) -> None:
    monkeypatch.setattr(privacy_detector, "_ocr_engine", lambda: (lambda _input: output))


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


def test_ocr_engine_uses_the_rapidocr_v3_module() -> None:
    """The engine must come from `rapidocr` 3.x, not `rapidocr_onnxruntime` (2.x).

    A regression here silently disables all OCR: the ImportError is swallowed by
    the caller and the image pipeline degrades to QR-only detection.
    """
    import importlib.util

    assert importlib.util.find_spec("rapidocr") is not None

    built: list[bool] = []

    def _fake_rapid_ocr() -> object:
        built.append(True)
        return object()

    import builtins

    real_import = builtins.__import__

    def _guarded_import(name, *args, **kwargs):
        if name == "rapidocr_onnxruntime":
            raise AssertionError("privacy_detector must not import rapidocr_onnxruntime")
        return real_import(name, *args, **kwargs)

    privacy_detector._ocr_engine.cache_clear()
    builtins.__import__ = _guarded_import
    try:
        import rapidocr

        original = rapidocr.RapidOCR
        rapidocr.RapidOCR = _fake_rapid_ocr
        try:
            privacy_detector._ocr_engine()
        finally:
            rapidocr.RapidOCR = original
    finally:
        builtins.__import__ = real_import
        privacy_detector._ocr_engine.cache_clear()

    assert built == [True]


def test_run_ocr_parses_rapidocr_v3_output(monkeypatch, tmp_path) -> None:
    """`_run_ocr` must read the v3 attribute-based output shape."""
    import numpy as np

    image_path = tmp_path / "sample.png"
    Image.new("RGB", (400, 200), "white").save(image_path)

    boxes = np.array([[[10.0, 20.0], [110.0, 20.0], [110.0, 60.0], [10.0, 60.0]]], dtype=np.float32)
    _install_fake_engine(
        monkeypatch,
        _FakeOcrOutput(txts=("手机号：13812345678",), boxes=boxes, scores=(0.98,)),
    )

    texts, out_boxes, scores = _run_ocr(str(image_path), 400, 200)

    assert texts == ["手机号：13812345678"]
    assert scores == [0.98]
    assert len(out_boxes) == 1
    assert np.asarray(out_boxes[0]).shape == (4, 2)


def test_run_ocr_returns_empty_lists_when_nothing_detected(monkeypatch, tmp_path) -> None:
    """rapidocr reports an empty result as None for all three fields."""
    image_path = tmp_path / "blank.png"
    Image.new("RGB", (320, 160), "white").save(image_path)

    _install_fake_engine(monkeypatch, _FakeOcrOutput(txts=None, boxes=None, scores=None))

    assert _run_ocr(str(image_path), 320, 160) == ([], [], [])


def test_run_ocr_skips_blank_text_and_missing_boxes(monkeypatch, tmp_path) -> None:
    import numpy as np

    image_path = tmp_path / "blank_rows.png"
    Image.new("RGB", (400, 200), "white").save(image_path)

    boxes = np.array(
        [
            [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]],
            [[10.0, 20.0], [110.0, 20.0], [110.0, 60.0], [10.0, 60.0]],
        ],
        dtype=np.float32,
    )
    _install_fake_engine(
        monkeypatch,
        _FakeOcrOutput(txts=("   ", "13812345678"), boxes=boxes, scores=(0.99, 0.97)),
    )

    texts, _boxes, scores = _run_ocr(str(image_path), 400, 200)

    assert texts == ["13812345678"]
    assert scores == [0.97]


def test_run_ocr_maps_downscaled_boxes_back_to_original_space(monkeypatch, tmp_path) -> None:
    """Large images are downscaled for speed, so points must be scaled back up."""
    import numpy as np

    image_path = tmp_path / "wide.png"
    Image.new("RGB", (3200, 800), "white").save(image_path)

    boxes = np.array([[[10.0, 10.0], [110.0, 10.0], [110.0, 40.0], [10.0, 40.0]]], dtype=np.float32)
    _install_fake_engine(
        monkeypatch,
        _FakeOcrOutput(txts=("13812345678",), boxes=boxes, scores=(0.99,)),
    )

    _texts, out_boxes, _scores = _run_ocr(str(image_path), 3200, 800)

    scale = 1600 / 3200
    mapped = np.asarray(out_boxes[0])
    # Dividing by `scale` halves the downscaled coordinates back to full size.
    assert mapped[0][0] == 10.0 / scale
    assert mapped[2][0] == 110.0 / scale


def test_ocr_failure_is_reported_as_unavailable(monkeypatch, tmp_path) -> None:
    """A broken OCR engine must not pretend the image is clean."""
    image_path = tmp_path / "sample.png"
    Image.new("RGB", (400, 200), "white").save(image_path)

    def _explode(_input):
        raise ImportError("rapidocr_onnxruntime missing")

    monkeypatch.setattr(privacy_detector, "_ocr_engine", lambda: _explode)

    response = privacy_detector.detect_privacy_items(str(image_path), "img_x", "/static/x.png")

    assert response.detectorMode == "unavailable"
    assert response.items == []
    assert "人工复核" in response.summary
