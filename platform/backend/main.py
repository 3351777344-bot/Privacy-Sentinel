import json
import logging
import re
import uuid
import zipfile
from datetime import datetime, timedelta
from io import BytesIO
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, Query, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, Response
from fastapi.staticfiles import StaticFiles
from PIL import Image, UnidentifiedImageError

from config import settings
from detector.privacy_agent import detect_privacy_items
from image_processor.blur import apply_blur_mask
from image_processor.mask import apply_black_mask
from image_processor.mosaic import apply_mosaic_mask
from modules.code_guardian.analyzer import analyze_code as run_code_guardian
from modules.doc_shield.completeness_checker import check_completeness
from modules.doc_shield.file_extractor import extract_file
from modules.doc_shield.format_checker import check_format
from modules.doc_shield.privacy_checker import check_privacy
from modules.doc_shield.report_generator import generate_report
from modules.doc_shield.requirement_parser import parse_requirement
from modules.link_guard.analyzer import analyze_link as run_link_guard
from modules.link_guard.qr_decoder import decode_qr_image
from schemas.models import (
    CodeAnalyzeResponse,
    CodeFixRequest,
    CodeFixResponse,
    DetectResponse,
    DocCheckResponse,
    HistoryRecord,
    HistoryCreate,
    LinkCheckRequest,
    LinkCheckResponse,
    MaskRequest,
    MaskResponse,
    PrivacyProcessRequest,
    QrDecodeResponse,
)
from storage.history_store import HistoryStore


BASE_DIR = Path(__file__).resolve().parent
logger = logging.getLogger("guardianhub")
UPLOAD_DIR = BASE_DIR / "static" / "uploads"
PROCESSED_DIR = BASE_DIR / "static" / "processed"
DETECTION_DIR = BASE_DIR / "data" / "detections"
HISTORY_FILE = BASE_DIR / "data" / "history.json"
HISTORY_DATABASE = BASE_DIR / "data" / "guardianhub.db"

for directory in [UPLOAD_DIR, PROCESSED_DIR, DETECTION_DIR, HISTORY_DATABASE.parent]:
    directory.mkdir(parents=True, exist_ok=True)
history_store = HistoryStore(HISTORY_DATABASE, HISTORY_FILE)
Image.MAX_IMAGE_PIXELS = settings.max_image_pixels

