import json
import re
import shutil
import uuid
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from PIL import Image, UnidentifiedImageError

from detector.mock_detector import detect_privacy_items
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
from schemas.models import (
    CodeAnalyzeResponse,
    DetectResponse,
    DocCheckResponse,
    HistoryRecord,
    LinkCheckRequest,
    LinkCheckResponse,
    MaskRequest,
    MaskResponse,
    ScamAnalyzeRequest,
    ScamAnalyzeResponse,
    TextFinding,
)


BASE_DIR = Path(__file__).resolve().parent
UPLOAD_DIR = BASE_DIR / "static" / "uploads"
PROCESSED_DIR = BASE_DIR / "static" / "processed"
HISTORY_FILE = BASE_DIR / "data" / "history.json"

for directory in [UPLOAD_DIR, PROCESSED_DIR, HISTORY_FILE.parent]:
    directory.mkdir(parents=True, exist_ok=True)
if not HISTORY_FILE.exists():
    HISTORY_FILE.write_text("[]", encoding="utf-8")

app = FastAPI(title="GuardianHub API", version="0.5.0")
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


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok", "message": "GuardianHub backend is running"}


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


@app.post("/api/code/analyze", response_model=CodeAnalyzeResponse)
async def analyze_code(request: Request) -> CodeAnalyzeResponse:
    content_type = request.headers.get("content-type", "")
    language: str | None = None
    filename: str | None = None
    code = ""

    if "multipart/form-data" in content_type:
        form = await request.form()
        language_value = form.get("language")
        language = str(language_value) if language_value is not None else None
        upload = form.get("file")
        if upload is None or not hasattr(upload, "read"):
            raise HTTPException(status_code=400, detail="请上传单个代码文件。")
        filename = getattr(upload, "filename", "") or ""
        extension = Path(filename).suffix.lower()
        if extension == ".zip":
            raise HTTPException(status_code=400, detail="项目级 zip 扫描为后续扩展功能，请先上传单个代码文件。")
        if extension not in {".py", ".java", ".js", ".ts", ".sql", ".txt"}:
            raise HTTPException(status_code=400, detail="当前仅支持 .py、.java、.js、.ts、.sql、.txt 文件。")
        code = _decode_upload(await upload.read())
    else:
        try:
            payload = await request.json()
        except json.JSONDecodeError:
            raise HTTPException(status_code=400, detail="请提交 JSON 或 multipart/form-data 请求。")
        language = payload.get("language")
        code = str(payload.get("code") or "")

    if not code.strip():
        raise HTTPException(status_code=400, detail="请输入或上传需要检测的代码。")

    return CodeAnalyzeResponse(**run_code_guardian(code=code, language=language, filename=filename))


@app.post("/api/scam/analyze", response_model=ScamAnalyzeResponse)
def analyze_scam(request: ScamAnalyzeRequest) -> ScamAnalyzeResponse:
    """Archived compatibility endpoint. The frontend no longer displays this legacy module."""
    text = request.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="请输入需要分析的聊天文本。")

    rules = [
        ("索要验证码", r"验证码|短信码|校验码|动态码", 35, "high"),
        ("诱导转账", r"转账|汇款|垫付|保证金|手续费|刷流水|解冻金|押金", 35, "high"),
        ("高额回报", r"高额回报|稳赚|保本|返利|日结|佣金|中奖|补贴|奖学金|返现", 30, "high"),
        ("催促决策", r"截止|逾期|马上|立即|最后\s*机会|今日.*失效|限时|名额有限", 20, "medium"),
        ("脱离平台", r"加微信|加QQ|私聊|扫码进群|下载.*app|绕过平台|线下交易", 30, "high"),
        ("隐瞒他人", r"不要告诉|别告诉|保密|悄悄|不要和.*说|只告诉你", 25, "medium"),
        ("冒充身份", r"客服|老师|辅导员|学工|银行|公安|法院|平台审核", 20, "medium"),
        ("可疑链接", r"https?://|点击链接|扫码|二维码|短链接|bit\.ly|tinyurl", 25, "medium"),
        ("索要敏感资料", r"银行卡|身份证|密码|人脸|账号|支付密码|银行卡号", 30, "high"),
    ]

    reasons: list[TextFinding] = []
    score = 0
    for label, pattern, weight, level in rules:
        match = re.search(pattern, text, flags=re.IGNORECASE)
        if match:
            score += weight
            start = max(match.start() - 12, 0)
            end = min(match.end() + 12, len(text))
            reasons.append(TextFinding(label=label, evidence=text[start:end], riskLevel=level))

    if not reasons:
        reasons.append(TextFinding(label="未命中典型诈骗话术", evidence="未发现典型高危关键词。", riskLevel="low"))

    risk_level = _level_from_score(score)
    suggestions = {
        "high": ["停止转账、提交验证码或填写银行卡。", "通过学校官网、辅导员或官方客服电话二次确认。", "保留聊天记录并向反诈或校园安全渠道反馈。"],
        "medium": ["不要直接点击对方发送的链接。", "核对通知来源，优先使用学校或平台官方入口。", "涉及个人信息时先询问可信联系人。"],
        "low": ["当前未发现明显诈骗特征。", "仍建议不要在聊天中发送验证码、密码、身份证或银行卡信息。"],
    }[risk_level]

    return ScamAnalyzeResponse(riskLevel=risk_level, score=min(score, 100), reasons=reasons, suggestions=suggestions)


@app.post("/api/link/check", response_model=LinkCheckResponse)
def check_link(request: LinkCheckRequest) -> LinkCheckResponse:
    if not request.url.strip():
        raise HTTPException(status_code=400, detail="请输入需要检测的 URL。")
    return LinkCheckResponse(**run_link_guard(request.url, request.source))


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

    parsed_requirements = parse_requirement(requirement_text)
    extracted_files = []
    for file in files:
        content = await file.read()
        file_name = (file.filename or "未命名材料").strip()
        extracted_files.append(extract_file(file_name, file.content_type, content))

    checks = [
        *check_format(extracted_files, parsed_requirements),
        *check_completeness(extracted_files, parsed_requirements),
        *check_privacy(extracted_files),
    ]
    report = generate_report(parsed_requirements, extracted_files, checks)
    return DocCheckResponse(**report)
