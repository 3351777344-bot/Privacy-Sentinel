import json
import shutil
import uuid
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from PIL import Image, UnidentifiedImageError

from detector.mock_detector import detect_privacy_items
from image_processor.blur import apply_blur_mask
from image_processor.mask import apply_black_mask
from image_processor.mosaic import apply_mosaic_mask
from schemas.models import DetectResponse, HistoryRecord, MaskRequest, MaskResponse


BASE_DIR = Path(__file__).resolve().parent
UPLOAD_DIR = BASE_DIR / "static" / "uploads"
PROCESSED_DIR = BASE_DIR / "static" / "processed"
HISTORY_FILE = BASE_DIR / "data" / "history.json"

for directory in [UPLOAD_DIR, PROCESSED_DIR, HISTORY_FILE.parent]:
    directory.mkdir(parents=True, exist_ok=True)
if not HISTORY_FILE.exists():
    HISTORY_FILE.write_text("[]", encoding="utf-8")

app = FastAPI(title="Privacy Sentinel API", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.mount("/static", StaticFiles(directory=BASE_DIR / "static"), name="static")


def _load_history() -> list[dict]:
    try:
        return json.loads(HISTORY_FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []


def _save_history(records: list[dict]) -> None:
    HISTORY_FILE.write_text(json.dumps(records[:20], ensure_ascii=False, indent=2), encoding="utf-8")


def _append_history(record: HistoryRecord) -> None:
    records = _load_history()
    records.insert(0, record.model_dump())
    _save_history(records)


def _update_processed_history(image_id: str, processed_url: str) -> None:
    records = _load_history()
    for record in records:
        if record.get("imageId") == image_id:
            record["processedImageUrl"] = processed_url
            record["status"] = "已处理"
            break
    _save_history(records)


def _find_uploaded_image(image_id: str) -> Path:
    matches = list(UPLOAD_DIR.glob(f"{image_id}.*"))
    if not matches:
        raise HTTPException(status_code=404, detail="未找到对应图片，请先完成检测。")
    return matches[0]


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok", "message": "Privacy Sentinel backend is running"}


@app.post("/api/detect", response_model=DetectResponse)
async def detect(file: UploadFile = File(...)) -> DetectResponse:
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="请上传图片文件。")

    extension = Path(file.filename or "upload.png").suffix.lower() or ".png"
    image_id = f"img_{uuid.uuid4().hex[:12]}"
    saved_path = UPLOAD_DIR / f"{image_id}{extension}"

    with saved_path.open("wb") as target:
        shutil.copyfileobj(file.file, target)

    try:
        with Image.open(saved_path) as image:
            image.verify()
    except (UnidentifiedImageError, OSError):
        saved_path.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail="图片无法识别，请更换 PNG/JPG 等常见格式。")

    original_url = f"/static/uploads/{saved_path.name}"
    result = detect_privacy_items(str(saved_path), image_id, original_url)
    _append_history(
        HistoryRecord(
            imageId=image_id,
            originalImageUrl=original_url,
            processedImageUrl=None,
            riskLevel=result.riskLevel,
            summary=result.summary,
            createdAt=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            status="待处理",
        )
    )
    return result


@app.post("/api/mask", response_model=MaskResponse)
def mask_image(request: MaskRequest) -> MaskResponse:
    if request.maskType not in {"black", "blur", "mosaic"}:
        raise HTTPException(status_code=400, detail="maskType 仅支持 black、blur、mosaic。")
    if not request.items:
        raise HTTPException(status_code=400, detail="请至少选择一个需要处理的隐私区域。")

    image_path = _find_uploaded_image(request.imageId)
    with Image.open(image_path) as image:
        if request.maskType == "black":
            output = apply_black_mask(image, request.items)
        elif request.maskType == "blur":
            output = apply_blur_mask(image, request.items)
        else:
            output = apply_mosaic_mask(image, request.items)

    processed_name = f"{request.imageId}_safe.png"
    processed_path = PROCESSED_DIR / processed_name
    output.save(processed_path, format="PNG")

    processed_url = f"/static/processed/{processed_name}"
    _update_processed_history(request.imageId, processed_url)
    return MaskResponse(processedImageUrl=processed_url, message="已完成安全处理。")


@app.get("/api/history", response_model=list[HistoryRecord])
def history() -> list[HistoryRecord]:
    return [HistoryRecord(**record) for record in _load_history()]