app = FastAPI(title="GuardianHub API", version="0.5.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=list(settings.cors_origins),
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.mount("/static", StaticFiles(directory=BASE_DIR / "static"), name="static")


def _append_history(record: HistoryRecord, result_json: str | None = None) -> None:
    data = record.model_dump()
    if result_json is not None:
        data["resultJson"] = result_json
    if record.score == 100:
        data["processed"] = True
        data["processedScore"] = 100
        data["status"] = "已处理"
    history_store.add(data)


def _append_analysis_history(module: str, risk_level: str, score: int, summary: str, result_json: str | None = None) -> None:
    data: dict[str, object] = {
        "module": module,
        "riskLevel": risk_level,
        "score": score,
        "summary": summary,
        "status": "已生成报告",
        "createdAt": datetime.now().astimezone().isoformat(timespec="seconds"),
    }
    if result_json is not None:
        data["resultJson"] = result_json
    if score == 100:
        data["processed"] = True
        data["processedScore"] = 100
        data["status"] = "已处理"
    history_store.add(data)


def _update_processed_history(image_id: str, processed_url: str, processed_score: int | None = None) -> None:
    history_store.update_processed(image_id, processed_url, processed_score)


async def _read_upload_limited(file: UploadFile, max_bytes: int) -> bytes:
    chunks: list[bytes] = []
    total = 0
    while chunk := await file.read(min(1024 * 1024, max_bytes + 1 - total)):
        total += len(chunk)
        if total > max_bytes:
            raise HTTPException(status_code=413, detail=f"文件过大，最大允许 {max_bytes // (1024 * 1024)} MB。")
        chunks.append(chunk)
    return b"".join(chunks)


def _cleanup_expired_files() -> None:
    if settings.retention_hours <= 0:
        return
    cutoff = datetime.now().timestamp() - timedelta(hours=settings.retention_hours).total_seconds()
    for directory in (UPLOAD_DIR, PROCESSED_DIR):
        for path in directory.iterdir():
            if path.is_file() and path.name != ".gitkeep" and path.stat().st_mtime < cutoff:
                path.unlink(missing_ok=True)
    for path in DETECTION_DIR.iterdir():
        if path.is_file() and path.stat().st_mtime < cutoff:
            path.unlink(missing_ok=True)
    history_store.delete_expired(settings.retention_hours)


def _find_uploaded_image(image_id: str) -> Path:
    matches = list(UPLOAD_DIR.glob(f"{image_id}.*"))
    if not matches:
        raise HTTPException(status_code=404, detail="未找到对应图片，请先完成检测。")
    return matches[0]


def _detection_path(image_id: str) -> Path:
    return DETECTION_DIR / f"{image_id}.json"


def _save_detection_result(result: DetectResponse) -> None:
    _detection_path(result.imageId).write_text(result.model_dump_json(indent=2), encoding="utf-8")


def _load_detection_result(image_id: str) -> DetectResponse:
    path = _detection_path(image_id)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Detection result not found. Please scan the image again.")
    try:
        return DetectResponse(**json.loads(path.read_text(encoding="utf-8")))
    except (json.JSONDecodeError, OSError, ValueError):
        raise HTTPException(status_code=500, detail="Stored detection result is unreadable. Please scan again.")


def _valid_mask_type(mask_type: str | None) -> str:
    if mask_type in {"black", "blur", "mosaic"}:
        return mask_type
    if settings.default_mask_type in {"black", "blur", "mosaic"}:
        return settings.default_mask_type
    return "mosaic"


def _apply_mask(image_id: str, mask_type: str, boxes: list) -> MaskResponse:
    detection = _load_detection_result(image_id)
    total_items = len(detection.items)
    processed_count = len(boxes)
    ratio = min(1.0, processed_count / max(total_items, 1))
    original_score = detection.score
    improvement = int(round((100 - original_score) * ratio * 0.8))
    new_score = min(100, original_score + improvement)

    image_path = _find_uploaded_image(image_id)
    with Image.open(image_path) as image:
        if mask_type == "black":
            output = apply_black_mask(image, boxes)
        elif mask_type == "blur":
            output = apply_blur_mask(image, boxes)
        else:
            output = apply_mosaic_mask(image, boxes)

    processed_name = f"{image_id}_safe.png"
    processed_path = PROCESSED_DIR / processed_name
    output.save(processed_path, format="PNG")

    processed_url = f"/static/processed/{processed_name}"
    _update_processed_history(image_id, processed_url, new_score)
    return MaskResponse(processedImageUrl=processed_url, message=f"处理完成（{processed_count}/{total_items} 项），评分提升：{original_score} → {new_score}")


def _level_from_score(score: int) -> str:
    if score >= 70:
        return "high"
    if score >= 35:
        return "medium"
    return "low"


def _decode_upload(content: bytes) -> str:
    for encoding in ("utf-8", "utf-8-sig", "gb18030"):
        try:
            return content.decode(encoding)
        except UnicodeDecodeError:
            continue
    return content.decode("utf-8", errors="ignore")


def _validate_document_upload(file_name: str, content: bytes) -> None:
    extension = Path(file_name).suffix.lower()
    if not content:
        raise HTTPException(status_code=400, detail=f"材料文件为空：{file_name}。")
    if extension == ".pdf" and not content.startswith(b"%PDF-"):
        raise HTTPException(status_code=400, detail=f"{file_name} 的内容不是有效 PDF。")
    if extension == ".rar" and not content.startswith((b"Rar!\x1a\x07\x00", b"Rar!\x1a\x07\x01\x00")):
        raise HTTPException(status_code=400, detail=f"{file_name} 的内容不是有效 RAR。")
    if extension == ".ppt" and not content.startswith(b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1"):
        raise HTTPException(status_code=400, detail=f"{file_name} 的内容不是有效 PPT。")
    if extension in {".zip", ".docx", ".pptx"}:
        try:
            with zipfile.ZipFile(BytesIO(content)) as archive:
                names = archive.namelist()
                if len(names) > 5000:
                    raise HTTPException(status_code=400, detail=f"{file_name} 包含过多文件，拒绝处理。")
                if extension == ".docx" and not any(name.startswith("word/") for name in names):
                    raise HTTPException(status_code=400, detail=f"{file_name} 的内容不是有效 DOCX。")
                if extension == ".pptx" and not any(name.startswith("ppt/") for name in names):
                    raise HTTPException(status_code=400, detail=f"{file_name} 的内容不是有效 PPTX。")
        except zipfile.BadZipFile:
            raise HTTPException(status_code=400, detail=f"{file_name} 的压缩结构无效。")
    if extension in {".png", ".jpg", ".jpeg"}:
        try:
            with Image.open(BytesIO(content)) as image:
                image.verify()
        except (Image.DecompressionBombError, UnidentifiedImageError, OSError):
            raise HTTPException(status_code=400, detail=f"{file_name} 的内容不是有效图片。")


@app.get("/api/health")
def health() -> dict[str, str]:
    return {
        "status": "ok",
        "message": "GuardianHub backend is running",
        "privacyDetector": "demo" if settings.demo_mode else settings.privacy_engine,
    }


@app.post("/api/detect", response_model=DetectResponse)
async def detect(
    file: UploadFile = File(...),
    processing_mode: str = Form(default="local"),
) -> DetectResponse:
    _cleanup_expired_files()
    if processing_mode not in {"local", "online"}:
        raise HTTPException(status_code=400, detail="处理模式仅支持 local 或 online。")
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="请上传图片文件。")

    content = await _read_upload_limited(file, settings.max_image_bytes)
    if not content:
        raise HTTPException(status_code=400, detail="图片文件为空。")

    try:
        with Image.open(BytesIO(content)) as image:
            image.verify()
        with Image.open(BytesIO(content)) as image:
            width, height = image.size
            image_format = (image.format or "").upper()
    except (Image.DecompressionBombError, UnidentifiedImageError, OSError):
        raise HTTPException(status_code=400, detail="图片无法识别，或像素尺寸超过安全限制。")

    format_extensions = {"PNG": ".png", "JPEG": ".jpg", "WEBP": ".webp"}
    extension = format_extensions.get(image_format)
    if extension is None:
        raise HTTPException(status_code=400, detail="当前仅支持 PNG、JPEG、WEBP 图片。")
    if width * height > settings.max_image_pixels:
        raise HTTPException(status_code=413, detail="图片像素尺寸过大，请压缩后重试。")

    image_id = f"img_{uuid.uuid4().hex[:12]}"
    saved_path = UPLOAD_DIR / f"{image_id}{extension}"
    saved_path.write_bytes(content)

    original_url = f"/static/uploads/{saved_path.name}"
    try:
        result = detect_privacy_items(
            str(saved_path),
            image_id,
            original_url,
            processing_mode=processing_mode,
        )
    except Exception:
        logger.exception("Privacy detector failed for image %s", image_id)
        saved_path.unlink(missing_ok=True)
        raise HTTPException(status_code=503, detail="图片检测引擎暂不可用，请稍后重试。")
    _save_detection_result(result)
    _append_history(
        HistoryRecord(
            module="privacy",
            imageId=image_id,
            originalImageUrl=original_url,
            processedImageUrl=None,
            riskLevel=result.riskLevel,
            score=result.score,
            summary=result.summary,
            createdAt=datetime.now().astimezone().isoformat(timespec="seconds"),
            status="待处理",
        ),
        result_json=result.model_dump_json(),
    )
    return result


@app.post("/api/mask", response_model=MaskResponse)
def mask_image(request: MaskRequest) -> MaskResponse:
    return _apply_mask(request.imageId, request.maskType, request.items)


@app.post("/api/privacy/process", response_model=MaskResponse)
def process_privacy_image(request: PrivacyProcessRequest) -> MaskResponse:
    detection = _load_detection_result(request.imageId)
    if request.scope == "all":
        selected_items = detection.items
    elif request.scope == "high":
        selected_items = [item for item in detection.items if item.riskLevel == "high"]
    else:
        selected_ids = set(request.itemIds)
        selected_items = [item for item in detection.items if item.id in selected_ids]

    if not selected_items:
        raise HTTPException(status_code=400, detail="No privacy areas were selected for processing.")

    mask_type = _valid_mask_type(request.maskType)
    return _apply_mask(request.imageId, mask_type, [item.box for item in selected_items])


@app.get("/api/history")
def history(offset: int = Query(default=0, ge=0), limit: int = Query(default=20, ge=1, le=100)) -> dict:
    _cleanup_expired_files()
    records = [HistoryRecord(**record) for record in history_store.list(limit=limit, offset=offset)]
    total = history_store.count()
    return {"records": records, "total": total, "offset": offset, "limit": limit}

@app.get("/api/history/module-averages")
def module_averages() -> dict[str, int]:
    averages = history_store.module_averages()
    defaults = {"privacy": 100, "code": 100, "link": 100, "doc": 100}
    return {key: averages.get(key, defaults[key]) for key in defaults}

@app.delete("/api/history/{record_id}")
def delete_history_record(record_id: str) -> dict[str, bool]:
    deleted = history_store.delete_by_id(record_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="记录不存在。")
    return {"ok": True}


@app.post("/api/history", response_model=HistoryRecord)
def create_history(request: HistoryCreate) -> HistoryRecord:
    record = history_store.add(
        {
            "module": request.module,
            "riskLevel": request.riskLevel,
            "score": request.score,
            "summary": request.summary,
            "status": request.status,
            "createdAt": datetime.now().astimezone().isoformat(timespec="seconds"),
        }
    )
    return HistoryRecord(**record)


@app.post("/api/code/analyze", response_model=CodeAnalyzeResponse)
async def analyze_code(request: Request) -> CodeAnalyzeResponse:
    content_type = request.headers.get("content-type", "")
    language: str | None = None
    filename: str | None = None
    processing_mode = "local"
    code = ""

    if "multipart/form-data" in content_type:
        form = await request.form()
        language_value = form.get("language")
        language = str(language_value) if language_value is not None else None
        processing_mode = str(form.get("processing_mode") or "local")
        upload = form.get("file")
        if upload is None or not hasattr(upload, "read"):
            raise HTTPException(status_code=400, detail="请上传单个代码文件。")
        filename = getattr(upload, "filename", "") or ""
        extension = Path(filename).suffix.lower()
        if extension == ".zip":
            raise HTTPException(status_code=400, detail="项目级 zip 扫描为后续扩展功能，请先上传单个代码文件。")
        if extension not in {".py", ".java", ".js", ".ts", ".sql", ".txt"}:
            raise HTTPException(status_code=400, detail="当前仅支持 .py、.java、.js、.ts、.sql、.txt 文件。")
        code = _decode_upload(await _read_upload_limited(upload, settings.max_code_bytes))
    else:
        try:
            payload = await request.json()
        except json.JSONDecodeError:
            raise HTTPException(status_code=400, detail="请提交 JSON 或 multipart/form-data 请求。")
        if not isinstance(payload, dict):
            raise HTTPException(status_code=400, detail="JSON 请求体必须是对象。")
        language = payload.get("language")
        processing_mode = str(payload.get("processingMode") or "local")
        code = str(payload.get("code") or "")
        if len(code.encode("utf-8")) > settings.max_code_bytes:
            raise HTTPException(status_code=413, detail="代码内容过大，最大允许 1 MB。")

    if not code.strip():
        raise HTTPException(status_code=400, detail="请输入或上传需要检测的代码。")
    if processing_mode not in {"local", "online"}:
        raise HTTPException(status_code=400, detail="处理模式仅支持 local 或 online。")

    result = CodeAnalyzeResponse(
        **run_code_guardian(
            code=code,
            language=language,
            filename=filename,
            processing_mode=processing_mode,
        )
    )
    _append_analysis_history("code", result.riskLevel, result.score, result.summary, result_json=result.model_dump_json())
    return result




@app.post("/api/link/check", response_model=LinkCheckResponse)
def check_link(request: LinkCheckRequest) -> LinkCheckResponse:
    if not request.url.strip():
        raise HTTPException(status_code=400, detail="请输入需要检测的 URL。")
    try:
        result = LinkCheckResponse(**run_link_guard(request.url, request.source))
    except ValueError:
        raise HTTPException(status_code=400, detail="URL 格式不合法，请检查域名、端口和括号是否完整。")
    _append_analysis_history("link", result.riskLevel, result.score, result.summary, result_json=result.model_dump_json())
    return result


@app.post("/api/link/qr/decode", response_model=QrDecodeResponse)
async def decode_link_qr(file: UploadFile = File(...)) -> QrDecodeResponse:
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="请上传二维码图片。")
    content = await _read_upload_limited(file, settings.max_image_bytes)
    if not content:
        raise HTTPException(status_code=400, detail="二维码图片为空。")
    try:
        decoded_texts = decode_qr_image(content, settings.max_image_pixels)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    if not decoded_texts:
        raise HTTPException(status_code=422, detail="图片中未识别到可用二维码，请换一张更清晰的图片。")
    return QrDecodeResponse(
        decodedTexts=decoded_texts,
        primaryText=decoded_texts[0],
        message=f"已在本地解析 {len(decoded_texts)} 个二维码，未主动访问其中的链接。",
    )


