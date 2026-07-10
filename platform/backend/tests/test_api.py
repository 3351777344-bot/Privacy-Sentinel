from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image

import main
from modules.risk_scoring import calculate_security_score
from schemas.models import DetectResponse
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
    uploads.mkdir()
    processed.mkdir()
    monkeypatch.setattr(main, "UPLOAD_DIR", uploads)
    monkeypatch.setattr(main, "PROCESSED_DIR", processed)
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


def test_non_privacy_history_can_be_persisted(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(main, "history_store", HistoryStore(tmp_path / "history.db"))
    response = client.post(
        "/api/history",
        json={"module": "code", "riskLevel": "medium", "score": 76, "summary": "发现一项待复核问题。"},
    )
    assert response.status_code == 200
    assert response.json()["module"] == "code"
    assert client.get("/api/history").json()[0]["module"] == "code"
