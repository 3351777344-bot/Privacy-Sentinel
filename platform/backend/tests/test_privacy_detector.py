from detector.privacy_detector import findings_from_ocr


BOX = [[10, 10], [300, 10], [300, 50], [10, 50]]


def test_ocr_privacy_findings_are_located_and_redacted() -> None:
    items = findings_from_ocr(
        ["手机号：13812345678", "邮箱：student@example.edu.cn"],
        [BOX, BOX],
        [0.99, 0.95],
        400,
        200,
        "img_000000000000",
    )
    assert [item.type for item in items] == ["phone", "email"]
    assert items[0].text == "138****5678"
    assert items[1].text == "st***@example.edu.cn"
    assert items[0].box.width > 0


def test_low_confidence_ocr_text_is_ignored() -> None:
    items = findings_from_ocr(
        ["13812345678"], [BOX], [0.2], 400, 200, "img_000000000000"
    )
    assert items == []