@app.post("/api/doc/check", response_model=DocCheckResponse)
async def check_doc(
    requirement_text: str = Form(...),
    files: list[UploadFile] = File(...),
) -> DocCheckResponse:
    requirement_text = requirement_text.strip()
    if not requirement_text:
        raise HTTPException(status_code=400, detail="请输入提交要求。")
    if not files:
        raise HTTPException(status_code=400, detail="请至少上传一个材料文件。")
    if len(files) > settings.max_doc_files:
        raise HTTPException(status_code=413, detail=f"单次最多上传 {settings.max_doc_files} 个材料文件。")

    parsed_requirements = parse_requirement(requirement_text)
    extracted_files = []
    total_bytes = 0
    allowed_extensions = {".txt", ".md", ".pdf", ".docx", ".png", ".jpg", ".jpeg", ".zip", ".rar", ".ppt", ".pptx"}
    for file in files:
        file_name = (file.filename or "未命名材料").strip()
        extension = Path(file_name).suffix.lower()
        if extension not in allowed_extensions:
            raise HTTPException(status_code=400, detail=f"不支持的材料格式：{extension or '无后缀'}。")
        content = await _read_upload_limited(file, settings.max_doc_bytes)
        total_bytes += len(content)
        if total_bytes > settings.max_doc_total_bytes:
            limit_mb = settings.max_doc_total_bytes / (1024 * 1024)
            raise HTTPException(status_code=413, detail=f"材料总大小超过 {limit_mb:g} MB，请分批检查。")
        _validate_document_upload(file_name, content)
        extracted_files.append(extract_file(file_name, file.content_type, content))

    checks = [
        *check_format(extracted_files, parsed_requirements),
        *check_completeness(extracted_files, parsed_requirements),
        *check_privacy(extracted_files),
    ]
    result = DocCheckResponse(**generate_report(parsed_requirements, extracted_files, checks))
    _append_analysis_history("doc", result.riskLevel, result.score, result.summary, result_json=result.model_dump_json())
    return result


