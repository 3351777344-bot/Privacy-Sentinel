from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image

import main
from modules.risk_scoring import calculate_security_score
from schemas.models import Box, DetectResponse, PrivacyItem
from storage.history_store import HistoryStore


client = TestClient(main.app)


def test_health_and_code_auto_detection() -> None:
    assert client.get("/api/health").status_code == 200
    response = client.post("/api/code/analyze", json={"language": "auto", "code": "def hello():\n    return True"})
    assert response.status_code == 200
    assert response.json()["language"] == "python"


def test_invalid_image_is_rejected() -> None:
    response = client.post("/api/detect", files={"file": ("fake.png", b"not an image", "image/png")})
    assert response.status_code == 400


def test_valid_image_uses_detector_and_persists_history(tmp_path, monkeypatch) -> None:
    uploads = tmp_path / "uploads"
    processed = tmp_path / "processed"
    detections = tmp_path / "detections"
    uploads.mkdir()
    processed.mkdir()
    detections.mkdir()
    monkeypatch.setattr(main, "UPLOAD_DIR", uploads)
    monkeypatch.setattr(main, "PROCESSED_DIR", processed)
    monkeypatch.setattr(main, "DETECTION_DIR", detections)
    monkeypatch.setattr(main, "history_store", HistoryStore(tmp_path / "history.db"))

    def fake_detector(path: str, image_id: str, original_url: str) -> DetectResponse:
        return DetectResponse(
            imageId=image_id,
            originalImageUrl=original_url,
            riskLevel="low",
            score=calculate_security_score([]),
            summary="测试图片未发现风险。",
            detectorMode="ocr",
            detectorMessage="测试检测器",
            items=[],
        )

    monkeypatch.setattr(main, "detect_privacy_items", fake_detector)
    buffer = BytesIO()
    Image.new("RGB", (100, 80), "white").save(buffer, format="PNG")
    response = client.post("/api/detect", files={"file": ("image.png", buffer.getvalue(), "image/png")})
    assert response.status_code == 200
    assert response.json()["detectorMode"] == "ocr"
    assert len(main.history_store.list()) == 1
    assert len(list(detections.glob("img_*.json"))) == 1


def test_privacy_process_uses_stored_detection_items(tmp_path, monkeypatch) -> None:
    uploads = tmp_path / "uploads"
    processed = tmp_path / "processed"
    detections = tmp_path / "detections"
    uploads.mkdir()
    processed.mkdir()
    detections.mkdir()
    monkeypatch.setattr(main, "UPLOAD_DIR", uploads)
    monkeypatch.setattr(main, "PROCESSED_DIR", processed)
    monkeypatch.setattr(main, "DETECTION_DIR", detections)
    monkeypatch.setattr(main, "history_store", HistoryStore(tmp_path / "history.db"))

    image_id = "img_000000000000"
    buffer = BytesIO()
    Image.new("RGB", (100, 80), "white").save(buffer, format="PNG")
    (uploads / f"{image_id}.png").write_bytes(buffer.getvalue())

    result = DetectResponse(
        imageId=image_id,
        originalImageUrl=f"/static/uploads/{image_id}.png",
        riskLevel="high",
        score=75,
        summary="test",
        detectorMode="agent",
        detectorMessage="local agent",
        items=[
            PrivacyItem(
                id=f"{image_id}_phone_1",
                type="phone",
                label="phone",
                text="138****5678",
                riskLevel="high",
                box=Box(x=5, y=5, width=30, height=20),
                suggestion="mask it",
            )
        ],
    )
    main._save_detection_result(result)

    response = client.post(
        "/api/privacy/process",
        json={"imageId": image_id, "scope": "high", "maskType": "black"},
    )
    assert response.status_code == 200
    assert response.json()["processedImageUrl"].endswith(f"{image_id}_safe.png")
    assert (processed / f"{image_id}_safe.png").exists()


def test_non_privacy_history_can_be_persisted(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(main, "history_store", HistoryStore(tmp_path / "history.db"))
    response = client.post(
        "/api/history",
        json={"module": "code", "riskLevel": "medium", "score": 76, "summary": "发现一项待复核问题。"},
    )
    assert response.status_code == 200
    assert response.json()["module"] == "code"
    assert client.get("/api/history").json()[0]["module"] == "code"