@app.post("/api/export/image/{image_id}")
def export_image(image_id: str) -> FileResponse:
    processed_path = PROCESSED_DIR / f"{image_id}_safe.png"
    if not processed_path.exists():
        raise HTTPException(status_code=404, detail="已处理图片不存在，请先完成隐私处理。")
    return FileResponse(
        path=processed_path,
        media_type="image/png",
        filename=f"{image_id}_safe.png",
        headers={"Content-Disposition": f'attachment; filename="{image_id}_safe.png"'},
    )


@app.post("/api/code/fix", response_model=CodeFixResponse)
def fix_code(request: CodeFixRequest) -> CodeFixResponse:
    from openai import OpenAI

    if not settings.deepseek_enabled or not settings.deepseek_api_key:
        raise HTTPException(status_code=503, detail="DeepSeek 代码修复服务未启用。")

    items_desc = ""
    if request.items:
        vulns_desc = []
        for item in request.items:
            t = item.get("title", "")
            ln = item.get("line", "")
            sn = item.get("snippet", "")
            vulns_desc.append(f"- [{t}] line {ln}: {sn}")
        items_desc = "Focus on fixing these specific vulnerabilities:\n" + "\n".join(vulns_desc) + "\n\n"

    prompt = f"""You are an expert code fixer. {items_desc}Fix all security issues in the following {request.language} code.
Return ONLY a JSON object with this exact structure:
{{
  "fixed_code": "the fully corrected code as a string",
  "explanation": "brief explanation of changes in Chinese"
}}

Code to fix ({request.language}):
```{request.language}
{request.code}
```"""

    try:
        client = OpenAI(api_key=settings.deepseek_api_key, base_url=settings.deepseek_api_base)
        response = client.chat.completions.create(
            model=settings.deepseek_model,
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"},
            max_tokens=8192,
            temperature=0.1,
        )
        content = response.choices[0].message.content
        if not content:
            raise HTTPException(status_code=502, detail="DeepSeek 未返回有效响应。")
        result = json.loads(content)

        if request.recordId and request.totalVulns > 0:
            fixed = len(request.items)
            improvement = int(round((100 - request.originalScore) * (fixed / request.totalVulns) * 0.8))
            new_score = min(100, request.originalScore + improvement)
            history_store.mark_processed(request.recordId, new_score)

        return CodeFixResponse(
            fixedCode=result.get("fixed_code", ""),
            explanation=result.get("explanation", ""),
            language=request.language,
        )
    except json.JSONDecodeError:
        raise HTTPException(status_code=502, detail="无法解析 AI 修复结果。")
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("DeepSeek code fix failed")
        raise HTTPException(status_code=502, detail=f"代码修复失败：{exc}")


@app.post("/api/export/code")
def export_code(code: str = Form(...)) -> Response:
    if not code.strip():
        raise HTTPException(status_code=400, detail="代码内容为空。")
    return Response(
        content=code.encode("utf-8"),
        media_type="text/plain; charset=utf-8",
        headers={"Content-Disposition": 'attachment; filename="fixed_code.txt"'},
    )
